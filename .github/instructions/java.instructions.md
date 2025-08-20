---
applyTo: "src/**/*.java"
---

# Copilot instructions for Java/Quarkus code

- Target **Java 21** and Quarkus idioms (Jakarta EE APIs where applicable).
- Keep `quarkus.package.type=fast-jar`.
- Expose endpoints compatible with the quickstart; the health endpoint is `/q/health` on port 8080.
- Prefer JUnit 5 for tests; keep tests lightweight and deterministic.
- Do not introduce heavy frameworks or change the project layout (stay close to the Quarkus Getting Started guide).
