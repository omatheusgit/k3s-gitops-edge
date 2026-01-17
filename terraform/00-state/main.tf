# Camada zero: o bucket e a tabela de lock que guardam o state das outras
# camadas. Roda uma vez, com state local, antes de existir o Atlantis.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
      s3       = var.localstack
      dynamodb = var.localstack
      sts      = var.localstack
    }
  }

  default_tags {
    tags = {
      projeto    = "k3s-gitops-edge"
      camada     = "00-state"
      gerenciado = "terraform"
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = var.bucket
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = var.tabela_lock
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
