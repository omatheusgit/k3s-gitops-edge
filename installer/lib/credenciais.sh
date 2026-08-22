# shellcheck shell=bash
# Grava a chave AWS da loja no namespace external-secrets. E o unico Secret
# criado fora do GitOps: todos os outros vem do Secrets Manager via ESO.
# Os namespaces tambem sao do instalador, e nao de um bundle do Fleet: o
# "loja" guarda banco e filas e nao pode depender do ciclo de vida de um
# release do Helm (apagar ou reinstalar um bundle nao pode apagar dados).

criar_namespaces() {
  kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace external-secrets --overwrite \
    pod-security.kubernetes.io/enforce=baseline pod-security.kubernetes.io/warn=restricted
  kubectl create namespace loja --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace loja --overwrite \
    pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
}

gravar_credencial_aws() {
  criar_namespaces
  kubectl -n external-secrets create secret generic aws-credenciais \
    --from-literal=access-key-id="${LOJA_ACCESS_KEY_ID}" \
    --from-literal=secret-access-key="${LOJA_SECRET_ACCESS_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# Depois de trocar a chave, pede ao ESO para reler tudo na hora.
forcar_sincronia() {
  kubectl get externalsecrets -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' |
    while read -r ns nome; do
      [[ -n "${nome}" ]] && kubectl -n "${ns}" annotate externalsecret "${nome}" \
        force-sync="$(date +%s)" --overwrite >/dev/null
    done
}
