"""Consome os eventos da loja.

Cada etapa e idempotente por conta propria (upsert do recibo, upsert na
busca, confirmacao de pagamento que so vale uma vez). O Redis guarda os ids
ja processados so para evitar trabalho repetido quando o relay reentrega.
"""
import json
import logging
import threading
import time

import pika
import psycopg
import redis
import requests

from . import config, fila, recibo, saude

log = logging.getLogger("consumidor")
JA_PROCESSADO_TTL = 24 * 3600

# Erros de conexao nao se resolvem tentando de novo na mesma conexao: o
# consumo para e o laco de fora reconecta.
ERROS_DE_CONEXAO = (psycopg.OperationalError, redis.exceptions.ConnectionError)
# Dependencia HTTP fora (Gotenberg, Meilisearch): a etapa pausa com espera
# crescente; as outras etapas seguem, cada uma na sua conexao.
ERROS_PASSAGEIROS = (requests.RequestException,)
# Mensagem que nunca vai dar certo: direto para "mortos", sem 10 tentativas.
ERROS_DE_DADOS = (json.JSONDecodeError, KeyError, TypeError, psycopg.errors.DataError)
ESPERA_MAXIMA = 300


class DependenciaFora(Exception):
    """Etapa interrompida por falha passageira de uma dependencia HTTP."""


class Etapas:
    def __init__(self, banco, cache):
        self.banco = banco
        self.cache = cache
        self.http = requests.Session()
        self.http.headers["Authorization"] = f"Bearer {config.BUSCA_CHAVE}"

    def preparar_busca(self) -> None:
        for indice, campos in (("produtos", ["nome", "sku"]), ("vendas", ["id", "status"])):
            self.http.post(f"{config.BUSCA_URL}/indexes", json={"uid": indice, "primaryKey": "id"}, timeout=10)
            self.http.put(f"{config.BUSCA_URL}/indexes/{indice}/settings/searchable-attributes",
                          json=campos, timeout=10).raise_for_status()
        # Chave so de busca para o caixa; 409 = ja existe (o uid e fixo).
        resp = self.http.post(f"{config.BUSCA_URL}/keys", timeout=10, json={
            "uid": config.BUSCA_UID_PESQUISA, "name": "caixa-busca", "actions": ["search"],
            "indexes": ["produtos", "vendas"], "expiresAt": None})
        if resp.status_code != 409:
            resp.raise_for_status()

    def recibos(self, tipo: str, evento: dict) -> None:
        venda = self.banco.execute(
            """select v.id, v.total_centavos, v.criada_em, o.nome as operador
                 from loja.vendas v join loja.operadores o on o.id = v.operador_id
                where v.id = %s""", (evento["venda_id"],)).fetchone()
        if venda is None:
            log.warning("venda %s nao encontrada", evento["venda_id"])
            return
        itens = self.banco.execute(
            """select i.quantidade, i.preco_centavos, p.nome
                 from loja.itens_venda i join loja.produtos p on p.id = i.produto_id
                where i.venda_id = %s order by p.nome""", (venda["id"],)).fetchall()
        html = recibo.montar_html(config.LOJA_ID, venda, itens)
        resp = requests.post(f"{config.GOTENBERG_URL}/forms/chromium/convert/html",
                             files={"files": ("index.html", html.encode(), "text/html")},
                             data={"paperWidth": "3.15", "marginTop": "0.2", "marginBottom": "0.2"},
                             timeout=100)
        resp.raise_for_status()
        self.banco.execute(
            """insert into loja.recibos (venda_id, pdf) values (%s, %s)
               on conflict (venda_id) do update set pdf = excluded.pdf, gerado_em = now()""",
            (venda["id"], resp.content))
        log.info("recibo da venda %s gerado (%d bytes)", venda["id"], len(resp.content))

    def busca(self, tipo: str, evento: dict) -> None:
        if tipo.startswith("produto."):
            indice, documento = "produtos", evento
        else:
            linha = self.banco.execute(
                "select id::text, total_centavos, status, criada_em::text from loja.vendas where id = %s",
                (evento["venda_id"],)).fetchone()
            if linha is None:
                return
            indice, documento = "vendas", linha
        self.http.post(f"{config.BUSCA_URL}/indexes/{indice}/documents",
                       json=[documento], timeout=10).raise_for_status()

    def pagamentos(self, tipo: str, evento: dict) -> None:
        # O banco so quita a venda se o valor bater; divergencia fica registrada.
        resultado = self.banco.execute(
            "select loja.confirmar_pagamento(%s, %s, %s) as r",
            (evento["venda_id"], evento["pagamento_ref"], int(evento["valor_centavos"]))).fetchone()["r"]
        log.info("pagamento %s da venda %s: %s", evento["pagamento_ref"], evento["venda_id"], resultado)


