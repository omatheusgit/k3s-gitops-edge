# shellcheck shell=bash
# Modo sem Rancher: a central roda so o Fleet, e a loja instala o fleet-agent
# com o token de registro desta loja, publicado pela central no SSM
# (/frota/lojas/<id>/registro). Um token por loja: o de uma nao registra outra.

registrar_fleet() {
  local valores rc=0
  valores="$(mktemp)"
  # O arquivo tem o token de registro: sai em qualquer caminho, inclusive erro.
  trap 'rm -f "${valores}"' RETURN
  parametro "lojas/${LOJA_ID}/registro" >"${valores}"
  grep -q '^token:' "${valores}" || morrer "a central ainda nao publicou o registro de ${LOJA_ID}"
  local -a labels=(
    --set-string "labels.loja=${LOJA_ID}"
    --set-string "labels.regiao=${REGIAO}"
    --set-string "labels.perfil=${PERFIL}"
    --set-string "labels.ambiente=${AMBIENTE:-producao}"
  )
  [[ -n "${IP_LAN:-}" ]] && labels+=(--set-string "labels.ip-lan=${IP_LAN}")
  helm repo add fleet https://rancher.github.io/fleet-helm-charts/ --force-update >/dev/null
  helm upgrade --install fleet-agent fleet/fleet-agent --version "${FLEET_VERSAO}" \
    -n cattle-fleet-system --create-namespace --wait --timeout 5m \
    --values "${valores}" "${labels[@]}" --set-string "clientID=${LOJA_ID}" || rc=$?
  return "${rc}"
}
