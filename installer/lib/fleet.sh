# shellcheck shell=bash
# Modo sem Rancher: a central roda so o Fleet, e a loja instala o fleet-agent
# com o token de registro desta loja, publicado pela central no SSM
# (/frota/lojas/<id>/registro). Um token por loja: o de uma nao registra outra.

# Chart do fleet-agent na versao fixa, conferido por sha256 antes de instalar.
#   baixar_chart_fleet <diretorio>   -> deixa o .tgz em <diretorio>
baixar_chart_fleet() {
  local dir="$1"
  helm pull fleet-agent --repo https://rancher.github.io/fleet-helm-charts/ \
    --version "${FLEET_VERSAO}" -d "${dir}" >/dev/null
  echo "${FLEET_CHART_SHA256}  ${dir}/fleet-agent-${FLEET_VERSAO}.tgz" | sha256sum --check --strict --quiet
}

registrar_fleet() {
  local valores rc=0
  valores="$(mktemp)"
  # O arquivo tem o token de registro: sai em qualquer caminho, inclusive erro.
  trap 'rm -f "${valores}"' RETURN
  parametro "lojas/${LOJA_ID}/registro" >"${valores}"
  grep -q '^token:' "${valores}" || morrer "a central ainda nao publicou o registro de ${LOJA_ID}"
  grep -q '^clientID:' "${valores}" || morrer "o registro de ${LOJA_ID} nao tem clientID (central desatualizada)"
  # Labels e identidade vem do Cluster que a central criou; o agente nao
  # declara os proprios (senao uma loja se diria de outro perfil ou ambiente).
  local dir_chart
  dir_chart="$(mktemp -d)"
  baixar_chart_fleet "${dir_chart}" ||
    { rm -rf -- "${dir_chart:?}"; morrer "chart fleet-agent ${FLEET_VERSAO} nao confere com o sha256 esperado"; }
  helm upgrade --install fleet-agent "${dir_chart}/fleet-agent-${FLEET_VERSAO}.tgz" \
    -n cattle-fleet-system --create-namespace --wait --timeout 5m \
    --values "${valores}" || rc=$?
  rm -rf -- "${dir_chart:?}"
  return "${rc}"
}
