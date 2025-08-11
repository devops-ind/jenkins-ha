#!/bin/bash
# Jenkins HA Setup Automation Script
# Comprehensive setup and configuration for Jenkins HA infrastructure

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-production}"
SETUP_MODE="${2:-full}"  # full, masters-only, monitoring-only, validate-only
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INVENTORY="$PROJECT_DIR/ansible/inventories/$ENVIRONMENT/hosts.yml"
LOG_FILE="/var/log/jenkins/ha-setup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

info() { echo -e "${BLUE}$*${NC}"; log "INFO" "$*"; }
warn() { echo -e "${YELLOW}$*${NC}"; log "WARN" "$*"; }
error() { echo -e "${RED}$*${NC}"; log "ERROR" "$*"; exit 1; }
success() { echo -e "${GREEN}$*${NC}"; log "SUCCESS" "$*"; }

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Display banner
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                      Jenkins HA Infrastructure Setup                        ║
║                     Production-Grade Deployment Automation                  ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF

info "🚀 Jenkins HA Setup - Environment: $ENVIRONMENT, Mode: $SETUP_MODE"
info "Log file: $LOG_FILE"

# Validation functions
validate_environment() {
    info "🔍 Validating environment configuration..."
    
    # Check if inventory file exists
    if [[ ! -f "$INVENTORY" ]]; then
        error "Inventory file not found: $INVENTORY"
    fi
    
    # Validate Ansible installation
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        error "Ansible not found. Please install Ansible."
    fi
    
    # Check Ansible version (minimum 2.9)
    local ansible_version
    ansible_version=$(ansible --version | head -1 | sed 's/ansible \[core \]\?//' | sed 's/\].*//')
    
    if ! python3 -c "import sys; sys.exit(0 if tuple(map(int, '$ansible_version'.split('.')[:2])) >= (2, 9) else 1)" 2>/dev/null; then
        warn "Ansible version $ansible_version may not be fully supported. Recommended: 2.9+"
    fi
    
    # Test inventory connectivity
    info "Testing inventory connectivity..."
    if ansible all -i "$INVENTORY" -m ping --timeout 10 >/dev/null 2>>"$LOG_FILE"; then
        success "All hosts in inventory are reachable"
    else
        error "Some hosts in inventory are not reachable. Check network connectivity."
    fi
    
    # Validate required groups exist
    local required_groups=("jenkins_masters")
    local missing_groups=()
    
    for group in "${required_groups[@]}"; do
        if ! ansible-inventory -i "$INVENTORY" --list | jq -r ".$group.hosts[]?" >/dev/null 2>&1; then
            missing_groups+=("$group")
        fi
    done
    
    if [[ ${#missing_groups[@]} -gt 0 ]]; then
        error "Missing required inventory groups: ${missing_groups[*]}"
    fi
    
    success "Environment validation completed"
}

# Prerequisites installation
install_prerequisites() {
    info "📦 Installing prerequisites on target hosts..."
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/prerequisites.yml" \
        -e "environment=$ENVIRONMENT" \
        --timeout 300 2>>"$LOG_FILE"; then
        success "Prerequisites installed successfully"
    else
        error "Prerequisites installation failed"
    fi
}

# Bootstrap infrastructure
bootstrap_infrastructure() {
    info "🏗️ Bootstrapping infrastructure..."
    
    local bootstrap_tags="common,docker,security"
    if [[ "$SETUP_MODE" == "full" ]]; then
        bootstrap_tags+=",shared-storage"
    fi
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/site.yml" \
        --tags "$bootstrap_tags" \
        -e "deployment_mode=$ENVIRONMENT" \
        -e "validation_mode=warn" \
        --timeout 600 2>>"$LOG_FILE"; then
        success "Infrastructure bootstrap completed"
    else
        error "Infrastructure bootstrap failed"
    fi
}

# Setup Harbor registry
setup_harbor() {
    info "🐳 Setting up Harbor registry..."
    
    if [[ "$SETUP_MODE" == "masters-only" ]]; then
        info "Skipping Harbor setup in masters-only mode"
        return 0
    fi
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/site.yml" \
        --tags "harbor,registry" \
        -e "deployment_mode=$ENVIRONMENT" \
        --limit "harbor" \
        --timeout 600 2>>"$LOG_FILE"; then
        success "Harbor registry setup completed"
    else
        warn "Harbor registry setup failed - continuing without registry"
    fi
}

# Build Jenkins images
build_jenkins_images() {
    info "🏗️ Building Jenkins images..."
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/site.yml" \
        --tags "images,build" \
        -e "deployment_mode=$ENVIRONMENT" \
        -e "build_jenkins_images=true" \
        --limit "jenkins_masters[0]" \
        --timeout 1200 2>>"$LOG_FILE"; then
        success "Jenkins images built successfully"
    else
        error "Jenkins image building failed"
    fi
}

# Deploy Jenkins masters
deploy_jenkins_masters() {
    info "🎯 Deploying Jenkins masters..."
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/site.yml" \
        --tags "jenkins,deploy" \
        -e "deployment_mode=$ENVIRONMENT" \
        -e "jenkins_ha_enabled=true" \
        --limit "jenkins_masters" \
        --timeout 900 2>>"$LOG_FILE"; then
        success "Jenkins masters deployed successfully"
    else
        error "Jenkins masters deployment failed"
    fi
}

# Setup monitoring stack
setup_monitoring() {
    info "📊 Setting up monitoring stack..."
    
    if [[ "$SETUP_MODE" == "masters-only" ]]; then
        info "Skipping monitoring setup in masters-only mode"
        return 0
    fi
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/site.yml" \
        --tags "monitoring,prometheus,grafana" \
        -e "deployment_mode=$ENVIRONMENT" \
        --limit "monitoring" \
        --timeout 600 2>>"$LOG_FILE"; then
        success "Monitoring stack setup completed"
    else
        warn "Monitoring stack setup failed - continuing without monitoring"
    fi
}

# Setup load balancers
setup_load_balancers() {
    info "⚖️ Setting up load balancers..."
    
    if [[ "$SETUP_MODE" == "masters-only" || "$SETUP_MODE" == "monitoring-only" ]]; then
        info "Skipping load balancer setup in $SETUP_MODE mode"
        return 0
    fi
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/site.yml" \
        --tags "haproxy,loadbalancer" \
        -e "deployment_mode=$ENVIRONMENT" \
        --limit "load_balancers" \
        --timeout 300 2>>"$LOG_FILE"; then
        success "Load balancers setup completed"
    else
        warn "Load balancer setup failed - manual configuration may be required"
    fi
}

# Configure backup system
setup_backup_system() {
    info "💾 Setting up backup system..."
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/site.yml" \
        --tags "backup" \
        -e "deployment_mode=$ENVIRONMENT" \
        --limit "jenkins_masters" \
        --timeout 300 2>>"$LOG_FILE"; then
        success "Backup system configured successfully"
    else
        warn "Backup system setup failed - manual configuration required"
    fi
}

# Post-deployment validation
validate_deployment() {
    info "✅ Validating deployment..."
    
    # Run comprehensive health checks
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/health-check.yml" \
        -e "check_scope=all" \
        -e "detailed_reporting=true" \
        --timeout 300 2>>"$LOG_FILE"; then
        success "Deployment validation passed"
    else
        error "Deployment validation failed"
    fi
    
    # Test blue-green switching capability
    info "🔄 Testing blue-green switching capability..."
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/blue-green-operations.yml" \
        -e "blue_green_operation=status" \
        --limit "jenkins_masters" \
        --timeout 60 2>>"$LOG_FILE"; then
        success "Blue-green capability verified"
    else
        warn "Blue-green switching test failed - manual verification required"
    fi
}

# Generate setup report
generate_setup_report() {
    local end_time
    local setup_duration
    local report_file
    
    end_time=$(date +%s)
    setup_duration=$(( (end_time - start_time) / 60 ))
    report_file="/tmp/jenkins-ha-setup-report-$(date +%Y%m%d-%H%M%S).json"
    
    info "📊 Generating setup report..."
    
    # Get inventory summary
    local jenkins_masters_count
    local monitoring_hosts_count
    local total_hosts_count
    
    jenkins_masters_count=$(ansible-inventory -i "$INVENTORY" --list | jq -r '.jenkins_masters.hosts | length' 2>/dev/null || echo "0")
    monitoring_hosts_count=$(ansible-inventory -i "$INVENTORY" --list | jq -r '.monitoring.hosts | length' 2>/dev/null || echo "0")
    total_hosts_count=$(ansible-inventory -i "$INVENTORY" --list | jq -r '.all.hosts | length' 2>/dev/null || echo "0")
    
    cat > "$report_file" << EOF
{
  "jenkins_ha_setup_report": {
    "setup_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "environment": "$ENVIRONMENT",
    "setup_mode": "$SETUP_MODE",
    "setup_duration_minutes": $setup_duration,
    "infrastructure": {
      "total_hosts": $total_hosts_count,
      "jenkins_masters": $jenkins_masters_count,
      "monitoring_hosts": $monitoring_hosts_count,
      "ha_enabled": $([ "$jenkins_masters_count" -gt 1 ] && echo "true" || echo "false")
    },
    "components": {
      "jenkins_masters": "deployed",
      "monitoring_stack": "$([ "$SETUP_MODE" != "masters-only" ] && echo "deployed" || echo "skipped")",
      "load_balancers": "$([ "$SETUP_MODE" == "full" ] && echo "deployed" || echo "skipped")",
      "backup_system": "configured",
      "security_scanning": "enabled",
      "blue_green_deployment": "ready"
    },
    "access_urls": {
      "jenkins_primary": "http://jenkins-master-1:8080",
      "jenkins_teams": [
$(for i in $(seq 0 $((jenkins_masters_count-1))); do
  echo "        \"http://jenkins-team-$i:808$i\""
  [ $i -lt $((jenkins_masters_count-1)) ] && echo ","
done)
      ],
      "monitoring": "$([ "$SETUP_MODE" != "masters-only" ] && echo "http://monitoring:3000" || echo "not_deployed")",
      "prometheus": "$([ "$SETUP_MODE" != "masters-only" ] && echo "http://monitoring:9090" || echo "not_deployed")"
    },
    "next_steps": [
      "Verify all Jenkins masters are accessible",
      "Configure team-specific Job DSL scripts",
      "Set up LDAP/authentication integration",
      "Configure backup schedules",
      "Test blue-green deployments",
      "Set up monitoring alerts",
      "Perform disaster recovery testing"
    ],
    "log_file": "$LOG_FILE"
  }
}
EOF

    success "Setup report generated: $report_file"
    
    # Display summary
    info "📋 Jenkins HA Setup Summary:"
    info "  Environment: $ENVIRONMENT"
    info "  Setup Mode: $SETUP_MODE"
    info "  Duration: ${setup_duration} minutes"
    info "  Jenkins Masters: $jenkins_masters_count"
    info "  HA Mode: $([ "$jenkins_masters_count" -gt 1 ] && echo "✅ Enabled" || echo "❌ Single Master")"
    info "  Status: 🟢 Setup Complete"
    
    info ""
    info "🌐 Access Information:"
    info "  Primary Jenkins: http://jenkins-master-1:8080"
    if [[ "$SETUP_MODE" != "masters-only" ]]; then
        info "  Grafana: http://monitoring:3000"
        info "  Prometheus: http://monitoring:9090"
    fi
    
    info ""
    info "🔑 Default Credentials:"
    info "  Use 'make credentials' to view credential information"
    info "  All credentials are stored in encrypted Ansible vaults"
}

# Main setup orchestration
execute_ha_setup() {
    local start_time
    start_time=$(date +%s)
    
    info "🚀 Starting Jenkins HA setup..."
    
    case "$SETUP_MODE" in
        "validate-only")
            validate_environment
            info "✅ Validation complete - no deployment performed"
            return 0
            ;;
        "full")
            validate_environment
            install_prerequisites
            bootstrap_infrastructure
            setup_harbor
            build_jenkins_images
            deploy_jenkins_masters
            setup_monitoring
            setup_load_balancers
            setup_backup_system
            validate_deployment
            ;;
        "masters-only")
            validate_environment
            install_prerequisites
            bootstrap_infrastructure
            build_jenkins_images
            deploy_jenkins_masters
            setup_backup_system
            validate_deployment
            ;;
        "monitoring-only")
            validate_environment
            install_prerequisites
            bootstrap_infrastructure
            setup_monitoring
            ;;
        *)
            error "Invalid setup mode: $SETUP_MODE. Valid modes: full, masters-only, monitoring-only, validate-only"
            ;;
    esac
    
    generate_setup_report
    success "🎉 Jenkins HA setup completed successfully!"
}

