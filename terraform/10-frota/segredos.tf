locals {
  # Uma senha por servico, por loja. Nada disso esta no git: e gerado aqui
  # e so existe no state (criptografado no S3) e no Secrets Manager.
  senhas = toset(["postgres", "autenticador", "eventos", "rabbitmq", "redis", "meili", "webhook"])

  pares = { for p in setproduct(keys(var.lojas), local.senhas) : "${p[0]}/${p[1]}" => { loja = p[0], nome = p[1] } }
}

resource "random_password" "loja" {
  for_each = local.pares
  length   = 32
  special  = false
}

resource "aws_secretsmanager_secret" "loja" {
  for_each                = var.lojas
  name                    = "lojas/${each.key}/app"
  description             = "Segredos de aplicacao da ${each.key}"
  recovery_window_in_days = var.ambiente == "lab" ? 0 : 7
}

resource "aws_secretsmanager_secret_version" "loja" {
  for_each  = var.lojas
  secret_id = aws_secretsmanager_secret.loja[each.key].id
  secret_string = jsonencode({
    postgres_senha     = random_password.loja["${each.key}/postgres"].result
    autenticador_senha = random_password.loja["${each.key}/autenticador"].result
    eventos_senha      = random_password.loja["${each.key}/eventos"].result
    rabbitmq_senha     = random_password.loja["${each.key}/rabbitmq"].result
    redis_senha        = random_password.loja["${each.key}/redis"].result
    meili_chave        = random_password.loja["${each.key}/meili"].result
    webhook_hmac       = random_password.loja["${each.key}/webhook"].result
  })
}

# Chave dos JWT do caixa. Compartilhada pela frota para que um token emitido
# na central (futuro SSO) tambem valha na loja.
resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "frota/jwt"
  recovery_window_in_days = var.ambiente == "lab" ? 0 : 7
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({ jwt_secret = random_password.jwt.result })
}

resource "aws_secretsmanager_secret" "registro" {
  name                    = "frota/registry"
  recovery_window_in_days = var.ambiente == "lab" ? 0 : 7
}

resource "aws_secretsmanager_secret_version" "registro" {
  secret_id     = aws_secretsmanager_secret.registro.id
  secret_string = jsonencode(var.registro)
}
