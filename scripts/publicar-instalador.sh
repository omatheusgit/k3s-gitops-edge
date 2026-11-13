#!/usr/bin/env bash
# Copia para o bucket do instalador (releases/<versao>/)
# exatamente o pacote que o workflow release.yml construiu e assinou, depois
# de conferir a assinatura com o mesmo codigo do stage0. Nada e empacotado
# na maquina de quem publica (#32).
#   scripts/publicar-instalador.sh v1.3.0
# Use AWS_ENDPOINT_URL=http://localhost:4566 no laboratorio.
set -euo pipefail

VERSAO="${1:?informe a versao (ex.: v1.3.0)}"
BUCKET="${BUCKET:-k3s-gitops-edge-instalador}"
REPO="${REPO:-omatheusgit/k3s-gitops-edge}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$(mktemp -d)"
trap 'rm -rf "${DIST}"' EXIT

ARQUIVOS=(instalador.tar.gz instalador.tar.gz.sha256 instalador.tar.gz.sigstore.json)
for arquivo in "${ARQUIVOS[@]}"; do
  curl -fsSL --retry 3 -o "${DIST}/${arquivo}" \
    "https://github.com/${REPO}/releases/download/${VERSAO}/${arquivo}"
done

# shellcheck source=../installer/stage0.sh
STAGE0_BIBLIOTECA=1 source "${RAIZ}/installer/stage0.sh"
garantir_cosign "${DIST}"
verificar_assinatura "${DIST}/cosign" "${DIST}/instalador.tar.gz" "${DIST}/instalador.tar.gz.sigstore.json" ||
  { echo "assinatura do pacote ${VERSAO} nao confere; nada publicado" >&2; exit 1; }

# So releases/<versao>: o stage0 exige versao explicita (sem latest).
for arquivo in "${ARQUIVOS[@]}"; do
  aws s3 cp --only-show-errors "${DIST}/${arquivo}" "s3://${BUCKET}/releases/${VERSAO}/${arquivo}"
done
echo "publicado em s3://${BUCKET}/releases/${VERSAO}/ (assinatura conferida)"
