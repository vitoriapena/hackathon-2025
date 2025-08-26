# Quarkus Getting Started — Deploy Automatizado (k3d)

Repositório com a aplicação Quarkus "Getting Started" preparada para build, containerização e deploy local em k3d usando apenas manifests YAML puros (sem Kustomize/Helm).

## Sumário

- [Visão geral](#visão-geral)
- [Etapas do desafio](#etapas-do-desafio)
- [Pré-requisitos](#pré-requisitos)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Como executar (resumo rápido)](#como-executar-resumo-rápido)
- [Observações sobre manifests e overlays](#observações-sobre-manifests-e-overlays)
- [CI/CD](#cicd)
- [Resumo das mudanças (commits recentes)](#resumo-das-mudanças-commits-recentes)
- [Onde ler mais](#onde-ler-mais)
- [Contribuição](#contribuição)

---

## Visão geral

- App: Quarkus Getting Started (Java 21, Maven)
- Container: `Dockerfile` multi-stage (builder: maven + temurin-21; runtime: temurin-21-jre)
- Orquestração: k3d local com namespaces `des` e `prd`
- Deploy: manifests YAML puros em `deploy/base/` com overlays por ambiente em `deploy/des/` e `deploy/prd/` (sem Kustomize)
- CI: GitHub Actions — build, test, Trivy scan e push para GHCR

## Etapas do desafio

- Leitura e entendimento do desafio
- Criação de PRDs com o apoio de IA generativa
- Revisão e adaptação dos PRDs
- Definição do `copilot-instructions.md`
- PRD-01: Cluster k3d local — criação e validação do cluster local
- PRD-02: Build & Package Quarkus — Maven com Java 21 e testes
- PRD-03: Containerização e Registro — Dockerfile multi-stage e push para GHCR
- PRD-04: CI GitHub Actions — build, test, Trivy scan e publicação
- PRD-05: Deploy DES — namespaces, service, deployment e smoke job
- PRD-06: Deploy PRD com aprovação — gatilho manual reutilizando a imagem do CI
- PRD-07: Versionamento & Documentação — SemVer/Conventional Commits e README final

## Pré-requisitos

- Java 21 (Temurin) para desenvolvimento local
- Maven
- Docker
- k3d, kubectl
- Acesso ao GHCR para push de imagens (se for publicar)

## Estrutura do repositório

- `src/` — código fonte Quarkus
- `Dockerfile` — build multi-stage
- `deploy/`
  - `base/` — manifests genéricos (`deployment.yaml`, `service.yaml`, `namespaces.yaml`, `smoke-job.yaml`) com `${NAMESPACE}`
  - `des/` — manifests de ambiente (ex.: `deploy/des/deployment.yaml` com `image:` definido)
  - `prd/` — manifests de produção simulada
- `.github/workflows/` — workflows CI e deploy
- `infra/k3d/` — config e scripts para criar o cluster local
- `docs/PRDs/` — PRDs que guiaram a implementação

## Como executar (resumo rápido)

- Build (maven):

```bash
mvn -B -DskipTests=false package
```

- Build de imagem (exemplo):

```bash
docker build -t ghcr.io/<org>/<repo>:<sha> .
```

- Deploy DES (exemplo — sequência declarativa):

```bash
# aplicar base parametrizada (usa ${NAMESPACE})
export NAMESPACE=des
find deploy/base -maxdepth 1 -name "*.yaml" -print0 | xargs -0 -I {} sh -c 'envsubst < "{}" | kubectl apply -f -'

# aplicar overlay do ambiente e aguardar rollout
kubectl apply -R -f deploy/des
kubectl -n des rollout status deploy/app

# verificar smoke-job in-cluster
envsubst < deploy/base/smoke-job.yaml | kubectl apply -f -
kubectl -n des wait --for=condition=complete job/smoke-health --timeout=60s
kubectl -n des get job smoke-health -o jsonpath='{.status.succeeded}'
```

- Smoke test (externo — fallback com --resolve):

```bash
curl --resolve app.des.local:80:127.0.0.1 http://app.des.local/q/health
```

Dica: para um fluxo automatizado (build → DES → aprovação para PRD), use `scripts/bash/build-deploy-local.sh`. Detalhes completos no guia abaixo.

## Observações sobre manifests e overlays

- Não há ferramentas extras: a tag da imagem pode ser definida nos overlays (`deploy/des/` e `deploy/prd/`) ou substituída por script.
- Os YAMLs em `deploy/base/` são agnósticos de ambiente e exigem `NAMESPACE` ao aplicar manualmente (use `envsubst`).
- Defaults:
  - DES: 1 réplica
  - PRD: 2 réplicas
  - Probes: `readiness` e `liveness` em `/q/health` (porta 8080)
  - Segurança: `runAsNonRoot`, capabilities mínimas

## CI/CD

- `ci.yml` realiza:
  1. checkout (fetch-depth 0)
  2. setup-java (Temurin 21)
  3. `mvn test package`
  4. build da imagem
  5. scan com Trivy (falha em HIGH/CRITICAL)
  6. push para GHCR

- Deploy automático para DES: merge em `main` → `kubectl apply -f deploy/des -R` e smoke test
- Deploy para PRD: manual via `workflow_dispatch` com aprovação; usa a mesma imagem publicada pelo CI

Aprenda o passo a passo no guia: `docs/ci-cd-lab.md`.

## Resumo das mudanças (commits recentes)

- Base/Build: app Quarkus adicionada; Maven e compilação em Java 21; testes habilitados.
- Health: dependência `quarkus-smallrye-health` para expor `/q/health`.
- Container/Segurança: Dockerfile multi-stage Temurin 21; Trivy trocado para a action oficial; ajustes de referências e `.trivyignore`.
- CI: Workflow de build/test/scan/push; CodeQL comentado por permissões; correções em paths de artefatos e `fetch-depth`.
- k3d/Deploy: setup local k3d; manifests base (namespaces, service, deployment, smoke job); scripts de build/deploy locais.
- CD: pipeline efêmero com k3d — DES automático após CI verde; PRD manual com aprovação; criação do tag `:des` pós-deploy.
- Confiabilidade: namespace dinâmico, robustez no import de imagem no k3d, retry no smoke job e correções menores.

## Onde ler mais

- PRDs detalhados: `docs/PRDs/`
- Guia de cluster k3d: `docs/cluster.md`
- Guia de build: `docs/build.md`
- Execução local: `docs/local.md`
- Guia de deploy local: `docs/deploy.md`
- CD efêmero (GitHub Actions): `docs/cd-ephemeral-actions.md`
- Instruções do Copilot: `.github/copilot-instructions.md`

## Contribuição

Siga as convenções descritas nos PRDs: PRs pequenos, Conventional Commits, e mantenha os ajustes de infraestrutura simples.
