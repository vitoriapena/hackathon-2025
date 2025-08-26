# PRD-06 — Deploy PRD (simulado) com aprovação

## Objetivo
Promover a mesma imagem aprovada em DES para `prd` mediante aprovação manual.

## Escopo
- **Overlay** `deploy/prd/` com manifests YAML específicos (p.ex. `deploy/prd/deployment.yaml`):
  - Réplicas `2`.
  - Host `app.prd.local`.
  - Variáveis de configuração para “produção simulada”.
- Workflow `cd.yaml` (job PRD manual):
  - `workflow_dispatch` com input `imageTag`.
  - **Environment protection** com reviewers obrigatórios.
  - `kubectl apply -f deploy/prd -R` + `kubectl rollout status` + smoke (`/q/health`).

## Critérios de Aceite
- Aprovação requerida antes da execução.
- Rollout e smoke bem-sucedidos, usando **a mesma tag** construída no CI.

## Alternativa futura: Azure DevOps
Stage `PRD` com `approvals`/`ManualValidation` e `kubectl apply -f deploy/prd -R`.