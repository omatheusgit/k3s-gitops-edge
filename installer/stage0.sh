#!/usr/bin/env bash
# Primeiro passo no servidor novo. Baixa o pacote do instalador do bucket
# privado usando a chave da propria loja, confere a assinatura (Sigstore) e
# abre o menu. So roda pacote assinado pelo workflow release.yml deste
# repositorio numa tag de versao: quem tiver escrita no bucket nao consegue
# trocar o pacote (#32).
#
#   curl -fsSL <url-do-stage0> | sudo -E bash
#   (ou) sudo -E ./stage0.sh
#
# Variaveis: VERSAO (obrigatoria, ex.: v1.3.0), BUCKET, LOJA_ACCESS_KEY_ID,
# LOJA_SECRET_ACCESS_KEY, AWS_ENDPOINT_URL (laboratorio).
set -euo pipefail

# Versao explicita: com "latest", quem escreve no bucket podia trocar por uma
# versao antiga, assinada e vulneravel. A versao pedida tem que bater com a
# que vem dentro do pacote assinado.
VERSAO="${VERSAO:-}"
BUCKET="${BUCKET:-k3s-gitops-edge-instalador}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DESTINO="${DESTINO:-/opt/loja-instalador}"

# Quem pode assinar o pacote: o workflow de release deste repositorio, numa
# tag vX.Y.Z, com a identidade OIDC do GitHub Actions.
IDENTIDADE='^https://github\.com/omatheusgit/k3s-gitops-edge/\.github/workflows/release\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$'
REPOSITORIO="omatheusgit/k3s-gitops-edge"
# Outra identidade so no ensaio do proprio release.yml (STAGE0_LAB=1); em
# producao a variavel e ignorada, mesmo com sudo -E.
if [[ "${STAGE0_LAB:-0}" == 1 && -n "${STAGE0_IDENTIDADE:-}" ]]; then IDENTIDADE="${STAGE0_IDENTIDADE}"; fi
EMISSOR="https://token.actions.githubusercontent.com"
COSIGN_VERSAO="v3.1.3"
COSIGN_SHA256="4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71"

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
# cosign em versao fixa, conferido por sha256 antes de ser executado.
garantir_cosign() {
  local destino="$1"
  curl -fsSL --retry 3 -o "${destino}/cosign" \
    "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSAO}/cosign-linux-amd64"
  echo "${COSIGN_SHA256}  ${destino}/cosign" | sha256sum --check --strict --quiet ||
    { echo "cosign baixado nao confere com o sha256 esperado; abortando" >&2; exit 1; }
  chmod 755 "${destino}/cosign"
}

verificar_assinatura() {
  local cosign="$1" pacote="$2" bundle="$3"
  "${cosign}" verify-blob --bundle "${bundle}" \
    --certificate-identity-regexp "${IDENTIDADE}" \
    --certificate-github-workflow-repository "${REPOSITORIO}" \
    --certificate-oidc-issuer "${EMISSOR}" "${pacote}" >/dev/null 2>&1
}

# Testes (e publicar-instalador.sh) carregam so as funcoes.
[[ "${STAGE0_BIBLIOTECA:-0}" == 1 ]] && return 0

[[ "${VERSAO}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "informe VERSAO=vX.Y.Z (sem latest)" >&2; exit 1; }
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
tentar s3 cp --only-show-errors "${prefixo}/instalador.tar.gz.sigstore.json" "${tmp}/"
garantir_cosign "${tmp}"
verificar_assinatura "${tmp}/cosign" "${tmp}/instalador.tar.gz" "${tmp}/instalador.tar.gz.sigstore.json" ||
  { echo "assinatura do pacote nao confere (nao veio do release.yml deste repositorio); abortando" >&2; exit 1; }

rm -rf "${DESTINO}"
install -d -m 750 "${DESTINO}"
tar -xzf "${tmp}/instalador.tar.gz" -C "${DESTINO}"
dentro="$(cat "${DESTINO}/installer/VERSAO" 2>/dev/null || true)"
[[ "${dentro}" == "${VERSAO}" ]] ||
  { rm -rf "${DESTINO}"; echo "o pacote assinado e da versao '${dentro}', nao ${VERSAO}; abortando" >&2; exit 1; }

if tem_tty; then
  exec "${DESTINO}/installer/instalar.sh" "$@" </dev/tty
else
  exec "${DESTINO}/installer/instalar.sh" "$@"
fi
