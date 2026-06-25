from datetime import datetime
from html import escape


def reais(centavos: int) -> str:
    inteiro, resto = divmod(centavos, 100)
    return f"R$ {inteiro:,}".replace(",", ".") + f",{resto:02d}"


def montar_html(loja: str, venda: dict, itens: list[dict]) -> str:
    linhas = "".join(
        f"<tr><td>{item['quantidade']}x {escape(item['nome'])}</td>"
        f"<td class='v'>{reais(item['quantidade'] * item['preco_centavos'])}</td></tr>"
        for item in itens
    )
    data = venda["criada_em"]
    if isinstance(data, datetime):
        data = data.strftime("%d/%m/%Y %H:%M")
    return f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><style>
body {{ font-family: monospace; width: 72mm; margin: 0 auto; font-size: 12px; }}
h1 {{ font-size: 14px; text-align: center; }}
table {{ width: 100%; border-collapse: collapse; }}
.v {{ text-align: right; }}
.total td {{ border-top: 1px dashed #000; font-weight: bold; }}
</style></head><body>
<h1>{escape(loja)}</h1>
<p>Venda {escape(str(venda['id']))[:8]}<br>{escape(str(data))}<br>Operador: {escape(venda['operador'])}</p>
<table>{linhas}<tr class="total"><td>Total</td><td class="v">{reais(venda['total_centavos'])}</td></tr></table>
<p>Documento sem valor fiscal.</p>
</body></html>"""
