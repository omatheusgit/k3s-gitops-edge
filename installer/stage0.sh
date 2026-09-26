#!/usr/bin/env bash
# Primeiro passo no servidor novo. Baixa o pacote do instalador do bucket
# privado usando a chave da propria loja, confere o sha256 e abre o menu.
#
#   curl -fsSL <url-do-stage0> | sudo -E bash
#   (ou) sudo -E ./stage0.sh
#
# Variaveis: VERSAO (padrao: latest), BUCKET, LOJA_ACCESS_KEY_ID,
# LOJA_SECRET_ACCESS_KEY, AWS_ENDPOINT_URL (laboratorio).
set -euo pipefail

VERSAO="${VERSAO:-latest}"
BUCKET="${BUCKET:-k3s-gitops-edge-instalador}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DESTINO="${DESTINO:-/opt/loja-instalador}"

# /dev/tty pode existir sem terminal de controle (cron, CI, docker sem -t).
tem_tty() { { : </dev/tty; } 2>/dev/null; }

tty_ler() {
  # Rodando via pipe, o stdin e o proprio script; as perguntas vao para o tty.
  local var="$1" texto="$2" oculto="${3:-}"
  [[ -n "${!var:-}" ]] && return 0
  tem_tty || { echo "${var} nao informado e sem terminal para perguntar" >&2; exit 1; }
  if [[ -n "${oculto}" ]]; then read -r -s -p "${texto}: " "${var?}" </dev/tty; echo >&2
  else read -r -p "${texto}: " "${var?}" </dev/tty; fi
}

tentar() {
  local n=1 espera=2
  until "$@"; do
    (( n >= 4 )) && return 1
    echo "falhou (tentativa ${n}/4), nova tentativa em ${espera}s" >&2
    sleep "${espera}"; n=$((n + 1)); espera=$((espera * 2))
  done
}

command -v aws >/dev/null || { echo "instale o aws cli v2 antes" >&2; exit 1; }
tty_ler LOJA_ACCESS_KEY_ID "Access key da loja"
tty_ler LOJA_SECRET_ACCESS_KEY "Secret key da loja" oculto
export LOJA_ACCESS_KEY_ID LOJA_SECRET_ACCESS_KEY AWS_REGION

s3() {
  AWS_ACCESS_KEY_ID="${LOJA_ACCESS_KEY_ID}" AWS_SECRET_ACCESS_KEY="${LOJA_SECRET_ACCESS_KEY}" \
    aws --region "${AWS_REGION}" s3 "$@"
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

prefixo="s3://${BUCKET}/releases/${VERSAO}"
tentar s3 cp --only-show-errors "${prefixo}/instalador.tar.gz" "${tmp}/"
tentar s3 cp --only-show-errors "${prefixo}/instalador.tar.gz.sha256" "${tmp}/"
(cd "${tmp}" && sha256sum --check --strict instalador.tar.gz.sha256) ||
  { echo "pacote corrompido ou adulterado; abortando" >&2; exit 1; }

rm -rf "${DESTINO}"
install -d -m 750 "${DESTINO}"
tar -xzf "${tmp}/instalador.tar.gz" -C "${DESTINO}"

if tem_tty; then
  exec "${DESTINO}/installer/instalar.sh" "$@" </dev/tty
else
  exec "${DESTINO}/installer/instalar.sh" "$@"
fi
