"""Topologia do RabbitMQ vista pela aplicacao.

As filas, bindings e policies sao do broker (apps/rabbitmq/definicoes.json.modelo):
nenhum processo tem permissao de configure, entao nenhum deles consegue criar,
apagar ou religar fila, nem redeclarar exchange (#28). Aqui ficam so os nomes
e quais routing keys cada fila recebe, para o relay nao publicar evento que
nenhuma etapa ligada consome.
"""
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
