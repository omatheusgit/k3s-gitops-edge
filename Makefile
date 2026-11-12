SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := ajuda
.NOTPARALLEL:

LOJA  ?= loja-001
PORTA ?= 8080
MODO  ?= fleet
VENDAS ?= 60

BUNDLES_KUSTOMIZE := platform/00-namespaces platform/20-secret-store platform/40-ingress \
                     apps/perfis/completo apps/perfis/enxuto smoke
SCRIPTS := $(shell git ls-files '*.sh')

.PHONY: ajuda
ajuda: ## mostra os alvos
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

## ---- validacao (nao precisa de cluster) ----

.PHONY: lint
lint: lint-shell lint-k8s lint-tf testes ## roda todas as validacoes estaticas

.PHONY: lint-shell
lint-shell: ## shellcheck em todos os scripts
	shellcheck -x -S warning $(SCRIPTS)

.PHONY: lint-k8s
lint-k8s: ## renderiza bundles e confere as politicas do repositorio
	helm lint platform/30-loja
	helm template loja platform/30-loja --set loja=loja-001 --set ip=10.0.0.10 \
	  --set registroPrivado=true >/dev/null
	@for d in $(BUNDLES_KUSTOMIZE); do echo "  $$d"; kubectl kustomize $$d >/dev/null; done
	@for d in apps/perfis/completo apps/perfis/enxuto smoke; do \
	  kubectl kustomize $$d | python3 scripts/verificar-politicas.py; done
	@echo "  politicas ok"

.PHONY: lint-tf
lint-tf: ## fmt e validate das camadas do Terraform
	terraform fmt -recursive -check terraform
	@for d in terraform/00-state terraform/10-frota; do \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
	  terraform -chdir=$$d validate -no-color; done

.PHONY: testes
testes: ## testes unitarios do servico de eventos (em container)
	docker run --rm -v "$(CURDIR)/src/eventos:/src:ro" python:3.13-slim sh -c \
	  "pip install -q --root-user-action=ignore -r /src/requirements.txt pytest==9.2.0 >/dev/null && \
	   cp -r /src /tmp/s && cd /tmp/s && python -m pytest -q -p no:cacheprovider"

## ---- laboratorio (k3d + LocalStack) ----

.PHONY: nuvem
nuvem: ## sobe LocalStack e aplica o Terraform
	lab/nuvem.sh up

.PHONY: central
central: ## sobe a central (MODO=fleet leve | MODO=rancher completo)
	lab/central.sh up $(MODO)

.PHONY: loja
loja: ## cria uma loja simulada e roda o instalador (LOJA=loja-001 PORTA=8080)
	lab/loja.sh up $(LOJA) $(PORTA)

.PHONY: up
up: nuvem central loja semente ## tudo: nuvem + central + loja-001 pronta, com dados de demonstracao

.PHONY: semente
semente: ## dados de demonstracao na loja (operadores caixa1/caixa2 e produtos)
	lab/semente.sh $(LOJA)

.PHONY: e2e
e2e: ## teste de ponta a ponta da loja (venda, recibo, busca, pagamento)
	lab/testes/e2e.sh $(LOJA) $(PORTA)

.PHONY: demo
demo: ## simula um dia de movimento e imprime o relatorio (VENDAS=60)
	lab/demo/movimento.sh $(LOJA) $(PORTA) $(VENDAS)

.PHONY: status
status: ## containers e memoria do laboratorio
	@docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'k3d|localstack|git-lab|atlantis|NAMES' || true
	@free -h 2>/dev/null | sed -n 1,2p || vm_stat | head -5

.PHONY: down
down: ## derruba todo o laboratorio
	-@for c in $$(k3d cluster list -o json | jq -r '.[].name' | grep -E '^(central|loja-[0-9]+)$$'); do k3d cluster delete $$c; done
	lab/nuvem.sh down
	lab/git.sh down
	-lab/atlantis.sh down 2>/dev/null
	@# Estado que enganaria a proxima subida (modo da central, estado do instalador, kubeconfigs).
	rm -rf lab/.cache/modo-central lab/.cache/estado-* lab/.cache/*.kubeconfig
	-@docker network rm k3s-gitops-edge >/dev/null 2>&1
