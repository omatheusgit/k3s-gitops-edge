#!/usr/bin/env bash
# Simula o servidor de uma loja com k3d e roda o instalador de verdade nele.
#   ./loja.sh up loja-001 [porta]    (porta HTTP no host, padrao 8080)
#   ./loja.sh down loja-001
# shellcheck source=comum.sh
source "$(dirname "${BASH_SOURCE[0]}")/comum.sh"

subir() {
  local loja="$1" porta="${2:-8080}"
  precisa docker k3d kubectl helm jq aws terraform
  [[ -f "${CACHE}/modo-central" ]] || falha "suba a central antes (./central.sh up fleet|rancher)"

  local kcfg="${CACHE}/${loja}.kubeconfig"
  if ! k3d cluster list "${loja}" >/dev/null 2>&1; then
    passo "criando cluster ${loja} (HTTP em localhost:${porta})"
    k3d cluster create "${loja}" --image "${K3S_IMAGEM}" --network "${REDE}" \
      --servers 1 --agents 0 -p "127.0.0.1:${porta}:80@loadbalancer" \
      --k3s-arg "--disable=metrics-server@server:0" \
      --kubeconfig-update-default=false --wait --timeout 180s >/dev/null
  fi
  k3d kubeconfig get "${loja}" >"${kcfg}"
  chmod 600 "${kcfg}"

  # A imagem dos eventos e construida localmente; em producao vem do GHCR.
  passo "importando a imagem ${EVENTOS_IMAGEM}"
  docker image inspect "${EVENTOS_IMAGEM}" >/dev/null 2>&1 ||
    docker build -q -t "${EVENTOS_IMAGEM}" "${RAIZ}/src/eventos" >/dev/null
  k3d image import -c "${loja}" "${EVENTOS_IMAGEM}" >/dev/null

  local dados
  dados="$(tf 10-frota output -json)"
  passo "rodando o instalador (modo $(cat "${CACHE}/modo-central"))"
  KUBECONFIG="${kcfg}" \
  SEM_K3S=1 SIM=1 SEM_TUI=1 AMBIENTE=lab \
  ESTADO_DIR="${CACHE}/estado-${loja}" \
  MODO_CENTRAL="$(cat "${CACHE}/modo-central")" \
  AWS_ENDPOINT_URL=http://localhost:4566 RANCHER_INSEGURO=1 \
  LOJA_ID="${loja}" \
  REGIAO="$(jq -r --arg l "${loja}" '.lojas.value[$l].regiao' <<<"${dados}")" \
  PERFIL="$(jq -r --arg l "${loja}" '.lojas.value[$l].perfil' <<<"${dados}")" \
  LOJA_ACCESS_KEY_ID="$(jq -r --arg l "${loja}" '.credenciais.value[$l].access_key_id' <<<"${dados}")" \
  LOJA_SECRET_ACCESS_KEY="$(jq -r --arg l "${loja}" '.credenciais.value[$l].secret_access_key' <<<"${dados}")" \
    "${RAIZ}/installer/instalar.sh" instalar
}

case "${1:-}" in
  up) subir "${2:?informe a loja}" "${3:-8080}" ;;
  down) k3d cluster delete "${2:?informe a loja}" >/dev/null 2>&1 || true ;;
  *) echo "uso: $0 up|down <loja> [porta]" >&2; exit 1 ;;
esac
