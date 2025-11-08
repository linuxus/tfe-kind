#!/bin/bash

# Script to create self-signed TLS certificates for TFE
# and store them in a Kubernetes secret

set -e

NAMESPACE="terraform-enterprise"
SECRET_NAME="tfe-tls"
HOSTNAME="tfe.local"
CERT_DIR="/tmp/tfe-certs"

echo "========================================="
echo "TFE TLS Certificate Generator"
echo "========================================="
echo ""

# Create temporary directory for certificates
mkdir -p ${CERT_DIR}

echo "1. Generating private key..."
openssl genrsa -out ${CERT_DIR}/tls.key 2048

echo "2. Creating certificate signing request..."
openssl req -new -key ${CERT_DIR}/tls.key -out ${CERT_DIR}/tls.csr \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=${HOSTNAME}"

echo "3. Generating self-signed certificate (valid for 365 days)..."
openssl x509 -req -days 365 -in ${CERT_DIR}/tls.csr \
  -signkey ${CERT_DIR}/tls.key -out ${CERT_DIR}/tls.crt \
  -extfile <(printf "subjectAltName=DNS:${HOSTNAME},DNS:*.${HOSTNAME},DNS:localhost")

echo "4. Verifying certificate..."
openssl x509 -in ${CERT_DIR}/tls.crt -text -noout | grep -A1 "Subject:"

echo ""
echo "5. Creating Kubernetes TLS secret in namespace '${NAMESPACE}'..."

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    echo "   Namespace '${NAMESPACE}' does not exist. Creating it..."
    kubectl create namespace ${NAMESPACE}
fi

# Delete existing secret if it exists
if kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} &> /dev/null; then
    echo "   Secret '${SECRET_NAME}' already exists. Deleting it..."
    kubectl delete secret ${SECRET_NAME} -n ${NAMESPACE}
fi

# Create the TLS secret
kubectl create secret tls ${SECRET_NAME} \
  --cert=${CERT_DIR}/tls.crt \
  --key=${CERT_DIR}/tls.key \
  -n ${NAMESPACE}

echo ""
echo "6. Verifying secret creation..."
kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}

echo ""
echo "7. Cleaning up temporary files..."
rm -rf ${CERT_DIR}

echo ""
echo "========================================="
echo "✓ TLS certificates created successfully!"
echo "========================================="
echo ""
echo "Secret name: ${SECRET_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Hostname: ${HOSTNAME}"
echo ""
echo "Certificate details:"
openssl x509 -in <(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.tls\.crt}' | base64 -d) -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:)"
echo ""
