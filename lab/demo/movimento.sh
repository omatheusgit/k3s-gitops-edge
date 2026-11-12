#!/usr/bin/env bash
# Simula um dia de movimento numa loja do laboratorio, pela borda (Traefik):
# dois operadores vendendo, pagamentos chegando pelo webhook (alguns repetidos,
# como um gateway de pagamento faz), estoque acabando. No fim imprime um
# relatorio em Markdown com o que ficou no banco, na fila e no razao.
#   ./movimento.sh loja-001 [porta] [vendas] [saida-do-dump]
set -euo pipefail

LOJA="${1:-loja-001}"
PORTA="${2:-8080}"
VENDAS="${3:-60}"
DUMP="${4:-}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export KUBECONFIG="${RAIZ}/lab/.cache/${LOJA}.kubeconfig"
PDV="http://pdv.localhost:${PORTA}"
WEBHOOK="http://webhook.localhost:${PORTA}"

# Semente fixa: a mesma quantidade de vendas gera o mesmo movimento.
RANDOM=42

psql_loja() { kubectl -n loja exec postgres-0 -- psql -U postgres -d loja -Atc "$1"; }
# pg_temp.reais(): centavos -> "2.540,72"; vive so na sessao do psql.
REAIS="create function pg_temp.reais(centavos numeric) returns text language sql immutable
  as \$\$ select translate(to_char(centavos / 100.0, 'FM999G999G990D00'), ',.', '.,') \$\$;"
tabela_md() { kubectl -n loja exec postgres-0 -- psql -U postgres -d loja -qAF ' | ' -c "${REAIS} $1" \
  | sed '$d' | awk 'NR == 1 { print "| " $0 " |"; n = gsub(/\|/, "|"); s = "|"; for (i = 0; i <= n; i++) s = s " --- |"; print s; next } { print "| " $0 " |" }'; }
log() { printf '%s\n' "$*" >&2; }
CORPO="$(mktemp)"; LIMITES="$(mktemp)"; trap 'rm -f "${CORPO}" "${LIMITES}"' EXIT

entrar() {
  curl -fsS -X POST "${PDV}/api/rpc/entrar" -H 'Content-Type: application/json' \
    -d "{\"login\":\"$1\",\"pin\":\"$2\"}" | jq -r .token
}
"${RAIZ}/lab/semente.sh" "${LOJA}" >&2
TOKENS=("$(entrar caixa1 1234)" "$(entrar caixa2 4321)")
SEGREDO="$(kubectl -n loja get secret loja-segredos -o jsonpath='{.data.webhook_hmac}' | base64 -d)"

# POST com reenvio quando a borda limita a taxa (429), como um cliente educado
# faria. Roda em subshell, entao conta os 429 num arquivo.
postar() {
  local saida tentativa
  for tentativa in 1 2 3 4 5; do
    saida="$(curl -s -o "${CORPO}" -w '%{http_code} %{time_total}' "$@")"
    [[ "${saida%% *}" != 429 ]] && break
    echo >> "${LIMITES}"; sleep "${tentativa}"
  done
  printf '%s\n' "${saida}"
}

pagar() {
  local venda="$1" evento="$2" corpo ts assinatura
  corpo="$(jq -cn --arg e "${evento}" --arg v "${venda}" '{evento_id: $e, venda_id: $v, status: "aprovado"}')"
  ts="$(date +%s)"
  assinatura="sha256=$(printf '%s.%s' "${ts}" "${corpo}" | openssl dgst -sha256 -hmac "${SEGREDO}" -r | cut -d' ' -f1)"
  postar -X POST "${WEBHOOK}/pagamentos/confirmacao" -H 'Content-Type: application/json' \
    -H "X-Timestamp: ${ts}" -H "X-Assinatura: ${assinatura}" -d "${corpo}" | cut -d' ' -f1
}

OK=0; SEM_ESTOQUE=0; OUTROS=0; PAGAMENTOS=0; REPETIDOS=0
TEMPOS=()
INICIO=${SECONDS}
log "Movimento de ${VENDAS} vendas em ${PDV}"

