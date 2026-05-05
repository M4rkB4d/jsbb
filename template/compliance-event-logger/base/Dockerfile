# =============================================================================
# Multi-stage Spring Boot container.
# maven:3.9.10-eclipse-temurin-21-alpine builder + eclipse-temurin:21-jre-alpine
# runtime, Asia/Manila TZ, non-root user 1001, port 8181 (bank convention).
# =============================================================================

# -------- Build stage --------
FROM maven:3.9.10-eclipse-temurin-21-alpine AS builder
WORKDIR /build

# settings.xml is uploaded as a Secure File in Azure DevOps and pulled at CI time.
COPY pom.xml .
COPY settings.xml .
RUN mvn -s settings.xml -B dependency:go-offline

COPY src ./src
RUN mvn -s settings.xml -B -f pom.xml package -DskipTests -Dcheckstyle.skip=true

# -------- Runtime stage --------
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/Asia/Manila /etc/localtime && \
    echo "Asia/Manila" > /etc/timezone && \
    apk del tzdata && \
    addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

VOLUME /tmp
VOLUME /logs

COPY src/main/resources/logback-spring.xml /app/logback-spring.xml
COPY --from=builder /build/target/*.jar /app/app.jar

RUN mkdir -p /logs && \
    chown -R appuser:appgroup /app /tmp /logs

USER appuser

EXPOSE 8181

CMD ["java", "-jar", "app.jar"]
