# Arquitetura

## Labels do cluster

O Fleet decide o que cada loja recebe pelos labels do cluster, definidos pelo instalador no registro.

| Label | Valores | Efeito |
| :-- | :-- | :-- |
| `loja` | `loja-NNN` | Seleciona o cluster no GitRepo da frota; vira o caminho do segredo (`lojas/<loja>/app`). |
| `regiao` | `sudeste`, `sul`, ... | Informativo (ConfigMap `loja-contexto`). |
| `perfil` | `completo`, `enxuto` | `enxuto` usa `apps/perfis/enxuto` (sem busca e sem PDF). |
| `ambiente` | `lab`, `producao` | `lab` aponta o ESO para o LocalStack; `producao` nao recebe `smoke/`. |
| `ip-lan` | IP | Cria a zona `<loja>.lan` no CoreDNS. |
| `registro-privado` | `true` | Cria o pull secret a partir de `frota/registry`. |

## Ordem dos bundles

```
00-namespaces ──> 10-external-secrets ──> 20-secret-store ──> 30-loja ──┐
      └──────────────────────────────────> 40-ingress ──────────────────┴──> apps
                                                └──> smoke
```

Cada `fleet.yaml` declara `labels.app.kubernetes.io/component` e depende dos anteriores por seletor desse label.

## Segredos

```
Terraform (random_password) ──> Secrets Manager lojas/<loja>/app ─┐
                               Secrets Manager frota/jwt ─────────┤
instalador ──> Secret external-secrets/aws-credenciais            │
                       │                                          │
                ClusterSecretStore "aws" (so namespace loja) <────┘
                       │
                ExternalSecret loja-segredos ──> Secret loja/loja-segredos
                       (senhas + PGRST_DB_URI, DATABASE_URL, AMQP_URL, REDIS_URL)
```

O unico Secret criado fora do GitOps e a chave AWS da loja, gravada pelo instalador.

## Rede da loja

- Namespace `loja` com Pod Security `restricted`.
- NetworkPolicy: tudo negado; liberado trafego interno, entrada do Traefik so para pods com `exposto: "sim"`, e DNS.
- Nenhuma aplicacao sai para a internet. O Chromium do Gotenberg nao resolve nenhum nome.
- Rotas por host (`pdv.*`, `webhook.*`, `rabbit.*`), entao o mesmo manifest serve `pdv.localhost` no lab e `pdv.loja-001.lan` na loja.

## Adicionar uma loja

1. Incluir a loja em `var.lojas` (`terraform/10-frota`) e abrir PR; o Atlantis comenta o plano.
2. Depois do apply, entregar `terraform output -json credenciais` ao tecnico (canal seguro).
3. No servidor: `curl -fsSL <stage0> | sudo -E bash` e escolher **instalar**.
4. Acompanhar em `./instalar.sh diagnostico` ou no Rancher.
