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


def ativas(etapas) -> dict:
    """Filas das etapas ligadas nesta loja (perfil enxuto nao tem recibo nem busca)."""
    return {nome: chaves for nome, chaves in FILAS.items() if nome in etapas}


def _casa(padrao: str, chave: str) -> bool:
    """Casamento de routing key de exchange topic: * e uma palavra, # zero ou mais."""
    def casar(p, c):
        if not p:
            return not c
        if p[0] == "#":
            return any(casar(p[1:], c[i:]) for i in range(len(c) + 1))
        return bool(c) and p[0] in ("*", c[0]) and casar(p[1:], c[1:])
    return casar(padrao.split("."), chave.split("."))


def tem_destino(chave: str, etapas) -> bool:
    return any(_casa(p, chave) for chaves in ativas(etapas).values() for p in chaves)


def declarar(canal, etapas=None, limpar: bool = False) -> None:
    """Declara exchanges e as filas das etapas ativas.

    Fila sem consumidor so acumula ate o RabbitMQ bloquear quem publica; com
    limpar=True (so o consumidor usa) as filas de etapas desligadas sao
    apagadas, caso a loja tenha mudado de perfil.
    """
    etapas = set(FILAS) if etapas is None else set(etapas)
    canal.exchange_declare(EXCHANGE, "topic", durable=True)
    canal.exchange_declare(MORTOS, "fanout", durable=True)
    # Argumentos de fila sao imutaveis; so o tipo vai aqui. Limite de entregas
    # e fila de mortos ficam na policy, que da para mudar com a fila em uso.
    canal.queue_declare("mortos", durable=True, arguments={"x-queue-type": "quorum"})
    canal.queue_bind("mortos", MORTOS)
    for fila, chaves in FILAS.items():
        if fila not in etapas:
            if limpar:
                canal.queue_delete(fila)
            continue
        canal.queue_declare(fila, durable=True, arguments={"x-queue-type": "quorum"})
        for chave in chaves:
            canal.queue_bind(fila, EXCHANGE, routing_key=chave)
