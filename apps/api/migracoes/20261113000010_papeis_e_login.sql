-- migrate:up
-- Rodada 2 da revisao de seguranca.

-- O relay usava o papel "eventos", o mesmo do consumidor, que pode confirmar
-- pagamento: quem tomasse o relay quitava venda direto no banco. Papel proprio,
-- que so le e marca o outbox. A senha vem do Secret e e aplicada a cada deploy
-- pelo initContainer "papeis" da API.
do $$
begin
  if not exists (select from pg_roles where rolname = 'relay') then
    create role relay login;
  end if;
end $$;
grant usage on schema loja to relay;
grant select, update on loja.outbox to relay;

-- O papel eventos lia pin_hash: com ele, forca bruta offline nos PINs.
revoke select on loja.operadores from eventos;
grant select (id, nome) on loja.operadores to eventos;

-- Login: tentativas paralelas do mesmo operador passavam juntas pelo contador.
create or replace function api.entrar(login text, pin text) returns json
language plpgsql security definer set search_path = loja, public, pg_temp as $$
declare
  op loja.operadores;
  erros integer;
begin
  perform pg_advisory_xact_lock(hashtext('login:' || entrar.login));
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

-- migrate:down
revoke select (id, nome) on loja.operadores from eventos;
grant select on loja.operadores to eventos;
revoke select, update on loja.outbox from relay;
revoke usage on schema loja from relay;
drop role if exists relay;
