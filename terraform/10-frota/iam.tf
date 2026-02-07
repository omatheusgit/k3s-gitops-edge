# Um usuario por loja. A chave dele e a unica credencial AWS que vai para o
# servidor da loja, e so abre o proprio segredo mais os da frota.
resource "aws_iam_user" "loja" {
  for_each = var.lojas
  name     = each.key
  path     = "/lojas/"
}

data "aws_iam_policy_document" "loja" {
  for_each = var.lojas

  statement {
    sid     = "SegredosDaLoja"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.loja[each.key].arn,
      aws_secretsmanager_secret.jwt.arn,
      aws_secretsmanager_secret.registro.arn,
    ]
  }

  statement {
    sid       = "ParametrosDoInstalador"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [for p in aws_ssm_parameter.instalador : p.arn]
  }

  statement {
    sid       = "PacoteDoInstalador"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.instalador.arn}/releases/*"]
  }
}

resource "aws_iam_user_policy" "loja" {
  for_each = var.lojas
  name     = "acesso-minimo"
  user     = aws_iam_user.loja[each.key].name
  policy   = data.aws_iam_policy_document.loja[each.key].json
}

resource "aws_iam_access_key" "loja" {
  for_each = var.lojas
  user     = aws_iam_user.loja[each.key].name
}
