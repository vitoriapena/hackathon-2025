# Build local — Getting Started (Quarkus)

Pré-requisitos
- JDK 17 ou 21 (recomendado: Temurin 21)
- Maven (ou Maven Wrapper `./mvnw` se o wrapper estiver completo)
- Docker (opcional, apenas para criar a imagem)

Build
- Usando Maven instalado:
  mvn -B -DskipTests=false package
- Usando o wrapper (se completo):
  ./mvnw -B -DskipTests=false package
- Forçar `fast-jar` (se necessário):
  mvn -B -DskipTests=false -Dquarkus.package.type=fast-jar package

Verificações pós-build (esperadas pelo PRD-02)
- Diretório Quarkus gerado:
  ls -la target/quarkus-app
- Propriedades do artefato:
  cat target/quarkus-artifact.properties
- Relatórios de teste JUnit:
  ls -la target/surefire-reports
  grep -n "<testsuite" target/surefire-reports/*.xml || true

Executar localmente
- Executável Quarkus (fast-jar):
  java -jar target/quarkus-app/quarkus-run.jar
- Ou executar o JAR empacotado (se presente):
  java -jar target/getting-started-*.jar

Criar imagem Docker (exemplo)
- Se houver `Dockerfile` no root do repositório:
  docker build -t ghcr.io/<org>/<repo>:<sha> .
- Se o Dockerfile estiver em `src/main/docker` (ex.: `Dockerfile.jvm`):
  docker build -f src/main/docker/Dockerfile.jvm -t ghcr.io/<org>/<repo>:<sha> .
- Executar imagem:
  docker run --rm -p 8080:8080 ghcr.io/<org>/<repo>:<sha>

Notas
- O PRD-02 exige que `mvn -B -DskipTests=false package` gere `target/quarkus-app/`.
- Se o Maven Wrapper estiver incompleto no repositório, prefira instalar Maven localmente (SDKMAN ou pacote do SO) ou restaurar os arquivos em `.mvn/wrapper/`.
- Em CI (GitHub Actions) publique `target/surefire-reports` como artefatos para inspeção de relatórios JUnit.
