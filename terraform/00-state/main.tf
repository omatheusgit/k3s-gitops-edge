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
      kms      = var.localstack
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

# O state da camada 10-frota guarda as access keys e as senhas de todas as
# lojas: chave KMS propria (com rotacao) em vez da chave padrao do S3, para
# que ler o objeto nao baste; e preciso tambem permissao na chave (#32).
resource "aws_kms_key" "state" {
  description             = "state do Terraform da frota"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "state" {
  name          = "alias/k3s-gitops-edge-state"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

# Nada de state trafegando sem TLS.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SoComTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        # Sem cabecalho vale a criptografia padrao do bucket (KMS); quem pedir
        # outra explicitamente (SSE-S3) e recusado.
        Sid       = "SoComKMS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.state.arn}/*"
        Condition = { StringNotEqualsIfExists = { "s3:x-amz-server-side-encryption" = "aws:kms" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.state]
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
