# shellcheck shell=bash
# Importa o cluster da loja no Rancher pela API (provisioning v1) e aplica o
# manifesto do agente. Os labels viram labels do Cluster no Fleet, e e por
# eles que os bundles escolhem o que instalar em cada loja.

rancher_api() {
  local metodo="$1" caminho="$2"; shift 2
  curl -fsS ${RANCHER_INSEGURO:+-k} --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 3 \
    -X "${metodo}" "${RANCHER_URL}${caminho}" \
    -H "Authorization: Bearer ${RANCHER_TOKEN}" -H 'Content-Type: application/json' "$@"
}

labels_json() {
  jq -cn --arg loja "${LOJA_ID}" --arg regiao "${REGIAO}" --arg perfil "${PERFIL}" \
    --arg ambiente "${AMBIENTE:-producao}" --arg ip "${IP_LAN:-}" \
    '{loja: $loja, regiao: $regiao, perfil: $perfil, ambiente: $ambiente}
     + (if $ip != "" then {"ip-lan": $ip} else {} end)'
}

garantir_cluster_rancher() {
  local caminho="/v1/provisioning.cattle.io.clusters/fleet-default/${LOJA_ID}"
  if rancher_api GET "${caminho}" >/dev/null 2>&1; then
    info "cluster ${LOJA_ID} ja existe no Rancher; reaproveitando"
    return 0
  fi
  rancher_api POST /v1/provisioning.cattle.io.clusters --data "$(jq -cn \
    --arg nome "${LOJA_ID}" --argjson labels "$(labels_json)" \
    '{type: "provisioning.cattle.io.cluster",
      metadata: {namespace: "fleet-default", name: $nome, labels: $labels},
      spec: {}}')" >/dev/null
}

id_cluster_rancher() {
  rancher_api GET "/v1/provisioning.cattle.io.clusters/fleet-default/${LOJA_ID}" |
    jq -r '.status.clusterName // empty'
}

aplicar_agente_rancher() {
  local id="" manifesto="" limite=$((SECONDS + 120))
  # O Rancher cria o token de registro alguns segundos depois do cluster.
  until [[ -n "${manifesto}" ]]; do
    (( SECONDS > limite )) && return 1
    id="${id:-$(id_cluster_rancher)}"
    [[ -n "${id}" ]] && manifesto="$(rancher_api GET "/v3/clusterregistrationtokens?clusterId=${id}" |
      jq -r '.data[0].manifestUrl // empty')"
    [[ -n "${manifesto}" ]] || sleep 5
  done
  curl -fsS ${RANCHER_INSEGURO:+-k} --retry 3 "${manifesto}" | kubectl apply -f -
}

esperar_cluster_ativo() {
  local limite=$((SECONDS + TIMEOUT_REGISTRO))
  until [[ "$(rancher_api GET "/v1/provisioning.cattle.io.clusters/fleet-default/${LOJA_ID}" |
              jq -r '.status.ready // false')" == "true" ]]; do
    (( SECONDS > limite )) && return 1
    sleep 10
  done
}
