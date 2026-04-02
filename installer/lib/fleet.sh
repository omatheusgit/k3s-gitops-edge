# shellcheck shell=bash
# Modo sem Rancher: a central roda so o Fleet, e a loja instala o fleet-agent
# com o token de registro guardado no SSM (/frota/fleet/registro).

registrar_fleet() {
  local valores
  valores="$(mktemp)"
  parametro fleet/registro >"${valores}"
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
    --values "${valores}" "${labels[@]}" --set-string "clientID=${LOJA_ID}"
  local rc=$?
  rm -f "${valores}"
  return "${rc}"
}
