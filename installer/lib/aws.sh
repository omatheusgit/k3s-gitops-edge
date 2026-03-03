# shellcheck shell=bash
# Acesso a AWS com a chave da loja. AWS_ENDPOINT_URL (opcional) aponta para
# o LocalStack no laboratorio; o aws cli v2 respeita essa variavel sozinho.

aws_loja() {
  AWS_ACCESS_KEY_ID="${LOJA_ACCESS_KEY_ID}" AWS_SECRET_ACCESS_KEY="${LOJA_SECRET_ACCESS_KEY}" \
    AWS_RETRY_MODE=adaptive AWS_MAX_ATTEMPTS=5 aws --region "${AWS_REGION}" "$@"
}

validar_chave_aws() {
  aws_loja sts get-caller-identity --query Arn --output text
}

parametro() {
  aws_loja ssm get-parameter --name "${SSM_PREFIXO}/$1" --with-decryption \
    --query Parameter.Value --output text
}
