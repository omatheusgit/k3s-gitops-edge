"""Le loja.outbox e publica no RabbitMQ (transactional outbox).

Entrega pelo menos uma vez: se cair depois de publicar e antes do commit,
o evento sai de novo. Os consumidores sao idempotentes por isso.
"""
import json
import logging
import time

import pika
import psycopg

from . import config, fila, saude

log = logging.getLogger("relay")
LOTE = 100

PENDENTES = """
    select id, tipo, payload from loja.outbox
     where publicado_em is null
     order by id
     limit %s
       for update skip locked
"""


def publicar_lote(banco, canal) -> int:
    with banco.transaction():
        linhas = banco.execute(PENDENTES, (LOTE,)).fetchall()
        for id_, tipo, payload in linhas:
            # Evento que nenhuma etapa desta loja consome (perfil enxuto) e so
            # marcado como publicado; com mandatory=True ele voltaria como erro.
            if not fila.tem_destino(tipo, config.ETAPAS):
                continue
            canal.basic_publish(
                fila.EXCHANGE,
                routing_key=tipo,
                body=json.dumps(payload).encode(),
                properties=pika.BasicProperties(
                    message_id=str(id_),
                    type=tipo,
                    content_type="application/json",
                    delivery_mode=pika.DeliveryMode.Persistent,
                    headers={"loja": config.LOJA_ID},
                ),
                mandatory=True,
            )
        if linhas:
            banco.execute("update loja.outbox set publicado_em = now() where id = any(%s)",
                          ([linha[0] for linha in linhas],))
    return len(linhas)


def ciclo() -> None:
    with psycopg.connect(config.DATABASE_URL, autocommit=True) as banco, \
         psycopg.connect(config.DATABASE_URL, autocommit=True) as escuta:
        amqp = fila.conectar(config.AMQP_URL)
        try:
            canal = amqp.channel()
            canal.confirm_delivery()
            fila.declarar(canal, config.ETAPAS)
            escuta.execute("listen outbox")
            saude.pronto.set()
            log.info("relay pronto")
            while True:
                while (n := publicar_lote(banco, canal)):
                    log.info("publicados %d eventos", n)
                # Acorda com NOTIFY do trigger ou a cada 5 s, o que vier primeiro.
                for _ in escuta.notifies(timeout=5, stop_after=1):
                    pass
                amqp.process_data_events(0)
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
        except (psycopg.OperationalError, pika.exceptions.AMQPError) as erro:
            log.warning("conexao perdida (%s); tentando de novo em %ds", erro, espera)
            time.sleep(espera)
            espera = min(espera * 2, 30)
