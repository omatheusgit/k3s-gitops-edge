# Pacotes versionados do instalador. O stage0 baixa daqui e confere o sha256.
resource "aws_s3_bucket" "instalador" {
  bucket        = "k3s-gitops-edge-instalador"
  force_destroy = var.ambiente == "lab"
}

resource "aws_s3_bucket_versioning" "instalador" {
  bucket = aws_s3_bucket.instalador.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "instalador" {
  bucket = aws_s3_bucket.instalador.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "instalador" {
  bucket                  = aws_s3_bucket.instalador.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
