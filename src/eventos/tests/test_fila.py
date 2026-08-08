from unittest import mock

from eventos import fila


def test_politica_usa_vhost_e_credenciais_da_url():
    with mock.patch("eventos.fila.requests.put") as put:
        fila.aplicar_politica("amqp://loja:s%40nha@rabbitmq:5672/%2F")
    url = put.call_args.args[0]
    assert url == "http://rabbitmq:15672/api/policies/%2F/filas-da-loja"
    assert put.call_args.kwargs["auth"] == ("loja", "s@nha")
    definicao = put.call_args.kwargs["json"]["definition"]
    assert definicao["delivery-limit"] == 10
    assert definicao["dead-letter-exchange"] == fila.MORTOS


def test_toda_fila_tem_routing_key():
    assert all(chaves for chaves in fila.FILAS.values())
