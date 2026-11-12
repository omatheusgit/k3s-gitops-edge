-- migrate:up
-- A chave do JWT ficava numa GUC do banco (alter database ... set
-- app.jwt_secret): qualquer sessao lia com current_setting, inclusive o papel
-- eventos. Agora fica numa tabela que so o dono le, e so a funcao que assina
-- (security definer) chega nela (#26).
create table loja.chave_jwt (
  unica   boolean primary key default true check (unica),
  segredo text not null
);
revoke all on loja.chave_jwt from public;
insert into loja.chave_jwt (segredo) values (current_setting('app.jwt_secret'));

create or replace function loja.assinar_jwt(claims jsonb) returns text
language sql stable security definer set search_path = loja, public, pg_temp as $$
  with t as (
    select loja.base64url(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8'))
           || '.' || loja.base64url(convert_to(claims::text, 'utf8')) as corpo
  )
  select corpo || '.' || loja.base64url(hmac(corpo, (select segredo from loja.chave_jwt), 'sha256'))
  from t;
$$;
revoke execute on function loja.assinar_jwt(jsonb) from public;

do $$
begin
  execute format('alter database %I reset app.jwt_secret', current_database());
end $$;

-- migrate:down
do $$
begin
  execute format('alter database %I set app.jwt_secret to %L', current_database(),
                 (select segredo from loja.chave_jwt));
end $$;

create or replace function loja.assinar_jwt(claims jsonb) returns text
language sql stable as $$
  with t as (
    select loja.base64url(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8'))
           || '.' || loja.base64url(convert_to(claims::text, 'utf8')) as corpo
  )
  select corpo || '.' || loja.base64url(hmac(corpo, current_setting('app.jwt_secret'), 'sha256'))
  from t;
$$;

drop table loja.chave_jwt;
