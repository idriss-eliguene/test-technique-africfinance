# Étape de compilation : les dépendances Maven restent dans cette étape.
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /workspace

# Ce calque est réutilisable tant que le pom.xml ne change pas.
COPY pom.xml .
RUN mvn -B dependency:resolve

# Le code source est copié après les dépendances pour préserver le cache Docker.
COPY src ./src
RUN mvn -B clean package

# Étape d'exécution : image JRE séparée, sans Maven ni outils de build.
FROM eclipse-temurin:21-jre-noble

WORKDIR /app

# L'application ne s'exécute pas avec les privilèges root.
RUN groupadd --system app && useradd --system --gid app --home-dir /app app

COPY --from=build /workspace/target/africfinance-app-0.0.1-SNAPSHOT.jar app.jar
RUN chown app:app app.jar

USER app
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
