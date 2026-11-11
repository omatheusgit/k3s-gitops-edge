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
        resposta = pagina.goto(BASE, wait_until="networkidle")
        try:
            pagina.wait_for_selector("input[name=pin]", state="visible", timeout=30_000)
            break
        except Exception:
            # Falha intermitente no CI: registra o que a borda devolveu em vez de adivinhar.
            status = resposta.status if resposta else "sem resposta"
            print(f"tentativa {tentativa + 1}: HTTP {status} em {pagina.url}", file=sys.stderr)
            print(pagina.content()[:600], file=sys.stderr)
            pagina.screenshot(path=f"{SAIDA}/falha-{tentativa + 1}.png")
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
    # Prefere os mesmos produtos dos prints do README, mas so os que tem estoque
    # (depois do workflow demo, alguns acabam).
    estoque = dict(pagina.eval_on_selector_all(
        "#produtos li",
        "lis => lis.map(li => [li.querySelector('strong').textContent,"
        " parseInt(li.querySelector('small').textContent.split('estoque ')[1])])"))
    preferidos = ["Cafe torrado 500g", "Leite integral 1L", "Pao de forma 500g"]
    escolhidos = [n for n in preferidos if estoque.get(n, 0) >= 2]
    escolhidos += [n for n, q in estoque.items() if q >= 2 and n not in escolhidos][: 3 - len(escolhidos)]
    for nome in escolhidos + escolhidos[1:2]:
        pagina.click(f"#produtos li:has-text('{nome}')")
    pagina.screenshot(path=f"{SAIDA}/caixa-venda.png")
    # A tela lista so as 8 vendas mais recentes: depois do workflow demo todas ja
    # tem recibo, entao contar botoes nao serve. Espera a venda nova, no topo, ganhar o dela.
    topo_antes = pagina.eval_on_selector("#vendas", "ul => ul.firstElementChild?.dataset.venda ?? ''")
    pagina.click("#finalizar")
    pagina.wait_for_function("document.querySelectorAll('#carrinho li').length === 0")
    # O recibo chega depois: outbox -> RabbitMQ -> Gotenberg. A tela atualiza a cada 10 s.
    pagina.wait_for_function(
        """antes => {
            const topo = document.querySelector('#vendas li');
            return topo && topo.dataset.venda !== antes && topo.querySelector('button');
        }""",
        arg=topo_antes, timeout=120_000)
    pagina.screenshot(path=f"{SAIDA}/caixa-recibo.png")
    navegador.close()
