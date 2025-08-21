#!/usr/bin/env bash
set -euo pipefail

# idempotent k3d cluster up script
CLUSTER_NAME="${K3D_CLUSTER:-hackathon-k3d}"
K3D_CONFIG="$(dirname "${BASH_SOURCE[0]}")/../infra/k3d/cluster.yaml"
HOSTS_FILE="$(dirname "${BASH_SOURCE[0]}")/../infra/k3d/hosts.conf"
HOSTS_MARKER_BEGIN="# >>> hackathon-2025 hosts BEGIN"
HOSTS_MARKER_END="# <<< hackathon-2025 hosts END"

# ensure k3d is installed
if ! command -v k3d >/dev/null 2>&1; then
  echo "k3d not found. Please install k3d: https://k3d.io/#installation"
  exit 1
fi

# create cluster if not exists
if k3d cluster list -o json | jq -e ".[] | select(.name==\"${CLUSTER_NAME}\")" >/dev/null 2>&1; then
  echo "Cluster ${CLUSTER_NAME} already exists. Skipping creation."
else
  echo "Creating cluster ${CLUSTER_NAME} from ${K3D_CONFIG}"
  # Use positional NAME argument for compatibility across k3d versions
  k3d cluster create "${CLUSTER_NAME}" -c "${K3D_CONFIG}"
fi

# apply declarative resources
if [ -d "$(dirname "${BASH_SOURCE[0]}")/../deploy/base" ]; then
  kubectl apply -R -f "$(dirname "${BASH_SOURCE[0]}")/../deploy/base" || true
fi
# ensure namespaces and environment overlay
if [ -d "$(dirname "${BASH_SOURCE[0]}")/../deploy/des" ]; then
  kubectl apply -R -f "$(dirname "${BASH_SOURCE[0]}")/../deploy/des" || true
else
  echo "Info: $(dirname "${BASH_SOURCE[0]}")/../deploy/des not found; skipping environment overlay"
fi

# inject hosts from infra/k3d/hosts.conf if present
if [ -f "${HOSTS_FILE}" ]; then
  echo "Applying hosts from ${HOSTS_FILE} to /etc/hosts (requires sudo)"
  tmp=$(mktemp)
  # copy /etc/hosts excluding any previous block
  awk -v b="${HOSTS_MARKER_BEGIN}" -v e="${HOSTS_MARKER_END}" '
    $0==b {inside=1; next}
    $0==e {inside=0; next}
    !inside {print}
  ' /etc/hosts > "${tmp}"

  # append fresh block
  printf "%s\n" "${HOSTS_MARKER_BEGIN}" >> "${tmp}"
  sed '/^\s*#/d;/^\s*$/d' "${HOSTS_FILE}" >> "${tmp}"
  printf "%s\n" "${HOSTS_MARKER_END}" >> "${tmp}"

  if [[ $EUID -ne 0 ]]; then
    sudo cp "${tmp}" /etc/hosts
  else
    cp "${tmp}" /etc/hosts
  fi
  rm -f "${tmp}"
  echo "/etc/hosts updated from ${HOSTS_FILE}"
else
  echo "No ${HOSTS_FILE} found; skipping /etc/hosts update"
fi

echo "k3d cluster is ready. Current namespaces:"
kubectl get ns
