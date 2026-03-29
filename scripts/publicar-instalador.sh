#!/usr/bin/env bash
# Envia o pacote para o bucket do instalador em releases/<versao>/ e
# releases/latest/. Use AWS_ENDPOINT_URL=http://localhost:4566 no laboratorio.
#   scripts/publicar-instalador.sh <versao>
set -euo pipefail

VERSAO="${1:?informe a versao (ex.: v1.0.0)}"
BUCKET="${BUCKET:-k3s-gitops-edge-instalador}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$(mktemp -d)"
trap 'rm -rf "${DIST}"' EXIT

"${RAIZ}/scripts/empacotar-instalador.sh" "${VERSAO}" "${DIST}" >/dev/null
for prefixo in "releases/${VERSAO}" releases/latest; do
  for arquivo in instalador.tar.gz instalador.tar.gz.sha256; do
    aws s3 cp --only-show-errors "${DIST}/${arquivo}" "s3://${BUCKET}/${prefixo}/${arquivo}"
  done
done
echo "publicado em s3://${BUCKET}/releases/${VERSAO}/"
