pipeline {
    agent any

    environment {
        REGISTRY = 'yosrikhiari'
        DOCKER_REGISTRY = 'https://index.docker.io/v1/'
        DOCKER_CREDENTIALS_ID = 'docker-hub-credentials'
        KUBECONFIG = "${WORKSPACE}/kubeconfig"
    }

    stages {
        stage('Setup Kubernetes Config') {
            steps {
                script {
                    // Create a corrected kubeconfig in the workspace
                    sh '''
                        # Copy the original kubeconfig
                        cp /var/jenkins_home/.kube/config ${WORKSPACE}/kubeconfig

                        # Get the correct Minikube IP that Jenkins can reach
                        MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "192.168.49.2")
                        echo "Detected Minikube IP: $MINIKUBE_IP"

                        # Try to use host.docker.internal for Docker Desktop environments
                        if getent hosts host.docker.internal > /dev/null 2>&1; then
                            echo "Using host.docker.internal for Docker Desktop"
                            MINIKUBE_SERVER="https://host.docker.internal:8443"
                        else
                            # For Linux environments, try to get the correct IP
                            # First try the docker0 interface IP
                            DOCKER_HOST_IP=$(ip route | grep docker0 | awk '{print $9}' | head -1)
                            if [ ! -z "$DOCKER_HOST_IP" ]; then
                                echo "Using Docker host IP: $DOCKER_HOST_IP"
                                MINIKUBE_SERVER="https://$DOCKER_HOST_IP:8443"
                            else
                                # Fallback to detected Minikube IP
                                MINIKUBE_SERVER="https://$MINIKUBE_IP:8443"
                            fi
                        fi

                        echo "Using Kubernetes server: $MINIKUBE_SERVER"

                        # Update paths to point to the mounted directories
                        sed -i 's|/home/yosri/.minikube/ca.crt|/var/jenkins_home/.minikube/ca.crt|g' ${WORKSPACE}/kubeconfig
                        sed -i 's|/home/yosri/.minikube/profiles/minikube/client.crt|/var/jenkins_home/.minikube/profiles/minikube/client.crt|g' ${WORKSPACE}/kubeconfig
                        sed -i 's|/home/yosri/.minikube/profiles/minikube/client.key|/var/jenkins_home/.minikube/profiles/minikube/client.key|g' ${WORKSPACE}/kubeconfig

                        # Update the server URL
                        sed -i "s|server: https://.*:8443|server: $MINIKUBE_SERVER|g" ${WORKSPACE}/kubeconfig

                        # Verify the certificate files exist
                        echo "Checking certificate files:"
                        ls -la /var/jenkins_home/.minikube/ca.crt || echo "ca.crt not found"
                        ls -la /var/jenkins_home/.minikube/profiles/minikube/client.crt || echo "client.crt not found"
                        ls -la /var/jenkins_home/.minikube/profiles/minikube/client.key || echo "client.key not found"

                        # Show the corrected kubeconfig
                        echo "Updated kubeconfig:"
                        cat ${WORKSPACE}/kubeconfig

                        # Test network connectivity first
                        echo "Testing network connectivity..."
                        nc -zv $(echo $MINIKUBE_SERVER | sed 's|https://||' | sed 's|:.*||') 8443 || echo "Cannot reach Kubernetes API server"

                        # Test kubectl connection with timeout
                        timeout 30 kubectl --kubeconfig=${WORKSPACE}/kubeconfig cluster-info || {
                            echo "Failed to connect to Kubernetes cluster"
                            echo "Trying alternative approaches..."

                            # Try using kubectl proxy (if available)
                            if command -v kubectl >/dev/null 2>&1; then
                                echo "Attempting to use kubectl proxy..."
                                kubectl proxy --port=8080 &
                                PROXY_PID=$!
                                sleep 5

                                # Create a proxy-based kubeconfig
                                cat > ${WORKSPACE}/kubeconfig-proxy << EOF
apiVersion: v1
clusters:
- cluster:
    server: http://localhost:8080
  name: minikube-proxy
contexts:
- context:
    cluster: minikube-proxy
    user: minikube
  name: minikube-proxy
current-context: minikube-proxy
kind: Config
users:
- name: minikube
  user: {}
EOF
                                # Test proxy connection
                                kubectl --kubeconfig=${WORKSPACE}/kubeconfig-proxy cluster-info || kill $PROXY_PID
                                kill $PROXY_PID 2>/dev/null || true
                            fi
                        }
                    '''
                }
            }
        }

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

        stage('Create Namespace') {
            steps {
                script {
                    sh """
                        kubectl --kubeconfig=${KUBECONFIG} create namespace chexy --dry-run=client -o yaml | \
                        kubectl --kubeconfig=${KUBECONFIG} apply -f -
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
                        sh """
                            kubectl --kubeconfig=${KUBECONFIG} create configmap realm-export \
                                --from-file=Chexy-B/keycloak/realm-export.json \
                                -n chexy --dry-run=client -o yaml | \
                            kubectl --kubeconfig=${KUBECONFIG} apply -f -
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

                    sh "kubectl --kubeconfig=${KUBECONFIG} apply -f kubernetes/deployment.yaml"

                    def components = ['ai-model', 'keycloak', 'backend', 'frontend']
                    for (comp in components) {
                        sh """
                            kubectl --kubeconfig=${KUBECONFIG} set image \
                                deployment/chexy-${comp} \
                                chexy-${comp}=${REGISTRY}/chexy-${comp}:${BUILD_NUMBER} \
                                -n chexy
                        """
                    }

                    for (comp in components) {
                        sh """
                            kubectl --kubeconfig=${KUBECONFIG} rollout status \
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
                // Debug kubectl configuration and network
                sh "echo 'Debugging kubectl config and network:'"
                sh "ls -la /var/jenkins_home/.kube/ || true"
                sh "ls -la /var/jenkins_home/.minikube/ || true"
                sh "minikube status || true"
                sh "minikube ip || true"
                sh "netstat -tuln | grep 8443 || true"
                sh "ip route || true"
            }
        }
        success {
            echo '✅ Pipeline completed successfully!'
        }
    }
}