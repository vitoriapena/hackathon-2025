#!/usr/bin/env bash
# build-deploy-local.sh — build image, import to k3d (if present), apply manifests (base -> des overlay) and run smoke job
# Usage:
#   ORG=your-org REPO=your-repo ./scripts/build-deploy-local.sh
set -euo pipefail

# --- config / env ---
CLUSTER="${K3D_CLUSTER:-des}"        # k3d cluster name used for k3d image import (default: des)
NAMESPACE="des"
TIMEOUT_ROLLOUT="${TIMEOUT_ROLLOUT:-120s}"
TIMEOUT_SMOKE="${TIMEOUT_SMOKE:-60s}"
TMPDIR="$(mktemp -d)"
CLEANUP_ON_EXIT=true

trap 'if [ "${CLEANUP_ON_EXIT}" = true ]; then rm -rf "${TMPDIR}"; fi' EXIT

# --- helpers ---
err() { printf '%s
' "$*" >&2; }
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command not found: $1"; exit 2; }
}

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

# --- preflight ---
require_cmd mvn
require_cmd docker
require_cmd kubectl
require_cmd git

if command -v k3d >/dev/null 2>&1; then
  HAVE_K3D=true
else
  HAVE_K3D=false
fi

# ORG/REPO/TAG/IMAGE
TAG="${TAG:-$(git rev-parse --short HEAD)}"
ORG="${ORG:-}"
REPO="${REPO:-}"

if [[ -z "$ORG" || -z "$REPO" ]]; then
  if inferred=$(infer_org_repo); then
    read -r iorg irepo <<<"$inferred"
    ORG="${ORG:-$iorg}"
    REPO="${REPO:-$irepo}"
  fi
fi

if [[ -z "$ORG" || -z "$REPO" ]]; then
  err "ORG and REPO not set and could not be inferred. Set env ORG and REPO, e.g.:"
  err "  ORG=my-org REPO=my-repo ./scripts/build-deploy-local.sh"
  exit 1
fi

IMAGE="ghcr.io/${ORG}/${REPO}:${TAG}"
IMAGE_DES="ghcr.io/${ORG}/${REPO}:des"

printf "Will build image: %s (alias: %s)\n" "$IMAGE" "$IMAGE_DES"

# --- build ---
printf "\n1) Maven build\n"
mvn -B -DskipTests=false package

printf "\n2) Docker build\n"
docker build -t "${IMAGE}" .

# also tag :des for last DES deploy convenience
docker tag "${IMAGE}" "${IMAGE_DES}" || true

# --- make image available to k3d ---
if [ "${HAVE_K3D}" = true ]; then
  # auto-detect current kubectl context cluster if CLUSTER not found
  ACTUAL_CLUSTER="${CLUSTER}"
  if ! k3d cluster list | grep -q "^${CLUSTER}"; then
    # try to infer from kubectl context
    current_context=$(kubectl config current-context 2>/dev/null || true)
    if [[ "$current_context" =~ k3d-(.+) ]]; then
      detected_cluster="${BASH_REMATCH[1]}"
      printf "\n3) Cluster '%s' not found, but detected '%s' from kubectl context. Using detected cluster.\n" "${CLUSTER}" "${detected_cluster}"
      ACTUAL_CLUSTER="${detected_cluster}"
    fi
  fi
  
  if k3d cluster list | grep -q "^${ACTUAL_CLUSTER}"; then
    printf "\n3) Importing image into k3d cluster '%s'\n" "${ACTUAL_CLUSTER}"
    k3d image import "${IMAGE}" --cluster "${ACTUAL_CLUSTER}" || true
    k3d image import "${IMAGE_DES}" --cluster "${ACTUAL_CLUSTER}" || true
  else
    printf "\n3) k3d present but cluster '%s' not found. Skipping import. Create cluster or push to registry.\n" "${ACTUAL_CLUSTER}"
  fi
else
  printf "\n3) k3d not available. Ensure the image is reachable by the cluster (push to registry) and update overlays accordingly.\n"
fi

# --- prepare overlay with concrete image (work in tmp to avoid changing git tracked files) ---
printf "\n4) Preparing overlay with concrete image in temp dir: %s\n" "${TMPDIR}"
mkdir -p "${TMPDIR}/des"
cp -a deploy/des/* "${TMPDIR}/des/" 2>/dev/null || true

# replace placeholder occurrences in all files under tmpdir
find "${TMPDIR}" -type f -name '*.yaml' -o -name '*.yml' | while read -r f; do
  if grep -q "ghcr.io/<org>/<repo>:<sha>" "$f" 2>/dev/null; then
    sed -i "s|ghcr.io/<org>/<repo>:<sha>|${IMAGE}|g" "$f"
  fi
done || true

# --- apply manifests (declarative sequence) ---
printf "\n5) Cleaning old smoke job/pods (if any) before applying deploy/base\n"
kubectl -n "${NAMESPACE}" delete job smoke-health --ignore-not-found || true
kubectl -n "${NAMESPACE}" delete pods -l job-name=smoke-health --ignore-not-found || true

printf "\n5) Applying deploy/base\n"
kubectl apply -R -f deploy/base

printf "\n6) Applying deploy/des (from temp overlay)\n"
kubectl apply -R -f "${TMPDIR}/des"

printf "\n7) Waiting for rollout of deploy/app in namespace '%s'\n" "${NAMESPACE}"
kubectl -n "${NAMESPACE}" rollout status deploy/app --timeout="${TIMEOUT_ROLLOUT}"

# --- smoke job ---
SMOKE_YAML="deploy/base/smoke-job.yaml"
if [ -f "${SMOKE_YAML}" ]; then
  printf "\n8) Ensuring old smoke job (if any) is removed and running smoke job (in-cluster): %s\n" "${SMOKE_YAML}"
  # remove previous job to avoid immutable field errors when reapplying
  kubectl -n "${NAMESPACE}" delete job smoke-health --ignore-not-found || true
  kubectl -n "${NAMESPACE}" apply -f "${SMOKE_YAML}"
  kubectl -n "${NAMESPACE}" wait --for=condition=complete job/smoke-health --timeout="${TIMEOUT_SMOKE}" || {
    err "Smoke job did not complete successfully. Showing job logs for diagnosis."
    kubectl -n "${NAMESPACE}" logs job/smoke-health || true
    err "You can try a port-forward fallback: kubectl -n ${NAMESPACE} port-forward svc/app 8080:8080 &"
    exit 3
  }
  printf "\nSmoke job succeeded. Logs:\n"
  kubectl -n "${NAMESPACE}" logs job/smoke-health || true
else
  err "Smoke job not found at ${SMOKE_YAML}. Skipping smoke step."
fi

printf "\nDone: application deployed to '%s' and smoke validated.\n" "${NAMESPACE}"
printf "Temporary overlay folder %s removed on exit.\n" "${TMPDIR}"
