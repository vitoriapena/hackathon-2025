# PRD-01 — Cluster Kubernetes local (k3d)

## Objetivo
Ter um cluster Kubernetes local reprodutível com dois namespaces (`des`, `prd`) para implantar a aplicação Quarkus Getting Started.

## Escopo
- Provisionamento via **k3d** com script idempotente.
- Namespaces: `des` e `prd`.
- Ingress nativo do k3d (Traefik) com hosts locais:
  - `127.0.0.1 app.des.local`
  - `127.0.0.1 app.prd.local`

## Fora do escopo
Alta disponibilidade, TLS/mkcert, Prometheus/metrics.

## Critérios de Aceite
- `make k3d-up` cria o cluster; `make k3d-down` remove.
- `kubectl get ns` exibe `des` e `prd`.
- Manifests aplicados com sucesso (`kubectl apply -n des ...`).

## Entregáveis
- `infra/k3d/cluster.yaml`
- `scripts/k3d-up.sh`, `scripts/k3d-down.sh`
- `docs/cluster.md` com passo a passo e edição de `/etc/hosts`.

## Observações
Executar os workflows de deploy em runner **self-hosted** com acesso ao kubeconfig do k3d.

## Alternativa futura: Azure DevOps
Pipeline YAML em um **self-hosted agent** executando os mesmos scripts (`k3d-up`, `k3d-down`).