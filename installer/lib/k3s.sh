# shellcheck shell=bash

k3s_instalado() {
  command -v k3s >/dev/null 2>&1 && systemctl is-active --quiet k3s
}

instalar_k3s() {
  # Versao fixa: o servidor da loja nao pode atualizar sozinho no meio do dia.
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSAO}" sh -s - server \
    --disable servicelb \
    --write-kubeconfig-mode 600 \
    --node-label "loja=${LOJA_ID}"
}

esperar_no_pronto() {
  local limite=$((SECONDS + 180))
  until kubectl get nodes 2>/dev/null | grep -q ' Ready '; do
    (( SECONDS > limite )) && return 1
    sleep 5
  done
}
