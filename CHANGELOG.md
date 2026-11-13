# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), versões em [SemVer](https://semver.org/lang/pt-BR/).

## [1.3.0] - 2026-11-12

Versão da segunda revisão adversarial, que conferiu as correções da primeira e achou o que ainda dava para contornar. Todas as issues da revisão estão fechadas.

### Adicionado
- e2e nos dois perfis (completo e enxuto), com rotação da chave do webhook na AWS, um commit que precisa chegar sozinho na loja pelo Fleet e o instalador rodando de novo na mesma loja (#35).
- Perfis `lab-completo` e `lab-enxuto`: o lab testa a imagem do `eventos` construída do próprio PR, e produção usa a publicada por digest.
- `LICENSE` (MIT) e `SECURITY.md`, com aviso de segurança privado.

### Segurança
- Borda só aceita `localhost` e `loja-NNN.lan` (DNS rebinding); o nginx do caixa só tem a chave de busca do Meilisearch, derivada da mestra num initContainer (#31).
- Um usuário do RabbitMQ por processo, sem permissão de configurar o broker: filas, bindings e policies são do broker, e o relay não consegue publicar pagamento nem pela exchange de mortos (#28).
- Papel próprio do relay no banco (sem acesso a `confirmar_pagamento`); o papel `eventos` não lê `pin_hash`; chave do JWT e senha do relay sincronizadas do Secret a cada deploy; login com lock contra tentativas paralelas.
- Instalador assinado com Sigstore (identidade do `release.yml` numa tag), versão obrigatória e conferida contra o pacote; k3s e chart do Fleet por sha256; no modo Fleet, identidade secreta por loja e labels decididos pela central (#32).
- Imagens e actions por digest, inclusive as do CI; state do Terraform com chave KMS própria, só por TLS e só com KMS.
- Atlantis com workflow e requisitos de apply só no servidor.
- Traefik só nas portas de serviço dos pods expostos.

### Corrigido
- Workflow `imagem` vermelho: o pacote antigo ficou preso a outro repositório; agora é `k3s-gitops-edge-eventos` e os manifestos usam a 0.2.0, com as correções de eventos.
- `make up` depois de reiniciar o Docker: o LocalStack volta vazio e o lab recriava segredos com as lojas presas aos antigos; agora detecta (#33).
- CI: cache dos providers do Terraform, limpeza de disco em paralelo e prints só sob demanda (#34).

## [1.2.0] - 2026-11-12

Versão da primeira revisão adversarial: três frentes (README, segurança, lab/CI) acharam cerca de 60 problemas, que viraram as issues #25 a #36; esta versão fecha os mais graves.

### Adicionado
- Workflow `demo`: um dia de movimento na loja (vendas de dois operadores, pagamentos repetidos, estoque acabando), com relatório no resumo do job e dump do banco como artefato (#21). Com `manter_no_ar`, o caixa fica num link público temporário durante o job, conferido de fora pelo próprio job.
- e2e com a loja sem internet: rota cortada, AWS e central congeladas, pods reiniciados; login, venda e recibo precisam funcionar, e o External Secrets precisa voltar a ler a AWS depois (#35).
- e2e confere que a rede interna barra o caixa de chegar ao banco e a fila, e que o banco tem todas as migrações aplicadas.
- Instalador: drop-in do k3s com GC de imagens a partir de 70% do disco, antes do despejo de pods (#23).
- `reprocessar-mortos` no serviço de eventos; actionlint e política de migrações na CI.

### Segurança
- Registro por loja no lugar do token de API do admin do Rancher, que toda loja lia do SSM (#25).
- Chave do JWT por loja, guardada numa tabela que só a função que assina lê; a GUC legível por qualquer sessão foi removida (#26).
- Operadores de demonstração (PIN fixo) só no laboratório; login bloqueia o operador depois de 5 PINs errados; `search_path` das funções `security definer` com `pg_temp` por último (#27).
- Pagamento só quita a venda quando o valor confirmado bate com o total (#30).
- Painel do RabbitMQ fora da borda; smoke (whoami/podinfo) só em `ambiente=lab` (#28, #31).
- NetworkPolicy por destino dentro da loja (#31).
- Actions fixadas por SHA; k3d da release conferido por sha256 (#32).

### Corrigido
- Instalador roda num servidor recem-instalado: dependências, kubectl do k3s, menu sem gum, servicelb de volta, SSH sem trancar o tecnico (#29).
- Nginx do caixa não subia sem internet (resolvia o nome do próprio DNS pelos dominios de busca do no) (#51).
- Migrações 6 e 7 fora do `configMapGenerator`, nunca aplicadas no cluster (#44).
- Perfil enxuto: filas sem consumidor cresciam até o RabbitMQ bloquear os publishers; fila cheia agora devolve o evento ao outbox; erro passageiro pausa só a etapa (#30).
- `make up && make e2e` numa maquina limpa; imagem do eventos sempre reconstruida; `make down` limpa o estado; bash 3.2 para com mensagem clara (#33).
- CI: `shell: bash` (pipefail) em todo workflow, timeouts, filtros de caminho, disco do runner liberado, upload de artefato sem reprovar job (#34).

## [1.1.0] - 2026-11-11

Primeira versão com todo o trabalho entrando por PR, com Atlantis e e2e no Actions.

### Adicionado
- Migrações de banco versionadas com dbmate, aplicadas antes da API subir (#6).
- Workflow `rancher`: Rancher 2.15 + loja importada pelo instalador, testado no Actions (#11).
- e2e com passo de resiliencia (Postgres derrubado no meio do teste) e prints do caixa gerados pelo CI (#15, #17).
- loja-004 no Nordeste, aplicada pelo Atlantis (#4).

### Corrigido
- Atlantis: v0.49.0 e `apply_requirements` possível num repo de uma pessoa (#2).
- Plano do Terraform mexia na policy de todas as lojas ao abrir uma nova (#4).
- Cada pod recebe só os segredos que usa (#8).
- RabbitMQ e Postgres voltam depois de restart (`fsGroupChangePolicy`) (#13).
- Consumidor reconecta depois de perder o banco (#15).
- Modo Rancher: hostname único, CA privada, espera do webhook e do CRD do Fleet (#11).

## [1.0.0] - 2026-10-24

### Adicionado
- README com historia, diagramas, decisoes, aprendizados e limites; `docs/arquitetura.md`; `AGENTS.md`.
- Atlantis no lab, com webhook via `gh webhook forward` e GitHub App próprio.

## [0.4.0] - 2026-09-26

### Adicionado
- CI: shellcheck, kubeconform, políticas do repositório, plano do Terraform no LocalStack, pytest, gitleaks, Trivy e e2e em k3d.
- Imagem do serviço de eventos no GHCR com SBOM e proveniência; pacote do instalador publicado no S3 com sha256 (`scripts/publicar-instalador.sh`); configuração do Renovate.

### Corrigido
- Upsert do recibo sem permissão de `SELECT` (aparecia como lentidao do Chromium no notebook).
- Imagem de eventos sem pip em runtime e com correções do Debian (achado pelo Trivy).

## [0.3.0] - 2026-08-22

### Adicionado
- Laboratorio em estagios (`lab/`): LocalStack + Terraform, central (Fleet ou Rancher), loja via instalador e teste e2e.
- Politicas do repositório como código (`scripts/verificar-politicas.py`).

### Corrigido
- Namespaces da loja passam a ser criados pelo instalador; bundles com estado usam `keepResources`.
- Chromium do Gotenberg com FS somente leitura (`XDG_*`) e sem resolução de nomes.
- Limite de entregas e fila de mortos do RabbitMQ via policy.

## [0.2.0] - 2026-06-27

### Adicionado
- Aplicacao da loja: Postgres (vendas, razão, outbox), PostgREST, caixa, Meilisearch, RabbitMQ, Redis, Gotenberg e o serviço de eventos.
- Perfis `completo` e `enxuto`; `smoke/` para diagnostico.

### Corrigido
- `enableServiceLinks: false` em todos os pods (`API_PORT` injetado pelo Service `api`).

## [0.1.0] - 2026-04-25

### Adicionado
- Terraform `00-state` e `10-frota`: segredos gerados por loja, IAM por loja, parametros e bucket do instalador.
- Instalador (`stage0.sh` + `instalar.sh` com gum).
- Bundles de plataforma do Fleet e GitRepo da frota.
