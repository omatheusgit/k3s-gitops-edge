import json
import re
from pathlib import Path
from unittest import mock

from eventos import fila


def test_policy_do_broker_cobre_as_filas_da_loja():
    # As policies vivem nas definicoes do RabbitMQ; o padrao tem que bater com FILAS.
    raiz = Path(__file__).resolve().parents[3]
    definicoes = json.loads((raiz / "apps/rabbitmq/definicoes.json.modelo").read_text())
    politica = next(p for p in definicoes["policies"] if p["name"] == "filas-da-loja")
    assert all(re.fullmatch(politica["pattern"], f) for f in fila.FILAS)
    assert politica["definition"]["overflow"] == "reject-publish"
    assert politica["definition"]["dead-letter-exchange"] == fila.MORTOS


def test_so_o_gateway_publica_pagamento():
    raiz = Path(__file__).resolve().parents[3]
    definicoes = json.loads((raiz / "apps/rabbitmq/definicoes.json.modelo").read_text())
    escrita = {t["user"]: t["write"] for t in definicoes["topic_permissions"]}
    assert re.search(escrita["gateway"], "pagamento.confirmado")
    assert not re.search(escrita["relay"], "pagamento.confirmado")
    assert re.search(escrita["relay"], "venda.registrada")
    assert not any(u["tags"] for u in definicoes["users"] if u["name"] != "loja")


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
