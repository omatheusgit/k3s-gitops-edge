output "bucket" {
  value = aws_s3_bucket.state.id
}

output "tabela_lock" {
  value = aws_dynamodb_table.lock.name
}
