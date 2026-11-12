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
  local -a extra=()
  if [[ "$(cat "${CACHE}/modo-central")" == "rancher" ]]; then
    # O agente do Rancher na loja precisa achar a central pelo mesmo nome do certificado.
    local ip
    ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${REDE}\").IPAddress}}" k3d-central-server-0)"
    extra=(--host-alias "${ip}:${RANCHER_HOST:-rancher.lab.internal}")
    # O instalador confere o certificado do Rancher com a CA do lab.
    export CURL_CA_BUNDLE="${CACHE}/ca.crt"
  fi
  if ! k3d cluster list "${loja}" >/dev/null 2>&1; then
    passo "criando cluster ${loja} (HTTP em localhost:${porta})"
    k3d cluster create "${loja}" --image "${K3S_IMAGEM}" --network "${REDE}" \
      --servers 1 --agents 0 -p "127.0.0.1:${porta}:80@loadbalancer" \
      --k3s-arg "--disable=metrics-server@server:0" "${extra[@]}" \
      -v "${RAIZ}/installer/etc/k3s-loja.yaml:/etc/rancher/k3s/config.yaml.d/10-loja.yaml@server:0" \
      --kubeconfig-update-default=false --wait --timeout 180s >/dev/null
  fi
  k3d kubeconfig get "${loja}" >"${kcfg}"
  chmod 600 "${kcfg}"

  # A imagem dos eventos e construida localmente; em producao vem do GHCR.
  # Build sempre (o cache de camadas deixa barato): com "so se nao existir",
  # mudanca em src/eventos nao chegava ao lab.
  passo "importando a imagem ${EVENTOS_IMAGEM}"
  docker build -q -t "${EVENTOS_IMAGEM}" "${RAIZ}/src/eventos" >/dev/null
  # O k3d image import devolve 0 mesmo quando o containerd do no recusa.
  local tentativa
  for tentativa in 1 2 3; do
    k3d image import -c "${loja}" "${EVENTOS_IMAGEM}" >/dev/null 2>&1 || true
    docker exec "k3d-${loja}-server-0" crictl inspecti "${EVENTOS_IMAGEM}" >/dev/null 2>&1 && break
    (( tentativa == 3 )) && falha "a imagem ${EVENTOS_IMAGEM} nao entrou no no da ${loja}"
    sleep 5
  done

  local dados
  dados="$(tf 10-frota output -json)"
  passo "rodando o instalador (modo $(cat "${CACHE}/modo-central"))"
  KUBECONFIG="${kcfg}" \
  SEM_K3S=1 SIM=1 SEM_TUI=1 AMBIENTE=lab \
  ESTADO_DIR="${CACHE}/estado-${loja}" \
  MODO_CENTRAL="$(cat "${CACHE}/modo-central")" \
  AWS_ENDPOINT_URL=http://localhost:4566 \
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
