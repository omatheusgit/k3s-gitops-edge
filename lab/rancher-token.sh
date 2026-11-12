#!/usr/bin/env bash
# Depois do Rancher subir: login com a senha de bootstrap, define o server-url
# que os agentes das lojas usam e cria, para cada loja do Terraform, o cluster
# no Rancher (com os labels da loja). O comando de registro de cada uma vai
# para /frota/lojas/<id>/registro no SSM, que so a chave daquela loja le.
#
# Nenhum token de API sai da central: o manifesto so registra aquele cluster.
# Em producao e o mesmo passo, rodado por quem opera a central.
#   ./rancher-token.sh <senha-bootstrap>
# shellcheck source=comum.sh
source "$(dirname "${BASH_SOURCE[0]}")/comum.sh"

SENHA="${1:?informe a senha de bootstrap}"
# Mesmo nome para o instalador (host) e para os agentes das lojas.
URL="https://${RANCHER_HOST:-rancher.lab.internal}"

api() {
  curl -fsS --cacert "${CACHE}/ca.crt" --retry 12 --retry-delay 10 --retry-all-errors \
    -H 'Content-Type: application/json' "$@"
}

esperar 600 "API do Rancher" api "${URL}/ping"

# Sessao local de login (expira); nao e publicada em lugar nenhum.
sessao="$(api -X POST "${URL}/v3-public/localProviders/local?action=login" \
  -d "$(jq -cn --arg s "${SENHA}" '{username: "admin", password: $s, responseType: "json", ttl: 3600000}')" | jq -r .token)"
[[ -n "${sessao}" && "${sessao}" != "null" ]] || falha "login no Rancher recusado"
auth=(-H "Authorization: Bearer ${sessao}")

api -X PUT "${URL}/v3/settings/server-url" "${auth[@]}" \
  -d "$(jq -cn --arg v "${URL}" '{name: "server-url", value: $v}')" >/dev/null
aws --endpoint-url http://localhost:4566 ssm put-parameter --overwrite \
  --name /frota/rancher/url --type String --value "${URL}" >/dev/null

lojas="$(tf 10-frota output -json lojas)"
for loja in $(jq -r 'keys[]' <<<"${lojas}"); do
  caminho="/v1/provisioning.cattle.io.clusters/fleet-default/${loja}"
  if ! api "${auth[@]}" "${URL}${caminho}" >/dev/null 2>&1; then
    labels="$(jq -c --arg l "${loja}" '.[$l] | {loja: $l, regiao, perfil, ambiente: "lab"}
      + (if (.ip_lan // "") != "" then {"ip-lan": .ip_lan} else {} end)' <<<"${lojas}")"
    api -X POST "${auth[@]}" "${URL}/v1/provisioning.cattle.io.clusters" -d "$(jq -cn \
      --arg nome "${loja}" --argjson labels "${labels}" \
      '{type: "provisioning.cattle.io.cluster",
        metadata: {namespace: "fleet-default", name: $nome, labels: $labels}, spec: {}}')" >/dev/null
  fi
  # O Rancher cria o id interno e o token de registro alguns segundos depois.
  manifesto=""
  limite=$((SECONDS + 180))
  until [[ -n "${manifesto}" ]]; do
    (( SECONDS > limite )) && falha "Rancher nao gerou o registro de ${loja}"
    id="$(api "${auth[@]}" "${URL}${caminho}" | jq -r '.status.clusterName // empty')"
    [[ -n "${id}" ]] && manifesto="$(api "${auth[@]}" "${URL}/v3/clusterregistrationtokens?clusterId=${id}" |
      jq -r '.data[0].manifestUrl // empty')"
    [[ -n "${manifesto}" ]] || sleep 5
  done
  aws --endpoint-url http://localhost:4566 ssm put-parameter --overwrite \
    --name "/frota/lojas/${loja}/registro" --type SecureString --value "${manifesto}" >/dev/null
  echo "${loja}: registro publicado em /frota/lojas/${loja}/registro"
done
