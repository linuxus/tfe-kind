# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Local deployment of **HashiCorp Terraform Enterprise (TFE)** on a **Kind (Kubernetes in Docker)** cluster for development/sandbox use. The stack includes TFE (deployed via Helm), PostgreSQL 14, and Redis 7.2, all running in a 3-node Kind cluster (1 control-plane + 2 workers).

## Common Commands

### Full Deployment
```bash
./scripts/setup-all.sh          # End-to-end: creates cluster, secrets, deploys all components
```

### Kind Cluster
```bash
kind create cluster --name tfe-kind --config kind-ha-cluster.yaml
kind get clusters
kind delete cluster --name tfe-kind
```

### Kubernetes Operations
```bash
kubectl get all -n terraform-enterprise
kubectl get pods -n terraform-enterprise -w     # Watch pod status
kubectl logs -f <pod> -n terraform-enterprise   # Stream logs
```

### Access TFE
```bash
./scripts/port-forward.sh       # Forward localhost:8443 → TFE :443 (must stay running)
# Then open https://tfe.local:8443
```

### Helm
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install terraform-enterprise hashicorp/terraform-enterprise -n terraform-enterprise -f helm/values.yaml
helm upgrade terraform-enterprise hashicorp/terraform-enterprise -n terraform-enterprise -f helm/values.yaml
```

### Secrets (all in manifests/secrets/)
```bash
./manifests/secrets/create-postgres-secret.sh
./manifests/secrets/create-redis-secret.sh      # Accepts REDIS_PASSWORD env var
./manifests/secrets/create-tls-certs.sh         # Generates self-signed cert for tfe.local
./manifests/secrets/create-license-secret.sh    # Reads license from ~/one-drive/Dev/Licenses/terraform.hclic
```

## Architecture

```
localhost:8443 (port-forward)
    → TFE (Helm chart, ClusterIP :443)
        → PostgreSQL (StatefulSet, :5432, 10Gi PVC)
        → Redis (StatefulSet, :6379, 5Gi PVC)
        → TFE Data PVC (20Gi)
```

- **Namespace**: `terraform-enterprise` for all resources
- **TFE**: Deployed via HashiCorp official Helm chart (`hashicorp/terraform-enterprise`). Configuration in `helm/values.yaml`. Image: `v202410-1`. Operational mode: External services (external PostgreSQL + Redis).
- **PostgreSQL**: StatefulSet from `manifests/postgres-*.yaml`. Database name: `terraform`.
- **Redis**: StatefulSet from `manifests/redis-*.yaml`. Password-protected with AOF+RDB persistence.
- **Storage**: Kind's default `standard` StorageClass (local-path provisioner). Three PVCs total.
- **TLS**: Self-signed certificates stored as K8s secrets.
- **No Ingress Controller**: Access is via `kubectl port-forward` only.

## Known Issues

- **Helm chart bug**: TFE Helm chart v1.6.5 `env.secretKeyRefs` doesn't populate properly. Workaround: manually create `terraform-enterprise-env-secrets` secret with TFE_LICENSE, TFE_REDIS_PASSWORD, TFE_REDIS_SIDEKIQ_PASSWORD, then restart TFE pod.
- **TFE startup time**: 5-10 minutes after pod starts for full initialization.
- **Host entry required**: `/etc/hosts` must have `127.0.0.1 tfe.local`.
- **Resource-heavy**: Needs 8+ CPU cores, 16GB+ RAM, 50GB+ disk.

## Key File Locations

- `helm/values.yaml` — All TFE Helm configuration (image, resources, env vars, database/redis connection strings)
- `scripts/setup-all.sh` — Master automation script (checks prereqs, creates cluster, deploys everything)
- `scripts/port-forward.sh` — Dynamic TFE service discovery and port forwarding
- `manifests/secrets/` — Secret creation scripts (postgres, redis, TLS certs, license)
- `kind-ha-cluster.yaml` — Kind cluster topology definition
