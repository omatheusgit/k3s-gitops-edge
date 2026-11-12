#!/usr/bin/env bash
# Rotacao de segredo, do jeito que se faria em producao: troca a chave do
# webhook no Secrets Manager, o External Secrets atualiza o Secret, o gateway
# reinicia e passa a aceitar so a chave nova.
#   ./rotacao.sh loja-001 [porta]
set -euo pipefail

LOJA="${1:-loja-001}"
PORTA="${2:-8080}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../comum.sh
source "${RAIZ}/lab/comum.sh"
export KUBECONFIG="${CACHE}/${LOJA}.kubeconfig"
WEBHOOK="http://webhook.localhost:${PORTA}/pagamentos/confirmacao"
SEGREDO_AWS="lojas/${LOJA}/app"
aws_lab() { aws --endpoint-url http://localhost:4566 "$@"; }

segredo_k8s() { kubectl -n loja get secret loja-segredos -o jsonpath='{.data.webhook_hmac}' | base64 -d; }
status_webhook() {
  local chave="$1" corpo ts assinatura
  corpo="$(jq -cn --arg e "rotacao-$RANDOM-$(date +%s%N)" '{evento_id: $e, venda_id: "00000000-0000-0000-0000-000000000000", valor_centavos: 1, status: "aprovado"}')"
  ts="$(date +%s)"
  assinatura="sha256=$(printf '%s.%s' "${ts}" "${corpo}" | openssl dgst -sha256 -hmac "${chave}" -r | cut -d' ' -f1)"
  curl -s -o /dev/null -w '%{http_code}' -X POST "${WEBHOOK}" -H 'Content-Type: application/json' \
    -H "X-Timestamp: ${ts}" -H "X-Assinatura: ${assinatura}" -d "${corpo}"
}

ANTIGA="$(segredo_k8s)"
NOVA="$(openssl rand -hex 24)"
echo "Rotacao da chave do webhook da ${LOJA}"
[[ "$(status_webhook "${ANTIGA}")" == 202 ]] || falha "a chave atual nao era aceita antes da rotacao"

atual="$(aws_lab secretsmanager get-secret-value --secret-id "${SEGREDO_AWS}" --query SecretString --output text)"
aws_lab secretsmanager put-secret-value --secret-id "${SEGREDO_AWS}" \
  --secret-string "$(jq -c --arg n "${NOVA}" '.webhook_hmac = $n' <<<"${atual}")" >/dev/null
kubectl -n loja annotate externalsecret loja-segredos force-sync="$(date +%s)" --overwrite >/dev/null
esperar 120 "Secret com a chave nova" bash -c "[[ \"\$(kubectl -n loja get secret loja-segredos -o jsonpath='{.data.webhook_hmac}' | base64 -d)\" == '${NOVA}' ]]"
# O gateway le a chave ao subir: reiniciar faz parte da rotacao.
kubectl -n loja rollout restart deploy/webhook-gateway >/dev/null
kubectl -n loja rollout status deploy/webhook-gateway --timeout=3m >/dev/null

nova="$(status_webhook "${NOVA}")"; antiga="$(status_webhook "${ANTIGA}")"
echo "  chave nova: HTTP ${nova} (esperado 202); chave antiga: HTTP ${antiga} (esperado 401)"
[[ "${nova}" == 202 && "${antiga}" == 401 ]] || falha "rotacao nao surtiu efeito"
echo "rotacao ok"
