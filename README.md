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
  - `base/` — manifests genéricos (`deployment.yaml`, `service.yaml`, `ingress.yaml`)
  - `des/` — manifests de ambiente (ex.: `deployment-des.yaml` com `image:` definido)
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
kubectl apply -R -f deploy/base
kubectl apply -R -f deploy/des
kubectl -n des rollout status deploy/app
# verificar smoke-job in-cluster
kubectl -n des apply -f deploy/base/smoke-job.yaml
kubectl -n des wait --for=condition=complete job/smoke-health --timeout=60s
kubectl -n des get job smoke-health -o jsonpath='{.status.succeeded}'
```

- Smoke test (externo — fallback com --resolve):

```bash
curl --resolve app.des.local:80:127.0.0.1 http://app.des.local/q/health
```

## Observações sobre manifests e overlays

- Não há ferramentas extras: a tag da imagem é definida diretamente nos manifests de overlay (`deploy/des/` e `deploy/prd/`).
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

## Onde ler mais

- PRDs detalhados: `docs/PRDs/`
- Instruções do Copilot: `.github/copilot-instructions.md`

## Contribuição

Siga as convenções descritas nos PRDs: PRs pequenos, Conventional Commits, e mantenha os ajustes de infraestrutura simples.
