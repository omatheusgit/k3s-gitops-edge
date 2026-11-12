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

  # Sem chave nenhuma para o usuario, desligar senha tranca o tecnico fora.
  if [[ -z "${ADMIN_CHAVE_SSH:-}" && ! -s "/home/${usuario}/.ssh/authorized_keys" && "${SIMULAR:-0}" != "1" ]]; then
    morrer "informe ADMIN_CHAVE_SSH: sem chave, desligar a senha do SSH tranca o acesso"
  fi

  # Firewall antes do SSH: a porta nova tem que estar aberta antes de o sshd
  # passar a escutar nela.
  if command -v ufw >/dev/null 2>&1; then
    executar ufw default deny incoming
    executar ufw default allow outgoing
    executar ufw allow "${porta}/tcp"
    # Trocando a porta, a 22 fica aberta ate alguem testar a nova.
    [[ "${porta}" == 22 ]] || executar ufw allow 22/tcp
    executar ufw allow 80/tcp
    executar ufw allow 443/tcp
    executar ufw allow in on cni0
    executar ufw --force enable
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
    sshd -t || { rm -f /etc/ssh/sshd_config.d/50-loja.conf; morrer "configuracao do sshd invalida; nada aplicado"; }
    if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
      # Ubuntu 22.10+: a porta e do socket, nao do sshd_config.
      systemctl daemon-reload
      systemctl restart ssh.socket
    else
      systemctl reload ssh 2>/dev/null || systemctl reload sshd
    fi
    [[ "${porta}" == 22 ]] || info "teste o SSH na porta ${porta} e depois feche a 22: ufw delete allow 22/tcp"
  else
    executar "escrever /etc/ssh/sshd_config.d/50-loja.conf (porta ${porta}, sem senha, sem root)"
  fi

  # A API do k3s (6443) fica fechada para a rede da loja (regras acima); o
  # agente do Rancher/Fleet so faz conexoes de saida.

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
