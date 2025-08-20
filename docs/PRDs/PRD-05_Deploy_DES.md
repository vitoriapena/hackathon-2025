# PRD-05 — Deploy DES (kubectl + manifests YAML)

## Objetivo
Implantar automaticamente em `des` após merge na `main` usando apenas YAMLs puros (zero tooling adicional).

## Escopo
- **Manifests Kubernetes** em `deploy/base/`:
  - `deployment.yaml`, `service.yaml`, `ingress.yaml`.
- Ambiente `deploy/des/` com manifests específicos (p.ex. `deployment-des.yaml`) — não usar ferramentas adicionais:
  - Definir `image: ghcr.io/<org>/<repo>:<sha>` diretamente no `deployment-des.yaml`.
  - Réplica única, requests/limits leves.
  - Probes (`/q/health` do Quarkus).
  - Ingress host `app.des.local`.

## Pipeline (workflow `deploy-des.yml`)
- Disparo: `push` para `main`.
- Runner: **self-hosted** com acesso ao kubeconfig do k3d.
- Passos: checkout → `kubectl apply -f deploy/des -R` → `kubectl -n des rollout status deploy/app` → smoke (`curl http://app.des.local/q/health`).

## Critérios de Aceite
- Rollout concluído com sucesso; smoke 200 OK.

## Alternativa futura: Azure DevOps
Stage `DES` chamando `kubectl apply -f deploy/des -R` a partir de agent self-hosted.
