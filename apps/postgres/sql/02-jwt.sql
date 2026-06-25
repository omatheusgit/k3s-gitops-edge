-- JWT HS256 assinado no proprio banco, com a mesma chave que o PostgREST
-- usa para validar. Evita um servico de autenticacao so para o caixa.
create function loja.base64url(dado bytea) returns text
language sql immutable as $$
  select translate(rtrim(encode(dado, 'base64'), '='), E'+/\n', '-_');
$$;

create function loja.assinar_jwt(claims jsonb) returns text
language sql stable as $$
  with t as (
    select loja.base64url(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8'))
           || '.' || loja.base64url(convert_to(claims::text, 'utf8')) as corpo
  )
  select corpo || '.' || loja.base64url(hmac(corpo, current_setting('app.jwt_secret'), 'sha256'))
  from t;
$$;
