#!/usr/bin/env bash
# Atlantis local: comenta plan/apply nos PRs que mexem no Terraform, aplicando
# no LocalStack. O webhook do GitHub chega pelo "gh webhook forward", entao
# nao precisa expor porta nem tunel.
#
# Pre-requisito (uma vez): um GitHub App para o Atlantis comentar com
# identidade propria, nao a sua. O lab/atlantis-app.py cria o App e salva
# app-id, app-slug, app.pem e webhook-secret em lab/.cache/atlantis/.
#   ./atlantis.sh up | down
# shellcheck source=comum.sh
source "$(dirname "${BASH_SOURCE[0]}")/comum.sh"

IMAGEM="ghcr.io/runatlantis/atlantis:v0.49.0"
DIR="${CACHE}/atlantis"
# Repo do origin (funciona em fork ou em repo de ensaio).
REPO="github.com/$(git -C "${RAIZ}" remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"

subir() {
  precisa docker gh
  for f in app-id app-slug app.pem webhook-secret; do
    [[ -s "${DIR}/${f}" ]] || falha "falta ${DIR}/${f} (veja o cabecalho deste script)"
  done
  garantir_rede
  docker rm -f atlantis >/dev/null 2>&1 || true
  # A chave vai por variavel: o Atlantis roda com outro UID e o arquivo e 600.
  docker run -d --name atlantis --network "${REDE}" -p 127.0.0.1:4141:4141 \
    -e ATLANTIS_GH_APP_ID="$(cat "${DIR}/app-id")" \
    -e ATLANTIS_GH_APP_KEY="$(cat "${DIR}/app.pem")" \
    -e ATLANTIS_GH_APP_SLUG="$(cat "${DIR}/app-slug")" \
    -e ATLANTIS_GH_WEBHOOK_SECRET="$(cat "${DIR}/webhook-secret")" \
    -e ATLANTIS_REPO_ALLOWLIST="${REPO}" \
    -e ATLANTIS_WRITE_GIT_CREDS=true \
    -e ATLANTIS_ATLANTIS_URL=http://localhost:4141 \
    -e ATLANTIS_DEFAULT_TF_VERSION=1.9.8 \
    -e ATLANTIS_REPO_CONFIG_JSON='{"repos":[{"id":"/.*/","allowed_overrides":["workflow","apply_requirements"],"allow_custom_workflows":true}]}' \
    -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_DEFAULT_REGION=us-east-1 \
    --memory 512m "${IMAGEM}" server >/dev/null
  esperar 180 "Atlantis no ar" curl -fs http://localhost:4141/healthz

  gh extension list | grep -q cli/gh-webhook || gh extension install cli/gh-webhook >/dev/null
  passo "repassando webhooks do GitHub para o Atlantis (Ctrl+C para parar)"
  gh webhook forward --repo="${REPO#github.com/}" \
    --events=issue_comment,pull_request,pull_request_review,push \
    --url=http://localhost:4141/events --secret="$(cat "${DIR}/webhook-secret")"
}

case "${1:-}" in
  up) subir ;;
  down) docker rm -f atlantis >/dev/null 2>&1 || true ;;
  *) echo "uso: $0 up|down" >&2; exit 1 ;;
esac
