# shellcheck shell=bash
# Interface do instalador. Usa o gum quando existe e ha terminal; sem isso,
# cai para prompts simples, o que permite rodar via SSH ruim ou em CI.

tem_gum() { command -v gum >/dev/null 2>&1 && [[ -t 0 && "${SEM_TUI:-0}" != "1" ]]; }

titulo() {
  if tem_gum; then
    gum style --border rounded --border-foreground 39 --padding "0 2" --bold "$@"
  else
    printf '\n== %s ==\n' "$*"
  fi
}

info() { printf '  %s\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
erro() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
morrer() { erro "$*"; exit 1; }

# perguntar VARIAVEL "Texto" [padrao] [senha]
perguntar() {
  local var="$1" texto="$2" padrao="${3:-}" senha="${4:-}"
  [[ -n "${!var:-}" ]] && return 0
  local resposta
  if tem_gum; then
    local args=(--prompt "${texto}: " --value "${padrao}")
    [[ -n "${senha}" ]] && args+=(--password)
    resposta="$(gum input "${args[@]}")"
  else
    [[ -t 0 ]] || morrer "${var} nao informado e nao ha terminal para perguntar"
    if [[ -n "${senha}" ]]; then
      read -r -s -p "${texto}: " resposta; echo
    else
      read -r -p "${texto} [${padrao}]: " resposta
    fi
    resposta="${resposta:-${padrao}}"
  fi
  printf -v "${var}" '%s' "${resposta}"
}

# escolher VARIAVEL grupo "Texto"  (opcoes vem de etc/opcoes.conf)
escolher() {
  local var="$1" grupo="$2" texto="$3"
  [[ -n "${!var:-}" ]] && return 0
  local -a valores descricoes
  while IFS='|' read -r g valor descricao; do
    [[ "${g}" == "${grupo}" ]] || continue
    valores+=("${valor}"); descricoes+=("${valor} - ${descricao}")
  done < <(grep -v '^#' "${BASE}/etc/opcoes.conf")
  local escolha
  if tem_gum; then
    escolha="$(gum choose --header "${texto}" "${descricoes[@]}")"
  else
    [[ -t 0 ]] || morrer "${var} nao informado e nao ha terminal para perguntar"
    PS3="${texto}: "
    select escolha in "${descricoes[@]}"; do [[ -n "${escolha}" ]] && break; done
  fi
  printf -v "${var}" '%s' "${escolha%% - *}"
}

confirmar() {
  [[ "${SIM:-0}" == "1" ]] && return 0
  if tem_gum; then
    gum confirm "$1"
  else
    local r; read -r -p "$1 [s/N] " r; [[ "${r}" =~ ^[sS]$ ]]
  fi
}

# etapa "Descricao" comando...  -> spinner enquanto roda; mostra o log se falhar
etapa() {
  local descricao="$1"; shift
  local log rc=0
  log="$(mktemp)"
  # O comando roda neste shell (pode ser uma funcao); o gum so anima a espera.
  "$@" >"${log}" 2>&1 &
  local pid=$!
  if tem_gum; then
    gum spin --spinner dot --title "${descricao}" -- bash -c "while kill -0 ${pid} 2>/dev/null; do sleep 0.3; done"
  else
    printf '  ... %s\n' "${descricao}"
  fi
  wait "${pid}" || rc=$?
  if (( rc == 0 )); then
    ok "${descricao}"
  else
    erro "${descricao}"
    sed 's/^/      /' "${log}" | tail -20 >&2
  fi
  rm -f "${log}"
  return "${rc}"
}
