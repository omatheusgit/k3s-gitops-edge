#!/usr/bin/env bash
# Atualizacao pelo GitOps, de ponta a ponta: um commit novo na branch que a
# central serve chega sozinho na loja. Faz um commit de verdade, por isso so
# roda no CI (no notebook ele mexeria no repositorio de quem esta testando).
#   ./atualizacao.sh loja-001
set -euo pipefail

LOJA="${1:-loja-001}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../comum.sh
source "${RAIZ}/lab/comum.sh"
[[ "${CI:-}" == true ]] || falha "este teste faz um commit; so roda no CI"

REVISAO="$(date +%s)"
echo "Atualizacao via Fleet: whoami com a revisao ${REVISAO}"
sed -i "0,/^  name: whoami$/s//  name: whoami\n  annotations:\n    k3s-gitops-edge\/revisao: \"${REVISAO}\"/" "${RAIZ}/smoke/smoke.yaml"
git -C "${RAIZ}" -c user.name=ci -c user.email=ci@localhost commit -qam "test: revisao ${REVISAO} do whoami"

revisao_na_loja() {
  [[ "$(KUBECONFIG="${CACHE}/${LOJA}.kubeconfig" kubectl -n loja get deploy whoami \
    -o jsonpath='{.metadata.annotations.k3s-gitops-edge/revisao}' 2>/dev/null)" == "${REVISAO}" ]]
}
inicio=${SECONDS}
# O GitRepo consulta o git a cada minuto; da folga para o Fleet aplicar.
esperar 420 "revisao ${REVISAO} na ${LOJA}" revisao_na_loja
echo "commit chegou na ${LOJA} em $((SECONDS - inicio))s, sem tocar na loja"
