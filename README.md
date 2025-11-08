# Terraform Enterprise on Kind Kubernetes Cluster

Complete deployment guide for running HashiCorp Terraform Enterprise (TFE) on a local Kind Kubernetes cluster.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Detailed Installation Steps](#detailed-installation-steps)
- [Accessing TFE](#accessing-tfe)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)
- [Cleanup](#cleanup)

## Overview

This repository provides a production-ready deployment of Terraform Enterprise on a local Kind Kubernetes cluster using Helm charts. The deployment includes:

- **Terraform Enterprise** (latest GA version)
- **PostgreSQL Database** (in-cluster deployment)
- **Persistent Storage** (local-path provisioner)
- **Self-signed TLS Certificates**
- **Port-forwarding access** (no ingress controller required)

**Note:** This setup is optimized for local development and sandbox environments.

## Prerequisites

### Required Tools
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running)
- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/) v0.20.0+
- [kubectl](https://kubernetes.io/docs/tasks/tools/) v1.27.0+
- [Helm](https://helm.sh/docs/intro/install/) v3.12.0+
- OpenSSL (for certificate generation)

### System Requirements
- **CPU:** 8+ cores recommended
- **Memory:** 16GB+ RAM recommended
- **Disk Space:** 50GB+ free space

### TFE License
- Valid Terraform Enterprise license file: `/Users/abdii/one-drive/Dev/Licenses/terraform.hclic`

### Verify Prerequisites
```bash
# Check Docker
docker --version

# Check Kind
kind version

# Check kubectl
kubectl version --client

# Check Helm
helm version

# Check OpenSSL
openssl version
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│          Local Machine (macOS)                  │
│  ┌───────────────────────────────────────────┐  │
│  │     Kind Kubernetes Cluster               │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │  Namespace: terraform-enterprise    │  │  │
│  │  │                                     │  │  │
│  │  │  ┌──────────────┐  ┌─────────────┐ │  │  │
│  │  │  │ TFE Pod      │  │ PostgreSQL  │ │  │  │
│  │  │  │              │◄─┤ Pod         │ │  │  │
│  │  │  │ 2-4 CPU      │  │             │ │  │  │
│  │  │  │ 4-8Gi RAM    │  │ 1-2 CPU     │ │  │  │
│  │  │  │              │  │ 2-4Gi RAM   │ │  │  │
│  │  │  └──────┬───────┘  └──────┬──────┘ │  │  │
│  │  │         │                 │        │  │  │
│  │  │    ┌────▼────┐      ┌────▼────┐   │  │  │
│  │  │    │ TFE PVC │      │ PG PVC  │   │  │  │
│  │  │    │  20Gi   │      │  10Gi   │   │  │  │
│  │  │    └─────────┘      └─────────┘   │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
│              ▲                                   │
│              │ Port Forward                      │
│              │ localhost:8443 → TFE:443         │
└──────────────┼───────────────────────────────────┘
               │
          Browser: https://tfe.local:8443
```

### Components

1. **Terraform Enterprise (TFE)**
   - Latest production GA version
   - Runs as a StatefulSet/Deployment
   - Exposes HTTPS on port 443 (ClusterIP Service)
   - Uses self-signed TLS certificates
   - Hostname: `tfe.local`

2. **PostgreSQL Database**
   - Version: 14 (compatible with TFE)
   - Runs as a StatefulSet
   - Persistent storage: 10Gi
   - Internal service: `postgres.terraform-enterprise.svc.cluster.local`

3. **Storage**
   - Uses Kind's default local-path provisioner
   - TFE data: 20Gi PersistentVolumeClaim
   - PostgreSQL data: 10Gi PersistentVolumeClaim

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/abdi-ibrahim-2025/tfe-kind.git
cd tfe-kind

# 2. Create Kind cluster (if not already created)
kind create cluster --name tfe-cluster

# 3. Create namespace
kubectl apply -f manifests/namespace.yaml

# 4. Create TLS certificates
./manifests/secrets/create-tls-certs.sh

# 5. Create license secret
./manifests/secrets/create-license-secret.sh

# 6. Deploy PostgreSQL
kubectl apply -f manifests/postgres-pvc.yaml
kubectl apply -f manifests/postgres-deployment.yaml
kubectl apply -f manifests/postgres-service.yaml

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n terraform-enterprise --timeout=300s

# 7. Deploy TFE using Helm
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install tfe hashicorp/terraform-enterprise \
  -n terraform-enterprise \
  -f helm/values.yaml \
  --wait

# 8. Configure /etc/hosts
echo "127.0.0.1 tfe.local" | sudo tee -a /etc/hosts

# 9. Start port forwarding
./scripts/port-forward.sh

# 10. Access TFE
open https://tfe.local:8443
```

## Detailed Installation Steps

### Step 1: Create Kind Cluster

If you don't have a Kind cluster running, create one:

```bash
kind create cluster --name tfe-cluster --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30443
    hostPort: 8443
    protocol: TCP
EOF
```

Verify the cluster:
```bash
kubectl cluster-info --context kind-tfe-cluster
kubectl get nodes
```

### Step 2: Create Namespace

```bash
kubectl apply -f manifests/namespace.yaml
```

Verify:
```bash
kubectl get namespace terraform-enterprise
```

### Step 3: Generate TLS Certificates

Create self-signed TLS certificates for `tfe.local`:

```bash
chmod +x manifests/secrets/create-tls-certs.sh
./manifests/secrets/create-tls-certs.sh
```

This creates a Kubernetes TLS secret named `tfe-tls` in the `terraform-enterprise` namespace.

Verify:
```bash
kubectl get secret tfe-tls -n terraform-enterprise
```

### Step 4: Create License Secret

```bash
chmod +x manifests/secrets/create-license-secret.sh
./manifests/secrets/create-license-secret.sh
```

This reads your license file from `/Users/abdii/one-drive/Dev/Licenses/terraform.hclic` and creates a Kubernetes secret.

Verify:
```bash
kubectl get secret tfe-license -n terraform-enterprise
```

### Step 5: Deploy PostgreSQL

```bash
# Create PersistentVolumeClaim
kubectl apply -f manifests/postgres-pvc.yaml

# Deploy PostgreSQL
kubectl apply -f manifests/postgres-deployment.yaml
kubectl apply -f manifests/postgres-service.yaml

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n terraform-enterprise --timeout=300s
```

Verify PostgreSQL is running:
```bash
kubectl get pods -n terraform-enterprise -l app=postgres
kubectl logs -n terraform-enterprise -l app=postgres
```

Test PostgreSQL connection:
```bash
kubectl exec -it -n terraform-enterprise \
  $(kubectl get pod -n terraform-enterprise -l app=postgres -o jsonpath='{.items[0].metadata.name}') \
  -- psql -U terraform -d tfe -c '\l'
```

### Step 6: Add HashiCorp Helm Repository

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

Verify:
```bash
helm search repo hashicorp/terraform-enterprise
```

### Step 7: Deploy TFE with Helm

```bash
helm install tfe hashicorp/terraform-enterprise \
  -n terraform-enterprise \
  -f helm/values.yaml \
  --wait \
  --timeout 15m
```

Monitor the deployment:
```bash
# Watch pods
kubectl get pods -n terraform-enterprise -w

# Check TFE logs
kubectl logs -n terraform-enterprise -l app.kubernetes.io/name=terraform-enterprise -f

# Check all resources
kubectl get all -n terraform-enterprise
```

The deployment may take 5-10 minutes as TFE initializes the database and starts all services.

### Step 8: Configure Local DNS

Add `tfe.local` to your `/etc/hosts` file:

```bash
echo "127.0.0.1 tfe.local" | sudo tee -a /etc/hosts
```

Verify:
```bash
grep tfe.local /etc/hosts
```

### Step 9: Set Up Port Forwarding

Start port forwarding to access TFE:

```bash
chmod +x scripts/port-forward.sh
./scripts/port-forward.sh
```

This forwards `localhost:8443` → `tfe-service:443` in the cluster.

**Note:** Keep this terminal window open. The port-forwarding will stop if you close it.

## Accessing TFE

### Initial Setup

1. Open your browser and navigate to: **https://tfe.local:8443**

2. You'll see a certificate warning (expected with self-signed certs):
   - **Chrome/Edge:** Click "Advanced" → "Proceed to tfe.local (unsafe)"
   - **Firefox:** Click "Advanced" → "Accept the Risk and Continue"
   - **Safari:** Click "Show Details" → "visit this website"

3. Complete the initial TFE setup wizard:
   - Create admin account
   - Configure organization settings
   - Set up first workspace

### Default Admin Account

Create your admin account during first-time setup. You'll be prompted to:
- Set admin username
- Set admin email
- Set admin password

### Subsequent Access

```bash
# Start port forwarding (if not running)
./scripts/port-forward.sh

# Access TFE
open https://tfe.local:8443
```

## Configuration

### Helm Values Customization

The main configuration is in `helm/values.yaml`. Key settings:

```yaml
# TFE Application Settings
tfe:
  hostname: "tfe.local"
  
# Database Configuration
database:
  host: "postgres.terraform-enterprise.svc.cluster.local"
  port: 5432
  
# Resource Limits
resources:
  requests:
    cpu: "2"
    memory: "4Gi"
  limits:
    cpu: "4"
    memory: "8Gi"
```

To update configuration:
```bash
# Edit values
vim helm/values.yaml

# Upgrade deployment
helm upgrade tfe hashicorp/terraform-enterprise \
  -n terraform-enterprise \
  -f helm/values.yaml
```

### PostgreSQL Configuration

PostgreSQL settings are in `manifests/postgres-deployment.yaml`:

```yaml
# Database credentials
POSTGRES_USER: terraform
POSTGRES_PASSWORD: terraform_password  # Change in production!
POSTGRES_DB: tfe
```

### Storage Configuration

To increase storage:

```yaml
# manifests/tfe-pvc.yaml
resources:
  requests:
    storage: 50Gi  # Increase from 20Gi

# manifests/postgres-pvc.yaml
resources:
  requests:
    storage: 20Gi  # Increase from 10Gi
```

**Note:** Changes to PVC size require deleting and recreating the PVC (data will be lost).

## Troubleshooting

### TFE Pod Not Starting

```bash
# Check pod status
kubectl get pods -n terraform-enterprise

# Describe pod for events
kubectl describe pod -n terraform-enterprise -l app.kubernetes.io/name=terraform-enterprise

# Check logs
kubectl logs -n terraform-enterprise -l app.kubernetes.io/name=terraform-enterprise --tail=100
```

Common issues:
- **License error:** Verify license secret is created correctly
- **Database connection:** Ensure PostgreSQL is running and accessible
- **Resource constraints:** Check if Kind cluster has enough resources

### PostgreSQL Connection Issues

```bash
# Check PostgreSQL pod
kubectl get pod -n terraform-enterprise -l app=postgres

# Check PostgreSQL logs
kubectl logs -n terraform-enterprise -l app=postgres

# Test connection from TFE pod
kubectl exec -it -n terraform-enterprise \
  $(kubectl get pod -n terraform-enterprise -l app.kubernetes.io/name=terraform-enterprise -o jsonpath='{.items[0].metadata.name}') \
  -- nc -zv postgres.terraform-enterprise.svc.cluster.local 5432
```

### Certificate Errors

If you need to regenerate certificates:

```bash
# Delete existing secret
kubectl delete secret tfe-tls -n terraform-enterprise

# Regenerate
./manifests/secrets/create-tls-certs.sh

# Restart TFE
kubectl rollout restart statefulset/tfe -n terraform-enterprise
```

### Port Forwarding Issues

```bash
# Check if port is already in use
lsof -i :8443

# Kill existing port-forward
pkill -f "kubectl port-forward"

# Restart port-forward
./scripts/port-forward.sh
```

### Viewing All Logs

```bash
# TFE logs
kubectl logs -n terraform-enterprise -l app.kubernetes.io/name=terraform-enterprise -f

# PostgreSQL logs
kubectl logs -n terraform-enterprise -l app=postgres -f

# All events in namespace
kubectl get events -n terraform-enterprise --sort-by='.lastTimestamp'
```

### Checking Resource Usage

```bash
# Pod resource usage
kubectl top pods -n terraform-enterprise

# Node resource usage
kubectl top nodes

# Describe node
kubectl describe node tfe-cluster-control-plane
```

## Maintenance

### Viewing TFE Version

```bash
kubectl exec -n terraform-enterprise \
  $(kubectl get pod -n terraform-enterprise -l app.kubernetes.io/name=terraform-enterprise -o jsonpath='{.items[0].metadata.name}') \
  -- cat /etc/terraform-enterprise/version
```

### Upgrading TFE

```bash
# Update Helm repo
helm repo update

# Check available versions
helm search repo hashicorp/terraform-enterprise --versions

# Upgrade to specific version
helm upgrade tfe hashicorp/terraform-enterprise \
  -n terraform-enterprise \
  -f helm/values.yaml \
  --version <VERSION> \
  --wait

# Or upgrade to latest
helm upgrade tfe hashicorp/terraform-enterprise \
  -n terraform-enterprise \
  -f helm/values.yaml \
  --wait
```

### Backup

#### Backup PostgreSQL Database

```bash
# Create backup
kubectl exec -n terraform-enterprise \
  $(kubectl get pod -n terraform-enterprise -l app=postgres -o jsonpath='{.items[0].metadata.name}') \
  -- pg_dump -U terraform tfe > tfe-backup-$(date +%Y%m%d).sql

# Verify backup
ls -lh tfe-backup-*.sql
```

#### Backup TFE Data

```bash
# Get TFE pod name
TFE_POD=$(kubectl get pod -n terraform-enterprise -l app.kubernetes.io/name=terraform-enterprise -o jsonpath='{.items[0].metadata.name}')

# Backup TFE data directory
kubectl exec -n terraform-enterprise $TFE_POD -- tar czf /tmp/tfe-data-backup.tar.gz /var/lib/terraform-enterprise

# Copy to local
kubectl cp terraform-enterprise/$TFE_POD:/tmp/tfe-data-backup.tar.gz ./tfe-data-backup-$(date +%Y%m%d).tar.gz
```

### Restore

#### Restore PostgreSQL Database

```bash
# Copy backup to pod
kubectl cp tfe-backup-20250108.sql \
  terraform-enterprise/$(kubectl get pod -n terraform-enterprise -l app=postgres -o jsonpath='{.items[0].metadata.name}'):/tmp/

# Restore
kubectl exec -n terraform-enterprise \
  $(kubectl get pod -n terraform-enterprise -l app=postgres -o jsonpath='{.items[0].metadata.name}') \
  -- psql -U terraform tfe < /tmp/tfe-backup-20250108.sql
```

### Restart TFE

```bash
# Restart TFE pods
kubectl rollout restart deployment/tfe -n terraform-enterprise

# Or delete pod (will be recreated)
kubectl delete pod -n terraform-enterprise -l app.kubernetes.io/name=terraform-enterprise
```

### Scaling

TFE in this configuration runs as a single instance. For development purposes, this is appropriate.

## Cleanup

### Remove TFE Deployment

```bash
# Uninstall Helm release
helm uninstall tfe -n terraform-enterprise

# Delete PostgreSQL
kubectl delete -f manifests/postgres-service.yaml
kubectl delete -f manifests/postgres-deployment.yaml
kubectl delete -f manifests/postgres-pvc.yaml

# Delete PVCs
kubectl delete pvc -n terraform-enterprise --all

# Delete secrets
kubectl delete secret tfe-license tfe-tls -n terraform-enterprise

# Delete namespace
kubectl delete namespace terraform-enterprise
```

### Remove Kind Cluster

```bash
# Delete cluster
kind delete cluster --name tfe-cluster

# Remove from /etc/hosts
sudo sed -i '' '/tfe.local/d' /etc/hosts
```

## Additional Resources

- [Terraform Enterprise Documentation](https://developer.hashicorp.com/terraform/enterprise)
- [TFE Helm Chart](https://github.com/hashicorp/terraform-helm)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Support

For issues specific to this deployment:
- Check the [Troubleshooting](#troubleshooting) section
- Review logs using commands in this guide
- Open an issue in this repository

For TFE-specific issues:
- [HashiCorp Support](https://support.hashicorp.com/)
- [TFE Community Forum](https://discuss.hashicorp.com/c/terraform-enterprise/)

---

**Version:** 1.0.0  
**Last Updated:** November 8, 2025  
**Maintainer:** Abdi Ibrahim
