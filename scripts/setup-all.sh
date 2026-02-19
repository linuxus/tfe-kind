#!/bin/bash

# Master setup script for TFE on Kind
# This script automates the complete deployment process

set -e

NAMESPACE="terraform-enterprise"

echo "========================================="
echo "  TFE on Kind - Complete Setup Script"
echo "========================================="
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "1. Checking prerequisites..."
echo ""

MISSING_TOOLS=()

if ! command_exists docker; then
    MISSING_TOOLS+=("docker")
fi

if ! command_exists kind; then
    MISSING_TOOLS+=("kind")
fi

if ! command_exists kubectl; then
    MISSING_TOOLS+=("kubectl")
fi

if ! command_exists helm; then
    MISSING_TOOLS+=("helm")
fi

if ! command_exists openssl; then
    MISSING_TOOLS+=("openssl")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "❌ Error: Missing required tools:"
    for tool in "${MISSING_TOOLS[@]}"; do
        echo "   - $tool"
    done
    echo ""
    echo "Please install the missing tools and try again."
    echo "Refer to the README.md for installation instructions."
    exit 1
fi

echo "✓ All required tools are installed"
echo ""

# Check if Kind cluster exists
echo "2. Checking Kind cluster..."
if ! kind get clusters | grep -q "tfe-cluster"; then
    echo "   Kind cluster 'tfe-cluster' not found."
    read -p "   Would you like to create it now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Creating Kind cluster..."
        kind create cluster --name tfe-cluster
        echo "   ✓ Cluster created"
    else
        echo "   Please create a Kind cluster named 'tfe-cluster' first."
        exit 1
    fi
else
    echo "   ✓ Kind cluster 'tfe-cluster' exists"
fi
echo ""

# Set kubectl context
echo "3. Setting kubectl context..."
kubectl config use-context kind-tfe-cluster
echo "   ✓ Context set to kind-tfe-cluster"
echo ""

# Create namespace
echo "4. Creating namespace..."
if kubectl get namespace ${NAMESPACE} &> /dev/null; then
    echo "   ✓ Namespace '${NAMESPACE}' already exists"
else
    kubectl apply -f manifests/namespace.yaml
    echo "   ✓ Namespace created"
fi
echo ""

# Create secrets
echo "5. Creating secrets..."
echo ""

echo "   5a. Creating PostgreSQL credentials..."
./manifests/secrets/create-postgres-secret.sh
echo ""

echo "   5b. Creating Redis credentials..."
./manifests/secrets/create-redis-secret.sh
echo ""

echo "   5c. Creating TLS certificates..."
./manifests/secrets/create-tls-certs.sh
echo ""

echo "   5d. Creating TFE license secret..."
./manifests/secrets/create-license-secret.sh
echo ""

# Deploy PostgreSQL
echo "6. Deploying PostgreSQL..."
echo ""

echo "   6a. Creating PostgreSQL PVC..."
kubectl apply -f manifests/postgres-pvc.yaml
echo ""

echo "   6b. Deploying PostgreSQL StatefulSet..."
kubectl apply -f manifests/postgres-deployment.yaml
echo ""

echo "   6c. Creating PostgreSQL Service..."
kubectl apply -f manifests/postgres-service.yaml
echo ""

echo "   6d. Waiting for PostgreSQL to be ready (this may take a few minutes)..."
kubectl wait --for=condition=ready pod -l app=postgres -n ${NAMESPACE} --timeout=300s
echo "   ✓ PostgreSQL is ready"
echo ""

# Create TFE PVC
echo "7. Creating TFE data PVC..."
kubectl apply -f manifests/tfe-pvc.yaml
echo "   ✓ TFE PVC created"
echo ""

# Deploy Redis
echo "8. Deploying Redis..."
echo ""

echo "   8a. Creating Redis PVC..."
kubectl apply -f manifests/redis-pvc.yaml
echo ""

echo "   8b. Deploying Redis StatefulSet..."
kubectl apply -f manifests/redis-statefulset.yaml
echo ""

echo "   8c. Creating Redis Service..."
kubectl apply -f manifests/redis-service.yaml
echo ""

echo "   8d. Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod -l app=redis -n ${NAMESPACE} --timeout=300s
echo "   ✓ Redis is ready"
echo ""

# Add HashiCorp Helm repo
echo "9. Setting up Helm repository..."
if helm repo list | grep -q hashicorp; then
    echo "   ✓ HashiCorp Helm repo already added"
else
    helm repo add hashicorp https://helm.releases.hashicorp.com
    echo "   ✓ HashiCorp Helm repo added"
fi
helm repo update
echo "   ✓ Helm repos updated"
echo ""

# Deploy TFE using Helm
echo "10. Deploying Terraform Enterprise (this will take 5-10 minutes)..."
echo ""

if helm list -n ${NAMESPACE} | grep -q tfe; then
    echo "   TFE release already exists. Upgrading..."
    helm upgrade tfe hashicorp/terraform-enterprise \
        -n ${NAMESPACE} \
        -f helm/values.yaml \
        --wait \
        --timeout 15m
    echo "   ✓ TFE upgraded"
else
    echo "   Installing TFE..."
    helm install tfe hashicorp/terraform-enterprise \
        -n ${NAMESPACE} \
        -f helm/values.yaml \
        --wait \
        --timeout 15m
    echo "   ✓ TFE installed"
fi
echo ""

# Configure /etc/hosts
echo "11. Configuring /etc/hosts..."
if grep -q "tfe.local" /etc/hosts; then
    echo "    ✓ tfe.local already in /etc/hosts"
else
    echo "    Adding tfe.local to /etc/hosts (requires sudo)..."
    echo "127.0.0.1 tfe.local" | sudo tee -a /etc/hosts
    echo "    ✓ /etc/hosts updated"
fi
echo ""

# Show deployment status
echo "========================================="
echo "  Deployment Status"
echo "========================================="
echo ""

echo "Pods:"
kubectl get pods -n ${NAMESPACE}
echo ""

echo "Services:"
kubectl get svc -n ${NAMESPACE}
echo ""

echo "PVCs:"
kubectl get pvc -n ${NAMESPACE}
echo ""

echo "========================================="
echo "  ✓ TFE Deployment Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Start port forwarding:"
echo "   ./scripts/port-forward.sh"
echo ""
echo "2. Access TFE in your browser:"
echo "   https://tfe.local:8443"
echo ""
echo "3. Accept the self-signed certificate warning"
echo ""
echo "4. Complete the initial TFE setup wizard"
echo ""
echo "For troubleshooting, refer to the README.md"
echo ""
