# Repository Custom Instructions — Quarkus Getting Started + k3d

> These instructions guide GitHub Copilot when working **in this repository**. They are short, reusable rules that apply to most tasks.

## Project summary
- **App**: Quarkus “Getting Started” (Java) — https://github.com/quarkusio/quarkus-quickstarts/tree/main/getting-started
- **Build**: Maven, Temurin **Java 21** preferred.
- **Container**: Dockerfile multi-stage (builder: maven+temurin-21; runtime: temurin-21-jre).
- **Orchestration**: k3d Kubernetes (local) with namespaces `des` and `prd`.
- **Deploy**: Raw Kubernetes manifests with **environment-specific YAML overlays** — **do not use Helm**.
- **CI/CD**: GitHub Actions. CI builds/tests/scans and publishes to GHCR. CD applies raw YAMLs to `des` on merge; `prd` is manual with approval.

## Source layout (conventions)
```
src/                      # Quarkus app source
Dockerfile                # multi-stage build
deploy/
  base/                   # K8s base (deployment, service, ingress)
  des/                    # overlay for DES (plain YAML manifests)
  prd/                    # overlay for PRD (plain YAML manifests)
.github/workflows/        # ci.yaml, deploy-des.yaml, deploy-prd.yaml
infra/k3d/                # k3d cluster config + scripts
```
If you add files, follow this structure.

## Build & test
- Use `mvn -B -DskipTests=false package` to build.
- Prefer JUnit 5, Quarkus test utilities; keep tests fast and deterministic.
- Don’t add heavyweight frameworks or change the quickstart’s architecture without a clear reason.

## Container image
- Build a **small** runtime image based on `eclipse-temurin:21-jre`.
- Run as **non-root**. Expose **8080**. Add a basic `HEALTHCHECK` hitting `/q/health`.
- Tagging convention: `ghcr.io/<org>/<repo>:<sha>` and `:des` for last DES deploy.

## Kubernetes (no Helm)
- Place generic manifests in `deploy/base/` and environment-specific patches in `deploy/des` and `deploy/prd` using plain YAML files (no Kustomize).
- Defaults:
  - Deployment: 1 replica in DES, 2 in PRD.
  - Probes: `readiness` and `liveness` using `/q/health` on port 8080.
  - Security: runAsNonRoot, drop capabilities; **no privileged containers**.
  - Service: ClusterIP. Ingress hosts: `app.des.local`, `app.prd.local` (Traefik).
- Don’t introduce CRDs or extra controllers unless explicitly requested.

## CI/CD (GitHub Actions)
- CI (`.github/workflows/ci.yaml`):
  - checkout (depth 0) → setup-java (Temurin 21) → `mvn test package`.
  - build Docker image → **Trivy image scan** (fail on HIGH/CRITICAL) → push to GHCR.
  - Keep workflow permissions minimal (`contents:read`, `packages:write`).
- Deploy DES on merge to `main`: `kubectl apply -f deploy/des -R` then smoke test `GET /q/health`.
- Deploy PRD is **manual** (workflow_dispatch) with approval and `kubectl apply -f deploy/prd -R` reusing the image tag from CI.

## Coding style & changes
- Keep PRs **small** and focused. Favor clear names, short methods, and Quarkus idioms.
- Don’t change ports, health endpoints, or Quarkus packaging type (`fast-jar`) unless a requirement demands it.
- Follow **Conventional Commits** and **SemVer** if you touch release/version files.
- Before applying automated edits to repository files, list the files to change, explain the reason, and wait for explicit user approval ("LGTM") to proceed.

## What NOT to do
- Do **not** add Helm charts, SealedSecrets, OPA, SBOM, or signing — these are out of scope.
- Do **not** commit secrets. Use repo environments/secrets when needed.
- Avoid changing the quickstart structure just to “modernize” it.

## Helpful commands (for references in explanations)
- Build/test: `mvn -B -DskipTests=false package`
- Local run: `./mvnw quarkus:dev` (dev mode)
- Image build: `docker build -t ghcr.io/<org>/<repo>:<sha> .`
- DES deploy: `kubectl apply -k deploy/des && kubectl -n des rollout status deploy/app`
- Smoke: `curl -fsS http://app.des.local/q/health`

---
These instructions live in `.github/copilot-instructions.md`. In VS Code you may also split rules into multiple files under `.github/instructions/*.instructions.md` using `applyTo` to target file patterns.

<!-- NOTE: prefer `.yaml` extension for GitHub workflows (e.g. `.github/workflows/ci.yaml`). -->
