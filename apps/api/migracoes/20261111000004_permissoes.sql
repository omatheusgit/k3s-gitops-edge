-- migrate:up
grant usage on schema api to anonimo, operador;
grant execute on function api.entrar(text, text) to anonimo, operador;

grant usage on schema loja to operador;
grant select on loja.produtos, loja.vendas, loja.recibos to operador;
grant select on api.produtos, api.vendas to operador;
grant execute on function api.autorizar(), api.registrar_venda(json), api.recibo(uuid) to operador;

grant usage on schema loja to eventos;
grant select, update on loja.outbox to eventos;
grant select on loja.vendas, loja.itens_venda, loja.produtos, loja.operadores to eventos;
-- ON CONFLICT DO UPDATE (upsert do recibo) exige SELECT alem de INSERT e UPDATE.
grant select, insert, update on loja.recibos to eventos;
grant execute on function loja.confirmar_pagamento(uuid, text) to eventos;

-- migrate:down
revoke all on all tables in schema loja from operador, eventos;
revoke all on all tables in schema api from operador;
revoke all on all functions in schema api from anonimo, operador;
revoke execute on function loja.confirmar_pagamento(uuid, text) from eventos;
revoke usage on schema loja from operador, eventos;
revoke usage on schema api from anonimo, operador;
