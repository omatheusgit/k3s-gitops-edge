# Parametros publicos do instalador, iguais para a frota toda.
locals {
  parametros = {
    "rancher/url" = { tipo = "String", valor = var.rancher_url }
    "gitops/repo" = { tipo = "String", valor = var.repositorio_gitops }
  }
}

resource "aws_ssm_parameter" "instalador" {
  for_each = local.parametros
  name     = "/frota/${each.key}"
  type     = each.value.tipo
  value    = each.value.valor
}

# Registro de cada loja na central: a URL do manifesto do agente do Rancher
# (com um token que so registra aquele cluster) ou os valores do fleet-agent
# com um token so daquela loja. Quem grava e a central, depois de criar o
# cluster; o Terraform cria o parametro e nao mexe mais no valor. Antes havia
# um token de API do admin do Rancher igual para todas as lojas (#25).
resource "aws_ssm_parameter" "registro" {
  for_each = var.lojas
  name     = "/frota/lojas/${each.key}/registro"
  type     = "SecureString"
  value    = "definir-depois"

  lifecycle {
    ignore_changes = [value]
  }
}
