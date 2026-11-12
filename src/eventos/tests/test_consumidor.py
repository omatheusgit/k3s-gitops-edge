from types import SimpleNamespace
from unittest import mock

import psycopg
import pytest
import requests

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


def test_erro_inesperado_devolve_sem_derrubar_o_consumo():
    def falha(tipo, evento):
        raise ValueError("caso nao previsto")

    tratar, canal, metodo, props = montar(falha)
    tratar(canal, metodo, props, b'{"venda_id": "v1"}')
    canal.basic_nack.assert_called_once_with(7, requeue=True)


def test_mensagem_invalida_vai_direto_para_mortos():
    tratar, canal, metodo, props = montar(lambda tipo, evento: None)
    tratar(canal, metodo, props, b"isso nao e json")
    canal.basic_nack.assert_called_once_with(7, requeue=False)


def test_campo_faltando_vai_direto_para_mortos():
    def precisa_de_venda(tipo, evento):
        return evento["venda_id"]

    tratar, canal, metodo, props = montar(precisa_de_venda)
    tratar(canal, metodo, props, b"{}")
    canal.basic_nack.assert_called_once_with(7, requeue=False)


def test_dependencia_http_fora_pausa_so_a_etapa():
    def gotenberg_fora(tipo, evento):
        raise requests.ConnectionError("gotenberg recusou a conexao")

    tratar, canal, metodo, props = montar(gotenberg_fora)
    with pytest.raises(consumidor.DependenciaFora):
        tratar(canal, metodo, props, b'{"venda_id": "v1"}')
    canal.basic_nack.assert_called_once_with(7, requeue=True)


def test_pagamento_passa_o_valor_para_o_banco():
    banco = mock.Mock()
    banco.execute.return_value.fetchone.return_value = {"r": "confirmado"}
    etapas = consumidor.Etapas.__new__(consumidor.Etapas)
    etapas.banco = banco
    etapas.pagamentos("pagamento.confirmado", {"venda_id": "v1", "pagamento_ref": "pg-1", "valor_centavos": 1890})
    sql, params = banco.execute.call_args.args
    assert "confirmar_pagamento(%s, %s, %s)" in sql
    assert params == ("v1", "pg-1", 1890)
