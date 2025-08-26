# Laboratório CI/CD — simples e prático (k3d efêmero)

Este lab mostra, passo a passo, como nosso pipeline de CI/CD funciona e como você pode acompanhar e validar os deploys — sem precisar de um cluster externo. Tudo roda em um cluster k3d efêmero criado pelo GitHub Actions.

## O que você vai aprender

- CI: build/test do Quarkus (Java 21), build da imagem, scan de segurança com Trivy e push para o GHCR.
- CD DES: ao terminar o CI com sucesso no branch main, um workflow cria um k3d efêmero, importa a imagem, aplica os manifests (namespaces, service, ingress, deployment) e roda um smoke test.
- CD PRD: acionamento manual (com aprovação) reutilizando a mesma imagem publicada pelo CI.

## Conceitos rápidos

- Imagem: publicada como `ghcr.io/<org>/<repo>:<sha>` pelo CI.
- Manifests:
  - Base: `deploy/base/*.yaml` usa `${NAMESPACE}` e é aplicado com `envsubst`.
  - Overlays: `deploy/des/deployment.yaml` e `deploy/prd/deployment.yaml` usam `${IMAGE}` para definir a imagem.
  - Service é `ClusterIP` e o Ingress usa Traefik (`host: app.<ns>.local`).
- Health: `/q/health` (Quarkus SmallRye Health), porta 8080. Probes configuradas.

## Como o CI funciona

Arquivo: `.github/workflows/ci.yaml`

Etapas principais:
1. Checkout (fetch-depth 0) e setup do Java 21 (Temurin) com cache de Maven.
2. `mvn -B -DskipTests=false package` — build e testes.
3. Build da imagem local, scan com Trivy (falha em HIGH/CRITICAL).
4. Login no GHCR e push da imagem (`:sha` e, se houver tag de release, também `:vX.Y.Z`).

Resultados esperados:
- Artefatos de build (reports JUnit) e a imagem disponível no GHCR.

## Como o CD (DES) funciona

Arquivo: `.github/workflows/cd.yaml` (job `deploy_des`)

Quando dispara: automaticamente após CI bem‑sucedido no branch `main`.

O que faz:
1. Cria um cluster k3d efêmero e seleciona o contexto.
2. Faz pull da imagem `ghcr.io/<org>/<repo>:<sha>` e importa no cluster.
3. Aplica namespaces, Service e Ingress (com `envsubst` para `${NAMESPACE}`) e o Deployment do DES (com `${IMAGE}`).
4. Aguarda rollout (`kubectl rollout status`) e executa o Job de smoke, validando `/q/health` internamente e via Ingress.
5. Opcionalmente, marca a imagem como `:des` para facilitar consumo local.

Como inspecionar:
- Aba Actions → workflow CD → job Deploy DES → veja logs de `kubectl get`, `rollout`, e `logs job/smoke-health`.

## Como o CD (PRD) funciona

Arquivo: `.github/workflows/cd.yaml` (job `deploy_prd`)

Quando dispara: manualmente via `workflow_dispatch` com o input `image` (ex.: `ghcr.io/<org>/<repo>:<sha>`). Use a mesma `:sha` produzida pelo CI.

O que faz:
1. Cria cluster k3d efêmero.
2. Importa a imagem informada.
3. Aplica namespaces, Service, Ingress e o Deployment do PRD (2 réplicas por padrão).
4. Aguarda rollout e executa o smoke test.

## Dicas e troubleshooting

- Falha no Trivy: corrija vulnerabilidades ou use uma base de imagem mais recente. O scan falha em HIGH/CRITICAL.
- Erro de path de manifest: confira que os arquivos citados no workflow existem (des/prd usam `deployment.yaml`).
- Ingress/Traefik: o smoke valida `http://traefik.kube-system.svc.cluster.local:80/q/health` com header `Host: app.<ns>.local`.
- Ajuste de tempo: aumente `rollout status --timeout` se sua máquina/runner estiver lento.

## Alinhamento com o pipeline local

- Local: você pode usar `scripts/bash/build-deploy-local.sh` (ou a versão PowerShell) para buildar e implantar no seu k3d persistente (`hackathon-k3d`).
- Actions (lab): usa k3d efêmero, mas a sequência de aplicação é a mesma — base + overlay, waits e smoke.

Pronto! Com isso, qualquer iniciante consegue seguir o fluxo end‑to‑end e entender o que está acontecendo em cada etapa.
