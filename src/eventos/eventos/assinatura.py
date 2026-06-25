"""Assinatura dos webhooks: HMAC-SHA256 sobre "<timestamp>.<corpo>".

O timestamp entra na assinatura para que uma requisicao capturada nao possa
ser reenviada depois da janela de tolerancia.
"""
import hashlib
import hmac
import time

TOLERANCIA_S = 300


def assinar(segredo: str, timestamp: int, corpo: bytes) -> str:
    mensagem = str(timestamp).encode() + b"." + corpo
    return "sha256=" + hmac.new(segredo.encode(), mensagem, hashlib.sha256).hexdigest()


def verificar(segredo: str, timestamp: str, assinatura: str, corpo: bytes, agora: float | None = None) -> bool:
    if not segredo or not timestamp or not assinatura:
        return False
    try:
        ts = int(timestamp)
    except ValueError:
        return False
    if abs((agora or time.time()) - ts) > TOLERANCIA_S:
        return False
    return hmac.compare_digest(assinar(segredo, ts, corpo), assinatura)
