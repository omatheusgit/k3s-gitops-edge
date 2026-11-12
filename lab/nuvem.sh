#!/usr/bin/env bash
# "AWS" local: LocalStack + as duas camadas do Terraform.
# shellcheck source=comum.sh
source "$(dirname "${BASH_SOURCE[0]}")/comum.sh"

# O LocalStack Community nao persiste nada: depois de reiniciar o Docker ele
# volta vazio, mas o state local da 00-state continua dizendo que o bucket
# existe, e o da 10-frota (que mora no bucket) sumiu. Rodar o Terraform assim
# recriaria senhas e chaves novas, e as lojas no ar ficariam com as antigas.
conferir_localstack_zerado() {
  local state="${RAIZ}/terraform/00-state/terraform.tfstate" bucket
  [[ -s "${state}" ]] || return 0
  bucket="$(tf 00-state output -raw bucket 2>/dev/null)" || return 0
  aws --endpoint-url http://localhost:4566 s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1 && return 0
  if k3d cluster list -o json 2>/dev/null | jq -e '.[] | select(.name | test("^loja-"))' >/dev/null; then
    falha "o LocalStack voltou vazio (Docker reiniciado?) e ha lojas no ar com os segredos antigos: rode make down e make up"
  fi
  aviso "o LocalStack voltou vazio; recriando a nuvem do lab do zero"
  rm -f "${state}" "${state}.backup"
}

subir() {
  precisa docker terraform
  garantir_rede
  if ! docker ps --format '{{.Names}}' | grep -qx localstack; then
    passo "subindo LocalStack"
    docker rm -f localstack >/dev/null 2>&1 || true
    docker run -d --name localstack --network "${REDE}" -p 127.0.0.1:4566:4566 \
      -e SERVICES=s3,dynamodb,iam,sts,ssm,secretsmanager \
      --memory 768m "${LOCALSTACK_IMAGEM}" >/dev/null
  fi
  esperar 120 "LocalStack pronto" curl -fs http://localhost:4566/_localstack/health
  conferir_localstack_zerado

  passo "terraform 00-state (bucket e lock do state)"
  tf 00-state init -input=false >/dev/null
  tf 00-state apply -auto-approve -input=false -var localstack=http://localhost:4566 >/dev/null

  passo "terraform 10-frota (segredos, IAM e parametros das lojas)"
  tf 10-frota init -input=false -reconfigure -backend-config=lab.s3.tfbackend >/dev/null
  tf 10-frota apply -auto-approve -input=false -var localstack=http://localhost:4566 >/dev/null
  tf 10-frota output -json lojas
}

descer() {
  docker rm -f localstack >/dev/null 2>&1 || true
  rm -f "${RAIZ}"/terraform/00-state/terraform.tfstate*
}

case "${1:-}" in
  up) subir ;;
  down) descer ;;
  *) echo "uso: $0 up|down" >&2; exit 1 ;;
esac