for ((n = 1; n <= VENDAS; n++)); do
  token="${TOKENS[RANDOM % 2]}"
  # 1 a 3 itens distintos, 1 ou 2 unidades cada.
  declare -A escolhidos=()
  while (( ${#escolhidos[@]} < RANDOM % 3 + 1 )); do escolhidos[$((RANDOM % 8 + 1))]=1; done
  # Sorteio fora de subshell: o bash troca a semente do RANDOM em cada $(...).
  itens=""
  for p in $(printf '%s\n' "${!escolhidos[@]}" | sort -n); do
    itens+="${itens:+,}{\"produto_id\":${p},\"quantidade\":$((RANDOM % 2 + 1))}"
  done
  itens="[${itens}]"
  unset escolhidos
  read -r codigo tempo < <(postar -X POST "${PDV}/api/rpc/registrar_venda" \
    -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' -d "{\"itens\":${itens}}")
  case "${codigo}" in
    200)
      OK=$((OK + 1)); TEMPOS+=("${tempo}")
      venda="$(jq -r .venda_id "${CORPO}")"
      # ~85% pagam; ~10% dos pagamentos chegam duas vezes.
      if (( RANDOM % 100 < 85 )); then
        [[ "$(pagar "${venda}" "pg-${venda}")" == 202 ]] && PAGAMENTOS=$((PAGAMENTOS + 1))
        if (( RANDOM % 100 < 10 )); then pagar "${venda}" "pg-${venda}" >/dev/null; REPETIDOS=$((REPETIDOS + 1)); fi
      fi ;;
    400) SEM_ESTOQUE=$((SEM_ESTOQUE + 1)) ;;
    *) OUTROS=$((OUTROS + 1)); log "venda ${n}: HTTP ${codigo} $(head -c 200 "${CORPO}")" ;;
  esac
  (( n % 20 == 0 )) && log "  ${n}/${VENDAS}"
done
DURACAO=$((SECONDS - INICIO))
LIMITADAS="$(wc -l < "${LIMITES}")"

# Espera o assincrono assentar: outbox vazio, recibo para toda venda e todo
# pagamento aceito refletido na venda (gateway -> fila -> consumidor).
# O recibo e assincrono e sai um por vez (~20/min num runner do Actions): um
# pico de vendas vira fila, nao erro. A espera cresce com o volume.
ESPERA=$(( VENDAS * 6 > 180 ? VENDAS * 6 : 180 )); (( ESPERA > 900 )) && ESPERA=900
log "Esperando outbox, pagamentos e recibos (ate ${ESPERA}s)..."
limite=$((SECONDS + ESPERA))
while (( SECONDS < limite )); do
  pendentes="$(psql_loja "select (select count(*) from loja.outbox where publicado_em is null)
    + (select count(*) from loja.vendas v where not exists (select 1 from loja.recibos r where r.venda_id = v.id))
    + ${PAGAMENTOS} - (select count(*) from loja.vendas where status = 'paga')")"
  [[ "${pendentes}" == 0 ]] && break
  sleep 3
done
FILA_RECIBOS=$((SECONDS - INICIO - DURACAO))
POR_MINUTO="$(psql_loja "select round(count(*) * 60 / greatest(extract(epoch from max(gerado_em) - min(gerado_em)), 1))
  from loja.recibos")"

percentil() { printf '%s\n' "${TEMPOS[@]}" | sort -n | awk -v p="$1" '{ v[NR] = $1 } END { i = int(NR * p + 0.999); if (i < 1) i = 1; printf "%.0f", v[i] * 1000 }'; }
P50="$(percentil 0.50)"; P95="$(percentil 0.95)"

cat <<EOF
## Um dia de movimento na ${LOJA}

${VENDAS} tentativas de venda em ${DURACAO}s, de dois operadores, pela borda (Traefik → PostgREST).

| | |
| :-- | --: |
| vendas registradas | ${OK} |
| recusadas por falta de estoque | ${SEM_ESTOQUE} |
| outras falhas | ${OUTROS} |
| pagamentos confirmados pelo webhook | ${PAGAMENTOS} |
| pagamentos reenviados (deveriam ser ignorados) | ${REPETIDOS} |
| requisições limitadas pela borda (429, reenviadas) | ${LIMITADAS} |
| latência de \`registrar_venda\` p50 / p95 | ${P50} ms / ${P95} ms |
| recibos em PDF por minuto (Gotenberg, um por vez) | ${POR_MINUTO} |
| tempo até a fila de recibos zerar depois da última venda | ${FILA_RECIBOS}s |

### Vendas

$(tabela_md "select status, count(*) as vendas, pg_temp.reais(sum(total_centavos)) as \"total (R\$)\",
  pg_temp.reais(avg(total_centavos)) as \"ticket medio (R\$)\",
  count(*) filter (where exists (select 1 from loja.recibos r where r.venda_id = v.id)) as com_recibo
  from loja.vendas v group by status order by status")

### Razão (partidas dobradas)

$(tabela_md "select coalesce(conta, 'total') as conta, count(*) as lancamentos,
  pg_temp.reais(sum(valor_centavos)) as \"saldo (R\$)\"
  from loja.lancamentos group by rollup(conta) order by grouping(conta), conta")

Débito positivo, crédito negativo: a linha \`total\` tem que ser zero.

### Produtos mais vendidos

$(tabela_md "select p.nome as produto, sum(i.quantidade) as unidades, p.estoque as estoque_final
  from loja.itens_venda i join loja.produtos p on p.id = i.produto_id group by p.nome, p.estoque order by 2 desc limit 5")

### Filas no RabbitMQ

\`\`\`
$(kubectl -n loja exec rabbitmq-0 -- rabbitmqctl -q list_queues name messages consumers 2>/dev/null || echo "indisponivel")
\`\`\`

### Conferência

EOF

FALHOU=0
conf() { local desc="$1"; shift; if "$@"; then echo "- ✅ ${desc}"; else echo "- ❌ ${desc}"; FALHOU=1; fi; }
# shellcheck disable=SC2329  # chamada indiretamente por conf
zero() { [[ "$(psql_loja "$1")" == 0 ]]; }
conf "razão fecha em zero" zero "select coalesce(sum(valor_centavos), 0) from loja.lancamentos"
conf "toda venda tem recibo em PDF" zero \
  "select count(*) from loja.vendas v where not exists (select 1 from loja.recibos r where r.venda_id = v.id)"
conf "nenhum evento parado no outbox" zero "select count(*) from loja.outbox where publicado_em is null"
conf "pagamento repetido não lançou de novo" zero \
  "select count(*) from (select venda_id from loja.lancamentos where conta = 'caixa' group by venda_id having count(*) > 1) x"
conf "vendas pagas = pagamentos confirmados" zero "select count(*) - ${PAGAMENTOS} from loja.vendas where status = 'paga'"
conf "nenhuma falha inesperada" test "${OUTROS}" = 0
echo

if [[ -n "${DUMP}" ]]; then
  kubectl -n loja exec postgres-0 -- pg_dump -U postgres -d loja --no-owner | gzip > "${DUMP}"
  log "Dump do banco em ${DUMP}"
fi
exit "${FALHOU}"
