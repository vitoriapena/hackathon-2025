# PRD-03 — Containerização + Registro (GHCR)

## Objetivo
Construir imagem mínima e segura da aplicação e publicá-la no **GitHub Container Registry (GHCR)**.

## Escopo
- **Dockerfile multi-stage** (arquivo na raiz: `Dockerfile`):
  - Stage build: `docker.io/maven:3.9-eclipse-temurin-21`.
  - Stage runtime: `docker.io/eclipse-temurin:21-jre` (ver https://hub.docker.com/_/eclipse-temurin).
- Execução como **usuário não-root**; `EXPOSE 8080`; `HEALTHCHECK` simples.
- Tags de imagem:
  - `ghcr.io/<org>/<repo>:<sha>`
  - `ghcr.io/<org>/<repo>:des` (última aprovada em DES).

## Segurança (mínimo essencial)
- **Trivy image scan**: falha o job para severidades HIGH/CRITICAL.
- Base pinada (major version) e referenciada explicitamente via Docker Hub (`docker.io/eclipse-temurin:21-jre`); atualização via Dependabot.

## Critérios de Aceite
- `docker run --user 10001 -p 8080:8080 <img>` responde no `:8080`.
- Imagem publicada no GHCR e aprovada no scan.

## Entregáveis
- `Dockerfile` (root): multi-stage, non-root, HEALTHCHECK. Todas as referências à imagem Temurin devem usar o namespace docker.io (ex.: `docker.io/eclipse-temurin:21-jre`).
- `.trivyignore` (se necessário, documentando justificativas).

## Alternativa futura: Azure DevOps
Tarefa `Docker@2` para build/push em GHCR (ou ACR). Trivy executado via script bash no pipeline.