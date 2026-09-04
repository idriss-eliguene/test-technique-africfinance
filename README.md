# AfricFinance — Pipeline CI/CD Zero-to-Deploy

AfricFinance est une application Spring Boot minimale servant de support à une
chaîne CI/CD de livraison d'artefacts Java et conteneurisés. Le dépôt fournit
le pipeline principal GitHub Actions ainsi qu'un `Jenkinsfile` transposable
dans un environnement Jenkins.

## Table des matières

- [Architecture](#architecture)
- [Application](#application)
- [Pipeline CI/CD](#pipeline-cicd)
- [Chaîne DevSecOps](#chaîne-devsecops)
- [Image Docker](#image-docker)
- [GitHub Actions](#github-actions)
- [Jenkins](#jenkins)
- [Frontières de confiance](#frontières-de-confiance)
- [Secrets et credentials](#secrets-et-credentials)
- [Déploiement distant](#déploiement-distant)
- [État de validation](#état-de-validation)
- [Exploitation](#exploitation)
- [Dépannage](#dépannage)
- [Limites et évolutions](#limites-et-évolutions)

## Architecture

```mermaid
flowchart LR
    DEV[Developer] -->|Push master| GH[GitHub]
    GH --> CI[GitHub Actions]
    CI --> TEST[Build / Tests]
    TEST --> SAST[SAST - Semgrep]
    SAST --> SCA[SCA - Trivy FS]
    SCA --> BUILD[Docker Build]
    BUILD --> TRIVY[Trivy]
    TRIVY -->|PASS| GATE[Promotion Gate]
    TRIVY -->|FAIL| STOP[Pipeline stopped]
    GATE --> REG[GHCR]
    REG -->|SSH contrôlé| VPS[VPS Linux]
    VPS --> DOCKER[Docker]
    DOCKER --> APP[Spring Boot :8080]
    APP --> HC[Healthcheck HTTP]
    HC --> DAST[OWASP ZAP advisory]
```

## Application

L'application utilise Java 21, Spring Boot et Maven. Elle expose le port
`8080` et fournit un endpoint HTTP `GET /` avec une réponse JSON déterministe :

```json
{
  "message": "Hello AfricFinance",
  "status": "running"
}
```

### Tests et packaging

```bash
mvn clean test
mvn clean package
```

Le JAR produit est `target/africfinance-app-0.0.1-SNAPSHOT.jar`.

### Exécution locale

```bash
java -jar target/africfinance-app-0.0.1-SNAPSHOT.jar
curl http://localhost:8080/
```

## Pipeline CI/CD

Le pipeline est une chaîne de promotion :

```text
Commit
  ↓
Build
  ↓
Tests
  ↓
SAST
  ↓
SCA
  ↓
Container Build
  ↓
Container Security Gate
  ↓
Registry
  ↓
Deployment
  ↓
Runtime Verification
```

Un artefact ne progresse vers l'étape suivante que lorsque les gates
bloquantes précédentes réussissent. La publication GHCR intervient uniquement
après le build, le scan Trivy et la réussite de la gate de promotion.

## Chaîne DevSecOps

Les contrôles sont appliqués sur des surfaces complémentaires :

| Surface | Contrôle | Outil | Fonction |
|---------|----------|-------|----------|
| Fonctionnel | Tests | Maven / JUnit | Validation du comportement |
| Code | SAST | Semgrep | Analyse statique |
| Dépendances applicatives | SCA | Trivy filesystem | Vulnérabilités des composants |
| Container | Image scanning | Trivy image | Vulnérabilités de l'artefact |
| Runtime | Least privilege | Docker non-root | Réduction des privilèges |
| HTTP runtime | DAST | OWASP ZAP Baseline | Analyse dynamique advisory |

Le DAST HTTP avec OWASP ZAP est exécuté après le healthcheck via un tunnel SSH
et reste advisory.

### Security gates

```text
PASS
  │
  ▼
Promotion

FAIL
  │
  ▼
Pipeline stopped
```

Trivy analyse le repository et l'image avec les sévérités `HIGH,CRITICAL` et
`ignore-unfixed`. Les findings sont actuellement advisory ; une erreur
technique d'exécution du scanner reste bloquante. Les tests, le packaging, le
build Docker, GHCR, SSH, le pull, le run et le healthcheck restent bloquants.

Une image construite n'est pas automatiquement déployable. Elle devient
candidate à la promotion uniquement après les contrôles applicables :

```text
Build → Scan → Promote → Deploy
```

## Image Docker

Le `Dockerfile` utilise un build multi-stage :

- le stage de build utilise Maven avec Java 21 ;
- Maven et les outils de compilation ne sont pas présents dans le runtime ;
- le runtime utilise un JRE Java 21 ;
- l'application s'exécute avec l'utilisateur non privilégié `app` ;
- seul le JAR applicatif est copié dans l'image finale ;
- le port `8080` est exposé.

Commandes usuelles :

```bash
docker build -t africfinance-app:local .
docker run --rm --name africfinance-app -p 8080:8080 africfinance-app:local
```

## GitHub Actions

Le workflow `.github/workflows/ci-cd.yml` constitue le moteur d'exécution
principal. Il est déclenché par un push vers `master` ou par
`workflow_dispatch`.

Il orchestre les étapes suivantes avec Java 21 et le cache Maven :

1. checkout du dépôt ;
2. tests Maven ;
3. packaging du JAR ;
4. SAST Semgrep ;
5. SCA Trivy filesystem ;
6. construction de l'image Docker ;
7. scan Trivy de l'image en advisory ;
8. authentification et publication dans GHCR ;
9. déploiement SSH de l'image `sha-<git-sha>` ;
10. healthcheck HTTP ;
11. scan OWASP ZAP Baseline advisory via tunnel SSH ;
12. résumé GitHub du déploiement.

Le workflow utilise les permissions minimales `contents: read` et
`packages: write`. L'authentification GHCR repose sur `GITHUB_TOKEN` et ne
nécessite pas de PAT supplémentaire.

## Registry et promotion des images

GHCR est le registre des images publiées par GitHub Actions. L'image est
construite et analysée une seule fois, puis retaguée et poussée après la gate
Trivy ; aucun rebuild n'intervient entre le scan et la publication.

### Artifact publié

L'image Docker produite par le pipeline CI/CD est publiée dans GitHub
Container Registry (GHCR).

- Registry : `ghcr.io`
- Image : `ghcr.io/idriss-eliguene/africfinance-app`
- Package : <https://github.com/idriss-eliguene/test-technique-africfinance/pkgs/container/africfinance-app>
- Les builds sont identifiés par un tag immuable dérivé du commit Git :
  `sha-${GITHUB_SHA}`.

Exemple :

```bash
docker pull ghcr.io/idriss-eliguene/africfinance-app:<tag>
```

Les références publiées sont :

```text
ghcr.io/<owner>/africfinance-app:sha-<git-sha>
ghcr.io/<owner>/africfinance-app:latest
```

Le tag `sha-<git-sha>` est immuable dans la convention de livraison et assure
la traçabilité du commit vers l'image. Le tag `latest` est associé aux
exécutions sur `master`. L'image publiée est le même artefact que celui
analysé par Trivy.

La séquence de promotion est :

```text
Build → Scan → Promote → Deploy
```

Une violation d'une gate ou un échec d'authentification GHCR arrête le
pipeline avant publication.

## Jenkins

Le fichier `Jenkinsfile` fournit l'équivalent Jenkins de la chaîne :

```text
Checkout → Tests → Packaging → SAST → Trivy FS/SCA → Docker Build → Trivy Image
```

Les étapes Maven peuvent utiliser un agent conteneurisé Java 21/Maven. Les
étapes Docker et Trivy sont affectées à un agent Jenkins dédié portant le
label `container-build`.

Cet agent doit disposer de Docker, Trivy, d'un espace disque suffisant, d'un
accès réseau contrôlé et d'un workspace isolé. Le contrôleur Jenkins conserve
un rôle d'orchestration et n'est pas utilisé comme worker de build. Le socket
Docker du contrôleur n'est pas exposé aux conteneurs de jobs.

## Frontières de confiance

```text
SCM / CI
     │
     ▼
Build environment
     │
     ▼
Security gates
     │
     ▼
Registry
     │
     ▼
Deployment boundary
     │
     ▼
Runtime
```

Le repository fournit le code et la configuration. Le runner GitHub Actions,
ou l'agent Jenkins dédié, exécute les builds dans un environnement séparé.
Les gates contrôlent l'artefact avant toute promotion. Le registre, la
connexion SSH et le VPS constituent des frontières distinctes. Le runtime
Docker applique un utilisateur non-root.

## Secrets et credentials

| Secret | Utilisation | Portée |
|--------|-------------|--------|
| `GITHUB_TOKEN` | Authentification et publication dans GHCR | Token natif du workflow, permission `packages: write` |
| `ghcr-credentials` | Authentification GHCR du Jenkinsfile | Credential Jenkins username/password sur l'agent de publication |
| `VPS_HOST` | Adresse DNS du VPS | GitHub Actions Secrets |
| `VPS_USER` | Utilisateur SSH de déploiement | GitHub Actions Secrets |
| `VPS_SSH_KEY` | Clé privée SSH | GitHub Actions Secrets |
| `VPS_KNOWN_HOSTS` | Clés hôtes SSH approuvées | GitHub Actions Secrets |
| `VPS_PORT` | Port SSH optionnel | GitHub Actions Secrets, `22` par défaut |
| `GHCR_DEPLOY_USERNAME` | Utilisateur de lecture GHCR si package privé | GitHub Actions Secrets, optionnel si package public |
| `GHCR_DEPLOY_TOKEN` | Token `read:packages` si package privé | GitHub Actions Secrets, optionnel si package public |

Les credentials Jenkins `ghcr-credentials` doivent être créés dans Jenkins
sans valeur en clair dans le dépôt et avec une portée minimale.

Le déploiement utilise `scripts/deploy.sh`, tire l'image immuable
`sha-<git-sha>`, remplace `africfinance-app`, transmet `APP_ENV=production` et
vérifie `GET /` avec plusieurs tentatives. Pour un package GHCR privé, le token
de lecture est transmis à `docker login` via `--password-stdin`.

Le VPS doit disposer de Linux, Docker Engine, de la clé publique SSH dans
`authorized_keys`, d'un utilisateur autorisé à accéder au daemon Docker et d'un
pare-feu autorisant le port SSH. L'appartenance au groupe `docker` équivaut à
un niveau de privilège root sur l'hôte ; rootless Docker ou un mécanisme sudo
très restreint sont préférables en production durcie.

## Déploiement distant

Le pipeline contient le mécanisme de Continuous Deployment vers un serveur
Linux distant équipé de Docker et accessible par SSH. Aucune infrastructure VPS
ni aucun credential SSH n'ayant été fourni dans le cadre du test technique, le
déploiement distant n'a pas été exécuté sur une cible réelle.

Par défaut, lorsque `ENABLE_VPS_DEPLOYMENT` est absente ou différente de
`true`, les étapes suivantes sont ignorées proprement :

- SSH Deploy : skipped ;
- healthcheck distant : skipped ;
- DAST : skipped.

Les étapes CI et la publication GHCR restent exécutables. Le déploiement est
activé uniquement sur `master` lorsque `ENABLE_VPS_DEPLOYMENT` vaut `true`.

### Activer le déploiement

Configurer une variable de repository dans :

```text
GitHub → repository → Settings → Secrets and variables → Actions
       → Variables → New repository variable
```

```text
Name:  ENABLE_VPS_DEPLOYMENT
Value: true
```

Cette variable n'est pas un secret. Elle ne doit être définie à `true` qu'après
la configuration complète du VPS et des secrets SSH ci-dessous.

### Secrets SSH

Créer chaque secret dans :

```text
GitHub → repository → Settings → Secrets and variables → Actions
       → Secrets → New repository secret
```

| Nom | Description | Valeur / obtention |
| --- | --- | --- |
| `VPS_HOST` | Adresse IP publique ou nom DNS du serveur Linux cible | Adresse du VPS ; `203.0.113.10` est uniquement un exemple documentaire |
| `VPS_USER` | Utilisateur Linux de connexion SSH | Par exemple `deploy` |
| `VPS_PORT` | Port SSH du serveur | Généralement `22` |
| `VPS_SSH_KEY` | Clé privée ED25519 dédiée au déploiement | Contenu complet de `~/.ssh/africfinance-github-actions` |
| `VPS_KNOWN_HOSTS` | Clé d'hôte SSH vérifiée | Contenu complet du fichier known_hosts préparé après vérification |

Générer une clé dédiée si nécessaire :

```bash
ssh-keygen -t ed25519 \
  -f ~/.ssh/africfinance-github-actions \
  -C "github-actions-africfinance"
```

Installer uniquement la clé publique dans
`~/.ssh/authorized_keys` du compte `VPS_USER` :

```text
~/.ssh/africfinance-github-actions.pub
```

La valeur de `VPS_SSH_KEY` correspond au contenu complet de la clé privée,
incluant les marqueurs `-----BEGIN OPENSSH PRIVATE KEY-----` et
`-----END OPENSSH PRIVATE KEY-----`. Cette clé ne doit jamais être versionnée.

Pour préparer `VPS_KNOWN_HOSTS`, récupérer la clé d'hôte :

```bash
ssh-keyscan -t ed25519 -p 22 VPS_HOST
```

`ssh-keyscan` ne vérifie pas à lui seul l'identité du serveur. Comparer
l'empreinte avec la console du fournisseur ou directement sur le VPS :

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Après comparaison, enregistrer la valeur approuvée :

```bash
ssh-keyscan -t ed25519 -p 22 VPS_HOST > ~/.ssh/africfinance-known_hosts
```

Le contenu complet de `~/.ssh/africfinance-known_hosts` devient la valeur du
secret `VPS_KNOWN_HOSTS`.

### GHCR privé

Si le package GHCR est public, aucun credential de registry supplémentaire
n'est nécessaire sur le VPS. S'il est privé, créer également :

| Nom | Description |
| --- | --- |
| `GHCR_DEPLOY_USERNAME` | Compte autorisé à lire le package |
| `GHCR_DEPLOY_TOKEN` | Token limité à `read:packages` |

Le token est transmis à Docker avec `--password-stdin` et ne doit jamais être
documenté en clair.

### Tableau récapitulatif

| Nom | Type | Obligatoire | Description |
| --- | --- | --- | --- |
| `ENABLE_VPS_DEPLOYMENT` | Variable | Oui pour activer le CD | Active le déploiement distant |
| `VPS_HOST` | Secret | Oui | IP ou DNS du VPS |
| `VPS_USER` | Secret | Oui | Utilisateur SSH |
| `VPS_PORT` | Secret | Selon le workflow | Port SSH, généralement `22` |
| `VPS_SSH_KEY` | Secret | Oui | Clé privée ED25519 de déploiement |
| `VPS_KNOWN_HOSTS` | Secret | Oui | Clé d'hôte SSH vérifiée |
| `GHCR_DEPLOY_USERNAME` | Secret | Si GHCR privé | Compte autorisé à pull |
| `GHCR_DEPLOY_TOKEN` | Secret | Si GHCR privé | Token limité à `read:packages` |

### Prérequis VPS

Le serveur cible doit disposer de :

- Linux ;
- Docker Engine ;
- `curl` ;
- OpenSSH Server ;
- la clé publique installée dans `authorized_keys` ;
- un utilisateur `VPS_USER` autorisé à accéder au daemon Docker ;
- une connectivité sortante vers `ghcr.io` ;
- un port SSH accessible depuis le runner GitHub Actions ;
- le port applicatif `8080` disponible.

L'accès au groupe `docker` confère des privilèges très élevés, comparables à
root sur l'hôte. Rootless Docker ou un mécanisme `sudo` très restreint sont
préférables dans un environnement durci.

### Flux de déploiement

```mermaid
flowchart TD
    PUSH[Push master] --> CI[CI]
    CI --> BUILD[Build image]
    BUILD --> SCAN[Security scans]
    SCAN --> GHCR[GHCR Push]
    GHCR --> ENABLE{ENABLE_VPS_DEPLOYMENT == true ?}
    ENABLE -->|Non| SKIP[Deploy / Healthcheck / DAST skipped]
    ENABLE -->|Oui| SECRETS[Validation des secrets]
    SECRETS --> SSH[SSH]
    SSH --> PULL[docker pull sha-${GITHUB_SHA}]
    PULL --> REMOVE[Remove old container if present]
    REMOVE --> RUN[docker run]
    RUN --> HC[HTTP healthcheck]
    HC --> ZAP[DAST advisory]
```

Lorsque la variable vaut `true`, le workflow valide les secrets obligatoires
avant toute tentative SSH, transmet `APP_ENV=production`, récupère l'image
`sha-${GITHUB_SHA}`, remplace le conteneur existant puis vérifie `GET /` avec
plusieurs tentatives. Un secret obligatoire absent provoque un échec explicite
avant la tentative SSH.

Le script distant prêt à l'emploi est `scripts/deploy.sh`.

### Déclencher le pipeline

Un push sur `master` déclenche le workflow :

```bash
git push origin master
```

L'exécution peut être suivie depuis :

```text
GitHub → repository → Actions → workflow CI/CD
```

## État de validation

Le pipeline CI/CD et le mécanisme de déploiement SSH sont implémentés. La CI,
la construction Docker et la publication GHCR sont exécutées selon les runs
GitHub Actions disponibles. Aucune infrastructure VPS ni aucun credential SSH
n'ayant été fourni dans le cadre du test technique, le déploiement distant, le
healthcheck distant et le DAST distant n'ont pas été exécutés sur une cible
réelle. Jenkins est fourni comme alternative et n'a pas été exécuté.

## Exploitation

### Vérifier le conteneur

```bash
docker ps
docker inspect africfinance-app
```

### Consulter les logs

```bash
docker logs africfinance-app
```

### Tester l'application

```bash
curl -f http://localhost:8080/
```

### Arrêter et supprimer le conteneur

```bash
docker stop africfinance-app
docker rm africfinance-app
```

## Dépannage

### Pipeline Maven en échec

Consulter les logs de compilation et de tests, puis reproduire avec
`mvn clean test` dans un environnement Java 21.

### Security gate en échec

Identifier l'étape concernée dans les logs. Pour Trivy, examiner la sévérité,
le composant affecté et la disponibilité d'un correctif avant de reconstruire
l'image.

### Image introuvable

Vérifier le tag utilisé par `docker build`, puis lister les images locales avec
`docker images africfinance-app`.

### Conteneur non démarré

Consulter `docker logs africfinance-app` et vérifier qu'aucun autre processus
n'utilise le port `8080`.

## Limites et évolutions

Pour une plateforme de production plus complète, les évolutions usuelles
incluent :

- TLS et reverse proxy ;
- rollback automatisé ;
- stratégies blue/green ou canary ;
- observabilité et alerting ;
- Infrastructure as Code ;
- gestionnaire de secrets ;
- SBOM, provenance et signature d'images ;
- policy-as-code.

Le déploiement actuel reste single-container, sans rollback automatique,
blue/green, reverse proxy ou TLS. Les scanners SAST, SCA et image sont
temporairement advisory ; leurs findings doivent être traités avant une mise
en production durcie.
