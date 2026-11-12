#!/usr/bin/env bash
# Aplica os dados de demonstracao (lab/semente.sql) numa loja do laboratorio.
# Idempotente; espera a API ficar pronta, ou seja, as migracoes terem rodado.
#   ./semente.sh loja-001
set -euo pipefail

LOJA="${1:-loja-001}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${RAIZ}/lab/.cache/${LOJA}.kubeconfig"

limite=$((SECONDS + 900))
until kubectl -n loja get deploy api >/dev/null 2>&1; do
  (( SECONDS > limite )) && { echo "a API da ${LOJA} nao apareceu em 15 min" >&2; exit 1; }
  sleep 5
done
kubectl -n loja wait --for=condition=Available deploy/api --timeout=15m >/dev/null
kubectl -n loja exec -i postgres-0 -- psql -U postgres -d loja -v ON_ERROR_STOP=1 -q <"${RAIZ}/lab/semente.sql" >/dev/null
echo "semente aplicada na ${LOJA}"
