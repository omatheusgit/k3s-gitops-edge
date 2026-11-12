import logging
import sys

from . import consumidor, gateway, relay

PAPEIS = {
    "relay": relay.rodar,
    "consumidor": consumidor.rodar,
    "gateway": gateway.rodar,
    # Operacao: kubectl -n loja exec deploy/eventos-consumidor -- python -m eventos reprocessar-mortos
    "reprocessar-mortos": consumidor.reprocessar_mortos,
}


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    # O pika loga cada tentativa de conexao como ERROR; o retry ja e logado aqui.
    logging.getLogger("pika").setLevel(logging.CRITICAL)
    if len(sys.argv) != 2 or sys.argv[1] not in PAPEIS:
        sys.exit(f"uso: python -m eventos {{{'|'.join(PAPEIS)}}}")
    PAPEIS[sys.argv[1]]()


main()
