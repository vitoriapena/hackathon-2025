# Cluster local com k3d — passo a passo

Pré-requisitos (Ubuntu):
- Docker (instalado e rodando)
- k3d (https://k3d.io)
- kubectl
- jq (usado pelos scripts)

Opções de instalação rápidas (Ubuntu):
- Docker: https://docs.docker.com/engine/install/ubuntu/
- k3d: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
- kubectl: sudo snap install kubectl --classic
- jq: sudo apt-get install -y jq

Scripts úteis:
- scripts/bash/k3d-up.sh — cria cluster, aplica manifests declarativos e atualiza /etc/hosts a partir de `infra/k3d/hosts.conf` (se existir)
- scripts/bash/k3d-down.sh — remove cluster e limpa bloco marcado em /etc/hosts

Uso local (declarativo):
1. Torne os scripts executáveis: chmod +x scripts/bash/*.sh
2. Crie o cluster e aplique recursos declarativos:
   sudo ./scripts/bash/k3d-up.sh
   - nota: o sudo é necessário apenas para atualizar /etc/hosts; a criação do cluster não precisa de sudo se seu usuário estiver no grupo docker.
3. Verifique namespaces: kubectl get ns
4. Aplique/atualize manifests localmente (se necessário): kubectl apply -R -f deploy/base && kubectl apply -n des -R -f deploy/des
5. Acesse a app: curl -fsS http://app.des.local/q/health

Arquivo declarativo de hosts (opção local):
- `infra/k3d/hosts.conf` — mantenha aqui as entradas de host para o projeto. Quando presente, `k3d-up.sh` injeta um bloco marcado em `/etc/hosts`; `k3d-down.sh` remove esse bloco.
- Exemplo de `infra/k3d/hosts.conf`:
  ```
  # hosts declarativo para hackathon-2025
  127.0.0.1 app.des.local
  127.0.0.1 app.prd.local
  ```

Uso em CI / runners self-hosted:
- Prefira não editar `/etc/hosts` na runner. Em vez disso, use uma estratégia declarativa in-cluster e um smoke test que não dependa de /etc/hosts:
  - Smoke test sem editar /etc/hosts:
    curl -fsS --resolve app.des.local:80:127.0.0.1 http://app.des.local/q/health
  - Alternativa: aplicar `infra/k3d/hosts-configmap.yaml` no cluster posteriormente (não implementado por enquanto).

Checklist rápido pós-criação do cluster:
- kubectl cluster-info
- kubectl get nodes
- kubectl get ns | grep -E 'des|prd'
- kubectl -n des rollout status deploy/app
- curl -fsS --resolve app.des.local:80:127.0.0.1 http://app.des.local/q/health

Sugestão Makefile (opcional):
- Adicionar targets minimalistas que orquestram os passos declarativos:
  - `make k3d-up` -> `k3d create --config infra/k3d/cluster.yaml && ./scripts/bash/k3d-up.sh`
  - `make bootstrap` -> aplica `deploy/base` e `deploy/des`
  - `make k3d-down` -> `./scripts/bash/k3d-down.sh`

Observações de segurança:
- Não comitar kubeconfig com credenciais.
- Scripts alteram /etc/hosts; em ambientes controlados da runner prefira usar `--resolve` na verificação ou configurar DNS na infraestrutura da runner.
