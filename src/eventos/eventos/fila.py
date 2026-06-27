"""Topologia do RabbitMQ, declarada por quem publica e por quem consome."""
import pika

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
    canal.queue_declare("mortos", durable=True, arguments={"x-queue-type": "quorum"})
    canal.queue_bind("mortos", MORTOS)
    for fila, chaves in FILAS.items():
        # Quorum queue com limite de entregas: mensagem que falha 5 vezes
        # vai para "mortos" em vez de travar a fila.
        canal.queue_declare(fila, durable=True, arguments={
            "x-queue-type": "quorum",
            "x-delivery-limit": 5,
            "x-dead-letter-exchange": MORTOS,
        })
        for chave in chaves:
            canal.queue_bind(fila, EXCHANGE, routing_key=chave)
