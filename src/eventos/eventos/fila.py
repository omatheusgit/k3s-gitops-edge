"""Topologia do RabbitMQ, declarada por quem publica e por quem consome."""
from urllib.parse import quote, unquote, urlparse

import pika
import requests

EXCHANGE = "loja.eventos"
MORTOS = "loja.mortos"

# fila -> padroes de routing key
FILAS = {
    "recibos": ["venda.registrada"],
    "busca": ["produto.*", "venda.*"],
    "pagamentos": ["pagamento.confirmado"],
}


def conectar(url: str) -> pika.BlockingConnection:
    parametros = pika.URLParameters(url)
    parametros.heartbeat = 30
    parametros.connection_attempts = 5
    parametros.retry_delay = 3
    return pika.BlockingConnection(parametros)


def declarar(canal) -> None:
    canal.exchange_declare(EXCHANGE, "topic", durable=True)
    canal.exchange_declare(MORTOS, "fanout", durable=True)
    # Argumentos de fila sao imutaveis; so o tipo vai aqui. Limite de entregas
    # e fila de mortos ficam na policy, que da para mudar com a fila em uso.
    canal.queue_declare("mortos", durable=True, arguments={"x-queue-type": "quorum"})
    canal.queue_bind("mortos", MORTOS)
    for fila, chaves in FILAS.items():
        canal.queue_declare(fila, durable=True, arguments={"x-queue-type": "quorum"})
        for chave in chaves:
            canal.queue_bind(fila, EXCHANGE, routing_key=chave)


def aplicar_politica(url_amqp: str, painel_porta: int = 15672) -> None:
    """Mensagem que falha 10 vezes vai para "mortos" em vez de travar a fila."""
    url = urlparse(url_amqp)
    vhost = quote(unquote(url.path.lstrip("/")) or "/", safe="")
    requests.put(
        f"http://{url.hostname}:{painel_porta}/api/policies/{vhost}/filas-da-loja",
        auth=(unquote(url.username or ""), unquote(url.password or "")),
        json={
            "pattern": "^(" + "|".join(FILAS) + ")$",
            "apply-to": "queues",
            "definition": {"delivery-limit": 10, "dead-letter-exchange": MORTOS},
        },
        timeout=10,
    ).raise_for_status()
