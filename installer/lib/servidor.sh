# shellcheck shell=bash
# Preparacao do sistema operacional do servidor da loja (Ubuntu/Debian).
# Cada passo e idempotente; com SIMULAR=1 so mostra o que faria.

executar() {
  if [[ "${SIMULAR:-0}" == "1" ]]; then
    printf '      [simulado] %s\n' "$*"
  else
    "$@"
  fi
}

preparar_servidor() {
  local usuario="${ADMIN_USUARIO:-operacao}" porta="${SSH_PORTA:-22}"

  executar hostnamectl set-hostname "${LOJA_ID}"

  if ! id "${usuario}" >/dev/null 2>&1; then
    executar useradd --create-home --shell /bin/bash --groups sudo "${usuario}"
  fi
  if [[ -n "${ADMIN_CHAVE_SSH:-}" ]]; then
    executar install -d -m 700 -o "${usuario}" -g "${usuario}" "/home/${usuario}/.ssh"
    if [[ "${SIMULAR:-0}" != "1" ]]; then
      printf '%s\n' "${ADMIN_CHAVE_SSH}" >"/home/${usuario}/.ssh/authorized_keys"
      chown "${usuario}:${usuario}" "/home/${usuario}/.ssh/authorized_keys"
      chmod 600 "/home/${usuario}/.ssh/authorized_keys"
    fi
  fi

  # SSH so com chave, sem root. Arquivo proprio em sshd_config.d para nao
  # brigar com o arquivo do pacote em atualizacoes.
  if [[ "${SIMULAR:-0}" != "1" ]]; then
    cat >/etc/ssh/sshd_config.d/50-loja.conf <<CONF
Port ${porta}
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
CONF
    sshd -t && systemctl reload ssh || systemctl reload sshd
  else
    executar "escrever /etc/ssh/sshd_config.d/50-loja.conf (porta ${porta}, sem senha, sem root)"
  fi

  # Firewall: SSH, HTTP/HTTPS do caixa. A API do k3s (6443) fica fechada
  # para a rede da loja; o agente do Rancher/Fleet so faz conexoes de saida.
  if command -v ufw >/dev/null 2>&1; then
    executar ufw default deny incoming
    executar ufw default allow outgoing
    executar ufw allow "${porta}/tcp"
    executar ufw allow 80/tcp
    executar ufw allow 443/tcp
    executar ufw allow in on cni0
    executar ufw --force enable
  fi

  if command -v apt-get >/dev/null 2>&1; then
    executar apt-get install -y --no-install-recommends unattended-upgrades
  fi

  if [[ "${SIMULAR:-0}" != "1" ]]; then
    cat >/etc/sysctl.d/90-loja.conf <<CONF
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 524288
vm.swappiness = 10
CONF
    sysctl --system >/dev/null
  else
    executar "escrever /etc/sysctl.d/90-loja.conf (inotify, swappiness)"
  fi
}
