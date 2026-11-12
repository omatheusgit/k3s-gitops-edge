-- migrate:up
-- Bloqueio de PIN por tentativas: 5 erros em 15 minutos travam o login daquele
-- operador ate a janela passar. O erro e devolvido com response.status (e nao
-- com raise), senao a transacao desfaz o registro da tentativa.
create table loja.tentativas_login (
  login text not null,
  em    timestamptz not null default now()
);
create index tentativas_login_recentes on loja.tentativas_login (login, em);

-- pg_temp por ultimo: sem isso, quem conecta direto no banco pode criar uma
-- tabela temporaria com o mesmo nome e ela vence dentro da funcao definer.
create or replace function api.entrar(login text, pin text) returns json
language plpgsql security definer set search_path = loja, public, pg_temp as $$
declare
  op loja.operadores;
  erros integer;
begin
  delete from loja.tentativas_login t where t.em < now() - interval '1 day';
  select count(*) into erros from loja.tentativas_login t
   where t.login = entrar.login and t.em > now() - interval '15 minutes';
  if erros >= 5 then
    perform set_config('response.status', '429', true);
    return json_build_object('message', 'muitas tentativas; aguarde alguns minutos');
  end if;

  select * into op from loja.operadores o where o.login = entrar.login and o.ativo;
  if op.id is null or op.pin_hash <> crypt(entrar.pin, op.pin_hash) then
    insert into loja.tentativas_login (login) values (entrar.login);
    perform set_config('response.status', '401', true);
    return json_build_object('message', 'login ou PIN invalido');
  end if;

  delete from loja.tentativas_login t where t.login = entrar.login;
  return json_build_object(
    'nome', op.nome,
    'token', loja.assinar_jwt(jsonb_build_object(
      'role', 'operador',
      'operador_id', op.id,
      'nome', op.nome,
      'exp', extract(epoch from now() + interval '12 hours')::bigint)));
end $$;

alter function api.registrar_venda(json) set search_path = loja, public, pg_temp;
alter function api.recibo(uuid) set search_path = loja, pg_temp;
alter function loja.confirmar_pagamento(uuid, text) set search_path = loja, pg_temp;

-- migrate:down
alter function loja.confirmar_pagamento(uuid, text) set search_path = loja;
alter function api.recibo(uuid) set search_path = loja;
alter function api.registrar_venda(json) set search_path = loja, public;

create or replace function api.entrar(login text, pin text) returns json
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

drop table loja.tentativas_login;
