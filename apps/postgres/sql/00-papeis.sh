#!/bin/sh
# Roda uma unica vez, quando o volume do banco esta vazio (initdb).
# As senhas chegam por variavel de ambiente vindas do Secret loja-segredos.
set -eu

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v autenticador_senha="$AUTENTICADOR_SENHA" \
  -v eventos_senha="$EVENTOS_SENHA" \
  -v jwt_secret="$JWT_SECRET" <<'SQL'
-- PostgREST conecta como "autenticador" e troca para o papel do token.
create role autenticador login noinherit password :'autenticador_senha';
create role anonimo nologin;
create role operador nologin;
grant anonimo, operador to autenticador;

-- Usado pelos workers de eventos (outbox, recibos, pagamentos).
create role eventos login password :'eventos_senha';

alter database loja set app.jwt_secret to :'jwt_secret';
SQL
