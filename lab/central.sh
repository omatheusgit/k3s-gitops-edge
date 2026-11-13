#!/usr/bin/env bash
# Cluster central da frota.
#   ./central.sh up fleet     so o Fleet (leve, ~1 GB)
#   ./central.sh up rancher   Rancher completo (Fleet incluso, ~2,5 GB)
#   ./central.sh down
# shellcheck source=comum.sh
source "$(dirname "${BASH_SOURCE[0]}")/comum.sh"

KCFG="${CACHE}/central.kubeconfig"
RANCHER_VERSAO="2.15.3"
# Um nome so para o Rancher, que o host resolve pelo /etc/hosts (127.0.0.1) e
# a loja resolve pelo --host-alias do k3d (IP do container da central).
RANCHER_HOST="${RANCHER_HOST:-rancher.lab.internal}"
FLEET_VERSAO="0.16.3"

criar_cluster() {
  local -a portas=()
  [[ "$1" == "rancher" ]] && portas=(-p "127.0.0.1:443:443@server:0:direct")
  if ! k3d cluster list central >/dev/null 2>&1; then
    passo "criando cluster central"
    k3d cluster create central --image "${K3S_IMAGEM}" --network "${REDE}" \
      --servers 1 --agents 0 --no-lb "${portas[@]}" \
      --k3s-arg "--disable=metrics-server@server:0" \
      --k3s-arg "--tls-san=k3d-central-server-0@server:0" \
      --kubeconfig-update-default=false --wait --timeout 180s >/dev/null
  fi
  k3d kubeconfig get central >"${KCFG}"
  chmod 600 "${KCFG}"
  export KUBECONFIG="${KCFG}"
  kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' |
    base64 -d >"${CACHE}/central-ca.pem"
}

# O GitRepo do lab aponta para o servidor git local, que serve a branch atual.
aplicar_gitrepo() {
  local branch
  branch="$(git -C "${RAIZ}" rev-parse --abbrev-ref HEAD)"
  [[ "${branch}" != HEAD ]] || falha "HEAD desanexado: o Fleet le uma branch (git switch -c lab)"
  # O git-lab serve commits: arquivo editado e nao commitado nao chega no cluster.
  git -C "${RAIZ}" diff --quiet HEAD -- apps platform smoke central ||
    aviso "ha mudancas nao commitadas em apps/, platform/, smoke/ ou central/: o Fleet so ve o que esta commitado"
  passo "GitRepo 'lojas' -> git://git-lab/k3s-gitops-edge (${branch})"
  "${RAIZ}/lab/git.sh" up
  # Logo depois de instalar, o Rancher reinicia a API agregada e responde 503
  # por alguns segundos ("unable to handle the request"): tenta de novo.
  local tentativa
  for tentativa in $(seq 1 12); do
    kubectl create namespace fleet-default --dry-run=client -o yaml | kubectl apply -f - >/dev/null &&
      sed -e "s#repo: .*#repo: git://git-lab/k3s-gitops-edge#" -e "s#branch: .*#branch: ${branch}#" \
        "${RAIZ}/central/gitrepo.yaml" | kubectl apply -f - && return 0
    aviso "API da central indisponivel (tentativa ${tentativa}/12); de novo em 10s"
    sleep 10
  done
  falha "nao consegui aplicar o GitRepo na central"
}

publicar_ssm() {
  aws --endpoint-url http://localhost:4566 ssm put-parameter --overwrite \
    --name "$1" --type "${3:-SecureString}" --value "$2" >/dev/null
}

modo_fleet() {
  passo "instalando Fleet ${FLEET_VERSAO} (sem Rancher)"
  helm repo add fleet https://rancher.github.io/fleet-helm-charts/ --force-update >/dev/null
  helm -n cattle-fleet-system upgrade --install --create-namespace --wait \
    fleet-crd fleet/fleet-crd --version "${FLEET_VERSAO}" >/dev/null
  helm -n cattle-fleet-system upgrade --install --wait fleet fleet/fleet --version "${FLEET_VERSAO}" \
    --set apiServerURL=https://k3d-central-server-0:6443 \
    --set-file apiServerCA="${CACHE}/central-ca.pem" >/dev/null
  aplicar_gitrepo

  # Cada loja: Cluster pre-criado pela central, com os labels vindos do
  # Terraform e um clientID aleatorio. O clientID e o token vao so para o
  # parametro da propria loja. Sem isso, o token de uma loja registrava um
  # servidor com o clientID previsivel de outra e tomava os bundles dela (#25).
  local loja lojas id labels
  lojas="$(tf 10-frota output -json lojas)"
  for loja in $(jq -r 'keys[]' <<<"${lojas}"); do
    passo "Cluster e registro da ${loja} -> SSM /frota/lojas/${loja}/registro"
    id="$(kubectl -n fleet-default get clusters.fleet.cattle.io "${loja}" -o jsonpath='{.spec.clientID}' 2>/dev/null || true)"
    [[ -n "${id}" ]] || id="$(openssl rand -hex 16)"
    labels="$(jq -c --arg l "${loja}" '.[$l] | {loja: $l, regiao, perfil, ambiente: "lab"}
      + (if (.ip_lan // "") != "" then {"ip-lan": .ip_lan} else {} end)' <<<"${lojas}")"
    jq -n --arg nome "${loja}" --arg id "${id}" --argjson labels "${labels}" \
      '{apiVersion: "fleet.cattle.io/v1alpha1", kind: "Cluster",
        metadata: {name: $nome, namespace: "fleet-default", labels: $labels},
        spec: {clientID: $id}}' | kubectl apply -f - >/dev/null
    sed "s/LOJA/${loja}/" "${RAIZ}/central/token-registro.yaml" | kubectl apply -f - >/dev/null
    esperar 60 "secret do token da ${loja}" kubectl -n fleet-default get secret "${loja}"
    publicar_ssm "/frota/lojas/${loja}/registro" "$(
      kubectl -n fleet-default get secret "${loja}" -o jsonpath='{.data.values}' | base64 -d
      echo "clientID: ${id}"
      echo "apiServerURL: https://k3d-central-server-0:6443"
      echo "apiServerCA: |"
      sed 's/^/  /' "${CACHE}/central-ca.pem"
    )"
  done
}

