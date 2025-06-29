pipeline {
    agent any

    environment {
        REGISTRY = 'yosrikhiari'
        DOCKER_REGISTRY = 'https://index.docker.io/v1/'
        DOCKER_CREDENTIALS_ID = 'docker-hub-credentials'
        KUBE_CONFIG = '/var/jenkins_home/.kube/config'
        // For kubectl apply commands only
        KUBECTL_APPLY_FLAGS = '--validate=false'
    }

    stages {
        stage('Clone Repositories') {
            parallel {
                stage('Clone Chexy-B') {
                    steps {
                        dir('Chexy-B') {
                            git branch: 'main',
                                url: 'https://github.com/yosrikhiari/Chexy-B.git'
                        }
                    }
                }
                stage('Clone Chexy-F') {
                    steps {
                        dir('Chexy-F') {
                            git branch: 'main',
                                url: 'https://github.com/yosrikhiari/Chexy-F.git'
                        }
                    }
                }
                stage('Clone Chexy-M') {
                    steps {
                        dir('Chexy-M') {
                            git branch: 'main',
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

        stage('Test Kubernetes Connection') {
            steps {
                script {
                    // Test connection with timeout (no validate flag for get/cluster-info commands)
                    sh """
                        echo "Testing Kubernetes connection..."
                        timeout 30 kubectl --kubeconfig=${KUBE_CONFIG} cluster-info || echo "Cluster info failed - network issue"
                        timeout 30 kubectl --kubeconfig=${KUBE_CONFIG} get nodes || echo "Get nodes failed - network issue"
                        timeout 30 kubectl --kubeconfig=${KUBE_CONFIG} get namespaces || echo "Get namespaces failed - network issue"

                        # Check if namespace exists, create if not
                        kubectl --kubeconfig=${KUBE_CONFIG} get namespace chexy || \
                        kubectl --kubeconfig=${KUBE_CONFIG} create namespace chexy
                    """
                }
            }
        }

        stage('Create ConfigMap') {
            steps {
                script {
                    if (!fileExists('Chexy-B/keycloak/realm-export.json')) {
                        echo "Warning: realm-export.json not found, skipping ConfigMap creation"
                    } else {
                        // Only use validate=false with kubectl apply
                        sh """
                            echo "Creating ConfigMap with validation disabled..."
                            kubectl --kubeconfig=${KUBE_CONFIG} \
                                create configmap realm-export \
                                --from-file=Chexy-B/keycloak/realm-export.json \
                                -n chexy --dry-run=client -o yaml > /tmp/configmap.yaml || exit 1

                            echo "Applying ConfigMap..."
                            kubectl --kubeconfig=${KUBE_CONFIG} ${KUBECTL_APPLY_FLAGS} \
                                apply -f /tmp/configmap.yaml || exit 1

                            echo "✓ ConfigMap created successfully"
                        """
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    if (!fileExists('kubernetes/deployment.yaml')) {
                        error("Kubernetes deployment file not found: kubernetes/deployment.yaml")
                    }

                    // Apply deployment with validation disabled and extended timeout
                    sh """
                        echo "Applying Kubernetes deployment..."
                        kubectl --kubeconfig=${KUBE_CONFIG} ${KUBECTL_APPLY_FLAGS} \
                            apply -f kubernetes/deployment.yaml --timeout=300s
                    """

                    def components = ['ai-model', 'keycloak', 'backend', 'frontend']

                    // Update images with error handling
                    for (comp in components) {
                        sh """
                            echo "Updating image for ${comp}..."
                            kubectl --kubeconfig=${KUBE_CONFIG} \
                                set image deployment/chexy-${comp} \
                                chexy-${comp}=${REGISTRY}/chexy-${comp}:${BUILD_NUMBER} \
                                -n chexy --timeout=60s || echo "Warning: Failed to update ${comp}"
                        """
                    }

                    // Check rollout status
                    for (comp in components) {
                        sh """
                            echo "Checking rollout status for ${comp}..."
                            kubectl --kubeconfig=${KUBE_CONFIG} \
                                rollout status deployment/chexy-${comp} \
                                -n chexy --timeout=300s || echo "Warning: Rollout status check failed for ${comp}"
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                def components = ['ai-model', 'keycloak', 'backend', 'frontend']
                for (comp in components) {
                    sh "docker rmi ${REGISTRY}/chexy-${comp}:${BUILD_NUMBER} || true"
                    sh "docker rmi ${REGISTRY}/chexy-${comp}:latest || true"
                }
                sh "docker system prune -f || true"
            }
        }
        failure {
            echo '❌ Pipeline failed! Check the logs for details.'
            script {
                sh "pwd && ls -la"
                sh "docker images | grep chexy || true"

                // Enhanced debugging - removed incorrect validate flags
                sh """
                    echo "=== Kubernetes Debug Info ==="
                    kubectl --kubeconfig=${KUBE_CONFIG} version --client || true
                    kubectl --kubeconfig=${KUBE_CONFIG} config view || true

                    echo "=== Testing basic connectivity ==="
                    kubectl --kubeconfig=${KUBE_CONFIG} get nodes || true
                    kubectl --kubeconfig=${KUBE_CONFIG} get pods -n chexy || true

                    echo "=== Docker Network Info ==="
                    docker network ls || true
                    ip route || true

                    echo "=== Network connectivity test ==="
                    echo "Jenkins container IP: \$(hostname -I)"
                    echo "Minikube cluster IP: 192.168.49.2"
                    echo "Testing connectivity..."
                    nc -zv 192.168.49.2 8443 -w 5 || echo "Cannot reach Minikube API server"
                """
            }
        }
        success {
            echo '✅ Pipeline completed successfully!'
        }
    }
}