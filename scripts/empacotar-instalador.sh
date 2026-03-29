#!/usr/bin/env bash
# Gera dist/instalador.tar.gz e o .sha256 no formato que o stage0 confere.
#   scripts/empacotar-instalador.sh <versao> [destino]
set -euo pipefail

VERSAO="${1:?informe a versao (ex.: v1.0.0)}"
DESTINO="${2:-dist}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "${DESTINO}"
printf '%s\n' "${VERSAO}" >"${RAIZ}/installer/VERSAO"
tar -czf "${DESTINO}/instalador.tar.gz" -C "${RAIZ}" \
  --owner=0 --group=0 --sort=name --mtime='2026-01-01 00:00Z' installer
rm -f "${RAIZ}/installer/VERSAO"
(cd "${DESTINO}" && sha256sum instalador.tar.gz >instalador.tar.gz.sha256)
cat "${DESTINO}/instalador.tar.gz.sha256"