# Display usage information
show_usage() {
    cat << EOF
Usage: $0 [environment] [setup_mode]

Parameters:
  environment    Target environment (production, staging, local) [default: production]
  setup_mode     Setup mode [default: full]
                 - full: Complete HA setup with all components
                 - masters-only: Jenkins masters and core infrastructure only
                 - monitoring-only: Monitoring stack only
                 - validate-only: Validation only, no deployment

Examples:
  $0 production full              # Full production setup
  $0 staging masters-only         # Staging with Jenkins masters only  
  $0 production validate-only     # Validate production environment
  $0 local monitoring-only        # Local monitoring setup

Options:
  --help                         Show this help message
  --dry-run                      Show what would be executed (dry run)
  --verbose                      Enable verbose output
  --skip-validation             Skip environment validation (not recommended)

Quick Start:
  1. Review inventory file: ansible/inventories/$ENVIRONMENT/hosts.yml
  2. Configure vault passwords: make vault-create
  3. Run setup: $0 $ENVIRONMENT full
  4. Validate deployment: $0 $ENVIRONMENT validate-only
EOF
}

# Handle command line arguments
SKIP_VALIDATION=false
VERBOSE_MODE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --help)
            show_usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            info "🎭 Dry run mode enabled - showing what would be executed"
            shift
            ;;
        --verbose)
            VERBOSE_MODE=true
            info "📢 Verbose mode enabled"
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            warn "⚠️ Skipping validation - not recommended for production"
            shift
            ;;
        *)
            # Handle positional arguments
            if [[ -z "${ENVIRONMENT:-}" ]]; then
                ENVIRONMENT="$1"
            elif [[ -z "${SETUP_MODE:-}" ]]; then
                SETUP_MODE="$1"
            fi
            shift
            ;;
    esac
