'use strict';

const $ = (sel) => document.querySelector(sel);
const reais = (centavos) => (centavos / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

let token = sessionStorage.getItem('token');
let produtos = [];
const carrinho = new Map();

async function chamar(caminho, opcoes = {}) {
  const cabecalhos = { 'Content-Type': 'application/json', ...(opcoes.headers || {}) };
  if (token) cabecalhos.Authorization = `Bearer ${token}`;
  const resp = await fetch(caminho, { ...opcoes, headers: cabecalhos });
  if (resp.status === 401) { sair(); throw new Error('sessao expirada'); }
  if (!resp.ok) {
    const corpo = await resp.json().catch(() => ({}));
    throw new Error(corpo.message || `erro ${resp.status}`);
  }
  return resp;
}

function mostrar(logado) {
  $('#tela-login').hidden = logado;
  $('#tela-caixa').hidden = !logado;
  $('#sair').hidden = !logado;
  $('#operador').textContent = logado ? sessionStorage.getItem('operador') : '';
}

function sair() {
  token = null;
  sessionStorage.clear();
  mostrar(false);
}

async function entrar(evento) {
  evento.preventDefault();
  const dados = Object.fromEntries(new FormData(evento.target));
  try {
    const resp = await chamar('/api/rpc/entrar', { method: 'POST', body: JSON.stringify(dados) });
    const { token: novo, nome } = await resp.json();
    token = novo;
    sessionStorage.setItem('token', novo);
    sessionStorage.setItem('operador', nome);
    $('#erro-login').textContent = '';
    iniciar();
  } catch (erro) {
    $('#erro-login').textContent = erro.message;
  }
}

function desenharProdutos(lista) {
  $('#produtos').replaceChildren(...lista.map((p) => {
    const li = document.createElement('li');
    li.innerHTML = `<strong></strong><small></small><span></span>`;
    li.querySelector('strong').textContent = p.nome;
    li.querySelector('small').textContent = `${p.sku} · estoque ${p.estoque}`;
    li.querySelector('span').textContent = reais(p.preco_centavos);
    li.onclick = () => adicionar(p);
    return li;
  }));
}

// Busca no Meilisearch (tolerante a erro de digitacao); se a busca nao
// estiver disponivel nesta loja, filtra a lista local.
async function filtrar(termo) {
  if (!termo) return desenharProdutos(produtos);
  try {
    const resp = await chamar('/busca/indexes/produtos/search', {
      method: 'POST', body: JSON.stringify({ q: termo, limit: 20 }),
    });
    const { hits } = await resp.json();
    desenharProdutos(hits);
  } catch {
    const t = termo.toLowerCase();
    desenharProdutos(produtos.filter((p) => p.nome.toLowerCase().includes(t) || p.sku.includes(t)));
  }
}

function adicionar(produto) {
  const item = carrinho.get(produto.id) || { produto, quantidade: 0 };
  item.quantidade += 1;
  carrinho.set(produto.id, item);
  desenharCarrinho();
}

function desenharCarrinho() {
  let total = 0;
  $('#carrinho').replaceChildren(...[...carrinho.values()].map(({ produto, quantidade }) => {
    total += produto.preco_centavos * quantidade;
    const li = document.createElement('li');
    li.textContent = `${quantidade}x ${produto.nome}`;
    const valor = document.createElement('span');
    valor.textContent = reais(produto.preco_centavos * quantidade);
    li.append(valor);
    return li;
  }));
  $('#total').textContent = reais(total);
  $('#finalizar').disabled = carrinho.size === 0;
}

async function finalizar() {
  const itens = [...carrinho.values()].map(({ produto, quantidade }) => ({ produto_id: produto.id, quantidade }));
  try {
    await chamar('/api/rpc/registrar_venda', { method: 'POST', body: JSON.stringify({ itens }) });
    carrinho.clear();
    desenharCarrinho();
    $('#erro-venda').textContent = '';
    await carregar();
  } catch (erro) {
    $('#erro-venda').textContent = erro.message;
  }
}

async function baixarRecibo(id) {
  const resp = await chamar(`/api/rpc/recibo?venda=${id}`, { headers: { Accept: 'application/pdf' } });
  const url = URL.createObjectURL(await resp.blob());
  window.open(url, '_blank');
}

async function carregar() {
  produtos = await (await chamar('/api/produtos?order=nome')).json();
  filtrar($('#filtro').value.trim());
  const vendas = await (await chamar('/api/vendas?order=criada_em.desc&limit=8')).json();
  $('#vendas').replaceChildren(...vendas.map((v) => {
    const li = document.createElement('li');
    li.dataset.venda = v.id;
    const status = document.createElement('span');
    status.className = `status-${v.status}`;
    status.textContent = v.status.replace('_', ' ');
    li.append(`${reais(v.total_centavos)} `, status);
    if (v.tem_recibo) {
      const botao = document.createElement('button');
      botao.textContent = 'Recibo';
      botao.onclick = () => baixarRecibo(v.id);
      li.append(botao);
    }
    return li;
  }));
}

function iniciar() {
  mostrar(true);
  carregar().catch(() => {});
}

$('#form-login').addEventListener('submit', entrar);
$('#sair').addEventListener('click', sair);
$('#finalizar').addEventListener('click', finalizar);
let espera;
$('#filtro').addEventListener('input', (e) => {
  clearTimeout(espera);
  espera = setTimeout(() => filtrar(e.target.value.trim()), 200);
});
setInterval(() => token && carregar().catch(() => {}), 10000);

if (token) iniciar(); else mostrar(false);
