terraform {
  required_version = ">= 1.9"

  # Valores de bucket/endpoint vem de um arquivo -backend-config
  # (lab.s3.tfbackend no laboratorio).
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region                      = var.regiao
  s3_use_path_style           = var.localstack != ""
  skip_credentials_validation = var.localstack != ""
  skip_requesting_account_id  = var.localstack != ""

  dynamic "endpoints" {
    for_each = var.localstack != "" ? [1] : []
    content {
      iam            = var.localstack
      s3             = var.localstack
      secretsmanager = var.localstack
      ssm            = var.localstack
      sts            = var.localstack
    }
  }

  default_tags {
    tags = {
      projeto    = "k3s-gitops-edge"
      camada     = "10-frota"
      ambiente   = var.ambiente
      gerenciado = "terraform"
    }
  }
}
