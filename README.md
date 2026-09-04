# Test technique Lead DevOps — AfricFinance

Ce dépôt contient un test technique « Zero-to-Deploy ». L'application Spring Boot
sert de support à la future chaîne CI/CD, dont l'objectif final est d'automatiser
le build, les tests, l'analyse, la conteneurisation et le déploiement.

## État actuel

La première étape contient :

- Java 21 ;
- Spring Boot ;
- Maven ;
- un endpoint HTTP `GET /` ;
- un test MVC.

## Architecture applicative

```text
Client HTTP
    |
    v
Spring Boot
    |
    v
GET /
    |
    v
Réponse JSON
```

Réponse attendue :

```json
{
  "message": "Hello AfricFinance",
  "status": "running"
}
```

## Prérequis de développement

L'application nécessite Java 21 et Maven. Les tests peuvent également être
exécutés dans un conteneur Maven/Java 21 lorsque Docker est disponible.

## Tests

Commande locale :

```bash
mvn clean test
```

Commande Docker utilisée pendant la validation :

```bash
docker run --rm \
  -v "$PWD:/workspace" \
  -w /workspace \
  maven:3.9-eclipse-temurin-21 \
  mvn clean test
```

Résultat constaté : 1 test exécuté, 1 test réussi, 0 échec, avec `BUILD SUCCESS`.

## Packaging

```bash
mvn clean package
```

JAR produit :

```text
target/africfinance-app-0.0.1-SNAPSHOT.jar
```

## Exécution locale

```bash
java -jar target/africfinance-app-0.0.1-SNAPSHOT.jar
```

Puis :

```bash
curl http://localhost:8080/
```

## Architecture cible

Cette architecture correspond à la cible du test et non à l'état déjà implémenté.

```mermaid
flowchart LR
    DEV[Développeur] -->|Push master| GH[GitHub]
    GH --> CI[GitHub Actions]
    CI --> BUILD[Build et tests]
    BUILD --> SEC[Contrôles de sécurité]
    SEC --> IMG[Image Docker]
    IMG --> REG[Registry]
    CI -->|SSH| VPS[VPS Linux]
    REG --> VPS
    VPS --> APP[Application Spring Boot]
```

Cette architecture représente la cible du test. Les composants seront ajoutés progressivement au cours de l'implémentation.

## Roadmap du test

- [x] Application Spring Boot
- [x] Test applicatif
- [ ] Conteneurisation Docker
- [ ] Pipeline GitHub Actions
- [ ] SAST / SCA
- [ ] Scan de l'image
- [ ] Publication GHCR
- [ ] Déploiement SSH
- [ ] Healthcheck post-déploiement
- [ ] DAST
- [ ] Documentation d'exploitation du VPS