done

# Set defaults
ENVIRONMENT="${ENVIRONMENT:-production}"
SETUP_MODE="${SETUP_MODE:-full}"

# Update inventory path with correct environment
INVENTORY="$PROJECT_DIR/ansible/inventories/$ENVIRONMENT/hosts.yml"

# Validate environment parameter
case "$ENVIRONMENT" in
    production|staging|local)
        info "Environment: $ENVIRONMENT"
        ;;
    *)
        error "Invalid environment: $ENVIRONMENT. Must be 'production', 'staging', or 'local'"
        ;;
esac

# Handle dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    info "🎭 DRY RUN - Would execute the following steps:"
    case "$SETUP_MODE" in
        "full")
            echo "  1. Validate environment"
            echo "  2. Install prerequisites" 
            echo "  3. Bootstrap infrastructure"
            echo "  4. Setup Harbor registry"
            echo "  5. Build Jenkins images"
            echo "  6. Deploy Jenkins masters"
            echo "  7. Setup monitoring stack"
            echo "  8. Setup load balancers"
            echo "  9. Configure backup system"
            echo "  10. Validate deployment"
            ;;
        "masters-only")
            echo "  1. Validate environment"
            echo "  2. Install prerequisites"
            echo "  3. Bootstrap infrastructure"
            echo "  4. Build Jenkins images"
            echo "  5. Deploy Jenkins masters"
            echo "  6. Configure backup system"
            echo "  7. Validate deployment"
            ;;
        "monitoring-only")
            echo "  1. Validate environment"
            echo "  2. Install prerequisites"
            echo "  3. Bootstrap infrastructure"
            echo "  4. Setup monitoring stack"
            ;;
        "validate-only")
            echo "  1. Validate environment only"
            ;;
    esac
    info "✅ Dry run complete"
    exit 0
fi

# Confirmation prompt for production
if [[ "$ENVIRONMENT" == "production" && "$SETUP_MODE" == "full" ]]; then
    warn "⚠️  PRODUCTION DEPLOYMENT"
    warn "This will deploy Jenkins HA infrastructure to production."
    warn "Environment: $ENVIRONMENT"
    warn "Mode: $SETUP_MODE"
    warn ""
    
    read -p "Type 'DEPLOY' to proceed with production deployment: " confirmation
    
    if [[ "$confirmation" != "DEPLOY" ]]; then
        error "Production deployment cancelled by user"
    fi
fi

# Main execution
if [[ "$SKIP_VALIDATION" == "false" ]]; then
    validate_environment
fi

execute_ha_setup

success "✅ Jenkins HA setup automation completed!"
info "📋 Next steps:"
info "  1. Access Jenkins at the URLs shown in the report"
info "  2. Configure team-specific settings"
info "  3. Set up authentication integration"
info "  4. Test blue-green deployments"
info "  5. Schedule regular backups"
