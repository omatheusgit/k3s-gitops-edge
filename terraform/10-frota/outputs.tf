output "bucket_instalador" {
  value = aws_s3_bucket.instalador.id
}

output "lojas" {
  value = { for id, l in var.lojas : id => merge(l, { segredo = aws_secretsmanager_secret.loja[id].name }) }
}

# Entregue ao tecnico que instala a loja (ou lido pelo lab).
output "credenciais" {
  value = {
    for id, chave in aws_iam_access_key.loja : id => {
      access_key_id     = chave.id
      secret_access_key = chave.secret
    }
  }
  sensitive = true
}
