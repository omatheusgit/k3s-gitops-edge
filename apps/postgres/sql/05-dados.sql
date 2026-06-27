-- Dados de demonstracao. PIN do caixa: 1234.
insert into loja.operadores (login, nome, pin_hash) values
  ('caixa1', 'Ana (caixa 1)', crypt('1234', gen_salt('bf'))),
  ('caixa2', 'Bruno (caixa 2)', crypt('4321', gen_salt('bf')));

insert into loja.produtos (sku, nome, preco_centavos, estoque) values
  ('7891000100103', 'Cafe torrado 500g', 1890, 40),
  ('7891000053508', 'Leite integral 1L', 549, 120),
  ('7896004000855', 'Pao de forma 500g', 899, 30),
  ('7891910000197', 'Acucar refinado 1kg', 479, 60),
  ('7896036090244', 'Arroz tipo 1 5kg', 2790, 25),
  ('7891149103102', 'Feijao carioca 1kg', 849, 50),
  ('7894900011517', 'Refrigerante cola 2L', 1099, 48),
  ('7891000315507', 'Biscoito recheado 140g', 329, 80);
