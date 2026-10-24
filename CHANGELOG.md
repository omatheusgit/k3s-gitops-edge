# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), versoes em [SemVer](https://semver.org/lang/pt-BR/).

## [1.0.0] - 2026-10-24

### Adicionado
- README com historia, diagramas, decisoes, aprendizados e limites; `docs/arquitetura.md`; `AGENTS.md`.
- Atlantis no lab, com webhook via `gh webhook forward` e GitHub App proprio.

## [0.4.0] - 2026-09-26

### Adicionado
- CI: shellcheck, kubeconform, politicas do repositorio, plano do Terraform no LocalStack, pytest, gitleaks, Trivy e e2e em k3d.
- Imagem do servico de eventos no GHCR com SBOM e proveniencia; release do instalador com sha256; Renovate.

### Corrigido
- Upsert do recibo sem permissao de `SELECT` (achado pelo e2e no runner).
- Imagem de eventos sem pip em runtime e com correcoes do Debian (achado pelo Trivy).

## [0.3.0] - 2026-08-22

### Adicionado
- Laboratorio em estagios (`lab/`): LocalStack + Terraform, central (Fleet ou Rancher), loja via instalador e teste e2e.
- Politicas do repositorio como codigo (`scripts/verificar-politicas.py`).

### Corrigido
- Namespaces da loja passam a ser criados pelo instalador; bundles com estado usam `keepResources`.
- Chromium do Gotenberg com FS somente leitura (`XDG_*`) e sem resolucao de nomes.
- Limite de entregas e fila de mortos do RabbitMQ via policy.

## [0.2.0] - 2026-06-27

### Adicionado
- Aplicacao da loja: Postgres (vendas, razao, outbox), PostgREST, caixa, Meilisearch, RabbitMQ, Redis, Gotenberg e o servico de eventos.
- Perfis `completo` e `enxuto`; `smoke/` para diagnostico.

### Corrigido
- `enableServiceLinks: false` em todos os pods (`API_PORT` injetado pelo Service `api`).

## [0.1.0] - 2026-04-25

### Adicionado
- Terraform `00-state` e `10-frota`: segredos gerados por loja, IAM por loja, parametros e bucket do instalador.
- Instalador (`stage0.sh` + `instalar.sh` com gum).
- Bundles de plataforma do Fleet e GitRepo da frota.
