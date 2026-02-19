#!/bin/bash

# =============================================================================
# TFE on Kind - Complete Setup Script
# =============================================================================
# Deploys HashiCorp Terraform Enterprise on a Kind Kubernetes cluster with
# PostgreSQL, Redis, and all required secrets/configuration.
#
# Prerequisites:
#   - Docker installed and running
#   - kind CLI installed
#   - kubectl CLI installed
#   - helm CLI installed
#   - openssl CLI installed
#   - TFE license file (.hclic)
#
# Usage:
#   ./scripts/setup-all.sh                    # Full deployment
#   ./scripts/setup-all.sh --help             # Show usage
#   ./scripts/setup-all.sh --status           # Show deployment status
#   ./scripts/setup-all.sh --teardown         # Full cleanup
#   ./scripts/setup-all.sh --skip-cluster     # Skip Kind cluster creation
#   ./scripts/setup-all.sh --port-forward     # Start port-forward after deploy
#
# Environment Variables (optional overrides):
#   KIND_CLUSTER_NAME   - Kind cluster name (default: tfe-cluster)
#   TFE_NAMESPACE       - Kubernetes namespace (default: terraform-enterprise)
#   TFE_LICENSE_PATH    - Path to .hclic file (required, no default)
#   POSTGRES_PASSWORD   - PostgreSQL password (default: terraform_password_change_me)
#   REDIS_PASSWORD      - Redis password (default: redis_password_change_me)
#   HELM_TIMEOUT        - Helm install timeout (default: 15m)
#   LOCAL_PORT          - Local port for TFE access (default: 8443)
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-tfe-cluster}"
TFE_NAMESPACE="${TFE_NAMESPACE:-terraform-enterprise}"
TFE_LICENSE_PATH="${TFE_LICENSE_PATH:-}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-terraform_password_change_me}"
REDIS_PASSWORD="${REDIS_PASSWORD:-redis_password_change_me}"
HELM_TIMEOUT="${HELM_TIMEOUT:-15m}"
LOCAL_PORT="${LOCAL_PORT:-8443}"

# PID file for port-forward tracking
PF_PID_FILE="/tmp/tfe-port-forward.pid"

# CLI flags (defaults)
FLAG_TEARDOWN=false
FLAG_STATUS=false
FLAG_SKIP_CLUSTER=false
FLAG_SKIP_SECRETS=false
FLAG_PORT_FORWARD=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# =============================================================================
# Helper Functions
# =============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${MAGENTA}${BOLD}=== $1 ===${NC}\n"; }

check_url() {
    local url=$1
    local timeout=${2:-5}
    curl -sk -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" "$url" 2>/dev/null || echo "000"
}

