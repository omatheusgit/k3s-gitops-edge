from datetime import datetime

from eventos import recibo


def test_valores_em_reais():
    assert recibo.reais(5) == "R$ 0,05"
    assert recibo.reais(123456) == "R$ 1.234,56"


def test_html_escapa_nomes():
    venda = {"id": "abc12345-0000", "total_centavos": 1890,
             "criada_em": datetime(2026, 3, 2, 14, 5), "operador": "Ana"}
    itens = [{"quantidade": 1, "preco_centavos": 1890, "nome": "<script>cafe</script>"}]
    html = recibo.montar_html("loja-001", venda, itens)
    assert "<script>cafe" not in html
    assert "&lt;script&gt;" in html
    assert "02/03/2026 14:05" in html
    assert "R$ 18,90" in html
