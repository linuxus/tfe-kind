#!/bin/bash

# Script to set up port forwarding for TFE access

set -e

NAMESPACE="terraform-enterprise"
SERVICE_NAME="tfe"
LOCAL_PORT="8443"
REMOTE_PORT="443"

echo "========================================="
echo "TFE Port Forwarding Setup"
echo "========================================="
echo ""

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    echo "❌ Error: Namespace '${NAMESPACE}' does not exist."
    echo "   Please deploy TFE first."
    exit 1
fi

# Check if TFE service exists
if ! kubectl get service ${SERVICE_NAME} -n ${NAMESPACE} &> /dev/null; then
    echo "⚠️  Warning: TFE service '${SERVICE_NAME}' not found."
    echo "   Looking for alternative service names..."
    
    # Try to find TFE-related service
    TFE_SVC=$(kubectl get svc -n ${NAMESPACE} -o name | grep -i terraform | head -n 1)
    
    if [ -z "${TFE_SVC}" ]; then
        echo "❌ Error: No TFE service found in namespace '${NAMESPACE}'."
        echo ""
        echo "Available services:"
        kubectl get svc -n ${NAMESPACE}
        exit 1
    fi
    
    SERVICE_NAME=$(echo ${TFE_SVC} | cut -d'/' -f2)
    echo "   Found service: ${SERVICE_NAME}"
fi

echo "Service Details:"
kubectl get service ${SERVICE_NAME} -n ${NAMESPACE}
echo ""

echo "Starting port forwarding..."
echo "   Local:  https://localhost:${LOCAL_PORT}"
echo "   Remote: ${SERVICE_NAME}.${NAMESPACE}:${REMOTE_PORT}"
echo ""
echo "Access TFE at: https://tfe.localtest.me:${LOCAL_PORT}"
echo ""
echo "⚠️  Note: This terminal must remain open for port forwarding to work."
echo "   Press Ctrl+C to stop port forwarding."
echo ""
echo "========================================="
echo ""

# Start port forwarding
kubectl port-forward -n ${NAMESPACE} service/${SERVICE_NAME} ${LOCAL_PORT}:${REMOTE_PORT}
