-- migrate:up
-- Funcoes novas nao sao executaveis por PUBLIC; cada GRANT e explicito.
alter default privileges revoke execute on functions from public;

create extension if not exists pgcrypto;

create schema loja;
create schema api;

create table loja.produtos (
  id             serial primary key,
  sku            text not null unique,
  nome           text not null,
  preco_centavos integer not null check (preco_centavos > 0),
  estoque        integer not null default 0 check (estoque >= 0),
  atualizado_em  timestamptz not null default now()
);

create table loja.operadores (
  id       serial primary key,
  login    text not null unique,
  nome     text not null,
  pin_hash text not null,
  ativo    boolean not null default true
);

create table loja.vendas (
  id             uuid primary key default gen_random_uuid(),
  operador_id    integer not null references loja.operadores (id),
  total_centavos integer not null default 0,
  status         text not null default 'aguardando_pagamento'
                 check (status in ('aguardando_pagamento', 'paga', 'cancelada')),
  pagamento_ref  text unique,
  criada_em      timestamptz not null default now(),
  paga_em        timestamptz
);

create table loja.itens_venda (
  venda_id       uuid not null references loja.vendas (id) on delete cascade,
  produto_id     integer not null references loja.produtos (id),
  quantidade     integer not null check (quantidade > 0),
  preco_centavos integer not null,
  primary key (venda_id, produto_id)
);

-- Livro razao em partidas dobradas: debito positivo, credito negativo.
-- Todo fato contabil gera lancamentos que somam zero.
create table loja.lancamentos (
  id             bigserial primary key,
  venda_id       uuid not null references loja.vendas (id),
  conta          text not null check (conta in ('caixa', 'contas_a_receber', 'receita_vendas')),
  valor_centavos integer not null,
  historico      text not null,
  criado_em      timestamptz not null default now()
);

-- Transactional outbox: o evento e gravado na mesma transacao do fato.
-- O relay publica no RabbitMQ e marca publicado_em.
create table loja.outbox (
  id           bigserial primary key,
  tipo         text not null,
  payload      jsonb not null,
  criado_em    timestamptz not null default now(),
  publicado_em timestamptz
);
create index outbox_pendentes on loja.outbox (id) where publicado_em is null;

create table loja.recibos (
  venda_id  uuid primary key references loja.vendas (id),
  pdf       bytea not null,
  gerado_em timestamptz not null default now()
);

create function loja.avisa_outbox() returns trigger language plpgsql as $$
begin
  perform pg_notify('outbox', new.id::text);
  return new;
end $$;

create trigger outbox_notifica after insert on loja.outbox
  for each row execute function loja.avisa_outbox();

create function loja.produto_alterado() returns trigger language plpgsql as $$
begin
  insert into loja.outbox (tipo, payload)
  values ('produto.atualizado', jsonb_build_object(
    'id', new.id, 'sku', new.sku, 'nome', new.nome,
    'preco_centavos', new.preco_centavos, 'estoque', new.estoque));
  return new;
end $$;

create trigger produtos_outbox after insert or update on loja.produtos
  for each row execute function loja.produto_alterado();

-- migrate:down
drop schema api cascade;
drop schema loja cascade;
