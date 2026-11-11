-- migrate:up
-- Schema exposto pelo PostgREST. Nada de tabela direta: so views e funcoes.

create function api.entrar(login text, pin text) returns json
language plpgsql security definer set search_path = loja, public as $$
declare
  op loja.operadores;
begin
  select * into op from loja.operadores o where o.login = entrar.login and o.ativo;
  if op.id is null or op.pin_hash <> crypt(entrar.pin, op.pin_hash) then
    raise insufficient_privilege using message = 'login ou PIN invalido';
  end if;
  return json_build_object(
    'nome', op.nome,
    'token', loja.assinar_jwt(jsonb_build_object(
      'role', 'operador',
      'operador_id', op.id,
      'nome', op.nome,
      'exp', extract(epoch from now() + interval '12 hours')::bigint)));
end $$;

-- Usado pelo forwardAuth do Traefik: 200 com token valido, 401 sem.
create function api.autorizar() returns json
language plpgsql stable as $$
declare
  nome text := current_setting('request.jwt.claims', true)::json ->> 'nome';
begin
  perform set_config('response.headers', json_build_array(json_build_object('X-Operador', nome))::text, true);
  return json_build_object('operador', nome);
end $$;

create view api.produtos with (security_invoker = true) as
  select id, sku, nome, preco_centavos, estoque from loja.produtos;

create view api.vendas with (security_invoker = true) as
  select v.id, v.total_centavos, v.status, v.criada_em, v.paga_em,
         exists (select 1 from loja.recibos r where r.venda_id = v.id) as tem_recibo
  from loja.vendas v;

create function api.registrar_venda(itens json) returns json
language plpgsql security definer set search_path = loja, public as $$
declare
  operador integer := (current_setting('request.jwt.claims', true)::json ->> 'operador_id')::integer;
  venda uuid;
  total integer := 0;
  preco integer;
  item record;
begin
  if operador is null then
    raise insufficient_privilege using message = 'token sem operador';
  end if;
  if itens is null or json_array_length(itens) = 0 then
    raise exception 'venda sem itens' using errcode = '22023';
  end if;

  insert into vendas (operador_id) values (operador) returning id into venda;

  for item in
    select (e ->> 'produto_id')::integer as produto_id, (e ->> 'quantidade')::integer as quantidade
    from json_array_elements(itens) e
  loop
    update produtos
       set estoque = estoque - item.quantidade, atualizado_em = now()
     where id = item.produto_id and estoque >= item.quantidade
    returning preco_centavos into preco;
    if not found then
      raise exception 'produto % sem estoque suficiente', item.produto_id using errcode = '22023';
    end if;
    insert into itens_venda (venda_id, produto_id, quantidade, preco_centavos)
    values (venda, item.produto_id, item.quantidade, preco);
    total := total + preco * item.quantidade;
  end loop;

  update vendas set total_centavos = total where id = venda;

  insert into lancamentos (venda_id, conta, valor_centavos, historico) values
    (venda, 'contas_a_receber', total, 'venda registrada'),
    (venda, 'receita_vendas', -total, 'venda registrada');

  insert into outbox (tipo, payload)
  values ('venda.registrada', jsonb_build_object('venda_id', venda, 'total_centavos', total));

  return json_build_object('venda_id', venda, 'total_centavos', total, 'status', 'aguardando_pagamento');
end $$;

-- PostgREST devolve o tipo do dominio como Content-Type.
create domain "application/pdf" as bytea;

create function api.recibo(venda uuid) returns "application/pdf"
language sql stable security definer set search_path = loja as $$
  select pdf from recibos where venda_id = venda;
$$;

-- Chamado pelo worker de pagamentos. Idempotente: so a primeira
-- confirmacao de uma venda muda o estado e gera lancamentos.
create function loja.confirmar_pagamento(venda uuid, ref text) returns boolean
language plpgsql security definer set search_path = loja as $$
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

-- migrate:down
drop function loja.confirmar_pagamento(uuid, text);
drop function api.recibo(uuid);
drop domain "application/pdf";
drop function api.registrar_venda(json);
drop view api.vendas;
drop view api.produtos;
drop function api.autorizar();
drop function api.entrar(text, text);
