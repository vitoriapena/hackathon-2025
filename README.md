# Quarkus Getting Started — Deploy Automatizado (k3d)

Resumo curto

Repositório com a aplicação Quarkus "Getting Started" preparada para build, containerização e deploy local em k3d usando apenas manifests YAML puros (sem Kustomize/Helm).

Etapas do desafio

- Leitura e entendimento do desafio
- Criação de PRDs com o apoio de IA generativa
- Revisão e adaptação dos PRDs
- Definição do `copilot-instructions.md`

Visão geral

- App: Quarkus Getting Started (Java 21, Maven)
- Container: `Dockerfile` multi-stage (builder: maven+temurin-21; runtime: temurin-21-jre)
- Orquestração: k3d local com namespaces `des` e `prd`
- Deploy: manifests YAML puros em `deploy/base/` e overlays por ambiente em `deploy/des/` e `deploy/prd/` (sem Kustomize)
- CI: GitHub Actions — build, test, Trivy scan e push para GHCR

Pré-requisitos

- Java 21 (Temurin) para desenvolvimento local
- Maven
- Docker
- k3d, kubectl
- Acesso ao GHCR para push de imagens (se for publicar)

Estrutura do repositório

- `src/` — código fonte Quarkus
- `Dockerfile` — build multi-stage
- `deploy/`
  - `base/` — manifests genéricos (`deployment.yaml`, `service.yaml`, `ingress.yaml`)
  - `des/` — manifests de ambiente (ex.: `deployment-des.yaml` com `image:` definido)
  - `prd/` — manifests de produção simulada
- `.github/workflows/` — workflows CI e deploy
- `infra/k3d/` — config e scripts para criar o cluster local
- `docs/PRDs/` — PRDs que guiaram a implementação

Como executar (resumo rápido)

- Build: usar `mvn -B -DskipTests=false package` (gera `target/quarkus-app/`)
- Build de imagem: `docker build -t ghcr.io/<org>/<repo>:<sha> .`
- Deploy DES (exemplo): `kubectl apply -f deploy/des -R` e `kubectl -n des rollout status deploy/app`
- Smoke: `curl -fsS http://app.des.local/q/health`

Observações sobre manifests e overlays

- Não há ferramentas extras: a tag da imagem é definida diretamente nos manifests de overlay (`deploy/des/` e `deploy/prd/`).
- Defaults:
  - DES: 1 réplica
  - PRD: 2 réplicas
  - Probes: `readiness` e `liveness` em `/q/health` (porta 8080)
  - Segurança: `runAsNonRoot`, capabilities mínimas

CI/CD

- `ci.yml` realiza checkout (fetch-depth 0), setup-java (Temurin 21), `mvn test package`, build da imagem, scan com Trivy (fail em HIGH/CRITICAL) e push para GHCR.
- Deploy automático para DES ocorre em merge para `main` e usa `kubectl apply -f deploy/des -R`.
- Deploy para PRD é manual via workflow_dispatch com aprovação.

Onde ler mais

- PRDs detalhados: `docs/PRDs/`
- Instruções do Copilot: `.github/copilot-instructions.md`

Contribuição

Siga as convenções descritas nos PRDs: PRs pequenos, Conventional Commits, e mantenha os ajustes de infraestrutura simples.
