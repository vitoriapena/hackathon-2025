# Multi-stage Dockerfile for Quarkus (fast-jar)

# Builder stage
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /workspace

# Copy only what is needed for a reproducible build (usar mvn da imagem builder)
COPY pom.xml ./
COPY src src

# Build the application (fast-jar). Tests are skipped here because CI runs them prior to image build.
RUN mvn -B -DskipTests package -Dquarkus.package.type=fast-jar

# Runtime stage
FROM docker.io/eclipse-temurin:21-jre

# Create non-root user
ARG APP_UID=10001
ARG APP_GROUP=app
RUN groupadd -g ${APP_UID} ${APP_GROUP} || true \
    && useradd -r -u ${APP_UID} -g ${APP_GROUP} -d /home/${APP_GROUP} -s /sbin/nologin ${APP_GROUP} || true \
    && mkdir -p /home/${APP_GROUP}

WORKDIR /home/app

# Install curl for HEALTHCHECK
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Copy built app from builder
COPY --from=builder /workspace/target/quarkus-app /home/app/quarkus-app

# Ensure correct ownership for non-root execution
RUN chown -R ${APP_UID}:${APP_UID} /home/app/quarkus-app

USER ${APP_UID}

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/q/health || exit 1

ENTRYPOINT ["java","-jar","/home/app/quarkus-app/quarkus-run.jar"]
