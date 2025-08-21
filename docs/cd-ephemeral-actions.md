# CD efêmero com GitHub Actions + k3d

Este documento descreve o pipeline de CI/CD 100% no GitHub Actions, sem dependência de nuvem externa. O deploy usa um cluster k3d efêmero criado dentro do runner para validar a publicação.

Visão geral
- CI (`.github/workflows/ci.yaml`):
  - Build/test (Java 21, Maven) → Build Docker multi-stage → Trivy (falha em HIGH/CRITICAL) → Push para GHCR tag `:sha`.
- CD (`.github/workflows/cd.yaml`):
  - DES automático após CI bem-sucedido na `main` (workflow_run).
  - PRD manual via `workflow_dispatch` com aprovação no Environment `prd`.
  - Ambos criam um cluster k3d temporário, importam a imagem `:sha`, aplicam manifests e executam smoke em `/q/health` via Job. O cluster é destruído ao final.

Imagem e tags
- A imagem é publicada no CI como `ghcr.io/<org>/<repo>:<sha>`.
- Após DES bem-sucedido, o CD também publica a tag `:des` apontando para o mesmo digest.

Manifests e substituições
- Base em `deploy/base/` e overlays em `deploy/des` e `deploy/prd` (sem Helm/Kustomize).
- Variáveis substituídas no CD com `sed`:
  - `${NAMESPACE}` → `des`/`prd` nos manifests que usam placeholder.
  - `ghcr.io/<org>/<repo>:<sha>` → imagem real (CI: `:sha`, PRD: input).

Probes e segurança
- Liveness/readiness em `/q/health` porta 8080.
- Containers sem privilégios e com capabilities drop ALL.

Permissões e secrets
- Workflows usam permissões mínimas: `contents:read`, `packages:write`.
- Autenticação GHCR via `GITHUB_TOKEN` (sem secrets adicionais).
- Para PRD, configure Environment `prd` com aprovação obrigatória.

Fluxo detalhado (DES)
1) Disparo pós-CI. 2) k3d create. 3) docker pull `:sha` + `k3d image import`. 4) `kubectl apply` namespaces, Service (NAMESPACE=des) e Deployment de `deploy/des` com a imagem real. 5) `kubectl rollout status`. 6) Job de smoke `deploy/base/smoke-job.yaml` (NAMESPACE=des) e aguarda completar. 7) Retaga e publica `:des`. 8) k3d delete.

Fluxo detalhado (PRD)
- Igual ao DES, porém manual e com `NAMESPACE=prd` e Deployment de `deploy/prd`. A imagem é fornecida como input (tipicamente o mesmo SHA que passou no DES).

Troubleshooting
- Import da imagem: certifique-se que a imagem `:sha` existe no GHCR (veja o job do CI) e que o login foi realizado.
- Rollout travado: inspecione `kubectl -n <ns> describe deploy/app` e `kubectl -n <ns> logs deploy/app`.
- Job de smoke falhou: verifique logs com `kubectl -n <ns> logs job/smoke-health`.

Limitações e escopo
- O cluster k3d do CD é apenas para validação (não é ambiente persistente). Não há Ingress externo; o smoke usa Service interno.
- Não usar Helm/CRDs. Manter estrutura `deploy/base`, `deploy/des`, `deploy/prd`.
