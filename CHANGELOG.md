# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), versoes em [SemVer](https://semver.org/lang/pt-BR/).

## [1.2.0] - 2026-11-12

Versao da revisao adversarial: tres revisores (README, seguranca, lab/CI) acharam cerca de 60 problemas, que viraram as issues #25 a #36; esta versao fecha os mais graves.

### Adicionado
- Workflow `demo`: um dia de movimento na loja (vendas de dois operadores, pagamentos repetidos, estoque acabando), com relatorio no resumo do job e dump do banco como artefato (#21). Com `manter_no_ar`, o caixa fica num link publico temporario durante o job, conferido de fora pelo proprio job.
- e2e com a loja sem internet: rota cortada, AWS e central congeladas, pods reiniciados; login, venda e recibo precisam funcionar, e o External Secrets precisa voltar a ler a AWS depois (#35).
- e2e confere que a rede interna barra o caixa de chegar ao banco e a fila, e que o banco tem todas as migracoes aplicadas.
- Instalador: drop-in do k3s com GC de imagens a partir de 70% do disco, antes do despejo de pods (#23).
- `reprocessar-mortos` no servico de eventos; actionlint e politica de migracoes na CI.

### Seguranca
- Registro por loja no lugar do token de API do admin do Rancher, que toda loja lia do SSM (#25).
- Chave do JWT por loja, guardada numa tabela que so a funcao que assina le; a GUC legivel por qualquer sessao foi removida (#26).
- Operadores de demonstracao (PIN fixo) so no laboratorio; login bloqueia o operador depois de 5 PINs errados; `search_path` das funcoes `security definer` com `pg_temp` por ultimo (#27).
- Pagamento so quita a venda quando o valor confirmado bate com o total (#30).
- Painel do RabbitMQ fora da borda; smoke (whoami/podinfo) so em `ambiente=lab` (#28, #31).
- NetworkPolicy por destino dentro da loja (#31).
- Actions fixadas por SHA; k3d da release conferido por sha256 (#32).

### Corrigido
- Instalador roda num servidor recem-instalado: dependencias, kubectl do k3s, menu sem gum, servicelb de volta, SSH sem trancar o tecnico (#29).
- Nginx do caixa nao subia sem internet (resolvia o nome do proprio DNS pelos dominios de busca do no) (#51).
- Migracoes 6 e 7 fora do `configMapGenerator`, nunca aplicadas no cluster (#44).
- Perfil enxuto: filas sem consumidor cresciam ate o RabbitMQ bloquear os publishers; fila cheia agora devolve o evento ao outbox; erro passageiro pausa so a etapa (#30).
- `make up && make e2e` numa maquina limpa; imagem do eventos sempre reconstruida; `make down` limpa o estado; bash 3.2 para com mensagem clara (#33).
- CI: `shell: bash` (pipefail) em todo workflow, timeouts, filtros de caminho, disco do runner liberado, upload de artefato sem reprovar job (#34).

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
- Imagem do servico de eventos no GHCR com SBOM e proveniencia; pacote do instalador publicado no S3 com sha256 (`scripts/publicar-instalador.sh`); Renovate.

### Corrigido
- Upsert do recibo sem permissao de `SELECT` (aparecia como lentidao do Chromium no notebook).
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
