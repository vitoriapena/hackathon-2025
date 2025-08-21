#!/usr/bin/env bash
# build-deploy-local.sh — build image, import to k3d clusters, apply manifests (base -> env overlay) and run smoke job
# Usage:
#   ORG=your-org REPO=your-repo ./scripts/build-deploy-local.sh
set -euo pipefail

# --- config / env ---
K3D_CLUSTER="${K3D_CLUSTER:-hackathon-k3d}"
DES_NAMESPACE="${DES_NAMESPACE:-des}"
PRD_NAMESPACE="${PRD_NAMESPACE:-prd}"
TIMEOUT_ROLLOUT="${TIMEOUT_ROLLOUT:-120s}"
TIMEOUT_SMOKE="${TIMEOUT_SMOKE:-60s}"
APPROVE_PRD="${APPROVE_PRD:-false}"
TMPROOT="$(mktemp -d)"
CLEANUP_ON_EXIT=true

trap 'if [ "${CLEANUP_ON_EXIT}" = true ]; then rm -rf "${TMPROOT}"; fi' EXIT

# --- helpers ---
err() { printf '%s\n' "$*" >&2; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Required command not found: $1"; exit 2; }; }

# infer ORG/REPO from git remote if not supplied
infer_org_repo() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    url=$(git remote get-url origin 2>/dev/null || true)
    if [[ -n "$url" ]]; then
      if [[ "$url" =~ [:/]{1}([^/]+)/([^/.]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
        return 0
      fi
    fi
  fi
  return 1
}

# render function: copies manifests to env-specific tmp dir and substitutes tokens
render_manifests_env() {
  local env_ns="$1" env_dir="$2"
  mkdir -p "${env_dir}/base" "${env_dir}/overlay"
  cp -a deploy/base/. "${env_dir}/base/"
  if [ -d "deploy/${env_ns}" ]; then
    cp -a "deploy/${env_ns}/." "${env_dir}/overlay/"
  fi
  # Replace image placeholder in all yamls
  find "${env_dir}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | while IFS= read -r -d '' f; do
    if grep -q "ghcr.io/<org>/<repo>:<sha>" "$f" 2>/dev/null; then
      sed -i "s|ghcr.io/<org>/<repo>:<sha>|${IMAGE}|g" "$f"
    fi
  done
  # Resolve ${NAMESPACE} placeholders using envsubst (scoped to env_ns)
  find "${env_dir}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | while IFS= read -r -d '' f; do
    tmpf="${f}.rendered"
    NAMESPACE="${env_ns}" envsubst < "$f" > "$tmpf" && mv "$tmpf" "$f"
  done
}

# switch kubectl context to given k3d cluster name if it exists
use_k3d_context() {
  local cluster="$1" ctx="k3d-${1}"
  if kubectl config get-contexts -o name | grep -qx "$ctx"; then
    kubectl config use-context "$ctx" >/dev/null
    return 0
  fi
  return 1
}

# import image into k3d cluster if it exists
import_image_into_k3d() {
  local cluster="$1"
  if command -v k3d >/dev/null 2>&1; then
    if k3d cluster list | awk '{print $1}' | grep -qx "$cluster"; then
      printf "\nImporting image into k3d cluster '%s'\n" "$cluster"
      k3d image import "${IMAGE}" --cluster "$cluster" || true
      k3d image import "${IMAGE_DES}" --cluster "$cluster" || true
    else
      printf "\nCluster '%s' not found. Skipping image import.\n" "$cluster"
    fi
  fi
}

# deploy routine for one environment
deploy_env() {
  local cluster="$1" ns="$2" envtmp="$3"
  printf "\n==> Deploying to cluster '%s' namespace '%s'\n" "$cluster" "$ns"

  # try switch context
  if ! use_k3d_context "$cluster"; then
    printf "Context k3d-%s not found. Using current kubectl context.\n" "$cluster"
  fi

  printf "Ensuring namespace '%s' exists\n" "$ns"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -

  printf "Applying rendered deploy/base for '%s'\n" "$ns"
  kubectl apply -R -f "${envtmp}/base"

  if [ -d "${envtmp}/overlay" ]; then
    printf "Applying rendered overlay for '%s'\n" "$ns"
    kubectl apply -R -f "${envtmp}/overlay"
  fi

  printf "Waiting for rollout of deploy/app in '%s'\n" "$ns"
  kubectl -n "$ns" rollout status deploy/app --timeout="${TIMEOUT_ROLLOUT}"

  local smoke_yaml="${envtmp}/base/smoke-job.yaml"
  if [ -f "$smoke_yaml" ]; then
    printf "Running smoke job for '%s'\n" "$ns"
    kubectl -n "$ns" delete job smoke-health --ignore-not-found || true
    kubectl -n "$ns" apply -f "$smoke_yaml"
    kubectl -n "$ns" wait --for=condition=complete job/smoke-health --timeout="${TIMEOUT_SMOKE}" || {
      err "Smoke failed in ns=$ns. Logs:"; kubectl -n "$ns" logs job/smoke-health || true; exit 3; }
    kubectl -n "$ns" logs job/smoke-health || true
  fi
}

# --- preflight ---
require_cmd mvn
require_cmd docker
require_cmd kubectl
require_cmd git
require_cmd envsubst

HAVE_K3D=false
if command -v k3d >/dev/null 2>&1; then HAVE_K3D=true; fi

# ORG/REPO/TAG/IMAGE
TAG="${TAG:-$(git rev-parse --short HEAD)}"
ORG="${ORG:-}"
REPO="${REPO:-}"

if [[ -z "$ORG" || -z "$REPO" ]]; then
  if inferred=$(infer_org_repo); then read -r iorg irepo <<<"$inferred"; ORG="${ORG:-$iorg}"; REPO="${REPO:-$irepo}"; fi
fi

if [[ -z "$ORG" || -z "$REPO" ]]; then
  err "ORG and REPO not set and could not be inferred. Set env ORG and REPO."; exit 1
fi

IMAGE="ghcr.io/${ORG}/${REPO}:${TAG}"
IMAGE_DES="ghcr.io/${ORG}/${REPO}:des"

printf "Will build image: %s (alias: %s)\n" "$IMAGE" "$IMAGE_DES"

# --- build ---
printf "\n1) Maven build\n"; mvn -B -DskipTests=false package
printf "\n2) Docker build\n"; docker build -t "${IMAGE}" .; docker tag "${IMAGE}" "${IMAGE_DES}" || true

# --- make image available to k3d (both clusters if present) ---
if [ "${HAVE_K3D}" = true ]; then
  import_image_into_k3d "$K3D_CLUSTER"
else
  printf "\n3) k3d not available. Ensure the image is reachable by the cluster (push to registry).\n"
fi

# --- render per environment ---
DES_TMP="${TMPROOT}/des"; PRD_TMP="${TMPROOT}/prd"
printf "\n4) Rendering manifests (DES -> %s, PRD -> %s)\n" "$DES_TMP" "$PRD_TMP"
render_manifests_env "$DES_NAMESPACE" "$DES_TMP"
render_manifests_env "$PRD_NAMESPACE" "$PRD_TMP"

# --- deploy DES ---
printf "\n5) Deploying to DES (cluster=%s ns=%s)\n" "$K3D_CLUSTER" "$DES_NAMESPACE"
use_k3d_context "$K3D_CLUSTER" || true
deploy_env "$K3D_CLUSTER" "$DES_NAMESPACE" "$DES_TMP"
printf "DES deploy complete.\n"

# --- approval for PRD ---
DO_PRD=false
if [[ "${APPROVE_PRD}" == "true" ]]; then
  DO_PRD=true
else
  if [ -t 1 ]; then
    read -r -p $'\nProceed to deploy PRD (cluster=%s ns=%s)? [y/N]: ' -e -i "n" response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      DO_PRD=true
    fi
  fi
fi

if [ "$DO_PRD" = true ]; then
  printf "\n6) Deploying to PRD (cluster=%s ns=%s)\n" "$K3D_CLUSTER" "$PRD_NAMESPACE"
  use_k3d_context "$K3D_CLUSTER" || true
  deploy_env "$K3D_CLUSTER" "$PRD_NAMESPACE" "$PRD_TMP"
  printf "PRD deploy complete.\n"
else
  printf "\nPRD deployment skipped.\n"
fi

printf "\nDone: application deployed to DES and optionally PRD.\n"
printf "Temporary overlay folder %s removed on exit.\n" "${TMPROOT}"
