#!/bin/bash

# Script to create Kubernetes secret from TFE license file

set -e

NAMESPACE="terraform-enterprise"
SECRET_NAME="tfe-license"
LICENSE_FILE="${TFE_LICENSE_PATH:-}"

echo "========================================="
echo "TFE License Secret Generator"
echo "========================================="
echo ""

# Check if license path is provided
if [ -z "${LICENSE_FILE}" ]; then
    echo "❌ Error: TFE_LICENSE_PATH is not set."
    echo ""
    echo "Usage:"
    echo "  export TFE_LICENSE_PATH=/path/to/terraform.hclic"
    echo "  ./manifests/secrets/create-license-secret.sh"
    echo ""
    echo "You can obtain a license from https://developer.hashicorp.com/terraform/enterprise"
    exit 1
fi

# Check if license file exists
if [ ! -f "${LICENSE_FILE}" ]; then
    echo "❌ Error: License file not found at ${LICENSE_FILE}"
    echo ""
    echo "Please verify the TFE_LICENSE_PATH is correct."
    exit 1
fi

echo "1. Found license file: ${LICENSE_FILE}"

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    echo "   Namespace '${NAMESPACE}' does not exist. Creating it..."
    kubectl create namespace ${NAMESPACE}
fi

# Delete existing secret if it exists
if kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} &> /dev/null; then
    echo "2. Secret '${SECRET_NAME}' already exists. Deleting it..."
    kubectl delete secret ${SECRET_NAME} -n ${NAMESPACE}
fi

echo "3. Creating Kubernetes secret from license file..."
kubectl create secret generic ${SECRET_NAME} \
  --from-file=license=${LICENSE_FILE} \
  -n ${NAMESPACE}

echo ""
echo "4. Verifying secret creation..."
kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}

echo ""
echo "========================================="
echo "✓ License secret created successfully!"
echo "========================================="
echo ""
echo "Secret name: ${SECRET_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "License file: ${LICENSE_FILE}"
echo ""
echo "Secret details:"
kubectl describe secret ${SECRET_NAME} -n ${NAMESPACE}
echo ""
