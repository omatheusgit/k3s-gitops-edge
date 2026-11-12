import os

# As chaves do Secret loja-segredos chegam como variaveis de ambiente (envFrom).
DATABASE_URL = os.environ.get("DATABASE_URL", "")
AMQP_URL = os.environ.get("AMQP_URL", "")
REDIS_URL = os.environ.get("REDIS_URL", "")
BUSCA_URL = os.environ.get("BUSCA_URL", "http://busca:7700")
BUSCA_CHAVE = os.environ.get("meili_chave", "")
# uid fixo da chave so de busca do caixa: o pdv-web deriva a chave dele
# (HMAC-SHA256 do uid com a chave mestra), sem receber a mestra no nginx.
BUSCA_UID_PESQUISA = os.environ.get("BUSCA_UID_PESQUISA", "8f3a1c2e-5b7d-4e9a-9c1f-2d6b0a4e7f31")
GOTENBERG_URL = os.environ.get("GOTENBERG_URL", "http://gotenberg:3000")
WEBHOOK_SEGREDO = os.environ.get("webhook_hmac", "")
LOJA_ID = os.environ.get("LOJA_ID", "loja-000")
ETAPAS = {e.strip() for e in os.environ.get("ETAPAS", "recibos,busca,pagamentos").split(",") if e.strip()}
