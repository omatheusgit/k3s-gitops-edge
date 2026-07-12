#!/usr/bin/env bash
# Servidor git somente leitura para o Fleet ler a branch local.
# shellcheck source=comum.sh
source "$(dirname "${BASH_SOURCE[0]}")/comum.sh"

case "${1:-}" in
  up)
    garantir_rede
    docker image inspect k3s-gitops-edge/git-lab:local >/dev/null 2>&1 ||
      docker build -q -t k3s-gitops-edge/git-lab:local "${RAIZ}/lab/git" >/dev/null
    if ! docker ps --format '{{.Names}}' | grep -qx git-lab; then
      docker rm -f git-lab >/dev/null 2>&1 || true
      docker run -d --name git-lab --network "${REDE}" \
        -v "${RAIZ}:/srv/k3s-gitops-edge:ro" k3s-gitops-edge/git-lab:local >/dev/null
    fi
    ;;
  down) docker rm -f git-lab >/dev/null 2>&1 || true ;;
  *) echo "uso: $0 up|down" >&2; exit 1 ;;
esac
