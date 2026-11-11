#!/usr/bin/env bash
# Depois do Rancher subir: login com a senha de bootstrap, define o server-url
# que os agentes das lojas usam e publica um token de API no SSM, onde o
# instalador vai buscar.
#   ./rancher-token.sh <senha-bootstrap>
# shellcheck source=comum.sh
source "$(dirname "${BASH_SOURCE[0]}")/comum.sh"

SENHA="${1:?informe a senha de bootstrap}"
# Mesmo nome para o instalador (host) e para os agentes das lojas.
URL="https://${RANCHER_HOST:-rancher.lab.internal}"
SERVER_URL="${URL}"

api() {
  curl -fsS --cacert "${CACHE}/ca.crt" --retry 5 --retry-delay 5 --retry-all-errors \
    -H 'Content-Type: application/json' "$@"
}

esperar 600 "API do Rancher" api "${URL}/ping"

sessao="$(api -X POST "${URL}/v3-public/localProviders/local?action=login" \
  -d "$(jq -cn --arg s "${SENHA}" '{username: "admin", password: $s, responseType: "json"}')" | jq -r .token)"
[[ -n "${sessao}" && "${sessao}" != "null" ]] || falha "login no Rancher recusado"

api -X PUT "${URL}/v3/settings/server-url" -H "Authorization: Bearer ${sessao}" \
  -d "$(jq -cn --arg v "${SERVER_URL}" '{name: "server-url", value: $v}')" >/dev/null

token="$(api -X POST "${URL}/v3/tokens" -H "Authorization: Bearer ${sessao}" \
  -d '{"type": "token", "description": "instalador das lojas (lab)", "ttl": 0}' | jq -r .token)"
[[ -n "${token}" && "${token}" != "null" ]] || falha "nao consegui gerar o token de API"

aws --endpoint-url http://localhost:4566 ssm put-parameter --overwrite \
  --name /frota/rancher/token --type SecureString --value "${token}" >/dev/null
aws --endpoint-url http://localhost:4566 ssm put-parameter --overwrite \
  --name /frota/rancher/url --type String --value "${URL}" >/dev/null
echo "server-url=${SERVER_URL}; token publicado em /frota/rancher/token"
