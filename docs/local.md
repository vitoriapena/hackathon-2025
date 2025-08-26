# Local: do zero ao deploy

Guia rápido para recriar o cluster k3d, buildar a app, fazer deploy local e verificar.

## Pré‑requisitos
- Docker
- k3d, kubectl, jq
- Maven (Java 21) e envsubst (pacote gettext)

## 1) Reset do cluster k3d
```zsh
./scripts/bash/k3d-down.sh || true
./scripts/bash/k3d-up.sh
```
Observações:
- `k3d-up.sh` cria o cluster `hackathon-k3d` usando `infra/k3d/cluster.yaml` e atualiza `/etc/hosts` a partir de `infra/k3d/hosts.conf`.

## 2) Build e deploy local
```zsh
# Na raiz do repositório
cd /home/vmpm/environments/hackathon-2025

# Opcional: definir ORG/REPO se não quiser inferir do remote git
# export ORG="<sua-org>"
# export REPO="<seu-repo>"

# Opcional: aprovar PRD automaticamente
export APPROVE_PRD=true

# Build Maven -> build/tag Docker -> importar no k3d -> aplicar manifests -> smoke
./scripts/bash/build-deploy-local.sh
```

## 3) Verificação rápida
Sem Ingress exposto, o host app.des.local no seu computador não roteia para o Service dentro do cluster. As sondas e o smoke test passam porque acessam o Service internamente. Faça o health check de dentro do cluster:

```zsh
# Health checks (in-cluster)
kubectl -n des run curl --rm -it --restart=Never --image=curlimages/curl:8.9.1 -- \
  curl -fsS http://app:8080/q/health
# PRD (opcional)
kubectl -n prd run curl --rm -it --restart=Never --image=curlimages/curl:8.9.1 -- \
  curl -fsS http://app:8080/q/health

# Recursos implantados
kubectl -n des get deploy,svc,ingress,pods
kubectl -n prd get deploy,svc,ingress,pods

# Logs da aplicação (DES)
kubectl -n des logs deploy/app -f
```

## 4) Limpeza (opcional)
```zsh
./scripts/bash/k3d-down.sh
```
