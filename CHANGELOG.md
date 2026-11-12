# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), versoes em [SemVer](https://semver.org/lang/pt-BR/).

## [Nao lancado]

### Adicionado
- `lab/demo/movimento.sh` e workflow `demo`: um dia de movimento na loja, com relatorio no resumo do job e dump do banco como artefato (#21).
- actionlint na CI.

### Seguranca
- Operadores de demonstracao (PIN fixo) e produtos de exemplo sairam das migracoes: `lab/semente.sql`, aplicada so pelo laboratorio; bancos existentes tem esses operadores desativados (#27).
- Login bloqueia o operador por 15 minutos depois de 5 PINs errados; bcrypt cost 10.
- Funcoes `security definer` com `pg_temp` por ultimo no `search_path` (tabela temporaria nao sombreia mais as tabelas da loja).

- Pagamento so quita a venda quando o valor confirmado bate com o total; divergencia fica em `loja.pagamentos_divergentes` (#30).

### Corrigido
<<<<<<< HEAD
- Perfil enxuto: filas sem consumidor (recibos, busca) nao sao mais criadas nem alimentadas; antes cresciam ate o RabbitMQ bloquear os publishers (#30).
- Consumidor: mensagem invalida vai direto para `mortos`; Gotenberg ou Meilisearch fora pausam so a propria etapa (cada etapa tem a sua conexao), sem o `sleep` dentro do callback que travava todas as filas. `python -m eventos reprocessar-mortos` devolve as mensagens.
- Fila cheia recusa publicacao: o evento fica no outbox do Postgres ate a fila andar.
=======
- Migracoes 6 e 7 nao estavam no `configMapGenerator` e nunca rodavam no cluster; a CI agora barra migracao fora do ConfigMap e o e2e confere `schema_migrations` (#44).
>>>>>>> origin/fix/migracoes-no-configmap
- `make up` so termina com a loja pronta e com os dados de demonstracao (`make semente`), entao `make up && make e2e` funciona de primeira.
- Todo workflow com `shell: bash` (pipefail): um `script | tee` passava verde com o script falhando.
- Prints do caixa escolhem produtos com estoque e registram o que a borda devolveu quando falham.
- Prints intermitentes: o runner entrava em DiskPressure e o kubelet despejava o `pdv-web`; o e2e e o demo liberam disco antes de subir o lab.
- Relatorio do demo com semente de fato fixa e espera dos recibos proporcional ao volume.

## [1.1.0] - 2026-11-11

Primeira versao com todo o trabalho entrando por PR, com Atlantis e e2e no Actions.

### Adicionado
- Migracoes de banco versionadas com dbmate, aplicadas antes da API subir (#6).
- Workflow `rancher`: Rancher 2.15 + loja importada pelo instalador, testado no Actions (#11).
- e2e com passo de resiliencia (Postgres derrubado no meio do teste) e prints do caixa gerados pelo CI (#15, #17).
- loja-004 no Nordeste, aplicada pelo Atlantis (#4).

### Corrigido
- Atlantis: v0.49.0 e `apply_requirements` possivel num repo de uma pessoa (#2).
- Plano do Terraform mexia na policy de todas as lojas ao abrir uma nova (#4).
- Cada pod recebe so os segredos que usa (#8).
- RabbitMQ e Postgres voltam depois de restart (`fsGroupChangePolicy`) (#13).
- Consumidor reconecta depois de perder o banco (#15).
- Modo Rancher: hostname unico, CA privada, espera do webhook e do CRD do Fleet (#11).

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
