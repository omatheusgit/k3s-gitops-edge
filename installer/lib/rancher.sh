# shellcheck shell=bash
# Registro no Rancher. A central ja criou o cluster desta loja (com os labels,
# que o Fleet usa para escolher os bundles) e publicou a URL do manifesto do
# agente em /frota/lojas/<id>/registro. O token dentro dessa URL so registra
# este cluster: o instalador nao tem, nem precisa de, acesso a API do Rancher.

manifesto_rancher() {
  local url
  url="$(parametro "lojas/${LOJA_ID}/registro")"
  [[ "${url}" == https://* ]] || morrer "a central ainda nao publicou o registro de ${LOJA_ID} (/frota/lojas/${LOJA_ID}/registro)"
  printf '%s' "${url}"
}

aplicar_agente_rancher() {
  local url
  url="$(manifesto_rancher)"
  # Certificado nao conferido so no laboratorio (CA propria do lab).
  if [[ -n "${RANCHER_INSEGURO:-}" && "${AMBIENTE:-producao}" != lab ]]; then
    morrer "RANCHER_INSEGURO so e aceito com AMBIENTE=lab"
  fi
  curl -fsS ${RANCHER_INSEGURO:+-k} --retry 6 --retry-delay 10 --retry-all-errors "${url}" | kubectl apply -f -
}

esperar_agente_rancher() {
  # O agente conecta na central sozinho; daqui so da para ver que ele subiu.
  local limite=$((SECONDS + TIMEOUT_REGISTRO))
  until kubectl -n cattle-system get deploy cattle-cluster-agent >/dev/null 2>&1; do
    (( SECONDS > limite )) && return 1
    sleep 5
  done
  kubectl -n cattle-system rollout status deploy/cattle-cluster-agent --timeout="$(( limite - SECONDS ))s"
}
