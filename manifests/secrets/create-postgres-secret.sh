#!/bin/bash

# Script to create PostgreSQL credentials secret

set -e

NAMESPACE="terraform-enterprise"
SECRET_NAME="postgres-credentials"
POSTGRES_PASSWORD="terraform_password_change_me"

echo "========================================="
echo "PostgreSQL Credentials Secret Generator"
echo "========================================="
echo ""

echo "⚠️  WARNING: Using default password for PostgreSQL!"
echo "   For production use, change the password in this script."
echo ""

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    echo "   Namespace '${NAMESPACE}' does not exist. Creating it..."
    kubectl create namespace ${NAMESPACE}
fi

# Delete existing secret if it exists
if kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} &> /dev/null; then
    echo "1. Secret '${SECRET_NAME}' already exists. Deleting it..."
    kubectl delete secret ${SECRET_NAME} -n ${NAMESPACE}
fi

echo "2. Creating PostgreSQL credentials secret..."
kubectl create secret generic ${SECRET_NAME} \
  --from-literal=password=${POSTGRES_PASSWORD} \
  -n ${NAMESPACE}

echo ""
echo "3. Verifying secret creation..."
kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}

echo ""
echo "========================================="
echo "✓ PostgreSQL secret created successfully!"
echo "========================================="
echo ""
echo "Secret name: ${SECRET_NAME}"
echo "Namespace: ${NAMESPACE}"
echo ""
echo "IMPORTANT: The PostgreSQL password is set to: ${POSTGRES_PASSWORD}"
echo "           Change this for production deployments!"
echo ""
