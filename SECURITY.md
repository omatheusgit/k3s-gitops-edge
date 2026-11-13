# Segurança

Este é um projeto de estudo e portfólio, sem lojas reais em produção. Mesmo assim, achados de segurança são bem-vindos.

## Como reportar

Abra um [aviso de segurança privado](https://github.com/omatheusgit/k3s-gitops-edge/security/advisories/new) no GitHub. Não abra issue pública para algo explorável.

## O que já foi revisado

O repositório passou por duas revisões adversariais completas (README, segurança, laboratório e CI). Cada achado virou issue e foi corrigido por PR, com teste. O histórico está no [CHANGELOG](CHANGELOG.md), e os limites que continuam valendo estão no [README](README.md#limites-conhecidos).

## Modelo de ameaça, em uma linha por peça

- **Servidor da loja:** tem acesso físico de terceiros; uma loja comprometida não pode chegar às outras nem à central (segredo, chave do JWT, registro e usuário IAM por loja).
- **Rede da loja:** só o Traefik entra, e só nas portas de serviço; dentro, cada serviço aceita só quem fala com ele.
- **Instalador:** só executa pacote assinado pelo workflow de release deste repositório (Sigstore), na versão pedida.
- **CI:** actions e imagens fixadas por digest; nenhum segredo de longa duração para publicar.