cleanup() {
    log_warn "Caught interrupt signal. Cleaning up..."
    if [ -f "$PF_PID_FILE" ]; then
        local pid
        pid=$(cat "$PF_PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$PF_PID_FILE"
    fi
    exit 1
}

trap cleanup INT TERM

# =============================================================================
# Usage
# =============================================================================
usage() {
    echo -e "${BOLD}TFE on Kind - Complete Setup Script${NC}"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    $(basename "$0") [OPTIONS]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help              Show this help message and exit"
    echo "    --teardown              Full cleanup (Helm uninstall, delete manifests, delete cluster)"
    echo "    --status                Show current deployment status and exit"
    echo "    --skip-cluster          Skip Kind cluster creation"
    echo "    --skip-secrets          Skip secret creation"
    echo "    --port-forward          Start port forwarding in background after deploy"
    echo "    --license-path PATH     Override TFE license file path"
    echo "    --cluster-name NAME     Override Kind cluster name"
    echo ""
    echo -e "${BOLD}ENVIRONMENT VARIABLES:${NC}"
    echo "    KIND_CLUSTER_NAME       Kind cluster name (default: tfe-cluster)"
    echo "    TFE_NAMESPACE           Kubernetes namespace (default: terraform-enterprise)"
    echo "    TFE_LICENSE_PATH        Path to .hclic file (required)"
    echo "    POSTGRES_PASSWORD       PostgreSQL password (default: terraform_password_change_me)"
    echo "    REDIS_PASSWORD          Redis password (default: redis_password_change_me)"
    echo "    HELM_TIMEOUT            Helm install timeout (default: 15m)"
    echo "    LOCAL_PORT              Local port for TFE access (default: 8443)"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    # Full deployment with defaults"
    echo "    ./scripts/setup-all.sh"
    echo ""
    echo "    # Deploy and start port-forward"
    echo "    ./scripts/setup-all.sh --port-forward"
    echo ""
    echo "    # Use custom license path and cluster name"
    echo "    ./scripts/setup-all.sh --license-path /path/to/license.hclic --cluster-name my-tfe"
    echo ""
    echo "    # Skip cluster creation (already exists)"
    echo "    ./scripts/setup-all.sh --skip-cluster"
    echo ""
    echo "    # Check status of existing deployment"
    echo "    ./scripts/setup-all.sh --status"
    echo ""
    echo "    # Tear everything down"
    echo "    ./scripts/setup-all.sh --teardown"
}

# =============================================================================
# CLI Argument Parsing
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --teardown)
                FLAG_TEARDOWN=true
                shift
                ;;
            --status)
                FLAG_STATUS=true
                shift
                ;;
            --skip-cluster)
                FLAG_SKIP_CLUSTER=true
                shift
                ;;
            --skip-secrets)
                FLAG_SKIP_SECRETS=true
                shift
                ;;
            --port-forward)
                FLAG_PORT_FORWARD=true
                shift
                ;;
            --license-path)
                TFE_LICENSE_PATH="$2"
                shift 2
                ;;
            --cluster-name)
                KIND_CLUSTER_NAME="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Standalone Modes
# =============================================================================
show_status() {
    log_step "TFE Deployment Status"

    # Cluster
    log_info "Kind cluster:"
    if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        log_success "Cluster '${KIND_CLUSTER_NAME}' exists"
    else
        log_warn "Cluster '${KIND_CLUSTER_NAME}' not found"
        return 0
    fi

    # Context
    if ! kubectl config use-context "kind-${KIND_CLUSTER_NAME}" &>/dev/null; then
        log_error "Cannot set kubectl context to kind-${KIND_CLUSTER_NAME}"
        return 1
    fi

    echo ""
    log_info "Pods:"
    kubectl get pods -n "$TFE_NAMESPACE" 2>/dev/null || log_warn "No pods found"

    echo ""
    log_info "Services:"
    kubectl get svc -n "$TFE_NAMESPACE" 2>/dev/null || log_warn "No services found"

    echo ""
    log_info "PVCs:"
    kubectl get pvc -n "$TFE_NAMESPACE" 2>/dev/null || log_warn "No PVCs found"

    echo ""
    log_info "Secrets:"
    kubectl get secrets -n "$TFE_NAMESPACE" 2>/dev/null || log_warn "No secrets found"

    echo ""
    log_info "Helm releases:"
    helm list -n "$TFE_NAMESPACE" 2>/dev/null || log_warn "No Helm releases found"

    echo ""
    log_info "Port-forward status:"
    if [ -f "$PF_PID_FILE" ] && kill -0 "$(cat "$PF_PID_FILE")" 2>/dev/null; then
        log_success "Port-forward running (PID $(cat "$PF_PID_FILE")) on localhost:${LOCAL_PORT}"
    else
        log_warn "Port-forward not running"
        rm -f "$PF_PID_FILE"
    fi
}

