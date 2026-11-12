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

# Servidor recem-instalado: traz curl, jq e o aws cli pelo gerenciador do
# sistema (o aws cli v1 do Debian basta para s3, ssm e sts).
garantir_dependencias() {
  local faltando=()
  for cmd in curl jq aws; do command -v "${cmd}" >/dev/null || faltando+=("${cmd}"); done
  (( ${#faltando[@]} == 0 )) && return 0
  command -v apt-get >/dev/null || { echo "instale antes: ${faltando[*]}" >&2; exit 1; }
  (( EUID == 0 )) || { echo "rode com sudo para instalar: ${faltando[*]}" >&2; exit 1; }
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends ca-certificates curl jq >/dev/null
  if ! command -v aws >/dev/null; then
    if apt-cache show awscli >/dev/null 2>&1; then
      apt-get install -y -qq --no-install-recommends awscli >/dev/null
    elif command -v snap >/dev/null; then
      snap install aws-cli --classic >/dev/null
    else
      echo "instale o aws cli antes" >&2; exit 1
    fi
  fi
}
garantir_dependencias
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
