# Guia de Deploy Local (k3d)

Este guia descreve como preparar o ambiente local, construir a imagem e realizar o deploy nos namespaces `des` (sempre) e `prd` (com aprovação) em um único cluster k3d. Os manifests base são agnósticos de ambiente e usam a variável `NAMESPACE`; detalhes específicos ficam nos overlays em `deploy/des/` e `deploy/prd/`.

## Visão geral

- Um cluster k3d único com Traefik expondo 80/443 do host.
- Dois namespaces: `des` (desenvolvimento) e `prd` (produção simulada).
- Manifests:
  - `deploy/base/`: genéricos (Deployment, Service, Smoke Job) com `${NAMESPACE}`.
  - `deploy/des/`: ajustes de ambiente DES.
  - `deploy/prd/`: ajustes de ambiente PRD (ex.: `replicas: 2`).
- Fluxo recomendado: script automatizado que sempre implanta DES e solicita aprovação para PRD.

## Pré‑requisitos (Linux)

- Java 21 (Temurin)
- Maven
- Docker
- k3d (>= 5.x), kubectl
- jq, envsubst (pacote `gettext-base`), curl

Exemplo (Debian/Ubuntu):

```bash
sudo apt-get update && sudo apt-get install -y jq gettext-base curl
```

Instale k3d/kubectl/Docker conforme documentação oficial.

## Subir o cluster local

Use o script idempotente de criação do cluster (nome padrão: `hackathon-k3d`). Ele também atualiza `/etc/hosts` a partir de `infra/k3d/hosts.conf`.

```bash
scripts/bash/k3d-up.sh
```

Notas:
- O script usa o argumento posicional de nome do k3d: `k3d cluster create "${CLUSTER_NAME}" -c "infra/k3d/cluster.yaml"` (compatível com versões recentes do k3d).
- Contexto kubectl esperado: `k3d-hackathon-k3d`.

## Build da aplicação e imagem

1) Build/testes (rápidos e determinísticos):

```bash
mvn -B -DskipTests=false package
```

2) Build da imagem (exemplo de tag):

```bash
docker build -t ghcr.io/<org>/<repo>:<sha> .
```

Opcional (se não for puxar do registry): importar a imagem no k3d:

```bash
k3d image import ghcr.io/<org>/<repo>:<sha> -c hackathon-k3d
```

Importante: apesar do prefixo `ghcr.io/...`, essa é uma imagem LOCAL recém‑buildada. O fluxo atual não faz pull do GHCR automaticamente; o script usa a imagem local (e a importa no k3d, se disponível). O uso do namespace `ghcr.io/...` é apenas convenção de nomenclatura de tag.

Para usar uma imagem publicada no GHCR, você pode pular o build local e apontar os manifests para a tag publicada, garantindo acesso do cluster ao registro (por exemplo, com `imagePullSecret` se o repositório for privado). Esse fluxo ainda não está automatizado neste script.

## Deploy local automatizado (recomendado)

O script `scripts/bash/build-deploy-local.sh` constrói/renderiza os manifests por ambiente, substitui `${NAMESPACE}` com `envsubst`, faz rollout/wait e smoke test. Ele sempre publica em DES e pede aprovação para PRD (ou lê `APPROVE_PRD=true`).

Nota: por padrão, o script SEMPRE faz build da imagem local e usa essa imagem (tagueada como `ghcr.io/<org>/<repo>:<tag>`). Ele não realiza pull do GHCR.

Variáveis úteis:
- `IMAGE_TAG`: tag da imagem (ex.: `ghcr.io/<org>/<repo>:<sha>`) — usada para nomear a imagem local construída
- `K3D_CLUSTER`: nome do cluster k3d (default `hackathon-k3d`)
- `APPROVE_PRD`: se `true`, implanta PRD sem prompt

Exemplos:

```bash
IMAGE_TAG=ghcr.io/<org>/<repo>:<sha> scripts/bash/build-deploy-local.sh
APPROVE_PRD=true IMAGE_TAG=ghcr.io/<org>/<repo>:<sha> scripts/bash/build-deploy-local.sh
```

## Deploy manual (alternativa)

1) Aplicar base com substituição de `NAMESPACE` para DES:

```bash
export NAMESPACE=des
find deploy/base -maxdepth 1 -name "*.yaml" -print0 | xargs -0 -I {} sh -c 'envsubst < "{}" | kubectl apply -f -'
```

2) Aplicar overlay do DES e aguardar rollout:

```bash
kubectl apply -R -f deploy/des
kubectl -n des rollout status deploy/app
```

3) Smoke test in‑cluster (Job):

```bash
envsubst < deploy/base/smoke-job.yaml | kubectl apply -f -
kubectl -n des wait --for=condition=complete job/smoke-health --timeout=60s
kubectl -n des get job smoke-health -o jsonpath='{.status.succeeded}'
```

4) Smoke test externo (Traefik):

```bash
curl -fsS http://app.des.local/q/health
```

5) Promoção manual para PRD (mesma imagem):

```bash
export NAMESPACE=prd
find deploy/base -maxdepth 1 -name "*.yaml" -print0 | xargs -0 -I {} sh -c 'envsubst < "{}" | kubectl apply -f -'
kubectl apply -R -f deploy/prd
kubectl -n prd rollout status deploy/app
curl -fsS http://app.prd.local/q/health
```

## Limpeza

```bash
scripts/bash/k3d-down.sh
```

## Troubleshooting

- k3d: se vir erro sobre `--name`, confirme que o script usa o nome posicional (já corrigido) e a versão do k3d é compatível.
- Contexto kubectl: `kubectl config get-contexts` e selecione `k3d-hackathon-k3d`.
- Hosts/Traefik: confirme que `infra/k3d/hosts.conf` foi aplicado ao `/etc/hosts` pelo `k3d-up.sh`.
- Imagem não encontrada: importe com `k3d image import ...` ou faça push para GHCR e ajuste `IMAGE_TAG`.
- Variáveis: os YAMLs em `deploy/base/` exigem `NAMESPACE` ao aplicar manualmente; use `envsubst` como nos exemplos.