teardown() {
    log_step "Tearing Down TFE Environment"

    # Stop port-forward
    if [ -f "$PF_PID_FILE" ]; then
        local pid
        pid=$(cat "$PF_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping port-forward (PID $pid)..."
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$PF_PID_FILE"
    fi

    # Check if cluster exists
    if ! kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        log_warn "Cluster '${KIND_CLUSTER_NAME}' does not exist. Nothing to tear down."
        return 0
    fi

    kubectl config use-context "kind-${KIND_CLUSTER_NAME}" &>/dev/null || true

    # Helm uninstall
    if helm list -n "$TFE_NAMESPACE" 2>/dev/null | grep -q tfe; then
        log_info "Uninstalling TFE Helm release..."
        helm uninstall tfe -n "$TFE_NAMESPACE" --wait 2>/dev/null || true
        log_success "Helm release uninstalled"
    fi

    # Delete manifests (ignore errors — resources may already be gone)
    if kubectl get namespace "$TFE_NAMESPACE" &>/dev/null; then
        log_info "Deleting Kubernetes resources..."
        kubectl delete -f "$PROJECT_DIR/manifests/redis-statefulset.yaml" -n "$TFE_NAMESPACE" 2>/dev/null || true
        kubectl delete -f "$PROJECT_DIR/manifests/redis-service.yaml" -n "$TFE_NAMESPACE" 2>/dev/null || true
        kubectl delete -f "$PROJECT_DIR/manifests/redis-pvc.yaml" -n "$TFE_NAMESPACE" 2>/dev/null || true
        kubectl delete -f "$PROJECT_DIR/manifests/postgres-deployment.yaml" -n "$TFE_NAMESPACE" 2>/dev/null || true
        kubectl delete -f "$PROJECT_DIR/manifests/postgres-service.yaml" -n "$TFE_NAMESPACE" 2>/dev/null || true
        kubectl delete -f "$PROJECT_DIR/manifests/postgres-pvc.yaml" -n "$TFE_NAMESPACE" 2>/dev/null || true
        kubectl delete -f "$PROJECT_DIR/manifests/tfe-pvc.yaml" -n "$TFE_NAMESPACE" 2>/dev/null || true

        log_info "Deleting remaining PVCs..."
        kubectl delete pvc --all -n "$TFE_NAMESPACE" 2>/dev/null || true

        log_info "Deleting secrets..."
        kubectl delete secrets --all -n "$TFE_NAMESPACE" 2>/dev/null || true

        log_info "Deleting namespace..."
        kubectl delete namespace "$TFE_NAMESPACE" 2>/dev/null || true
        log_success "Kubernetes resources deleted"
    fi

    # Delete Kind cluster
    log_info "Deleting Kind cluster '${KIND_CLUSTER_NAME}'..."
    kind delete cluster --name "$KIND_CLUSTER_NAME"
    log_success "Kind cluster deleted"

    echo ""
    log_success "Teardown complete"
}

# =============================================================================
# Deployment Functions
# =============================================================================

# 1. Check prerequisites
check_prerequisites() {
    log_step "Step 1: Checking Prerequisites"

    local missing=()

    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    elif ! docker info &>/dev/null; then
        log_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi

    for tool in kind kubectl helm openssl; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Install with: brew install ${missing[*]}"
        exit 1
    fi
    log_success "All required tools installed"

    if [ -z "$TFE_LICENSE_PATH" ]; then
        log_error "TFE_LICENSE_PATH is not set"
        log_info "Set TFE_LICENSE_PATH env var or use --license-path /path/to/terraform.hclic"
        exit 1
    fi
    if [ ! -f "$TFE_LICENSE_PATH" ]; then
        log_error "TFE license file not found at: $TFE_LICENSE_PATH"
        log_info "Verify the path and try again"
        exit 1
    fi
    log_success "TFE license found: $TFE_LICENSE_PATH"
}

# 2. Create Kind cluster
setup_kind_cluster() {
    log_step "Step 2: Setting Up Kind Cluster"

    if [ "$FLAG_SKIP_CLUSTER" = true ]; then
        log_warn "Skipping cluster creation (--skip-cluster)"
        return 0
    fi

    if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        log_info "Cluster '${KIND_CLUSTER_NAME}' already exists, verifying connectivity..."
        if kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}" &>/dev/null; then
            log_success "Cluster is reachable"
            return 0
        else
            log_error "Cannot connect to existing cluster '${KIND_CLUSTER_NAME}'"
            exit 1
        fi
    fi

    log_info "Creating Kind cluster '${KIND_CLUSTER_NAME}'..."
    kind create cluster --name "$KIND_CLUSTER_NAME" --config "$PROJECT_DIR/kind-ha-cluster.yaml"
    log_success "Kind cluster created"
}

# 3. Set kubectl context
set_kubectl_context() {
    log_step "Step 3: Setting kubectl Context"

    kubectl config use-context "kind-${KIND_CLUSTER_NAME}"
    log_success "Context set to kind-${KIND_CLUSTER_NAME}"
}

