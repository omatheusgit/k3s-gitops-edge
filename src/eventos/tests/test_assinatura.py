from eventos import assinatura

SEGREDO = "segredo-de-teste"
CORPO = b'{"evento_id":"pg-1","venda_id":"v-1","status":"aprovado"}'


def test_assinatura_valida():
    sig = assinatura.assinar(SEGREDO, 1_000, CORPO)
    assert assinatura.verificar(SEGREDO, "1000", sig, CORPO, agora=1_010)


def test_corpo_alterado_e_rejeitado():
    sig = assinatura.assinar(SEGREDO, 1_000, CORPO)
    assert not assinatura.verificar(SEGREDO, "1000", sig, CORPO.replace(b"v-1", b"v-2"), agora=1_000)


def test_reenvio_fora_da_janela_e_rejeitado():
    sig = assinatura.assinar(SEGREDO, 1_000, CORPO)
    assert not assinatura.verificar(SEGREDO, "1000", sig, CORPO, agora=1_000 + 301)


def test_entradas_invalidas():
    assert not assinatura.verificar(SEGREDO, "abc", "sha256=00", CORPO)
    assert not assinatura.verificar("", "1000", "sha256=00", CORPO, agora=1_000)
    assert not assinatura.verificar(SEGREDO, "", "", CORPO)
