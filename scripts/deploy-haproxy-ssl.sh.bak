#!/bin/bash
# Robust HAProxy SSL Deployment Script
# Ensures proper SSL certificate generation and container deployment order

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INVENTORY="${INVENTORY:-local}"
ENVIRONMENT="${ENVIRONMENT:-local}"
DRY_RUN="${DRY_RUN:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
}

usage() {
    cat << EOF
HAProxy SSL Deployment Script

Usage: $0 [OPTIONS]

Options:
    -i, --inventory INVENTORY    Ansible inventory to use (default: local)
    -e, --environment ENV        Deployment environment (default: local)  
    -d, --dry-run               Show commands without executing
    -h, --help                  Show this help message

Environment Variables:
    INVENTORY                   Same as --inventory
    ENVIRONMENT                 Same as --environment
    DRY_RUN                     Same as --dry-run (true/false)

Examples:
    $0                          # Deploy to local environment
    $0 -i production -e prod    # Deploy to production
    $0 -d                       # Dry run (show commands only)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate inputs
if [[ ! -f "$PROJECT_ROOT/ansible/inventories/$INVENTORY/hosts.yml" ]]; then
    error "Inventory file not found: $PROJECT_ROOT/ansible/inventories/$INVENTORY/hosts.yml"
    exit 1
fi

log "HAProxy SSL Deployment Starting"
echo "================================"
echo "Inventory: $INVENTORY"
echo "Environment: $ENVIRONMENT"
echo "Project Root: $PROJECT_ROOT"
echo "Dry Run: $DRY_RUN"
echo ""

# Change to project directory
cd "$PROJECT_ROOT"

# Function to run Ansible commands
run_ansible() {
    local playbook="$1"
    local tags="${2:-}"
    local extra_vars="${3:-}"
    local description="$4"
    
    local cmd="ansible-playbook -i ansible/inventories/$INVENTORY/hosts.yml $playbook"
    
    if [[ -n "$tags" ]]; then
        cmd="$cmd --tags $tags"
    fi
    
    if [[ -n "$extra_vars" ]]; then
        cmd="$cmd --extra-vars '$extra_vars'"
    fi
    
    log "$description"
    echo "Command: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        success "$description completed"
        return 0
    else
        error "$description failed"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        error "ansible-playbook not found. Please install Ansible."
        return 1
    fi
    
    # Check Docker (on target host)
    if [[ "$INVENTORY" == "local" ]]; then
        if ! command -v docker &> /dev/null; then
            error "Docker not found. Please install Docker."
            return 1
        fi
        
        if ! docker info &> /dev/null; then
            error "Docker daemon not running. Please start Docker."
            return 1
        fi
    fi
    
    success "Prerequisites check passed"
    return 0
}

# Function to run troubleshooting if deployment fails
run_troubleshooting() {
    local mode="${1:-diagnose}"
    
    warning "Running HAProxy SSL troubleshooting (mode: $mode)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would run troubleshooting with mode: $mode"
        return 0
    fi
    
    ansible-playbook -i ansible/inventories/$INVENTORY/hosts.yml \
        troubleshoot-haproxy-ssl.yml \
        --extra-vars "troubleshoot_mode=$mode" || true
}

# Main deployment flow
main() {
    echo "======================================"
    echo "HAProxy SSL Deployment Process"
    echo "======================================"
    
    # Step 1: Prerequisites check
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Step 2: SSL certificate generation
    log "Phase 1: SSL Certificate Generation"
    echo "-----------------------------------"
    
    local ssl_extra_vars="ssl_enabled=true jenkins_domain=${JENKINS_DOMAIN:-192.168.86.30}"
    
    if ! run_ansible "ansible/site.yml" "ssl" "$ssl_extra_vars" "SSL certificate generation"; then
        error "SSL certificate generation failed"
        run_troubleshooting "diagnose"
        
        warning "Attempting to fix SSL issues..."
        run_troubleshooting "fix"
        
        # Retry SSL generation
        if ! run_ansible "ansible/site.yml" "ssl" "$ssl_extra_vars" "SSL certificate generation (retry)"; then
            error "SSL certificate generation retry failed"
            run_troubleshooting "recover"
            exit 1
        fi
    fi
    
    # Step 3: HAProxy configuration generation
    log "Phase 2: HAProxy Configuration"
    echo "------------------------------"
    
    local haproxy_config_vars="ssl_enabled=true"
    
    if ! run_ansible "ansible/site.yml" "configuration" "$haproxy_config_vars" "HAProxy configuration generation"; then
        error "HAProxy configuration generation failed"
        exit 1
    fi
    
    # Step 4: HAProxy container deployment
    log "Phase 3: HAProxy Container Deployment"
    echo "------------------------------------"
    
    local haproxy_deploy_vars="ssl_enabled=true"
    
    if ! run_ansible "ansible/site.yml" "haproxy,deploy" "$haproxy_deploy_vars" "HAProxy container deployment"; then
        error "HAProxy container deployment failed"
        run_troubleshooting "diagnose"
        
        warning "Attempting to fix container deployment issues..."
        run_troubleshooting "fix"
        
        # Retry container deployment
        if ! run_ansible "ansible/site.yml" "haproxy,deploy" "$haproxy_deploy_vars" "HAProxy container deployment (retry)"; then
            error "HAProxy container deployment retry failed"
            run_troubleshooting "recover"
            exit 1
        fi
    fi
    
    # Step 5: Post-deployment verification
    log "Phase 4: Post-Deployment Verification"
    echo "------------------------------------"
    
    if ! run_ansible "ansible/site.yml" "verify" "" "Post-deployment verification"; then
        warning "Post-deployment verification had issues"
        run_troubleshooting "diagnose"
    fi
    
    # Step 6: Final status report
    log "Phase 5: Final Status Report"
    echo "----------------------------"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry run completed successfully"
        echo "No actual deployment was performed."
    else
        success "HAProxy SSL deployment completed successfully!"
        
        echo ""
        echo "======================================"
        echo "Deployment Summary"
        echo "======================================"
        echo "Environment: $ENVIRONMENT"
        echo "Inventory: $INVENTORY"
        echo ""
        echo "Access Points:"
        if [[ "$INVENTORY" == "local" ]]; then
            echo "- HTTPS: https://localhost/"
            echo "- HAProxy Stats: http://localhost:8404/stats"
        else
            echo "- HTTPS: https://[your-server-ip]/"
            echo "- HAProxy Stats: http://[your-server-ip]:8404/stats"
        fi
        echo ""
        echo "Useful Commands:"
        echo "- Check container: docker ps | grep haproxy"
        echo "- View logs: docker logs jenkins-haproxy"
        echo "- Test SSL: curl -k https://localhost/"
        echo "- Troubleshoot: ansible-playbook -i ansible/inventories/$INVENTORY/hosts.yml troubleshoot-haproxy-ssl.yml"
        echo ""
        echo "For issues, run troubleshooting:"
        echo "  ./scripts/deploy-haproxy-ssl.sh --troubleshoot"
        echo "======================================"
    fi
}

# Handle troubleshooting mode
if [[ "${1:-}" == "--troubleshoot" ]]; then
    shift
    run_troubleshooting "${1:-diagnose}"
    exit 0
fi

# Execute main deployment
main

echo ""
success "HAProxy SSL deployment script completed"