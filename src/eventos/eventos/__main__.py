import logging
import sys

from . import consumidor, gateway, relay

PAPEIS = {"relay": relay.rodar, "consumidor": consumidor.rodar, "gateway": gateway.rodar}


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    if len(sys.argv) != 2 or sys.argv[1] not in PAPEIS:
        sys.exit(f"uso: python -m eventos {{{'|'.join(PAPEIS)}}}")
    PAPEIS[sys.argv[1]]()


main()
