#!/bin/bash

# Script to create Redis credentials secret

set -e

NAMESPACE="terraform-enterprise"
SECRET_NAME="redis-credentials"
REDIS_PASSWORD="${REDIS_PASSWORD:-redis_password_change_me}"

echo "========================================="
echo "Redis Credentials Secret Generator"
echo "========================================="
echo ""

echo "⚠️  WARNING: Using default password for Redis!"
echo "   For production use, set the REDIS_PASSWORD env var before running this script."
echo ""

# Ensure namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    echo "   Namespace '${NAMESPACE}' does not exist. Creating it..."
    kubectl create namespace ${NAMESPACE}
fi

# Remove existing secret if present to keep value in sync
if kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} &> /dev/null; then
    echo "1. Secret '${SECRET_NAME}' already exists. Deleting it..."
    kubectl delete secret ${SECRET_NAME} -n ${NAMESPACE}
fi

echo "2. Creating Redis credentials secret..."
kubectl create secret generic ${SECRET_NAME} \
  --from-literal=password=${REDIS_PASSWORD} \
  -n ${NAMESPACE}

echo ""
echo "3. Verifying secret creation..."
kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}

echo ""
echo "========================================="
echo "✓ Redis secret created successfully!"
echo "========================================="
echo ""
echo "Secret name: ${SECRET_NAME}"
echo "Namespace: ${NAMESPACE}"
echo ""
echo "IMPORTANT: The Redis password is set to: ${REDIS_PASSWORD}"
echo "           Change this for production deployments!"
echo ""
