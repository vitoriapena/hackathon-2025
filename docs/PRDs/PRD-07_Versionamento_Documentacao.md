# PRD-07 — Versionamento & Documentação

## Objetivo
Estabelecer rastreabilidade de versões e orientar a execução do desafio.

## Escopo
- **Conventional Commits** + **SemVer**.
- Releases opcionais automatizadas (ex.: `release-please`) — se usado, gerar tags e notas.
- **README.md** com:
  - requisitos (Docker, k3d, kubectl, make),
  - como subir cluster, buildar, publicar imagem e implantar,
  - validação (`curl /hello` e `/q/health`).
- **Makefile** com alvos: `k3d-up`, `k3d-down`, `build`, `image`, `push`, `deploy-des`, `deploy-prd`, `smoke`.

## Critérios de Aceite
- Qualquer pessoa consegue reproduzir localmente todo o fluxo apenas seguindo o README.

## Alternativa futura: Azure DevOps
Notas de release em Stage “Release” e versionamento por tag Git.