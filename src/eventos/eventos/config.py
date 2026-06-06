import os

# As chaves do Secret loja-segredos chegam como variaveis de ambiente (envFrom).
DATABASE_URL = os.environ.get("DATABASE_URL", "")
AMQP_URL = os.environ.get("AMQP_URL", "")
REDIS_URL = os.environ.get("REDIS_URL", "")
BUSCA_URL = os.environ.get("BUSCA_URL", "http://busca:7700")
BUSCA_CHAVE = os.environ.get("meili_chave", "")
GOTENBERG_URL = os.environ.get("GOTENBERG_URL", "http://gotenberg:3000")
WEBHOOK_SEGREDO = os.environ.get("webhook_hmac", "")
LOJA_ID = os.environ.get("LOJA_ID", "loja-000")
ETAPAS = {e.strip() for e in os.environ.get("ETAPAS", "recibos,busca,pagamentos").split(",") if e.strip()}
