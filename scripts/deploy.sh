#!/bin/bash
# Jenkins HA deployment automation script

set -e

# Configuration
ENVIRONMENT=${1:-production}
INVENTORY="ansible/inventories/$ENVIRONMENT/hosts.yml"
PLAYBOOK="ansible/site.yml"
VAULT_PASSWORD_FILE="environments/vault-passwords/.vault_pass_$ENVIRONMENT"
LOG_FILE="logs/deploy_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Create logs directory
mkdir -p logs

log "Starting Jenkins HA deployment for $ENVIRONMENT environment"

# Validate environment
case "$ENVIRONMENT" in
    production|staging)
        log "Deploying to $ENVIRONMENT environment"
        ;;
    *)
        error "Unknown environment: $ENVIRONMENT. Use 'production' or 'staging'"
        ;;
esac

# Validate files exist
[ ! -f "$INVENTORY" ] && error "Inventory file not found: $INVENTORY"
[ ! -f "$PLAYBOOK" ] && error "Playbook not found: $PLAYBOOK"
[ ! -f "$VAULT_PASSWORD_FILE" ] && warning "Vault password file not found: $VAULT_PASSWORD_FILE"

# Load environment variables
if [ -f "environments/$ENVIRONMENT.env" ]; then
    log "Loading environment variables from environments/$ENVIRONMENT.env"
    # shellcheck source=environments/production.env
    source "environments/$ENVIRONMENT.env"
fi

# Pre-deployment checks
log "Running pre-deployment checks..."

# Check Ansible version
ansible --version > /dev/null || error "Ansible not found or not installed"

# Syntax check
log "Checking playbook syntax..."
ansible-playbook "$PLAYBOOK" --syntax-check || error "Playbook syntax check failed"

# Inventory validation
log "Validating inventory..."
ansible-inventory -i "$INVENTORY" --list > /dev/null || error "Inventory validation failed"

# Ping all hosts
log "Testing connectivity to all hosts..."
if [ -f "$VAULT_PASSWORD_FILE" ]; then
    ansible all -i "$INVENTORY" --vault-password-file="$VAULT_PASSWORD_FILE" -m ping || error "Host connectivity test failed"
else
    ansible all -i "$INVENTORY" -m ping || error "Host connectivity test failed"
fi

# Deployment
log "Starting deployment..."

DEPLOY_CMD="ansible-playbook -i $INVENTORY $PLAYBOOK"

# Add vault password file if exists
if [ -f "$VAULT_PASSWORD_FILE" ]; then
    DEPLOY_CMD="$DEPLOY_CMD --vault-password-file=$VAULT_PASSWORD_FILE"
fi

# Add extra vars
DEPLOY_CMD="$DEPLOY_CMD -e deployment_environment=$ENVIRONMENT"
DEPLOY_CMD="$DEPLOY_CMD -e ansible_ssh_pipelining=true"

# Execute deployment
log "Executing: $DEPLOY_CMD"
if eval "$DEPLOY_CMD"; then
    success "Deployment completed successfully!"
else
    error "Deployment failed. Check logs for details."
fi

# Post-deployment verification
log "Running post-deployment verification..."

# Test Jenkins accessibility
if [ -n "$JENKINS_MASTER_HOST" ]; then
    log "Testing Jenkins master accessibility..."
    timeout 30 bash -c "until curl -s http://$JENKINS_MASTER_HOST:8080/login > /dev/null; do sleep 2; done" || warning "Jenkins master not accessible"
fi

# Test monitoring
if [ "$MONITORING_ENABLED" = "true" ] && [ -n "$PROMETHEUS_HOST" ]; then
    log "Testing monitoring accessibility..."
    timeout 30 bash -c "until curl -s http://$PROMETHEUS_HOST:9090/api/v1/query?query=up > /dev/null; do sleep 2; done" || warning "Prometheus not accessible"
fi

success "Deployment and verification completed!"
log "Log file: $LOG_FILE"

# Display summary
log "\n=== DEPLOYMENT SUMMARY ==="
log "Environment: $ENVIRONMENT"
log "Inventory: $INVENTORY"
log "Playbook: $PLAYBOOK"
log "Log file: $LOG_FILE"
log "========================="
