pipeline {
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
                sh 'semgrep scan --config p/java --error .'
            }
        }

        stage('SCA') {
            steps {
                echo 'Analyse SCA des dépendances Maven'
                sh '''
                    mvn org.owasp:dependency-check-maven:12.1.0:check \
                      -DfailBuildOnCVSS=7.0 \
                      -Dformats=HTML,JSON
                '''
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