def tratador(etapas: Etapas, nome: str):
    acao = getattr(etapas, nome)

    def tratar(canal, metodo, propriedades, corpo):
        chave = f"processado:{nome}:{propriedades.message_id}"
        try:
            if etapas.cache.exists(chave):
                canal.basic_ack(metodo.delivery_tag)
                return
            acao(metodo.routing_key, json.loads(corpo))
            etapas.cache.set(chave, 1, ex=JA_PROCESSADO_TTL)
            canal.basic_ack(metodo.delivery_tag)
        except ERROS_DE_CONEXAO:
            log.warning("conexao perdida em %s; devolvendo a mensagem e reconectando", nome)
            canal.basic_nack(metodo.delivery_tag, requeue=True)
            raise
        except ERROS_DE_DADOS:
            log.exception("mensagem invalida em %s (%s); indo para mortos", nome, metodo.routing_key)
            canal.basic_nack(metodo.delivery_tag, requeue=False)
        except ERROS_PASSAGEIROS as erro:
            log.warning("dependencia fora em %s (%s); pausando a etapa", nome, erro)
            canal.basic_nack(metodo.delivery_tag, requeue=True)
            raise DependenciaFora(str(erro)) from erro
        except Exception:
            # Bug ou caso nao previsto: volta para a fila e, depois do limite de
            # entregas da policy, vai para mortos em vez de travar a fila.
            log.exception("falha em %s (%s); devolvendo para a fila", nome, metodo.routing_key)
            canal.basic_nack(metodo.delivery_tag, requeue=True)

    return tratar


def ciclo(nome: str, pronta: threading.Event) -> None:
    """Uma etapa, com conexoes proprias: falha nela nao para as outras."""
    with psycopg.connect(config.DATABASE_URL, autocommit=True,
                         row_factory=psycopg.rows.dict_row) as banco:
        cache = redis.Redis.from_url(config.REDIS_URL, socket_timeout=5)
        etapas = Etapas(banco, cache)
        if nome == "busca":
            etapas.preparar_busca()
        amqp = fila.conectar(config.AMQP_URL)
        try:
            canal = amqp.channel()
            canal.basic_qos(prefetch_count=10)
            canal.basic_consume(nome, tratador(etapas, nome))
            pronta.chegou_a_consumir = True
            pronta.set()
            log.info("consumindo %s", nome)
            canal.start_consuming()
        finally:
            pronta.clear()
            if amqp.is_open:
                amqp.close()


def espera_antes_de_reconectar(espera: int, chegou_a_consumir: bool, erro: BaseException | None) -> int:
    """Quanto esperar antes de reconectar a etapa (o laco dobra depois).

    Se a etapa chegou a consumir e caiu por conexao (ex.: Postgres reiniciou),
    volta a 1 s: antes so voltava depois de 5 min seguidos no ar, entao uma
    etapa que tinha falhado ao subir levava minutos para voltar no restart
    seguinte. Dependencia HTTP fora (DependenciaFora) mantem a espera
    crescendo, senao a mensagem seria reentregue rapido e iria para "mortos".
    """
    if chegou_a_consumir and not isinstance(erro, DependenciaFora):
        return 1
    return espera


def laco(nome: str, pronta: threading.Event) -> None:
    espera = 1
    while True:
        erro = None
        pronta.chegou_a_consumir = False
        try:
            ciclo(nome, pronta)
        except (DependenciaFora, psycopg.OperationalError, pika.exceptions.AMQPError,
                redis.exceptions.ConnectionError, requests.RequestException) as e:
            erro = e
        except Exception as e:
            erro = e
            log.exception("%s: erro inesperado", nome)
        espera = espera_antes_de_reconectar(espera, pronta.chegou_a_consumir, erro)
        log.warning("%s: %s; tentando de novo em %ds", nome, erro or "consumo encerrado", espera)
        time.sleep(espera)
        espera = min(espera * 2, ESPERA_MAXIMA)


def rodar() -> None:
    saude.iniciar()
    prontas = {}
    for nome in fila.ativas(config.ETAPAS):
        prontas[nome] = threading.Event()
        threading.Thread(target=laco, args=(nome, prontas[nome]), name=nome, daemon=True).start()
    log.info("etapas: %s", ", ".join(sorted(prontas)))
    while True:
        # Pronto so com todas as etapas consumindo.
        if all(e.is_set() for e in prontas.values()):
            saude.pronto.set()
        else:
            saude.pronto.clear()
        time.sleep(2)


def reprocessar_mortos(limite: int = 1000) -> int:
    """Devolve as mensagens de "mortos" ao exchange, com a routing key original."""
    amqp = fila.conectar(config.AMQP_URL)
    try:
        canal = amqp.channel()
        canal.confirm_delivery()
        movidas = 0
        while movidas < limite:
            metodo, propriedades, corpo = canal.basic_get("mortos")
            if metodo is None:
                break
            canal.basic_publish(fila.EXCHANGE, metodo.routing_key, corpo, propriedades, mandatory=True)
            canal.basic_ack(metodo.delivery_tag)
            movidas += 1
        log.info("%d mensagens devolvidas de mortos", movidas)
        return movidas
    finally:
        if amqp.is_open:
            amqp.close()
