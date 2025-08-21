#!/usr/bin/env bash
set -euo pipefail

# scripts/build-local.sh
# Build the project, build a Docker image and run it detached to perform a smoke test
# Usage:
#   ./scripts/build-local.sh [--image IMAGE] [--port PORT] [--timeout SEC] [--no-clean]
# Examples:
#   ./scripts/build-local.sh
#   ./scripts/build-local.sh --image ghcr.io/org/repo:dev --no-clean

IMAGE="local-app:dev"
NAME="local-app-smoke"
PORT=8080
TIMEOUT=30
INTERVAL=2
NO_CLEAN=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --no-clean) NO_CLEAN=true; shift 1 ;;
    -h|--help)
      sed -n '1,120p' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 2 ;;
  esac
done

echo "IMAGE=${IMAGE}"
echo "PORT=${PORT}"

echo "Running Maven package (quiet)..."
mvn -q -DskipTests package

echo "Building Docker image ${IMAGE}"
docker build -t "${IMAGE}" .

echo "Starting container ${NAME} (detached, non-root user 10001)"
# remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -Eq "^${NAME}$"; then
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
fi
CONTAINER_ID=$(docker run -d --name "${NAME}" --user 10001 -p "${PORT}:8080" "${IMAGE}")

echo "Container started: ${CONTAINER_ID}"

cleanup() {
  if [ "$NO_CLEAN" = false ]; then
    echo "Stopping and removing container ${NAME}"
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
  else
    echo "--no-clean set, keeping container ${NAME} for debugging"
  fi
}

# ensure cleanup on exit (unless --no-clean)
trap cleanup EXIT

echo "Waiting for readiness endpoint http://localhost:${PORT}/q/health/ready (timeout ${TIMEOUT}s)"
start_ts=$(date +%s)
end_ts=$((start_ts + TIMEOUT))

while [ $(date +%s) -le ${end_ts} ]; do
  if curl -fsS "http://localhost:${PORT}/q/health/ready" >/dev/null 2>&1; then
    echo "Smoke test: READY OK"
    exit 0
  fi
  sleep ${INTERVAL}
done

echo "Smoke test failed: readiness endpoint did not become ready within ${TIMEOUT}s"
exit 1