# 4. Create namespace
create_namespace() {
    log_step "Step 4: Creating Namespace"

    kubectl apply -f "$PROJECT_DIR/manifests/namespace.yaml"
    log_success "Namespace '${TFE_NAMESPACE}' ready"
}

# 5. Create secrets
create_secrets() {
    log_step "Step 5: Creating Secrets"

    if [ "$FLAG_SKIP_SECRETS" = true ]; then
        log_warn "Skipping secret creation (--skip-secrets)"
        return 0
    fi

    # 5a. PostgreSQL credentials
    log_info "Creating PostgreSQL credentials..."
    kubectl create secret generic postgres-credentials \
        --from-literal=password="$POSTGRES_PASSWORD" \
        -n "$TFE_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    log_success "PostgreSQL credentials ready"

    # 5b. Redis credentials
    log_info "Creating Redis credentials..."
    kubectl create secret generic redis-credentials \
        --from-literal=password="$REDIS_PASSWORD" \
        -n "$TFE_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    log_success "Redis credentials ready"

    # 5c. TLS certificates (delegate to existing script — complex openssl logic)
    log_info "Creating TLS certificates..."
    "$PROJECT_DIR/manifests/secrets/create-tls-certs.sh"
    log_success "TLS certificates ready"

    # 5d. TFE license
    log_info "Creating TFE license secret..."
    kubectl create secret generic tfe-license \
        --from-file=license="$TFE_LICENSE_PATH" \
        -n "$TFE_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    log_success "TFE license secret ready"
}

# 6. Deploy PostgreSQL
deploy_postgres() {
    log_step "Step 6: Deploying PostgreSQL"

    kubectl apply -f "$PROJECT_DIR/manifests/postgres-pvc.yaml"
    kubectl apply -f "$PROJECT_DIR/manifests/postgres-deployment.yaml"
    kubectl apply -f "$PROJECT_DIR/manifests/postgres-service.yaml"

    log_info "Waiting for PostgreSQL to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgres -n "$TFE_NAMESPACE" --timeout=300s
    log_success "PostgreSQL is ready"
}

# 7. Create TFE PVC
create_tfe_pvc() {
    log_step "Step 7: Creating TFE Data PVC"

    kubectl apply -f "$PROJECT_DIR/manifests/tfe-pvc.yaml"
    log_success "TFE data PVC ready"
}

# 8. Deploy Redis
deploy_redis() {
    log_step "Step 8: Deploying Redis"

    kubectl apply -f "$PROJECT_DIR/manifests/redis-pvc.yaml"
    kubectl apply -f "$PROJECT_DIR/manifests/redis-statefulset.yaml"
    kubectl apply -f "$PROJECT_DIR/manifests/redis-service.yaml"

    log_info "Waiting for Redis to be ready..."
    kubectl wait --for=condition=ready pod -l app=redis -n "$TFE_NAMESPACE" --timeout=300s
    log_success "Redis is ready"
}

# 9. Setup Helm repo
setup_helm_repo() {
    log_step "Step 9: Setting Up Helm Repository"

    helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
    helm repo update
    log_success "Helm repository ready"
}

# 10. Deploy TFE (no --wait — pods won't start until env-secrets workaround)
deploy_tfe() {
    log_step "Step 10: Deploying Terraform Enterprise"

    if helm list -n "$TFE_NAMESPACE" 2>/dev/null | grep -q tfe; then
        log_info "TFE release exists. Upgrading..."
        helm upgrade tfe hashicorp/terraform-enterprise \
            -n "$TFE_NAMESPACE" \
            -f "$PROJECT_DIR/helm/values.yaml" \
            --timeout "$HELM_TIMEOUT"
        log_success "TFE upgraded"
    else
        log_info "Installing TFE..."
        helm install tfe hashicorp/terraform-enterprise \
            -n "$TFE_NAMESPACE" \
            -f "$PROJECT_DIR/helm/values.yaml" \
            --timeout "$HELM_TIMEOUT"
        log_success "TFE installed"
    fi
}

