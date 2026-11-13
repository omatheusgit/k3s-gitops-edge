# Decisões e limites

## Decisões

| Decisão | Por quê | Custo |
| :-- | :-- | :-- |
| **Fleet** e não Argo CD | Pensado para muitos clusters pequenos: o agente na loja puxa da central (só conexão de saída), e o alvo é escolhido por label. | Feedback mais lento: o `dependsOn` reavalia a cada poucos minutos. |
| **ESO com um store por loja** | A chave AWS fica num namespace que as aplicações não leem; a policy IAM abre só `lojas/<id>/app`, o registro da loja e `frota/registry`. | Senha nova no Secrets Manager não muda a do banco já inicializado (rotação exige migração). |
| **Usuário IAM por loja** | Simples e funciona fora da AWS, que é onde o servidor da loja está. | Chave de longa duração no servidor e no state; a alternativa é IAM Roles Anywhere. |
| **Liveness só por TCP** | Liveness que consulta banco reinicia a loja inteira quando o banco oscila. Readiness pode depender do banco. | Um processo travado com a porta aberta demora mais a ser detectado. |
| **PostgREST** em vez de API escrita à mão | Regras de negócio no banco, perto dos dados, que funcionam sem internet; o JWT é validado sem serviço extra. | A lógica fica em SQL. |
| **Outbox + RabbitMQ** | Venda e evento atômicos; recibo e indexação podem falhar e tentar de novo sem perder a venda. | Entrega pelo menos uma vez, então tudo precisa ser idempotente. |
| **Namespaces criados pelo instalador** | Namespace com banco não pode sumir junto com um release do Helm (ver [Aprendizados](aprendizados.md)). | Os labels de Pod Security desses namespaces ficam fora do GitOps. |
| **Migrações no `initContainer` da API** | No PostgREST o esquema é a API: ela só sobe com o banco na versão certa. Migração nova muda o hash do ConfigMap e o rollout aplica sozinho. | A API depende de o banco estar no ar para subir (o dbmate espera até 5 min). |
| **Rancher opcional** | O Fleet sozinho cabe em ~1 GB; o Rancher dá UI, RBAC e o import de clusters, mas pede ~3 GB a mais. | Dois caminhos de registro no instalador. |

## Limites conhecidos

- O LocalStack Community não aplica IAM, então o isolamento entre lojas só é garantido na AWS de verdade.
- Sem internet a loja vende (o e2e corta a rota, a AWS e a central e prova login, venda e recibo), mas a confirmação de pagamento e as atualizações esperam o link voltar.
- Sem backup do banco da loja, sem métricas nem alertas da frota e sem upgrade do K3s pelo GitOps (hoje, só reinstalando).
- O modo Rancher não cabe na memória do meu notebook: ele é provado no Actions, pelo workflow `rancher`. No dia a dia uso a central só com Fleet.
- O Atlantis do lab depende de um GitHub App próprio e do `gh webhook forward` aberto no terminal; não é um serviço sempre no ar.
- O recibo em PDF sai um por vez: de 20 a 30 por minuto no runner do Actions. Num pico, a venda não espera (o recibo é assíncrono), mas a fila de recibos leva alguns minutos para zerar; o workflow `demo` mede isso a cada execução.
- A rotação de senha do banco não é automática (ver Decisões). A chave do JWT e a senha do papel do relay, sim: vêm do Secret a cada deploy da API.
- Na rede da loja o caixa fala HTTP (PIN e JWT sem TLS na LAN). TLS local exige distribuir uma CA para os terminais do caixa, o que fica para quando houver terminal de verdade.
- O segredo do registro de imagens (`frota/registry`) é o mesmo para a frota: numa conta real, deve ser uma credencial só de leitura e só do pacote da loja.
- A instalação real do K3s e o `installer/lib/servidor.sh` (hardening do SO) nunca rodaram num servidor de verdade: o lab usa `SEM_K3S=1` e o hardening só rodou em `SIMULAR=1`.
