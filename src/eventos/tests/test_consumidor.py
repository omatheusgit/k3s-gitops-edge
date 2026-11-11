from types import SimpleNamespace
from unittest import mock

import psycopg
import pytest

from eventos import consumidor


def montar(acao):
    etapas = SimpleNamespace(cache=mock.Mock(), recibos=acao)
    etapas.cache.exists.return_value = False
    canal = mock.Mock()
    metodo = SimpleNamespace(delivery_tag=7, routing_key="venda.registrada")
    props = SimpleNamespace(message_id="42")
    return consumidor.tratador(etapas, "recibos"), canal, metodo, props


def test_sucesso_confirma_e_marca_como_processado():
    tratar, canal, metodo, props = montar(lambda tipo, evento: None)
    tratar(canal, metodo, props, b'{"venda_id": "v1"}')
    canal.basic_ack.assert_called_once_with(7)


def test_conexao_perdida_devolve_e_interrompe_para_reconectar():
    def falha(tipo, evento):
        raise psycopg.OperationalError("the connection is closed")

    tratar, canal, metodo, props = montar(falha)
    with pytest.raises(psycopg.OperationalError):
        tratar(canal, metodo, props, b'{"venda_id": "v1"}')
    canal.basic_nack.assert_called_once_with(7, requeue=True)


def test_erro_de_negocio_devolve_sem_derrubar_o_consumo():
    def falha(tipo, evento):
        raise ValueError("gotenberg 503")

    tratar, canal, metodo, props = montar(falha)
    with mock.patch("eventos.consumidor.time.sleep"):
        tratar(canal, metodo, props, b'{"venda_id": "v1"}')
    canal.basic_nack.assert_called_once_with(7, requeue=True)
