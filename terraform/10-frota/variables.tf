variable "regiao" {
  type    = string
  default = "us-east-1"
}

variable "ambiente" {
  type    = string
  default = "lab"

  validation {
    condition     = contains(["lab", "producao"], var.ambiente)
    error_message = "ambiente deve ser lab ou producao."
  }
}

variable "localstack" {
  description = "Endpoint do LocalStack. Vazio = AWS de verdade."
  type        = string
  default     = ""
}

variable "lojas" {
  description = "Lojas da frota. A chave vira o nome do cluster e o prefixo dos segredos."
  type = map(object({
    regiao = string
    perfil = string
  }))
  default = {
    loja-001 = { regiao = "sudeste", perfil = "completo" }
    loja-002 = { regiao = "sudeste", perfil = "enxuto" }
    loja-003 = { regiao = "sul", perfil = "completo" }
  }

  validation {
    condition     = alltrue([for id, l in var.lojas : can(regex("^loja-[0-9]{3}$", id))])
    error_message = "Use ids no formato loja-NNN."
  }

  validation {
    condition     = alltrue([for l in values(var.lojas) : contains(["completo", "enxuto"], l.perfil)])
    error_message = "perfil deve ser completo ou enxuto."
  }
}

variable "rancher_url" {
  type    = string
  default = "https://rancher.lab.localhost:8443"
}

variable "repositorio_gitops" {
  type    = string
  default = "https://github.com/omatheusgit/k3s-gitops-edge.git"
}

variable "registro" {
  description = "Credencial de leitura do registry privado (opcional)."
  type = object({
    servidor = string
    usuario  = string
    token    = string
  })
  default = {
    servidor = "ghcr.io"
    usuario  = ""
    token    = ""
  }
  sensitive = true
}
