#!/usr/bin/env bash
# Instalador do servidor da loja.
#
#   ./instalar.sh               menu interativo (gum)
#   ./instalar.sh instalar      k3s + chave AWS + registro na central
#   ./instalar.sh chave         troca a chave AWS da loja
#   ./instalar.sh registrar     so registra o cluster na central
#   ./instalar.sh preparar      endurece o sistema operacional
#   ./instalar.sh diagnostico   mostra o estado do cluster
#
# Respostas podem vir por variavel de ambiente (LOJA_ID, REGIAO, PERFIL,
# LOJA_ACCESS_KEY_ID, LOJA_SECRET_ACCESS_KEY) com SIM=1 para nao perguntar.
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=etc/padrao.env
source "${BASE}/etc/padrao.env"
for lib in ui validar aws k3s credenciais rancher fleet servidor; do
  # shellcheck source=/dev/null
  source "${BASE}/lib/${lib}.sh"
done
export KUBECONFIG

ESTADO="${ESTADO_DIR:-/etc/loja}/loja.env"

carregar_estado() {
  # shellcheck source=/dev/null
  [[ -r "${ESTADO}" ]] && source "${ESTADO}"
  return 0
}

salvar_estado() {
  install -d -m 700 "$(dirname "${ESTADO}")"
  umask 077
  printf 'LOJA_ID=%q\nREGIAO=%q\nPERFIL=%q\n' "${LOJA_ID}" "${REGIAO}" "${PERFIL}" >"${ESTADO}"
}

coletar_loja() {
  perguntar LOJA_ID "Id da loja" "loja-001"
  validar_loja_id "${LOJA_ID}"
  escolher REGIAO regiao "Regiao da loja"
  validar_opcao regiao "${REGIAO}"
  escolher PERFIL perfil "Perfil do servidor"
  validar_opcao perfil "${PERFIL}"
}

coletar_chave() {
  perguntar LOJA_ACCESS_KEY_ID "Access key da loja"
  perguntar LOJA_SECRET_ACCESS_KEY "Secret key da loja" "" senha
  local arn
  arn="$(validar_chave_aws 2>/dev/null)" || morrer "a chave AWS foi recusada"
  ok "chave valida (${arn})"
}

ler_central() {
  case "${MODO_CENTRAL}" in
    rancher)
      RANCHER_URL="${RANCHER_URL:-$(parametro rancher/url)}"
      RANCHER_TOKEN="${RANCHER_TOKEN:-$(parametro rancher/token)}"
      [[ "${RANCHER_TOKEN}" != "definir-depois" ]] || morrer "token do Rancher ainda nao foi publicado no SSM"
      ;;
    fleet) ;;
    *) morrer "MODO_CENTRAL invalido: ${MODO_CENTRAL}" ;;
  esac
}

registrar() {
  [[ "${MODO_CENTRAL}" == "fleet" ]] && verificar_dependencias helm
  ler_central
  if [[ "${MODO_CENTRAL}" == "rancher" ]]; then
    etapa "criar ${LOJA_ID} no Rancher" garantir_cluster_rancher
    etapa "aplicar o agente do Rancher" aplicar_agente_rancher
    etapa "esperar o Rancher marcar o cluster como ativo" esperar_cluster_ativo
  else
    etapa "registrar no Fleet da central" registrar_fleet
  fi
}

acao_instalar() {
  titulo "Instalacao da loja"
  carregar_estado
  coletar_loja
  coletar_chave
  confirmar "Instalar ${LOJA_ID} (${REGIAO}, ${PERFIL})?" || morrer "cancelado"
  if [[ "${SEM_K3S:-0}" == "1" ]]; then
    info "SEM_K3S=1: usando o cluster do KUBECONFIG atual"
  elif k3s_instalado; then
    info "k3s ja instalado; mantendo a versao atual"
  else
    precisa_root
    etapa "instalar k3s ${K3S_VERSAO}" instalar_k3s
  fi
  etapa "esperar o node ficar pronto" esperar_no_pronto
  etapa "gravar a chave AWS no cluster" gravar_credencial_aws
  registrar
  salvar_estado
  titulo "Pronto" "${LOJA_ID} registrada. O Fleet instala o resto (alguns minutos)."
  info "acompanhe com: ./instalar.sh diagnostico"
}

acao_chave() {
  titulo "Troca da chave AWS"
  carregar_estado
  perguntar LOJA_ID "Id da loja" "loja-001"
  coletar_chave
  etapa "gravar a chave nova" gravar_credencial_aws
  etapa "pedir ao ESO para reler os segredos" forcar_sincronia
}

acao_registrar() {
  titulo "Registro na central"
  carregar_estado
  coletar_loja
  coletar_chave
  registrar
  salvar_estado
}

acao_preparar() {
  titulo "Preparar o servidor"
  carregar_estado
  perguntar LOJA_ID "Id da loja" "loja-001"
  validar_loja_id "${LOJA_ID}"
  [[ "${SIMULAR:-0}" == "1" ]] || precisa_root
  preparar_servidor
  ok "servidor preparado"
}

acao_diagnostico() {
  titulo "Diagnostico"
  kubectl get nodes -o wide
  echo
  echo "Pods com problema:"
  kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | sed 's/^/  /'
  echo
  echo "Segredos sincronizados pelo ESO:"
  kubectl get externalsecrets -A 2>/dev/null | sed 's/^/  /' || info "ESO ainda nao instalado"
  echo
  echo "Bundles do Fleet nesta loja:"
  kubectl get bundledeployments -A 2>/dev/null | sed 's/^/  /' || info "agente do Fleet ainda nao chegou"
}

menu() {
  local acao
  if tem_gum; then
    titulo "Servidor da loja" "k3s + GitOps (Fleet) + segredos (ESO)"
    acao="$(gum choose --header "O que fazer?" \
      "instalar    - instalar e registrar a loja" \
      "chave       - trocar a chave AWS" \
      "registrar   - registrar na central" \
      "preparar    - endurecer o sistema operacional" \
      "diagnostico - ver o estado do cluster" \
      "sair")"
    acao="${acao%% *}"
  else
    acao="${1:-}"
    [[ -n "${acao}" ]] || { sed -n '2,14p' "$0"; exit 1; }
  fi
  despachar "${acao}"
}

despachar() {
  case "$1" in
    instalar) verificar_dependencias curl aws jq kubectl; acao_instalar ;;
    chave) verificar_dependencias aws kubectl; acao_chave ;;
    registrar) verificar_dependencias curl aws jq kubectl; acao_registrar ;;
    preparar) acao_preparar ;;
    diagnostico) verificar_dependencias kubectl; acao_diagnostico ;;
    sair) exit 0 ;;
    *) morrer "acao desconhecida: $1" ;;
  esac
}

if [[ $# -gt 0 ]]; then despachar "$1"; else menu; fi
