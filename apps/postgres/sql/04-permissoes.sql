grant usage on schema api to anonimo, operador;
grant execute on function api.entrar(text, text) to anonimo, operador;

grant usage on schema loja to operador;
grant select on loja.produtos, loja.vendas, loja.recibos to operador;
grant select on api.produtos, api.vendas to operador;
grant execute on function api.autorizar(), api.registrar_venda(json), api.recibo(uuid) to operador;

grant usage on schema loja to eventos;
grant select, update on loja.outbox to eventos;
grant select on loja.vendas, loja.itens_venda, loja.produtos, loja.operadores to eventos;
grant insert, update on loja.recibos to eventos;
grant execute on function loja.confirmar_pagamento(uuid, text) to eventos;
