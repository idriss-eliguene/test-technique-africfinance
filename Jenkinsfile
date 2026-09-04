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