modo_rancher() {
  # Sem getent (macOS): confere o /etc/hosts direto.
  grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]].*\b${RANCHER_HOST//./\\.}\b" /etc/hosts ||
    falha "adicione '127.0.0.1 ${RANCHER_HOST}' ao /etc/hosts antes (o navegador e o instalador usam esse nome)"
  passo "certificado de CA propria para ${RANCHER_HOST}"
  if [[ ! -f "${CACHE}/rancher.crt" ]]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=rancher-lab-ca" \
      -keyout "${CACHE}/ca.key" -out "${CACHE}/ca.crt" 2>/dev/null
    openssl req -newkey rsa:2048 -nodes -subj "/CN=${RANCHER_HOST}" \
      -keyout "${CACHE}/rancher.key" -out "${CACHE}/rancher.csr" 2>/dev/null
    openssl x509 -req -in "${CACHE}/rancher.csr" -CA "${CACHE}/ca.crt" -CAkey "${CACHE}/ca.key" \
      -CAcreateserial -days 365 -out "${CACHE}/rancher.crt" \
      -extfile <(printf 'subjectAltName=DNS:%s' "${RANCHER_HOST}") 2>/dev/null
  fi
  kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n cattle-system create secret tls tls-rancher-ingress \
    --cert="${CACHE}/rancher.crt" --key="${CACHE}/rancher.key" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n cattle-system create secret generic tls-ca \
    --from-file=cacerts.pem="${CACHE}/ca.crt" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  passo "instalando Rancher ${RANCHER_VERSAO} (1 replica, alguns minutos)"
  helm repo add rancher-stable https://releases.rancher.com/server-charts/stable --force-update >/dev/null
  local senha
  senha="$(openssl rand -hex 12)"
  helm -n cattle-system upgrade --install rancher rancher-stable/rancher --version "${RANCHER_VERSAO}" \
    --set hostname="${RANCHER_HOST}" --set replicas=1 \
    --set ingress.tls.source=secret --set privateCA=true \
    --set bootstrapPassword="${senha}" \
    --set resources.requests.memory=512Mi --set resources.limits.memory="${RANCHER_MEMORIA:-1536Mi}" \
    --wait --timeout 15m >/dev/null
  kubectl -n cattle-system rollout status deploy/rancher --timeout 10m >/dev/null
  echo "${senha}" >"${CACHE}/rancher-senha"
  chmod 600 "${CACHE}/rancher-senha"

  # A API de provisioning so aceita criar cluster com o rancher-webhook no ar
  # (antes disso responde 503).
  esperar 900 "rancher-webhook" kubectl -n cattle-system rollout status deploy/rancher-webhook
  esperar 300 "API de provisioning" kubectl get crd clusters.provisioning.cattle.io
  passo "server-url e cluster de cada loja no Rancher"
  "${RAIZ}/lab/rancher-token.sh" "${senha}"
  # O Rancher instala o Fleet sozinho, alguns minutos depois de subir.
  esperar 900 "CRD do GitRepo (Fleet do Rancher)" kubectl get crd gitrepos.fleet.cattle.io
  kubectl wait --for=condition=Established crd/gitrepos.fleet.cattle.io --timeout=120s >/dev/null
  esperar 600 "fleet-controller" kubectl -n cattle-fleet-system rollout status deploy/fleet-controller
  aplicar_gitrepo
  echo "Rancher: https://${RANCHER_HOST}  usuario admin  senha em lab/.cache/rancher-senha"
}

case "${1:-}" in
  up)
    precisa docker k3d kubectl helm openssl aws
    criar_cluster "${2:-fleet}"
    case "${2:-fleet}" in
      fleet) modo_fleet ;;
      rancher) modo_rancher ;;
      *) falha "modo desconhecido: $2" ;;
    esac
    echo "${2:-fleet}" >"${CACHE}/modo-central"
    ;;
  down)
    k3d cluster delete central >/dev/null 2>&1 || true
    rm -f "${CACHE}/modo-central"
    ;;
  *) echo "uso: $0 up [fleet|rancher] | down" >&2; exit 1 ;;
esac
