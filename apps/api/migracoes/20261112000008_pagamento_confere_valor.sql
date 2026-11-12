-- migrate:up
-- A confirmacao de pagamento passa a trazer o valor: so quita a venda se bater
-- com o total. Um "aprovado" de R$ 0,01 para uma venda de R$ 50 fica registrado
-- como divergencia e a venda continua aguardando pagamento.
create table loja.pagamentos_divergentes (
  id             bigserial primary key,
  venda_id       uuid not null references loja.vendas (id),
  pagamento_ref  text not null,
  valor_centavos integer not null,
  total_centavos integer,
  recebido_em    timestamptz not null default now(),
  unique (venda_id, pagamento_ref)
);

-- Retorna 'confirmado', 'ja_confirmado', 'divergente' ou 'venda_inexistente'.
create function loja.confirmar_pagamento(venda uuid, ref text, valor integer) returns text
language plpgsql security definer set search_path = loja, pg_temp as $$
declare
  v loja.vendas;
begin
  select * into v from loja.vendas where id = venda for update;
  if not found then
    return 'venda_inexistente';
  end if;
  if v.status <> 'aguardando_pagamento' then
    return 'ja_confirmado';
  end if;
  if v.total_centavos <> valor then
    insert into loja.pagamentos_divergentes (venda_id, pagamento_ref, valor_centavos, total_centavos)
    values (venda, ref, valor, v.total_centavos)
    on conflict (venda_id, pagamento_ref) do nothing;
    return 'divergente';
  end if;
  update loja.vendas set status = 'paga', paga_em = now(), pagamento_ref = ref where id = venda;
  insert into loja.lancamentos (venda_id, conta, valor_centavos, historico) values
    (venda, 'caixa', valor, 'pagamento ' || ref),
    (venda, 'contas_a_receber', -valor, 'pagamento ' || ref);
  insert into loja.outbox (tipo, payload)
  values ('venda.paga', jsonb_build_object('venda_id', venda, 'pagamento_ref', ref));
  return 'confirmado';
end $$;

revoke execute on function loja.confirmar_pagamento(uuid, text) from eventos;
drop function loja.confirmar_pagamento(uuid, text);
grant execute on function loja.confirmar_pagamento(uuid, text, integer) to eventos;

-- migrate:down
drop function loja.confirmar_pagamento(uuid, text, integer);
drop table loja.pagamentos_divergentes;

create function loja.confirmar_pagamento(venda uuid, ref text) returns boolean
language plpgsql security definer set search_path = loja, pg_temp as $$
declare
  total integer;
begin
  update vendas set status = 'paga', paga_em = now(), pagamento_ref = ref
   where id = venda and status = 'aguardando_pagamento'
  returning total_centavos into total;
  if not found then
    return false;
  end if;
  insert into lancamentos (venda_id, conta, valor_centavos, historico) values
    (venda, 'caixa', total, 'pagamento ' || ref),
    (venda, 'contas_a_receber', -total, 'pagamento ' || ref);
  insert into outbox (tipo, payload)
  values ('venda.paga', jsonb_build_object('venda_id', venda, 'pagamento_ref', ref));
  return true;
end $$;
grant execute on function loja.confirmar_pagamento(uuid, text) to eventos;
