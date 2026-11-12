#!/usr/bin/env bash
# Teste de ponta a ponta de uma loja, pela borda (Traefik), como o caixa usaria:
# login -> venda -> evento -> recibo PDF -> busca -> webhook de pagamento -> razao.
#   ./e2e.sh loja-001 [porta]
set -euo pipefail

LOJA="${1:-loja-001}"
PORTA="${2:-8080}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export KUBECONFIG="${RAIZ}/lab/.cache/${LOJA}.kubeconfig"
PDV="http://pdv.localhost:${PORTA}"
WEBHOOK="http://webhook.localhost:${PORTA}"
FALHAS=0

ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
nok() { printf '  \033[31mfalha\033[0m %s\n' "$*"; FALHAS=$((FALHAS + 1)); }
checar() { local desc="$1"; shift; if "$@"; then ok "${desc}"; else nok "${desc}"; fi; }
codigo() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
psql_loja() { kubectl -n loja exec postgres-0 -- psql -U postgres -d loja -Atc "$1"; }
esperar_ate() {
  local limite=$((SECONDS + $1)); shift
  until "$@"; do (( SECONDS > limite )) && return 1; sleep 2; done
}

"${RAIZ}/lab/semente.sh" "${LOJA}"
echo "Loja ${LOJA} em ${PDV}"

MIGRACOES_REPO="$(find "${RAIZ}/apps/api/migracoes" -name '*.sql' | wc -l)"
checar "banco com todas as ${MIGRACOES_REPO} migracoes do repositorio aplicadas" \
  test "$(psql_loja 'select count(*) from public.schema_migrations')" = "${MIGRACOES_REPO}"
checar "tela do caixa responde" test "$(codigo "${PDV}/")" = 200
checar "cabecalhos de seguranca na tela" bash -c "curl -sI '${PDV}/' | grep -qi '^x-frame-options: DENY'"
checar "API recusa quem nao fez login" test "$(codigo "${PDV}/api/produtos")" = 401
checar "PIN errado e recusado" test "$(codigo -X POST "${PDV}/api/rpc/entrar" \
  -H 'Content-Type: application/json' -d '{"login":"caixa1","pin":"0000"}')" = 401

TOKEN="$(curl -fsS -X POST "${PDV}/api/rpc/entrar" -H 'Content-Type: application/json' \
  -d '{"login":"caixa1","pin":"1234"}' | jq -r .token)"
AUTH=(-H "Authorization: Bearer ${TOKEN}")
checar "login do caixa devolve JWT" test "${TOKEN%%.*}" = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"

ESTOQUE_ANTES="$(curl -fsS "${AUTH[@]}" "${PDV}/api/produtos?id=eq.1" | jq '.[0].estoque')"
VENDA="$(curl -fsS -X POST "${PDV}/api/rpc/registrar_venda" "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d '{"itens":[{"produto_id":1,"quantidade":2},{"produto_id":7,"quantidade":1}]}')"
VENDA_ID="$(jq -r .venda_id <<<"${VENDA}")"
TOTAL="$(jq -r .total_centavos <<<"${VENDA}")"
checar "venda registrada (${VENDA_ID:0:8}, $(jq .total_centavos <<<"${VENDA}") centavos)" test -n "${VENDA_ID}"
checar "estoque baixou" test "$(curl -fsS "${AUTH[@]}" "${PDV}/api/produtos?id=eq.1" | jq '.[0].estoque')" -eq $((ESTOQUE_ANTES - 2))
checar "venda sem estoque e recusada" test "$(codigo -X POST "${PDV}/api/rpc/registrar_venda" "${AUTH[@]}" \
  -H 'Content-Type: application/json' -d '{"itens":[{"produto_id":1,"quantidade":99999}]}')" = 400

tem_recibo() { curl -fsS "${AUTH[@]}" "${PDV}/api/vendas?id=eq.${VENDA_ID}" | jq -e '.[0].tem_recibo' >/dev/null; }
checar "evento saiu do outbox e o recibo foi gerado (Gotenberg)" esperar_ate 90 tem_recibo
checar "recibo baixa como PDF" bash -c "curl -fsS -H 'Authorization: Bearer ${TOKEN}' -H 'Accept: application/pdf' \
  '${PDV}/api/rpc/recibo?venda=${VENDA_ID}' | head -c 4 | grep -q '%PDF'"

achou_na_busca() {
  curl -fsS -X POST "${AUTH[@]}" -H 'Content-Type: application/json' -d '{"q":"cafe torado"}' \
    "${PDV}/busca/indexes/produtos/search" | jq -e '.hits | length > 0' >/dev/null
}
checar "busca acha produto mesmo com erro de digitacao" esperar_ate 60 achou_na_busca
checar "busca exige JWT (forwardAuth no Traefik)" test "$(codigo -X POST -H 'Content-Type: application/json' \
  -d '{"q":"cafe"}' "${PDV}/busca/indexes/produtos/search")" = 401
