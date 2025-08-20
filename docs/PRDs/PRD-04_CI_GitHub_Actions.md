# PRD-04 — CI (GitHub Actions)

## Objetivo
Executar build, testes, scan e publicação de imagem a cada PR/push.

## Escopo (workflow `ci.yml`)
1. `actions/checkout` (fetch-depth 0).
2. `actions/setup-java` (Temurin 21) com cache Maven.
3. `mvn test package` e publicação de relatórios JUnit.
4. **CodeQL Java** (SAST leve).
5. Build da imagem Docker.
6. **Trivy image scan** com gate para HIGH/CRITICAL.
7. Login e **push** no GHCR.

## Políticas
- `permissions` mínimos: `contents: read`, `packages: write`, `security-events: write`.
- Actions **pinadas** por SHA.
- `concurrency` por branch; **branch protection** requer CI verde para merge.

## Critérios de Aceite
- PR só pode ser mergeado com todos os checks verdes.
- Artefatos do job incluem relatórios JUnit.

## Alternativa futura: Azure DevOps
Stage `CI` com `Maven@4`, `Docker@2` e extensão CodeQL (ou SonarCloud) se disponível.