# 11. Helm chart env-secrets workaround
create_env_secrets_workaround() {
    log_step "Step 11: Applying Env-Secrets Workaround"

    log_info "Helm chart v1.6.5 bug: secretKeyRefs doesn't populate env-secrets"
    log_info "Recreating terraform-enterprise-env-secrets with required values..."

    # Read license content
    local license_content
    license_content=$(cat "$TFE_LICENSE_PATH")

    # Delete the empty secret created by the Helm chart
    kubectl delete secret terraform-enterprise-env-secrets -n "$TFE_NAMESPACE" 2>/dev/null || true

    # Recreate with the required values
    kubectl create secret generic terraform-enterprise-env-secrets \
        --from-literal=TFE_LICENSE="$license_content" \
        --from-literal=TFE_DATABASE_PASSWORD="$POSTGRES_PASSWORD" \
        --from-literal=TFE_REDIS_PASSWORD="$REDIS_PASSWORD" \
        --from-literal=TFE_REDIS_SIDEKIQ_PASSWORD="$REDIS_PASSWORD" \
        -n "$TFE_NAMESPACE"
    log_success "Env-secrets workaround applied"

    # Restart TFE pod to pick up the new secret
    log_info "Restarting TFE pod..."
    kubectl delete pod -l app.kubernetes.io/name=terraform-enterprise -n "$TFE_NAMESPACE" 2>/dev/null || true
    log_success "TFE pod restarted"
}

# 12. Wait for TFE readiness
wait_for_tfe() {
    log_step "Step 12: Waiting for TFE Readiness"

    log_info "TFE takes 5-10 minutes to fully initialize..."
    log_info "Waiting up to 600s for TFE pod to be ready..."

    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=terraform-enterprise \
        -n "$TFE_NAMESPACE" \
        --timeout=600s
    log_success "TFE is ready"
}

