import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

pronto = threading.Event()


class _Saude(BaseHTTPRequestHandler):
    def do_GET(self):
        ok = self.path == "/vivo" or (self.path == "/pronto" and pronto.is_set())
        self.send_response(200 if ok else 503)
        self.end_headers()

    def log_message(self, *args):
        pass


def iniciar(porta: int = 8081) -> None:
    servidor = ThreadingHTTPServer(("0.0.0.0", porta), _Saude)
    threading.Thread(target=servidor.serve_forever, daemon=True).start()
