#!/bin/bash

# Step 1: Create adjusted kubeconfig inside Jenkins container (as root)
echo "Creating adjusted kubeconfig file..."
sudo docker exec -u 0 -it jenkins bash -c "
# Create the adjusted config file
cat > /var/jenkins_home/.kube/config-adjusted << 'EOF'
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /var/jenkins_home/.minikube/ca.crt
    extensions:
    - extension:
        last-update: Mon, 30 Jun 2025 05:19:34 CET
        provider: minikube.sigs.k8s.io
        version: v1.36.0
      name: cluster_info
    server: https://192.168.49.2:8443
  name: minikube
contexts:
- context:
    cluster: minikube
    extensions:
    - extension:
        last-update: Mon, 30 Jun 2025 05:19:34 CET
        provider: minikube.sigs.k8s.io
        version: v1.36.0
      name: context_info
    namespace: default
    user: minikube
  name: minikube
current-context: minikube
kind: Config
preferences: {}
users:
- name: minikube
  user:
    client-certificate: /var/jenkins_home/.minikube/profiles/minikube/client.crt
    client-key: /var/jenkins_home/.minikube/profiles/minikube/client.key
EOF

# Fix ownership and permissions
chown jenkins:jenkins /var/jenkins_home/.kube/config-adjusted
chmod 644 /var/jenkins_home/.kube/config-adjusted
"

# Step 2: Test the connection
echo "Testing Kubernetes connection with adjusted config..."
sudo docker exec -u 0 -it jenkins kubectl --kubeconfig=/var/jenkins_home/.kube/config-adjusted cluster-info

# Step 3: Update deploy.sh script (as root)
echo "Updating deploy.sh script..."
sudo docker exec -u 0 -it jenkins bash -c "
cat > /deploy.sh << 'EOF'
#!/bin/bash

echo 'Testing Kubernetes connection...'
kubectl --kubeconfig=/var/jenkins_home/.kube/config-adjusted cluster-info || echo 'Cluster info failed'
kubectl --kubeconfig=/var/jenkins_home/.kube/config-adjusted get nodes || echo 'Get nodes failed'
kubectl --kubeconfig=/var/jenkins_home/.kube/config-adjusted get namespaces || echo 'Get namespaces failed'

# Create namespace if it doesn't exist
kubectl --kubeconfig=/var/jenkins_home/.kube/config-adjusted get namespace chexy || kubectl --kubeconfig=/var/jenkins_home/.kube/config-adjusted create namespace chexy

# Apply deployment files
kubectl --kubeconfig=/var/jenkins_home/.kube/config-adjusted apply -f /var/jenkins_home/kubernetes/deployment.yaml
EOF

# Fix permissions and ownership
chmod +x /deploy.sh
chown jenkins:jenkins /deploy.sh
"

# Step 4: Verify the files were created correctly
echo "Verifying file creation..."
sudo docker exec -u 0 -it jenkins ls -la /var/jenkins_home/.kube/
sudo docker exec -u 0 -it jenkins ls -la /deploy.sh

echo ""
echo "Configuration updated successfully!"
echo "Now restart Jenkins to clear the plugin errors:"
echo "sudo docker restart jenkins"