# 13. Validate health
validate_health() {
    log_step "Step 13: Validating Deployment Health"

    local all_healthy=true

    # Check pods
    log_info "Checking pods..."
    local postgres_running
    postgres_running=$(kubectl get pods -n "$TFE_NAMESPACE" -l app=postgres --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$postgres_running" -ge 1 ]; then
        log_success "PostgreSQL: Running"
    else
        log_error "PostgreSQL: Not Running"
        all_healthy=false
    fi

    local redis_running
    redis_running=$(kubectl get pods -n "$TFE_NAMESPACE" -l app=redis --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$redis_running" -ge 1 ]; then
        log_success "Redis: Running"
    else
        log_error "Redis: Not Running"
        all_healthy=false
    fi

    local tfe_running
    tfe_running=$(kubectl get pods -n "$TFE_NAMESPACE" -l app.kubernetes.io/name=terraform-enterprise --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$tfe_running" -ge 1 ]; then
        log_success "TFE: Running"
    else
        log_error "TFE: Not Running"
        all_healthy=false
    fi

    # Check PVCs
    log_info "Checking PVCs..."
    local pvcs_bound
    pvcs_bound=$(kubectl get pvc -n "$TFE_NAMESPACE" --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    local pvcs_total
    pvcs_total=$(kubectl get pvc -n "$TFE_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$pvcs_bound" -eq "$pvcs_total" ] && [ "$pvcs_total" -gt 0 ]; then
        log_success "PVCs: ${pvcs_bound}/${pvcs_total} Bound"
    else
        log_error "PVCs: ${pvcs_bound}/${pvcs_total} Bound"
        all_healthy=false
    fi

    # Check services
    log_info "Checking services..."
    for svc in postgres redis; do
        if kubectl get svc "$svc" -n "$TFE_NAMESPACE" &>/dev/null; then
            log_success "Service '$svc': exists"
        else
            log_error "Service '$svc': missing"
            all_healthy=false
        fi
    done

    # Check critical secrets
    log_info "Checking secrets..."
    for secret in postgres-credentials redis-credentials tfe-tls tfe-license terraform-enterprise-env-secrets; do
        if kubectl get secret "$secret" -n "$TFE_NAMESPACE" &>/dev/null; then
            log_success "Secret '$secret': exists"
        else
            log_error "Secret '$secret': missing"
            all_healthy=false
        fi
    done

    echo ""
    if [ "$all_healthy" = true ]; then
        log_success "All health checks passed"
    else
        log_error "Some health checks failed. Review output above."
        return 1
    fi
}

# 14. Start port-forward (only with --port-forward flag)
start_port_forward() {
    if [ "$FLAG_PORT_FORWARD" != true ]; then
        return 0
    fi

    log_step "Step 14: Starting Port Forward"

    # Kill existing port-forward if running
    if [ -f "$PF_PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PF_PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log_info "Stopping existing port-forward (PID $old_pid)..."
            kill "$old_pid" 2>/dev/null || true
        fi
        rm -f "$PF_PID_FILE"
    fi

    # Find the TFE service
    local tfe_svc
    tfe_svc=$(kubectl get svc -n "$TFE_NAMESPACE" -l app.kubernetes.io/name=terraform-enterprise -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -z "$tfe_svc" ]; then
        # Fallback: look for any service with tfe/terraform-enterprise in the name
        tfe_svc=$(kubectl get svc -n "$TFE_NAMESPACE" --no-headers 2>/dev/null | grep -i -E "tfe|terraform-enterprise" | awk '{print $1}' | head -1)
    fi

    if [ -z "$tfe_svc" ]; then
        log_error "Could not find TFE service in namespace $TFE_NAMESPACE"
        return 1
    fi

    log_info "Forwarding localhost:${LOCAL_PORT} -> ${tfe_svc}:443..."
    kubectl port-forward "svc/${tfe_svc}" "${LOCAL_PORT}:443" -n "$TFE_NAMESPACE" &>/dev/null &
    echo $! > "$PF_PID_FILE"
    sleep 2

    if kill -0 "$(cat "$PF_PID_FILE")" 2>/dev/null; then
        log_success "Port-forward running (PID $(cat "$PF_PID_FILE"))"
    else
        log_error "Port-forward failed to start"
        rm -f "$PF_PID_FILE"
        return 1
    fi
}

# 15. Print summary
print_summary() {
    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo -e "${CYAN}${BOLD}         TFE on Kind - Deployment Complete!                 ${NC}"
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo ""
    echo -e "${BOLD}Access:${NC}"
    echo -e "  URL:             ${GREEN}https://tfe.localtest.me:${LOCAL_PORT}${NC}"
    echo -e "  DNS:             tfe.localtest.me resolves to 127.0.0.1 (no /etc/hosts needed)"
    echo ""
    echo -e "${BOLD}Kubernetes:${NC}"
    echo -e "  Cluster:         ${GREEN}kind-${KIND_CLUSTER_NAME}${NC}"
    echo -e "  Namespace:       ${GREEN}${TFE_NAMESPACE}${NC}"
    echo ""
    echo -e "${BOLD}Port Forward:${NC}"
    if [ -f "$PF_PID_FILE" ] && kill -0 "$(cat "$PF_PID_FILE")" 2>/dev/null; then
        echo -e "  Status:          ${GREEN}Running (PID $(cat "$PF_PID_FILE"))${NC}"
    else
        echo -e "  Status:          ${YELLOW}Not running${NC}"
        echo -e "  Start with:      ${BLUE}./scripts/port-forward.sh${NC}"
    fi
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo -e "  Watch pods:      kubectl get pods -n ${TFE_NAMESPACE} -w"
    echo -e "  TFE logs:        kubectl logs -f -l app.kubernetes.io/name=terraform-enterprise -n ${TFE_NAMESPACE}"
    echo -e "  Port-forward:    ./scripts/port-forward.sh"
    echo -e "  Status:          ./scripts/setup-all.sh --status"
    echo -e "  Teardown:        ./scripts/setup-all.sh --teardown"
    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"

    # Handle standalone modes
    if [ "$FLAG_STATUS" = true ]; then
        show_status
        exit 0
    fi

    if [ "$FLAG_TEARDOWN" = true ]; then
        teardown
        exit 0
    fi

    # Full deployment
    echo -e "${CYAN}${BOLD}"
    echo "============================================="
    echo "    TFE on Kind - Complete Setup Script"
    echo "============================================="
    echo -e "${NC}"

    check_prerequisites
    setup_kind_cluster
    set_kubectl_context
    create_namespace
    create_secrets
    deploy_postgres
    create_tfe_pvc
    deploy_redis
    setup_helm_repo
    deploy_tfe
    create_env_secrets_workaround
    wait_for_tfe
    validate_health
    start_port_forward
    print_summary
}

main "$@"
