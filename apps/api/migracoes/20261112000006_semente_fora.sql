-- migrate:up
-- A semente de demonstracao (operadores com PIN fixo e produtos) nao e mais
-- migracao: fica em lab/semente.sql e so o laboratorio aplica. Bancos criados
-- antes disso: os operadores de demonstracao sao desativados e os produtos de
-- exemplo que nunca foram vendidos saem do catalogo.
update loja.operadores set ativo = false where login in ('caixa1', 'caixa2');

delete from loja.produtos p
 where p.sku in ('7891000100103', '7891000053508', '7896004000855', '7891910000197',
                 '7896036090244', '7891149103102', '7894900011517', '7891000315507')
   and not exists (select 1 from loja.itens_venda i where i.produto_id = p.id);

-- migrate:down
-- Sem volta de proposito: a semente de demonstracao nao deve voltar a producao.
select 1;