checar "busca nao expoe a API administrativa do Meilisearch" test "$(codigo "${AUTH[@]}" "${PDV}/busca/keys")" = 404
checar "pod do caixa alcanca a busca, que ele usa (controle do teste abaixo)" \
  kubectl -n loja exec deploy/pdv-web -- nc -z -w 3 busca 7700
checar "pod do caixa nao alcanca o banco nem a fila (NetworkPolicy por destino)" bash -c \
  "! kubectl -n loja exec deploy/pdv-web -- sh -c 'nc -z -w 3 postgres 5432 || nc -z -w 3 rabbitmq 5672' 2>/dev/null"

SEGREDO="$(kubectl -n loja get secret loja-segredos -o jsonpath='{.data.webhook_hmac}' | base64 -d)"
EVENTO="pg-$(date +%s)"
CORPO="$(jq -cn --arg e "${EVENTO}-baixo" --arg v "${VENDA_ID}" '{evento_id: $e, venda_id: $v, valor_centavos: 1, status: "aprovado"}')"
TS="$(date +%s)"
ASSINATURA="sha256=$(printf '%s.%s' "${TS}" "${CORPO}" | openssl dgst -sha256 -hmac "${SEGREDO}" -r | cut -d' ' -f1)"
checar "pagamento com valor errado e aceito pelo webhook..." test "$(codigo -X POST "${WEBHOOK}/pagamentos/confirmacao" \
  -H 'Content-Type: application/json' -H "X-Timestamp: ${TS}" -H "X-Assinatura: ${ASSINATURA}" -d "${CORPO}")" = 202
divergente() { test "$(psql_loja "select count(*) from loja.pagamentos_divergentes where venda_id = '${VENDA_ID}'")" = 1; }
checar "...mas nao quita a venda: fica registrado como divergente" esperar_ate 60 divergente
checar "venda continua aguardando pagamento" test "$(psql_loja "select status from loja.vendas where id = '${VENDA_ID}'")" = aguardando_pagamento

CORPO="$(jq -cn --arg e "${EVENTO}" --arg v "${VENDA_ID}" --argjson t "${TOTAL}" '{evento_id: $e, venda_id: $v, valor_centavos: $t, status: "aprovado"}')"
TS="$(date +%s)"
ASSINATURA="sha256=$(printf '%s.%s' "${TS}" "${CORPO}" | openssl dgst -sha256 -hmac "${SEGREDO}" -r | cut -d' ' -f1)"
enviar() { codigo -X POST "${WEBHOOK}/pagamentos/confirmacao" -H 'Content-Type: application/json' \
  -H "X-Timestamp: $1" -H "X-Assinatura: $2" -d "${CORPO}"; }

checar "webhook com assinatura errada e recusado" test "$(enviar "${TS}" "sha256=00")" = 401
checar "webhook antigo (replay fora da janela) e recusado" test "$(enviar $((TS - 600)) "${ASSINATURA}")" = 401
checar "webhook valido e aceito" test "$(enviar "${TS}" "${ASSINATURA}")" = 202
checar "webhook repetido e tratado como duplicado" bash -c "curl -s -X POST '${WEBHOOK}/pagamentos/confirmacao' \
  -H 'Content-Type: application/json' -H 'X-Timestamp: ${TS}' -H 'X-Assinatura: ${ASSINATURA}' -d '${CORPO}' | grep -q duplicado"

paga() { curl -fsS "${AUTH[@]}" "${PDV}/api/vendas?id=eq.${VENDA_ID}" | jq -e '.[0].status == "paga"' >/dev/null; }
checar "venda ficou paga" esperar_ate 60 paga
checar "razao fecha em zero (partidas dobradas)" test "$(psql_loja 'select sum(valor_centavos) from loja.lancamentos')" = 0
checar "pagamento lancado uma vez so" test "$(psql_loja "select count(*) from loja.lancamentos where venda_id = '${VENDA_ID}' and conta = 'caixa'")" = 1
checar "nenhum evento pendente no outbox" esperar_ate 30 test "$(psql_loja 'select count(*) from loja.outbox where publicado_em is null')" = 0

echo
echo "Resiliencia: o Postgres reinicia no meio da operacao"
VENDAS_ANTES="$(psql_loja 'select count(*) from loja.vendas')"
kubectl -n loja delete pod postgres-0 --wait=false >/dev/null
sleep 5
kubectl -n loja wait --for=condition=Ready pod/postgres-0 --timeout=300s >/dev/null
checar "dados sobreviveram ao restart" test "$(psql_loja 'select count(*) from loja.vendas')" = "${VENDAS_ANTES}"

