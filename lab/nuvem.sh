#!/usr/bin/env bash
# "AWS" local: LocalStack + as duas camadas do Terraform.
# shellcheck source=comum.sh
source "$(dirname "${BASH_SOURCE[0]}")/comum.sh"

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
