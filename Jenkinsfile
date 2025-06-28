pipeline {
  agent any
  environment {
    REGISTRY = 'yosrikhiari'
    REGISTRY_CREDENTIAL = 'REDACTED'  // Jenkins credential ID for Docker Hub
    KUBE_CONFIG = '/config'  // Updated path to kubeconfig inside container
  }
  stages {
    stage('Clone Repositories') {
      steps {
        git url: 'https://github.com/yosrikhiari/Chexy-B.git', branch: 'main'
        dir('Chexy-F') {
          git url: 'https://github.com/yosrikhiari/Chexy-F.git', branch: 'main'
        }
        dir('Chexy-M') {
          git url: 'https://github.com/yosrikhiari/Chexy-M.git', branch: 'main'
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
          for (comp in components) {
            def image = docker.build("${comp.image}:${BUILD_NUMBER}", "-f ${comp.path}/Dockerfile ${comp.path}")
            docker.withRegistry('', REGISTRY_CREDENTIAL) {
              image.push("${BUILD_NUMBER}")
              image.push('latest')  // Optional: keep 'latest' for convenience
            }
          }
        }
      }
    }
    stage('Create ConfigMap') {
      steps {
        script {
          sh "kubectl --kubeconfig=${KUBE_CONFIG} create configmap realm-export --from-file=Chexy-B/keycloak/realm-export.json -n chexy --dry-run=client -o yaml | kubectl --kubeconfig=${KUBE_CONFIG} apply -f -"
        }
      }
    }
    stage('Deploy to Kubernetes') {
      steps {
        script {
          // Apply the deployment.yaml first (adjust path if needed)
          sh "kubectl --kubeconfig=${KUBE_CONFIG} apply -f kubernetes/deployment.yaml"
          
          // Update images with specific tags
          def components = ['ai-model', 'keycloak', 'backend', 'frontend']
          for (comp in components) {
            sh "kubectl --kubeconfig=${KUBE_CONFIG} set image deployment/chexy-${comp} chexy-${comp}=${REGISTRY}/chexy-${comp}:${BUILD_NUMBER} -n chexy"
          }
        }
      }
    }
    stage('Clean Up') {
      steps {
        script {
          def components = ['ai-model', 'keycloak', 'backend', 'frontend']
          for (comp in components) {
            sh "docker rmi ${REGISTRY}/chexy-${comp}:${BUILD_NUMBER} || true"
            sh "docker rmi ${REGISTRY}/chexy-${comp}:latest || true"
          }
        }
      }
    }
  }
  post {
    failure {
      echo 'Pipeline failed! Check the logs for details.'
    }
    success {
      echo 'Pipeline completed successfully!'
    }
  }
}
