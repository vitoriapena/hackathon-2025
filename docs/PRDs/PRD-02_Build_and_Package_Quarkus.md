# PRD-02 — Build & Package (Quarkus Getting Started)

Repositório de referência: <https://github.com/quarkusio/quarkus-quickstarts/tree/main/getting-started>

## Objetivo
Compilar e empacotar a aplicação Quarkus Getting Started em JAR executável.

## Escopo
- Build com **Maven** e Temurin **17** ou **21** (recomendado 21).
- `quarkus.package.type=fast-jar`.
- Testes unitários habilitados e publicados.

## Critérios de Aceite
- `mvn -B -DskipTests=false package` gera `target/quarkus-app/`.
- Relatórios JUnit disponíveis como artefatos no CI.

## Entregáveis
- `pom.xml` (do quickstart, sem alterações funcionais).
- `docs/build.md` (como rodar localmente).

## Alternativa futura: Azure DevOps
Tarefa `Maven@4` executando `package` e publicando testes com `PublishTestResults@2`.