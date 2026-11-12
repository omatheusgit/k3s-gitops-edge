from unittest import mock

from eventos import fila


def test_politica_usa_vhost_e_credenciais_da_url():
    with mock.patch("eventos.fila.requests.put") as put:
        fila.aplicar_politica("amqp://loja:s%40nha@rabbitmq:5672/%2F")
    chamadas = {c.args[0].rsplit("/", 1)[1]: c for c in put.call_args_list}
    filas = chamadas["filas-da-loja"]
    assert filas.args[0] == "http://rabbitmq:15672/api/policies/%2F/filas-da-loja"
    assert filas.kwargs["auth"] == ("loja", "s@nha")
    definicao = filas.kwargs["json"]["definition"]
    assert definicao["delivery-limit"] == 10
    assert definicao["dead-letter-exchange"] == fila.MORTOS
    # Fila cheia recusa publicacao: o evento fica no outbox, nao se perde.
    assert definicao["overflow"] == "reject-publish"
    assert chamadas["fila-de-mortos"].kwargs["json"]["definition"]["overflow"] == "drop-head"


def test_toda_fila_tem_routing_key():
    assert all(chaves for chaves in fila.FILAS.values())


def test_routing_key_de_topic():
    assert fila._casa("produto.*", "produto.atualizado")
    assert not fila._casa("produto.*", "produto.a.b")
    assert fila._casa("venda.#", "venda")
    assert fila._casa("venda.#", "venda.paga.estorno")
    assert not fila._casa("venda.*", "pagamento.confirmado")


def test_perfil_enxuto_so_tem_destino_para_pagamento():
    enxuto = {"pagamentos"}
    assert fila.tem_destino("pagamento.confirmado", enxuto)
    assert not fila.tem_destino("venda.registrada", enxuto)
    assert not fila.tem_destino("produto.atualizado", enxuto)
    assert fila.tem_destino("venda.registrada", set(fila.FILAS))


def test_declarar_so_as_filas_das_etapas_e_limpar_as_outras():
    canal = mock.Mock()
    fila.declarar(canal, {"pagamentos"}, limpar=True)
    declaradas = {c.args[0] for c in canal.queue_declare.call_args_list}
    assert declaradas == {"mortos", "pagamentos"}
    assert {c.args[0] for c in canal.queue_delete.call_args_list} == {"recibos", "busca"}


def test_publicador_nao_apaga_fila():
    canal = mock.Mock()
    fila.declarar(canal, {"pagamentos"})
    canal.queue_delete.assert_not_called()
