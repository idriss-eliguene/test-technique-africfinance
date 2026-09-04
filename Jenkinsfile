pipeline {
    parameters {
        string(name: 'GHCR_IMAGE', defaultValue: '', description: 'Référence GHCR complète, en minuscules (ex. ghcr.io/organisation/africfinance-app)')
        string(name: 'VPS_HOST', defaultValue: '', description: 'Nom DNS du VPS')
        string(name: 'VPS_PORT', defaultValue: '22', description: 'Port SSH du VPS')
    }

    environment {
        GHCR_IMAGE = "${params.GHCR_IMAGE}"
    }

    // Agent Docker requis côté Jenkins pour garantir Java 21 et Maven.
    agent {
        docker {
            image 'maven:3.9-eclipse-temurin-21'
        }
    }

    options {
        skipDefaultCheckout(true)
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Récupération du code source'
                checkout scm
            }
        }

        stage('Tests') {
            steps {
                echo 'Exécution des tests Maven'
                sh 'mvn clean test'
            }
        }

        stage('Packaging') {
            steps {
                echo 'Construction du package Maven'
                sh 'mvn package -DskipTests'
            }
        }

        stage('SAST') {
            agent {
                docker {
                    image 'semgrep/semgrep:1.139.0'
                }
            }
            steps {
                echo 'Analyse SAST du code source avec Semgrep'
                sh 'semgrep scan --config p/java .'
            }
        }

        stage('SCA') {
            agent {
                docker {
                    image 'ghcr.io/aquasecurity/trivy:0.70.0'
                }
            }
            steps {
                echo 'Analyse SCA du repository avec Trivy'
                sh '''
                    trivy fs \
                      --scanners vuln \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      --exit-code 0 \
                      .
                '''
            }
        }

        stage('Docker Build') {
            agent {
                label 'container-build'
            }
            steps {
                echo 'Construction de l’image Docker candidate'
                sh 'docker build -t africfinance-app:ci-${BUILD_NUMBER} .'
            }
        }

        stage('Trivy') {
            agent {
                label 'container-build'
            }
            steps {
                echo 'Contrôle Trivy de l’image avant promotion'
                sh '''
                    trivy image \
                      --scanners vuln \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      --exit-code 0 \
                      africfinance-app:ci-${BUILD_NUMBER}
                '''
            }
        }

        stage('Registry Login and Push') {
            agent {
                label 'container-build'
            }
            steps {
                echo 'Publication de l’image validée dans GHCR'
                withCredentials([usernamePassword(credentialsId: 'ghcr-credentials', usernameVariable: 'GHCR_USERNAME', passwordVariable: 'GHCR_PASSWORD')]) {
                    sh '''
                        test -n "$GHCR_IMAGE"
                        echo "$GHCR_PASSWORD" | docker login ghcr.io --username "$GHCR_USERNAME" --password-stdin
                        docker tag africfinance-app:ci-${BUILD_NUMBER} "$GHCR_IMAGE:sha-${GIT_COMMIT}"
                        docker push "$GHCR_IMAGE:sha-${GIT_COMMIT}"
                    '''
                }
            }
        }

        stage('Deploy + Healthcheck') {
            agent {
                label 'deploy'
            }
            steps {
                echo 'Déploiement SSH de l’image immuable et healthcheck HTTP'
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'vps-ssh-key', keyFileVariable: 'VPS_SSH_KEY', usernameVariable: 'VPS_USER'),
                    string(credentialsId: 'vps-known-hosts', variable: 'VPS_KNOWN_HOSTS'),
                    usernamePassword(credentialsId: 'ghcr-credentials', usernameVariable: 'GHCR_USERNAME', passwordVariable: 'GHCR_TOKEN')
                ]) {
                    sh '''
                        set -euo pipefail
                        test -n "$GHCR_IMAGE"
                        test -n "$VPS_HOST"
                        mkdir -p "$HOME/.ssh"
                        chmod 700 "$HOME/.ssh"
                        cp "$VPS_SSH_KEY" "$HOME/.ssh/deploy_key"
                        chmod 600 "$HOME/.ssh/deploy_key"
                        printf '%s\\n' "$VPS_KNOWN_HOSTS" > "$HOME/.ssh/known_hosts"
                        chmod 600 "$HOME/.ssh/known_hosts"
                        scp -P "$VPS_PORT" -i "$HOME/.ssh/deploy_key" \\
                          -o StrictHostKeyChecking=yes \\
                          -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \\
                          -o IdentitiesOnly=yes scripts/deploy.sh "$VPS_USER@$VPS_HOST:/tmp/africfinance-deploy.sh"
                        printf '%s\\n%s\\n' "$GHCR_USERNAME" "$GHCR_TOKEN" | \\
                          ssh -p "$VPS_PORT" -i "$HOME/.ssh/deploy_key" \\
                            -o StrictHostKeyChecking=yes \\
                            -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \\
                            -o IdentitiesOnly=yes "$VPS_USER@$VPS_HOST" \\
                            "bash /tmp/africfinance-deploy.sh '$GHCR_IMAGE:sha-${GIT_COMMIT}' africfinance-app 8080 production"
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline Jenkins terminé avec succès'
        }
        failure {
            echo 'Pipeline Jenkins en échec'
        }
        always {
            echo 'Fin du pipeline Jenkins'
        }
    }
}
