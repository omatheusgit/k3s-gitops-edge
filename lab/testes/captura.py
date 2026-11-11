"""Tira os prints do README a partir de uma loja do lab no ar.

  python lab/testes/captura.py http://pdv.localhost:8080 docs/img

Roda no job e2e do CI (Playwright em container) depois dos testes.
"""
import sys

from playwright.sync_api import sync_playwright

BASE = sys.argv[1]
SAIDA = sys.argv[2]

with sync_playwright() as p:
    navegador = p.chromium.launch()
    pagina = navegador.new_page(viewport={"width": 1180, "height": 720}, device_scale_factor=2)
    for tentativa in range(3):
        pagina.goto(BASE, wait_until="networkidle")
        try:
            pagina.wait_for_selector("input[name=pin]", state="visible", timeout=30_000)
            break
        except Exception:
            if tentativa == 2:
                raise
    pagina.fill("input[name=pin]", "1234")
    pagina.click("form button")
    pagina.wait_for_selector("#produtos li")
    pagina.fill("#filtro", "cafe torado")
    pagina.wait_for_timeout(1200)
    pagina.screenshot(path=f"{SAIDA}/caixa-busca.png")
    pagina.fill("#filtro", "")
    pagina.wait_for_timeout(800)
    for nome in ["Cafe torrado 500g", "Leite integral 1L", "Pao de forma 500g", "Leite integral 1L"]:
        pagina.click(f"#produtos li:has-text('{nome}')")
    pagina.screenshot(path=f"{SAIDA}/caixa-venda.png")
    recibos_antes = pagina.locator("#vendas button").count()
    pagina.click("#finalizar")
    pagina.wait_for_function("document.querySelectorAll('#carrinho li').length === 0")
    # O recibo chega depois: outbox -> RabbitMQ -> Gotenberg. A tela atualiza a cada 10 s.
    pagina.wait_for_function(
        f"document.querySelectorAll('#vendas button').length > {recibos_antes}", timeout=120_000)
    pagina.screenshot(path=f"{SAIDA}/caixa-recibo.png")
    navegador.close()
