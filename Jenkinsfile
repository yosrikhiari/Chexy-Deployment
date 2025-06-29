pipeline {
    agent any

    environment {
        REGISTRY = 'yosrikhiari'
        DOCKER_REGISTRY = 'https://index.docker.io/v1/'
        DOCKER_CREDENTIALS_ID = 'docker-hub-credentials'
        GITHUB_CREDENTIALS_ID = 'github-credentials' // Only if repos are private
        KUBE_CONFIG = '/home/yosri/.kube/config'
    }

    stages {
        stage('Clone Repositories') {
            parallel {
                stage('Clone Chexy-B') {
                    steps {
                        dir('Chexy-B') {
                            // Use credentials if repos are private, otherwise remove credentialsId
                            git branch: 'main',
                                credentialsId: "${GITHUB_CREDENTIALS_ID}",
                                url: 'https://github.com/yosrikhiari/Chexy-B.git'
                        }
                    }
                }
                stage('Clone Chexy-F') {
                    steps {
                        dir('Chexy-F') {
                            git branch: 'main',
                                credentialsId: "${GITHUB_CREDENTIALS_ID}",
                                url: 'https://github.com/yosrikhiari/Chexy-F.git'
                        }
                    }
                }
                stage('Clone Chexy-M') {
                    steps {
                        dir('Chexy-M') {
                            git branch: 'main',
                                credentialsId: "${GITHUB_CREDENTIALS_ID}",
                                url: 'https://github.com/yosrikhiari/Chexy-M.git'
                        }
                    }
                }
            }
        }

        stage('Verify Dockerfiles') {
            steps {
                script {
                    def dockerfiles = [
                        'Chexy-M/Models/Dockerfile',
                        'Chexy-B/keycloak/Dockerfile',
                        'Chexy-B/backend/Dockerfile',
                        'Chexy-F/Chexy/Dockerfile'
                    ]

                    for (dockerfile in dockerfiles) {
                        if (!fileExists(dockerfile)) {
                            error("Dockerfile not found: ${dockerfile}")
                        } else {
                            echo "✓ Found: ${dockerfile}"
                        }
                    }
                }
            }
        }

        stage('Build and Push Images') {
            steps {
                script {
                    def components = [
                        [name: 'ai-model', path: 'Chexy-M/Models', image: "${REGISTRY}/chexy-ai-model"],
                        [name: 'keycloak', path: 'Chexy-B/keycloak', image: "${REGISTRY}/chexy-keycloak"],
                        [name: 'backend', path: 'Chexy-B/backend', image: "${REGISTRY}/chexy-backend"],
                        [name: 'frontend', path: 'Chexy-F/Chexy', image: "${REGISTRY}/chexy-frontend"]
                    ]

                    docker.withRegistry("${DOCKER_REGISTRY}", "${DOCKER_CREDENTIALS_ID}") {
                        for (comp in components) {
                            echo "Building ${comp.name} image: ${comp.image}:${BUILD_NUMBER}"

                            // Verify the path exists
                            if (!fileExists("${comp.path}/Dockerfile")) {
                                error("Dockerfile not found at: ${comp.path}/Dockerfile")
                            }

                            def image = docker.build("${comp.image}:${BUILD_NUMBER}", "${comp.path}")

                            echo "Pushing ${comp.image}:${BUILD_NUMBER}"
                            image.push("${BUILD_NUMBER}")
                            image.push('latest')

                            echo "✓ Successfully built and pushed ${comp.image}"
                        }
                    }
                }
            }
        }

        stage('Create ConfigMap') {
            steps {
                script {
                    // Check if the realm-export.json file exists
                    if (!fileExists('Chexy-B/keycloak/realm-export.json')) {
                        echo "Warning: realm-export.json not found, skipping ConfigMap creation"
                    } else {
                        sh """
                            kubectl --kubeconfig=${KUBE_CONFIG} create configmap realm-export \
                                --from-file=Chexy-B/keycloak/realm-export.json \
                                -n chexy --dry-run=client -o yaml | \
                            kubectl --kubeconfig=${KUBE_CONFIG} apply -f -
                        """
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    // Check if deployment file exists
                    if (!fileExists('kubernetes/deployment.yaml')) {
                        error("Kubernetes deployment file not found: kubernetes/deployment.yaml")
                    }

                    // Apply the deployment
                    sh "kubectl --kubeconfig=${KUBE_CONFIG} apply -f kubernetes/deployment.yaml"

                    // Update images with specific tags
                    def components = ['ai-model', 'keycloak', 'backend', 'frontend']
                    for (comp in components) {
                        sh """
                            kubectl --kubeconfig=${KUBE_CONFIG} set image \
                                deployment/chexy-${comp} \
                                chexy-${comp}=${REGISTRY}/chexy-${comp}:${BUILD_NUMBER} \
                                -n chexy
                        """
                    }

                    // Wait for deployments to be ready
                    for (comp in components) {
                        sh """
                            kubectl --kubeconfig=${KUBE_CONFIG} rollout status \
                                deployment/chexy-${comp} -n chexy --timeout=300s
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                // Clean up local images to save space
                def components = ['ai-model', 'keycloak', 'backend', 'frontend']
                for (comp in components) {
                    sh "docker rmi ${REGISTRY}/chexy-${comp}:${BUILD_NUMBER} || true"
                    sh "docker rmi ${REGISTRY}/chexy-${comp}:latest || true"
                }

                // Clean up any dangling images
                sh "docker system prune -f || true"
            }
        }
        failure {
            echo '❌ Pipeline failed! Check the logs for details.'
            script {
                // Print useful debugging info
                sh "pwd && ls -la"
                sh "docker images | grep chexy || true"
            }
        }
        success {
            echo '✅ Pipeline completed successfully!'
        }
    }
}