variable "regiao" {
  type    = string
  default = "us-east-1"
}

variable "bucket" {
  type    = string
  default = "k3s-gitops-edge-tfstate"
}

variable "tabela_lock" {
  type    = string
  default = "k3s-gitops-edge-tflock"
}

variable "localstack" {
  description = "Endpoint do LocalStack. Vazio = AWS de verdade."
  type        = string
  default     = ""
}
