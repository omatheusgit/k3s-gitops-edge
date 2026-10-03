#!/usr/bin/env python3
"""Cria o GitHub App do Atlantis pelo fluxo de manifesto do GitHub.

Abre uma pagina local que envia o manifesto para o GitHub. Depois do clique
em "Create GitHub App", o GitHub volta para /retorno com um codigo, que e
trocado (via `gh api`) pelo id, chave privada e segredo do webhook. Tudo e
salvo em lab/.cache/atlantis/, o lugar que o lab/atlantis.sh le.

  python3 lab/atlantis-app.py <dono> <nome-do-app>
"""
import html
import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORTA = 4142
DESTINO = Path(__file__).resolve().parent / ".cache" / "atlantis"


def manifesto(dono: str, nome: str) -> dict:
    return {
        "name": nome,
        "url": f"https://github.com/{dono}",
        # Os eventos chegam pelo "gh webhook forward" do lab; o webhook do App fica desligado.
        "hook_attributes": {"url": "https://example.invalid/events", "active": False},
        "redirect_url": f"http://localhost:{PORTA}/retorno",
        "public": False,
        "default_permissions": {
            "administration": "read",
            "checks": "write",
            "contents": "write",
            "issues": "write",
            "metadata": "read",
            "pull_requests": "write",
            "statuses": "write",
        },
        "default_events": [],
    }


class Assistente(BaseHTTPRequestHandler):
    def responder(self, corpo: str) -> None:
        dados = corpo.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/":
            dados = html.escape(json.dumps(manifesto(DONO, NOME)))
            self.responder(f"""<!doctype html><meta charset="utf-8">
<p>Enviando o manifesto do App <b>{html.escape(NOME)}</b> para o GitHub...</p>
<form id="f" method="post" action="https://github.com/settings/apps/new">
<input type="hidden" name="manifest" value="{dados}"></form>
<script>document.getElementById('f').submit()</script>""")
            return
        if url.path == "/retorno":
            codigo = parse_qs(url.query).get("code", [""])[0]
            resposta = subprocess.run(
                ["gh", "api", "-X", "POST", f"app-manifests/{codigo}/conversions"],
                capture_output=True, text=True)
            if resposta.returncode != 0:
                self.responder(f"<p>Falhou: {html.escape(resposta.stderr)}</p>")
                return
            app = json.loads(resposta.stdout)
            DESTINO.mkdir(parents=True, exist_ok=True)
            os.chmod(DESTINO, 0o700)
            for nome, valor in (("app-id", str(app["id"])), ("app.pem", app["pem"]),
                                ("webhook-secret", app["webhook_secret"]), ("app-slug", app["slug"])):
                arquivo = DESTINO / nome
                arquivo.write_text(valor + ("\n" if not valor.endswith("\n") else ""))
                os.chmod(arquivo, 0o600)
            instalar = f"https://github.com/apps/{app['slug']}/installations/new"
            self.responder(f"""<!doctype html><meta charset="utf-8">
<p>App <b>{html.escape(app['slug'])}</b> criado e credenciais salvas.</p>
<p>Ultimo passo: <a href="{instalar}">instale o App</a> no repositorio do projeto.</p>""")
            print(f"app criado: {app['slug']} (id {app['id']}); instale em {instalar}", flush=True)
            raise SystemExit(0)
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("uso: atlantis-app.py <dono> <nome-do-app>")
    DONO, NOME = sys.argv[1], sys.argv[2]
    print(f"abra http://localhost:{PORTA}/", flush=True)
    try:
        HTTPServer(("127.0.0.1", PORTA), Assistente).serve_forever()
    except SystemExit:
        pass
