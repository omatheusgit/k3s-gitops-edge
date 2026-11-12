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


def test_bindings_do_broker_batem_com_as_filas_da_aplicacao():
    raiz = Path(__file__).resolve().parents[3]
    definicoes = json.loads((raiz / "apps/rabbitmq/definicoes.json.modelo").read_text())
    do_broker = {}
    for b in definicoes["bindings"]:
        if b["source"] == fila.EXCHANGE:
            do_broker.setdefault(b["destination"], set()).add(b["routing_key"])
    assert do_broker == {nome: set(chaves) for nome, chaves in fila.FILAS.items()}


def test_nenhum_processo_configura_o_broker():
    raiz = Path(__file__).resolve().parents[3]
    definicoes = json.loads((raiz / "apps/rabbitmq/definicoes.json.modelo").read_text())
    for p in definicoes["permissions"]:
        if p["user"] != "loja":
            assert p["configure"] == "^$", p["user"]
            assert p["write"] == "^loja\\.eventos$", p["user"]
