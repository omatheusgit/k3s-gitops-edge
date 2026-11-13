# shellcheck shell=bash

k3s_instalado() {
  command -v k3s >/dev/null 2>&1 && systemctl is-active --quiet k3s
}

instalar_k3s() {
  install -D -m 0644 "${BASE}/etc/k3s-loja.yaml" /etc/rancher/k3s/config.yaml.d/10-loja.yaml
  # Versao fixa: o servidor da loja nao pode atualizar sozinho no meio do dia.
  # O servicelb (klipper) e quem publica o Traefik nas portas 80/443 do
  # servidor; sem ele o Service fica <pending> e o caixa nao abre.
  # O install.sh da propria tag do k3s, conferido por sha256 (antes era
  # curl get.k3s.io | sh). Ele, por sua vez, confere o binario com o
  # sha256sum da release antes de instalar.
  local script
  script="$(mktemp)"
  curl -fsSL --retry 3 -o "${script}" \
    "https://raw.githubusercontent.com/k3s-io/k3s/${K3S_VERSAO/+/%2B}/install.sh"
  echo "${K3S_INSTALL_SHA256}  ${script}" | sha256sum --check --strict --quiet ||
    { rm -f "${script}"; morrer "install.sh do k3s ${K3S_VERSAO} nao confere com o sha256 esperado"; }
  INSTALL_K3S_VERSION="${K3S_VERSAO}" sh "${script}" server \
    --write-kubeconfig-mode 600 \
    --node-label "loja=${LOJA_ID}"
  rm -f "${script}"
}

# Num servidor novo o kubectl so existe depois do k3s (que traz o proprio).
garantir_kubectl() {
  command -v kubectl >/dev/null 2>&1 && return 0
  command -v k3s >/dev/null 2>&1 || morrer "kubectl nao encontrado (e o k3s ainda nao esta instalado)"
  kubectl() { k3s kubectl "$@"; }
}

esperar_no_pronto() {
  local limite=$((SECONDS + 180))
  until kubectl get nodes 2>/dev/null | grep -q ' Ready '; do
    (( SECONDS > limite )) && return 1
    sleep 5
  done
}
