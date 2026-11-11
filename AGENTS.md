# AGENTS.md

Regras deste repositorio para quem (pessoa ou agente) for alterar algo.

## Fluxo
- Toda mudanca entra por issue -> branch -> PR, com CI verde. Commits em conventional commits, em portugues.
- Mudanca de Terraform passa pelo plano do Atlantis/CI antes do apply.

## Invariantes (a CI confere)
- Nenhum segredo no git. Segredo nasce no Terraform (`random_password`) e chega ao cluster pelo External Secrets.
- Todo container: `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, seccomp `RuntimeDefault`, request e limit de memoria, tag fixa.
- Todo pod: `enableServiceLinks: false`.
- `livenessProbe` nunca HTTP e nunca dependente de banco/broker; essa dependencia so na readiness.
- FS somente leitura exige `emptyDir` para tudo que a aplicacao grava (`/tmp`, cache, socket).

## Decisoes que nao devem ser desfeitas sem discussao
- Namespaces `loja` e `external-secrets` sao criados pelo instalador, nao por bundle (dados nao podem depender de release do Helm).
- Bundles com estado usam `keepResources: true`.
- Nao usar `forceSyncGeneration` em producao.
- Argumentos de fila do RabbitMQ so `x-queue-type`; o resto vai em policy.
- Consumidores de eventos precisam ser idempotentes (entrega pelo menos uma vez).
- Mudanca de esquema = migracao nova em `apps/api/migracoes/` (com `-- migrate:down`). Nunca editar uma migracao ja aplicada.

## Onde mexer
- `platform/`: bundles de cluster (ordem pelos prefixos numericos).
- `apps/`: aplicacao da loja; perfis em `apps/perfis/`.
- `installer/`: roda no servidor da loja; tem que funcionar sem terminal (`SIM=1`).
- `lab/`: so laboratorio, nunca usado em producao.
