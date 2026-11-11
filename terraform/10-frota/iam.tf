# Um usuario por loja. A chave dele e a unica credencial AWS que vai para o
# servidor da loja, e so abre o proprio segredo mais os da frota.
resource "aws_iam_user" "loja" {
  for_each = var.lojas
  name     = each.key
  path     = "/lojas/"
}

# Policy montada com jsonencode, e nao com data "aws_iam_policy_document":
# o data com for_each depende do recurso inteiro, entao criar uma loja nova
# fazia o plano "alterar" a policy de todas as outras.
resource "aws_iam_user_policy" "loja" {
  for_each = var.lojas
  name     = "acesso-minimo"
  user     = aws_iam_user.loja[each.key].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SegredosDaLoja"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [
          aws_secretsmanager_secret.loja[each.key].arn,
          aws_secretsmanager_secret.jwt.arn,
          aws_secretsmanager_secret.registro.arn,
        ]
      },
      {
        Sid      = "ParametrosDoInstalador"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = [for p in aws_ssm_parameter.instalador : p.arn]
      },
      {
        Sid      = "PacoteDoInstalador"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.instalador.arn}/releases/*"]
      },
    ]
  })
}

resource "aws_iam_access_key" "loja" {
  for_each = var.lojas
  user     = aws_iam_user.loja[each.key].name
}
