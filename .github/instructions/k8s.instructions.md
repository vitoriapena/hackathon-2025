---
applyTo: "deploy/**/*.yaml"
---

# Copilot instructions for Kubernetes manifests

- Keep manifests plain YAML with environment-specific overlays. **No Helm**, **no Kustomize**.
- Base (`deploy/base`):
  - `Deployment`, `Service`, `Ingress`.
  - Container runs as **non-root**; do not request privileged mode.
  - Add `readinessProbe` and `livenessProbe` hitting `/q/health` on port 8080.
- Overlays:
  - `des`: replicas=1, lightweight requests/limits, host `app.des.local`.
  - `prd`: replicas=2, host `app.prd.local`.
- Services are `ClusterIP`. Use standard labels: `app.kubernetes.io/name`, `app.kubernetes.io/instance`.
- Image is **set directly** in the environment overlay YAMLs to `ghcr.io/<org>/<repo>:<sha>` for DES and the chosen tag for PRD. Do not rely on external tools to patch manifests.
- Defaults:
  - Deployment: 1 replica in DES, 2 in PRD.
  - Probes: `readiness` and `liveness` using `/q/health` on port 8080.
  - Security: runAsNonRoot, drop capabilities; **no privileged containers**.
  - Service: ClusterIP. Ingress hosts: `app.des.local`, `app.prd.local` (Traefik).
