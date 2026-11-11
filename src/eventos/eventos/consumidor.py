"""Consome os eventos da loja.

Cada etapa e idempotente por conta propria (upsert do recibo, upsert na
busca, confirmacao de pagamento que so vale uma vez). O Redis guarda os ids
ja processados so para evitar trabalho repetido quando o relay reentrega.
"""
import json
import logging
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
        mudou = self.banco.execute("select loja.confirmar_pagamento(%s, %s)",
                                   (evento["venda_id"], evento["pagamento_ref"])).fetchone()
        log.info("pagamento %s da venda %s: %s", evento["pagamento_ref"], evento["venda_id"],
                 "confirmado" if mudou["confirmar_pagamento"] else "ja estava confirmado")


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
        except Exception:
            log.exception("falha em %s (%s); devolvendo para a fila", nome, metodo.routing_key)
            time.sleep(5)
            canal.basic_nack(metodo.delivery_tag, requeue=True)

    return tratar


def ciclo() -> None:
    with psycopg.connect(config.DATABASE_URL, autocommit=True,
                         row_factory=psycopg.rows.dict_row) as banco:
        cache = redis.Redis.from_url(config.REDIS_URL, socket_timeout=5)
        etapas = Etapas(banco, cache)
        if "busca" in config.ETAPAS:
            etapas.preparar_busca()
        amqp = fila.conectar(config.AMQP_URL)
        try:
            canal = amqp.channel()
            fila.declarar(canal)
            fila.aplicar_politica(config.AMQP_URL)
            canal.basic_qos(prefetch_count=10)
            for nome in fila.FILAS:
                if nome in config.ETAPAS:
                    canal.basic_consume(nome, tratador(etapas, nome))
            saude.pronto.set()
            log.info("consumindo: %s", ", ".join(sorted(config.ETAPAS)))
            canal.start_consuming()
        finally:
            saude.pronto.clear()
            if amqp.is_open:
                amqp.close()


def rodar() -> None:
    saude.iniciar()
    espera = 1
    while True:
        try:
            ciclo()
        except (psycopg.OperationalError, pika.exceptions.AMQPError,
                redis.exceptions.ConnectionError, requests.ConnectionError) as erro:
            log.warning("dependencia indisponivel (%s); tentando de novo em %ds", erro, espera)
            time.sleep(espera)
            espera = min(espera * 2, 30)
