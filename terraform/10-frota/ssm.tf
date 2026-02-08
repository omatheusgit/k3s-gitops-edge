locals {
  parametros = {
    "rancher/url"   = { tipo = "String", valor = var.rancher_url }
    "gitops/repo"   = { tipo = "String", valor = var.repositorio_gitops }
    "rancher/token" = { tipo = "SecureString", valor = "definir-depois" }
  }
}

resource "aws_ssm_parameter" "instalador" {
  for_each = local.parametros
  name     = "/frota/${each.key}"
  type     = each.value.tipo
  value    = each.value.valor

  # O token do Rancher e gerado no proprio Rancher e gravado fora do
  # Terraform (lab/rancher.sh). O Terraform cria o parametro e nao mexe mais.
  lifecycle {
    ignore_changes = [value]
  }
}