nova_venda() {
  curl -fsS -X POST "${PDV}/api/rpc/registrar_venda" "${AUTH[@]}" -H 'Content-Type: application/json' \
    -d '{"itens":[{"produto_id":2,"quantidade":1}]}' 2>/dev/null | jq -c 'select(.venda_id)'
}
VENDA2=""; TOTAL2=""
venda_depois_do_restart() {
  local r; r="$(nova_venda)" || return 1
  VENDA2="$(jq -r .venda_id <<<"${r}")"; TOTAL2="$(jq -r .total_centavos <<<"${r}")"; [[ -n "${VENDA2}" ]]
}
checar "API volta a vender sozinha depois do restart" esperar_ate 120 venda_depois_do_restart
VENDA_ID="${VENDA2}"
checar "consumidor reconectou e gerou o recibo da venda nova" esperar_ate 180 tem_recibo
CORPO="$(jq -cn --arg e "pg-$(date +%s)-2" --arg v "${VENDA2}" --argjson t "${TOTAL2}" '{evento_id: $e, venda_id: $v, valor_centavos: $t, status: "aprovado"}')"
TS="$(date +%s)"
ASSINATURA="sha256=$(printf '%s.%s' "${TS}" "${CORPO}" | openssl dgst -sha256 -hmac "${SEGREDO}" -r | cut -d' ' -f1)"
checar "pagamento da venda nova aceito" test "$(enviar "${TS}" "${ASSINATURA}")" = 202
checar "venda nova ficou paga" esperar_ate 120 paga
checar "razao continua fechando em zero" test "$(psql_loja 'select sum(valor_centavos) from loja.lancamentos')" = 0

echo
echo "Sem internet: a loja perde a rota para fora, a AWS e a central"
NO_LOJA="k3d-${LOJA}-server-0"
mapfile -t FORA < <(echo localstack; echo git-lab; docker ps --format '{{.Names}}' | grep '^k3d-central-' || true)
ROTA="$(docker exec "${NO_LOJA}" ip route show default | head -1)"
religar() {
  docker unpause "${FORA[@]}" >/dev/null 2>&1 || true
  [[ -z "${ROTA}" ]] || docker exec "${NO_LOJA}" sh -c "ip route show default | grep -q . || ip route add ${ROTA}" || true
}
trap religar EXIT
docker exec "${NO_LOJA}" ip route del default
docker pause "${FORA[@]}" >/dev/null
checar "o servidor da loja ficou sem rota para fora" bash -c "! docker exec '${NO_LOJA}' ip route show default | grep -q ."
# Reinicia o que o caixa usa: as imagens ja estao no no e os Secrets no
# cluster, entao nada disso pode depender de internet para voltar.
kubectl -n loja rollout restart deploy/api deploy/pdv-web deploy/eventos-consumidor deploy/eventos-relay >/dev/null
checar "API, caixa e eventos voltam sem internet" kubectl -n loja rollout status deploy/api deploy/pdv-web \
  deploy/eventos-consumidor deploy/eventos-relay --timeout=5m
TOKEN_OFF=""
entrar_off() { TOKEN_OFF="$(curl -fsS -X POST "${PDV}/api/rpc/entrar" -H 'Content-Type: application/json' \
  -d '{"login":"caixa2","pin":"4321"}' 2>/dev/null | jq -r '.token // empty')"; [[ -n "${TOKEN_OFF}" ]]; }
checar "login sem internet" esperar_ate 120 entrar_off
VENDA_OFF="$(curl -fsS -X POST "${PDV}/api/rpc/registrar_venda" -H "Authorization: Bearer ${TOKEN_OFF}" \
  -H 'Content-Type: application/json' -d '{"itens":[{"produto_id":4,"quantidade":1}]}' | jq -r '.venda_id // empty')" || true
checar "venda sem internet" test -n "${VENDA_OFF}"
recibo_off() { curl -fsS -H "Authorization: Bearer ${TOKEN_OFF}" "${PDV}/api/vendas?id=eq.${VENDA_OFF}" | jq -e '.[0].tem_recibo' >/dev/null; }
checar "recibo em PDF sem internet (tudo local: outbox, fila, Gotenberg)" esperar_ate 180 recibo_off
checar "razao fecha em zero sem internet" test "$(psql_loja 'select sum(valor_centavos) from loja.lancamentos')" = 0

religar
trap - EXIT
checar "rota de volta" bash -c "docker exec '${NO_LOJA}' ip route show default | grep -q ."
# O refresh normal e de 1h: forca uma leitura nova para provar que voltou a AWS.
ANTES_SYNC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
kubectl -n loja annotate externalsecret --all force-sync="$(date +%s)" --overwrite >/dev/null
externalsecret_ok() {
  kubectl -n loja get externalsecret -o json | jq -e --arg t "${ANTES_SYNC}" \
    '[.items[].status | (.refreshTime // "") >= $t and any(.conditions[]?; .type == "Ready" and .status == "True")] | all' >/dev/null
}
checar "External Secrets volta a ler a AWS" esperar_ate 180 externalsecret_ok

echo
if (( FALHAS == 0 )); then echo "tudo certo"; else echo "${FALHAS} falha(s)"; exit 1; fi
