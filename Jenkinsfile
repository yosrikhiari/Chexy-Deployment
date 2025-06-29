pipeline {
  agent any
  environment {
    DOTENV_PATH = '.env'
  }
  stages {
    stage('Load Environment Variables') {
      steps {
        script {
          // Use relative path since Jenkins runs from the workspace
          def props = readProperties file: "${WORKSPACE}/.env"
          env.REGISTRY = props['REGISTRY']
          env.REGISTRY_CREDENTIAL = props['REGISTRY_CREDENTIAL']
          env.KUBE_CONFIG = props['KUBE_CONFIG']

          // Debug: Print loaded values (remove in production)
          echo "Registry: ${env.REGISTRY}"
          echo "Kube Config: ${env.KUBE_CONFIG}"
        }
      }
    }
    stage('Clone Repositories') {
      steps {
        dir('Chexy-B') {
          git url: 'https://github.com/yosrikhiari/Chexy-B.git', branch: 'main'
        }
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
            [name: 'ai-model', path: 'Chexy-M/Models', image: "${env.REGISTRY}/chexy-ai-model"],
            [name: 'keycloak', path: 'Chexy-B/keycloak', image: "${env.REGISTRY}/chexy-keycloak"],
            [name: 'backend', path: 'Chexy-B/backend', image: "${env.REGISTRY}/chexy-backend"],
            [name: 'frontend', path: 'Chexy-F/Chexy', image: "${env.REGISTRY}/chexy-frontend"]
          ]

          for (comp in components) {
            echo "Building image: ${comp.image}:${BUILD_NUMBER}"
            def image = docker.build("${comp.image}:${BUILD_NUMBER}", "-f ${comp.path}/Dockerfile ${comp.path}")

            docker.withRegistry('https://registry-1.docker.io/v2/', env.REGISTRY_CREDENTIAL) {
              image.push("${BUILD_NUMBER}")
              image.push('latest')
            }
          }
        }
      }
    }
    stage('Create ConfigMap') {
      steps {
        script {
          sh "kubectl --kubeconfig=${env.KUBE_CONFIG} create configmap realm-export --from-file=Chexy-B/keycloak/realm-export.json -n chexy --dry-run=client -o yaml | kubectl --kubeconfig=${env.KUBE_CONFIG} apply -f -"
        }
      }
    }
    stage('Deploy to Kubernetes') {
      steps {
        script {
          // Apply the deployment.yaml from Chexy-Deployment
          sh "kubectl --kubeconfig=${env.KUBE_CONFIG} apply -f kubernetes/deployment.yaml"

          // Update images with specific tags
          def components = ['ai-model', 'keycloak', 'backend', 'frontend']
          for (comp in components) {
            sh "kubectl --kubeconfig=${env.KUBE_CONFIG} set image deployment/chexy-${comp} chexy-${comp}=${env.REGISTRY}/chexy-${comp}:${BUILD_NUMBER} -n chexy"
          }
        }
      }
    }
    stage('Clean Up') {
      steps {
        script {
          def components = ['ai-model', 'keycloak', 'backend', 'frontend']
          for (comp in components) {
            sh "docker rmi ${env.REGISTRY}/chexy-${comp}:${BUILD_NUMBER} || true"
            sh "docker rmi ${env.REGISTRY}/chexy-${comp}:latest || true"
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