#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="hackathon-k3d"
HOSTS_MARKER_BEGIN="# >>> hackathon-2025 hosts BEGIN"
HOSTS_MARKER_END="# <<< hackathon-2025 hosts END"

function remove_hosts_block() {
  if ! grep -q "${HOSTS_MARKER_BEGIN}" /etc/hosts >/dev/null 2>&1; then
    echo "No hosts marker block in /etc/hosts; skipping removal"
    return
  fi

  tmp=$(mktemp)
  awk -v b="${HOSTS_MARKER_BEGIN}" -v e="${HOSTS_MARKER_END}" '
    $0==b {inside=1; next}
    $0==e {inside=0; next}
    !inside {print}
  ' /etc/hosts > "${tmp}"

  if [[ $EUID -ne 0 ]]; then
    sudo cp "${tmp}" /etc/hosts
  else
    cp "${tmp}" /etc/hosts
  fi
  rm -f "${tmp}"
  echo "Removed ${HOSTS_MARKER_BEGIN} block from /etc/hosts"
}

# delete cluster if exists
if command -v k3d >/dev/null 2>&1 && k3d cluster list -o json | jq -e ".[] | select(.name==\"${CLUSTER_NAME}\")" >/dev/null 2>&1; then
  echo "Deleting cluster ${CLUSTER_NAME}"
  k3d cluster delete "${CLUSTER_NAME}" || true
else
  echo "Cluster ${CLUSTER_NAME} not found or k3d not installed. Nothing to do."
fi

# clean hosts block
remove_hosts_block
