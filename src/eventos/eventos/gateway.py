"""Recebe a confirmacao de pagamento da adquirente e publica no RabbitMQ.

POST /pagamentos/confirmacao
  X-Timestamp:  epoch em segundos
  X-Assinatura: sha256=<hmac de "<timestamp>.<corpo>">
  {"evento_id": "...", "venda_id": "...", "valor_centavos": 1234, "status": "aprovado"}
"""
import json
import logging
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pika
import redis

from . import assinatura, config, fila, saude

log = logging.getLogger("gateway")
CORPO_MAX = 64 * 1024
DUPLICADO_TTL = 7 * 24 * 3600


class Publicador:
    """pika nao e thread-safe: uma conexao, protegida por lock, reaberta se cair."""

    def __init__(self):
        self._lock = threading.Lock()
        self._conexao = None
        self._canal = None

    def publicar(self, chave: str, mensagem_id: str, corpo: dict) -> None:
        with self._lock:
            for tentativa in (1, 2):
                try:
                    if self._conexao is None or self._conexao.is_closed:
                        self._conexao = fila.conectar(config.AMQP_URL)
                        self._canal = self._conexao.channel()
                        self._canal.confirm_delivery()
                        fila.declarar(self._canal, config.ETAPAS)
                    self._canal.basic_publish(
                        fila.EXCHANGE, chave, json.dumps(corpo).encode(),
                        pika.BasicProperties(message_id=mensagem_id, type=chave,
                                             content_type="application/json",
                                             delivery_mode=pika.DeliveryMode.Persistent),
                        mandatory=True)
                    return
                except pika.exceptions.AMQPConnectionError:
                    self._conexao = None
                    if tentativa == 2:
                        raise


publicador = Publicador()
cache = None


class Webhook(BaseHTTPRequestHandler):
    def responder(self, codigo: int, corpo: dict) -> None:
        dados = json.dumps(corpo).encode()
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_POST(self):
        if self.path != "/pagamentos/confirmacao":
            return self.responder(404, {"erro": "rota desconhecida"})
        tamanho = int(self.headers.get("Content-Length") or 0)
        if tamanho <= 0 or tamanho > CORPO_MAX:
            return self.responder(413, {"erro": "corpo vazio ou grande demais"})
        corpo = self.rfile.read(tamanho)
        if not assinatura.verificar(config.WEBHOOK_SEGREDO, self.headers.get("X-Timestamp", ""),
                                    self.headers.get("X-Assinatura", ""), corpo):
            log.warning("assinatura invalida de %s", self.client_address[0])
            return self.responder(401, {"erro": "assinatura invalida"})
        try:
            evento = json.loads(corpo)
            evento_id, venda_id = str(evento["evento_id"]), str(evento["venda_id"])
            valor = evento["valor_centavos"]
            if not isinstance(valor, int) or isinstance(valor, bool) or valor <= 0:
                raise ValueError("valor_centavos")
        except (ValueError, KeyError, TypeError):
            return self.responder(400, {"erro": "payload invalido"})
        if evento.get("status") != "aprovado":
            return self.responder(200, {"ignorado": True})
        if not cache.set(f"webhook:{evento_id}", 1, nx=True, ex=DUPLICADO_TTL):
            return self.responder(200, {"duplicado": True})
        try:
            publicador.publicar("pagamento.confirmado", evento_id,
                                {"venda_id": venda_id, "pagamento_ref": evento_id,
                                 "valor_centavos": valor})
        except Exception:
            cache.delete(f"webhook:{evento_id}")
            log.exception("falha ao publicar pagamento %s", evento_id)
            return self.responder(503, {"erro": "fila indisponivel, reenviar"})
        self.responder(202, {"recebido": evento_id})

    def log_message(self, formato, *args):
        log.info("%s %s", self.client_address[0], formato % args)


def rodar() -> None:
    global cache
    cache = redis.Redis.from_url(config.REDIS_URL, socket_timeout=5)
    saude.iniciar()
    saude.pronto.set()
    log.info("gateway escutando na porta 8080")
    ThreadingHTTPServer(("0.0.0.0", 8080), Webhook).serve_forever()
