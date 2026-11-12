# shellcheck shell=bash

validar_loja_id() {
  [[ "$1" =~ ^loja-[0-9]{3}$ ]] || morrer "id de loja invalido: '$1' (use loja-NNN)"
}

validar_ip() {
  # Vai parar no bloco hosts do CoreDNS: valor invalido derruba o DNS do cluster.
  local ip="$1" octeto
  [[ "${ip}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || morrer "IP_LAN invalido: '${ip}'"
  for octeto in "${BASH_REMATCH[@]:1}"; do (( 10#${octeto} <= 255 )) || morrer "IP_LAN invalido: '${ip}'"; done
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
