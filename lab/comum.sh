# Funcoes e nomes compartilhados pelos scripts do laboratorio.
# shellcheck shell=bash disable=SC2034  # variaveis usadas por quem faz source
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${RAIZ}/lab/.cache"
REDE="k3s-gitops-edge"
LOCALSTACK_IMAGEM="localstack/localstack:3.8"
K3S_IMAGEM="rancher/k3s:v1.35.5-k3s1"
EVENTOS_IMAGEM="ghcr.io/omatheusgit/k3s-gitops-edge/eventos:0.1.0"

AWS_CLI_IMAGEM="amazon/aws-cli:2.40.0"

export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
mkdir -p "${CACHE}/bin"

# O lab usa o aws cli oficial em container, para nao depender do que esta
# instalado na maquina. O shim fica em lab/.cache/bin e vai na frente do PATH.
if [[ ! -x "${CACHE}/bin/aws" ]]; then
  cat >"${CACHE}/bin/aws" <<'SHIM'
#!/usr/bin/env bash
exec docker run --rm -i --network host \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
  -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_ENDPOINT_URL \
  -e AWS_RETRY_MODE -e AWS_MAX_ATTEMPTS \
  -v "${PWD}:/aws" IMAGEM "$@"
SHIM
  sed -i "s#IMAGEM#${AWS_CLI_IMAGEM}#" "${CACHE}/bin/aws"
  chmod +x "${CACHE}/bin/aws"
fi
export PATH="${CACHE}/bin:${PATH}"

passo() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m[!] %s\033[0m\n' "$*" >&2; }
falha() { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

precisa() {
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || falha "comando obrigatorio ausente: ${cmd}"
  done
}

garantir_rede() {
  docker network inspect "${REDE}" >/dev/null 2>&1 || docker network create "${REDE}" >/dev/null
}

# Espera um comando dar certo, com limite de tempo.
esperar() {
  local limite="$1" descricao="$2"
  shift 2
  local inicio=${SECONDS}
  until "$@" >/dev/null 2>&1; do
    (( SECONDS - inicio > limite )) && falha "tempo esgotado: ${descricao}"
    sleep 3
  done
}

tf() {
  terraform -chdir="${RAIZ}/terraform/$1" "${@:2}"
}
