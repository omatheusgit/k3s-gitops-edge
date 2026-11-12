-- Dados de demonstracao, so para o laboratorio (lab/semente.sh). Producao
-- nunca recebe isto: operadores reais sao cadastrados pela loja.
-- SKUs com prefixo 2 (uso interno no padrao EAN), nada de codigo de marca real.
insert into loja.operadores (login, nome, pin_hash) values
  ('caixa1', 'Ana (caixa 1)', crypt('1234', gen_salt('bf', 10))),
  ('caixa2', 'Bruno (caixa 2)', crypt('4321', gen_salt('bf', 10)))
on conflict (login) do update set pin_hash = excluded.pin_hash, ativo = true;

insert into loja.produtos (id, sku, nome, preco_centavos, estoque) values
  (1, '2000000000015', 'Café torrado 500g', 1890, 40),
  (2, '2000000000022', 'Leite integral 1L', 549, 120),
  (3, '2000000000039', 'Pão de forma 500g', 899, 30),
  (4, '2000000000046', 'Açúcar refinado 1kg', 479, 60),
  (5, '2000000000053', 'Arroz tipo 1 5kg', 2790, 25),
  (6, '2000000000060', 'Feijão carioca 1kg', 849, 50),
  (7, '2000000000077', 'Refrigerante cola 2L', 1099, 48),
  (8, '2000000000084', 'Biscoito recheado 140g', 329, 80)
on conflict (id) do nothing;

select setval('loja.produtos_id_seq', greatest((select max(id) from loja.produtos), 1));
