# shellcheck shell=bash

validar_loja_id() {
  [[ "$1" =~ ^loja-[0-9]{3}$ ]] || morrer "id de loja invalido: '$1' (use loja-NNN)"
}

validar_opcao() {
  local grupo="$1" valor="$2"
  grep -q "^${grupo}|${valor}|" "${BASE}/etc/opcoes.conf" || morrer "${grupo} invalido: '${valor}'"
}

verificar_dependencias() {
  local faltando=()
  for cmd in "$@"; do command -v "${cmd}" >/dev/null 2>&1 || faltando+=("${cmd}"); done
  (( ${#faltando[@]} == 0 )) || morrer "instale antes: ${faltando[*]}"
}

precisa_root() {
  [[ "${EUID}" -eq 0 ]] || morrer "esta etapa precisa de root (sudo)"
}
