---
applyTo: ".github/workflows/*.yml"
---

# Copilot instructions for GitHub Actions workflows

- Use **checkout** with `fetch-depth: 0`.
- Use **setup-java** (Temurin 21) with Maven cache.
- Keep `permissions` minimal: `contents: read`, `packages: write`, add `security-events: write` only if running CodeQL.
- **Pin actions by SHA**.
- Add `concurrency` per branch to avoid duplicate runs.
- Steps (CI):
  1) `mvn -B -DskipTests=false package`
  2) Build Docker image and push to **GHCR**
  3) **trivy image** scan — fail on HIGH/CRITICAL
- Deploy (DES): run on merge to `main`, use **self-hosted** runner with kubeconfig; `kubectl apply -k deploy/des` + `kubectl rollout status` + smoke test.
- Deploy (PRD): trigger `workflow_dispatch` with `imageTag` input and use environment approval before `kubectl apply -k deploy/prd`.
