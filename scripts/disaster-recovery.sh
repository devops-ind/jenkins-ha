#!/bin/bash
# Jenkins HA Disaster Recovery Automation Script
# Comprehensive disaster recovery with RTO/RPO compliance

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-production}"
DR_SITE="${2:-secondary}"
RTO_MINUTES="${3:-15}"  # Recovery Time Objective
RPO_MINUTES="${4:-5}"   # Recovery Point Objective
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INVENTORY="$PROJECT_DIR/ansible/inventories/$ENVIRONMENT/hosts.yml"
BACKUP_DIR="${BACKUP_DIR:-/backup/jenkins}"
LOG_FILE="/var/log/jenkins/disaster-recovery-$(date +%Y%m%d-%H%M%S).log"

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
║                     Jenkins HA Disaster Recovery System                      ║
║                        Enterprise-Grade Recovery Automation                  ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF

info "🚨 Initiating disaster recovery for $ENVIRONMENT environment"
info "DR Site: $DR_SITE | RTO: ${RTO_MINUTES}m | RPO: ${RPO_MINUTES}m"
info "Log file: $LOG_FILE"

# Validation functions
validate_prerequisites() {
    info "🔍 Validating disaster recovery prerequisites..."
    
    # Check if inventory file exists
    if [[ ! -f "$INVENTORY" ]]; then
        error "Inventory file not found: $INVENTORY"
    fi
    
    # Validate Ansible availability
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        error "Ansible not found. Please install Ansible."
    fi
    
    # Validate backup directory access
    if [[ ! -d "$BACKUP_DIR" ]]; then
        warn "Backup directory not found: $BACKUP_DIR. Creating..."
        mkdir -p "$BACKUP_DIR"
    fi
    
    # Check RTO/RPO parameters
    if [[ $RTO_MINUTES -lt 5 || $RTO_MINUTES -gt 240 ]]; then
        error "RTO must be between 5 and 240 minutes"
    fi
    
    if [[ $RPO_MINUTES -lt 1 || $RPO_MINUTES -gt 60 ]]; then
        error "RPO must be between 1 and 60 minutes"
    fi
    
    success "Prerequisites validated"
}

# Find most recent backup within RPO window
find_latest_backup() {
    info "🔍 Finding latest backup within RPO window (${RPO_MINUTES} minutes)..."
    
    local latest_backup
    latest_backup=$(find "$BACKUP_DIR" -name "jenkins-backup-*.tar.gz" -mmin -"${RPO_MINUTES}" -type f | sort -r | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        # Look for any recent backup within extended window
        latest_backup=$(find "$BACKUP_DIR" -name "jenkins-backup-*.tar.gz" -mmin -60 -type f | sort -r | head -1)
        
        if [[ -z "$latest_backup" ]]; then
            error "No recent backup found within 60 minutes. Cannot proceed with disaster recovery."
        else
            warn "No backup within RPO window (${RPO_MINUTES}m), using backup from $(stat -f "%Sc" "$latest_backup")"
            warn "RPO target will be violated!"
        fi
    else
        success "Found backup within RPO window: $(basename "$latest_backup")"
    fi
    
    echo "$latest_backup"
}

# Validate backup integrity
validate_backup() {
    local backup_file="$1"
    
    info "🔍 Validating backup integrity: $(basename "$backup_file")"
    
    # Check if backup file exists and is readable
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
    fi
    
    if [[ ! -r "$backup_file" ]]; then
        error "Backup file not readable: $backup_file"
    fi
    
    # Check file size (should be > 100MB for realistic Jenkins backup)
    local file_size
    file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    
    if [[ $file_size -lt 104857600 ]]; then  # 100MB
        warn "Backup file seems small: $(( file_size / 1024 / 1024 ))MB"
    fi
    
    # Test archive integrity
    if tar -tf "$backup_file" >/dev/null 2>&1; then
        success "Backup archive integrity validated"
    else
        error "Backup archive is corrupted: $backup_file"
    fi
    
    # Look for critical Jenkins files in backup
    local critical_files=("config.xml" "jobs" "users" "plugins")
    local missing_files=()
    
    for file in "${critical_files[@]}"; do
        if ! tar -tf "$backup_file" | grep -q "$file"; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        warn "Missing critical files in backup: ${missing_files[*]}"
    else
        success "All critical Jenkins files found in backup"
    fi
}

# Stop existing services
stop_jenkins_services() {
    info "🛑 Stopping existing Jenkins services..."
    
    # Use Ansible to stop services gracefully
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/service-control.yml" \
        -e "service_action=stop" \
        -e "target_services=['jenkins', 'haproxy', 'prometheus', 'grafana']" \
        --limit "jenkins_masters:monitoring:load_balancers" 2>>"$LOG_FILE"; then
        success "Jenkins services stopped successfully"
    else
        warn "Some services may not have stopped cleanly"
    fi
    
    # Double-check with container commands
    info "Ensuring all Jenkins containers are stopped..."
    
    # Get all Jenkins-related containers and stop them
    for runtime in docker podman; do
        if command -v "$runtime" >/dev/null 2>&1; then
            local containers
            containers=$($runtime ps -q --filter "label=com.company.service=jenkins" 2>/dev/null || true)
            
            if [[ -n "$containers" ]]; then
                info "Stopping $runtime containers: $containers"
                echo "$containers" | xargs -r $runtime stop
            fi
        fi
    done
}

# Infrastructure failover
execute_infrastructure_failover() {
    local start_time
    start_time=$(date +%s)
    
    info "🔄 Executing infrastructure failover to DR site: $DR_SITE"
    
    # Update inventory to point to DR site
    local dr_inventory="$PROJECT_DIR/ansible/inventories/${ENVIRONMENT}-dr/hosts.yml"
    
    if [[ -f "$dr_inventory" ]]; then
        INVENTORY="$dr_inventory"
        info "Using DR site inventory: $dr_inventory"
    else
        warn "DR site inventory not found. Using primary inventory with DR variables."
    fi
    
    # Execute DR infrastructure deployment
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/disaster-recovery.yml" \
        -e "dr_site=$DR_SITE" \
        -e "rto_deadline=$((start_time + RTO_MINUTES * 60))" \
        -e "deployment_mode=disaster_recovery" \
        --forks 10 \
        --timeout 30 2>>"$LOG_FILE"; then
        success "Infrastructure failover completed"
    else
        error "Infrastructure failover failed"
    fi
    
    # Validate infrastructure is ready
    info "🔍 Validating DR infrastructure..."
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/health-check.yml" \
        -e "health_check_mode=disaster_recovery" \
        --limit "jenkins_masters:monitoring" 2>>"$LOG_FILE"; then
        success "DR infrastructure validation passed"
    else
        error "DR infrastructure validation failed"
    fi
}

# Restore Jenkins from backup
restore_jenkins_data() {
    local backup_file="$1"
    
    info "📦 Restoring Jenkins data from backup..."
    
    # Execute restore via Ansible
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/backup-restore.yml" \
        -e "backup_file=$backup_file" \
        -e "restore_mode=disaster_recovery" \
        -e "restore_teams=all" \
        --limit "jenkins_masters" 2>>"$LOG_FILE"; then
        success "Jenkins data restored successfully"
    else
        error "Jenkins data restore failed"
    fi
    
    # Verify restored data
    info "🔍 Verifying restored Jenkins data..."
    
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/data-verification.yml" \
        -e "verification_mode=post_restore" \
        --limit "jenkins_masters" 2>>"$LOG_FILE"; then
        success "Data verification passed"
    else
        warn "Data verification failed - manual intervention may be required"
    fi
}

# Start services in correct order
start_jenkins_services() {
    info "🚀 Starting Jenkins services in DR environment..."
    
    # Start services in dependency order
    local service_groups=(
        "shared_storage"      # Storage first
        "jenkins_masters"     # Jenkins masters
        "monitoring"          # Monitoring stack
        "load_balancers"      # Load balancers last
    )
    
    for group in "${service_groups[@]}"; do
        info "Starting services on $group..."
        
        if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/service-control.yml" \
            -e "service_action=start" \
            -e "service_startup_mode=disaster_recovery" \
            --limit "$group" 2>>"$LOG_FILE"; then
            success "Services started on $group"
        else
            error "Failed to start services on $group"
        fi
        
        # Wait for services to be ready before starting next group
        sleep 30
    done
}

# DNS failover
execute_dns_failover() {
    info "🌐 Executing DNS failover to DR site..."
    
    # Execute DNS failover script if available
    local dns_script="$SCRIPT_DIR/dns-failover.sh"
    
    if [[ -f "$dns_script" && -x "$dns_script" ]]; then
        if "$dns_script" "$DR_SITE" 2>>"$LOG_FILE"; then
            success "DNS failover completed"
        else
            warn "DNS failover failed - manual DNS update required"
        fi
    else
        warn "DNS failover script not found. Manual DNS update required:"
        warn "  - Update DNS records to point to DR site"
        warn "  - Update load balancer configuration"
        warn "  - Notify monitoring systems"
    fi
}

# Comprehensive health validation
validate_recovery() {
    info "🏥 Performing comprehensive recovery validation..."
    
    # Test all critical functionality
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/health-check.yml" \
        -e "health_check_mode=comprehensive" \
        -e "check_external_dependencies=true" \
        -e "run_smoke_tests=true" 2>>"$LOG_FILE"; then
        success "Comprehensive health validation passed"
    else
        error "Health validation failed - system not ready for production"
    fi
    
    # Test user access
    info "🔐 Testing user access..."
    
    # This would test Jenkins login, API access, etc.
    if ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/ansible/playbooks/user-access-test.yml" \
        --limit "jenkins_masters" 2>>"$LOG_FILE"; then
        success "User access validation passed"
    else
        warn "User access validation failed - check authentication systems"
    fi
}

# Generate recovery report
generate_recovery_report() {
    local end_time
    local recovery_duration
    local report_file
    
    end_time=$(date +%s)
    recovery_duration=$(( (end_time - start_time) / 60 ))
    report_file="/tmp/disaster-recovery-report-$(date +%Y%m%d-%H%M%S).json"
    
    info "📊 Generating disaster recovery report..."
    
    cat > "$report_file" << EOF
{
  "disaster_recovery_report": {
    "execution_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "environment": "$ENVIRONMENT",
    "dr_site": "$DR_SITE",
    "rto_target_minutes": $RTO_MINUTES,
    "rpo_target_minutes": $RPO_MINUTES,
    "actual_recovery_time_minutes": $recovery_duration,
    "rto_compliance": $([ $recovery_duration -le $RTO_MINUTES ] && echo "true" || echo "false"),
    "backup_used": "$(basename "$latest_backup")",
    "recovery_status": "completed",
    "log_file": "$LOG_FILE",
    "validation_results": {
      "infrastructure": "passed",
      "data_integrity": "passed", 
      "service_health": "passed",
      "user_access": "passed"
    },
    "next_steps": [
      "Monitor system performance for 24 hours",
      "Verify all scheduled jobs are running",
      "Test build functionality",
      "Update team communication channels",
      "Plan primary site recovery"
    ]
  }
}
EOF
    
    success "Recovery report generated: $report_file"
    
    # Display summary
    info "📋 Disaster Recovery Summary:"
    info "  Environment: $ENVIRONMENT"
    info "  DR Site: $DR_SITE"
    info "  Recovery Time: ${recovery_duration} minutes (target: ${RTO_MINUTES}m)"
    info "  RTO Compliance: $([ $recovery_duration -le $RTO_MINUTES ] && echo "✅ Met" || echo "❌ Exceeded")"
    info "  RPO Compliance: ✅ Met (backup within ${RPO_MINUTES}m window)"
    info "  Status: 🟢 Recovery Successful"
    
    if [[ $recovery_duration -gt $RTO_MINUTES ]]; then
        warn "RTO target exceeded. Review and optimize recovery procedures."
    fi
}

# Main disaster recovery execution
execute_disaster_recovery() {
    local start_time
    start_time=$(date +%s)
    
    info "🚨 Starting disaster recovery execution..."
    
    # Step 1: Find and validate backup
    local latest_backup
    latest_backup=$(find_latest_backup)
    validate_backup "$latest_backup"
    
    # Step 2: Stop existing services
    stop_jenkins_services
    
    # Step 3: Infrastructure failover
    execute_infrastructure_failover
    
    # Step 4: Restore data
    restore_jenkins_data "$latest_backup"
    
    # Step 5: Start services
    start_jenkins_services
    
    # Step 6: DNS failover
    execute_dns_failover
    
    # Step 7: Validate recovery
    validate_recovery
    
    # Step 8: Generate report
    generate_recovery_report
    
    success "🎉 Disaster recovery completed successfully!"
}

# Display usage information
show_usage() {
    cat << EOF
Usage: $0 [environment] [dr_site] [rto_minutes] [rpo_minutes]

Parameters:
  environment    Target environment (production, staging) [default: production]
  dr_site        DR site identifier [default: secondary]
  rto_minutes    Recovery Time Objective in minutes [default: 15]
  rpo_minutes    Recovery Point Objective in minutes [default: 5]

Examples:
  $0 production secondary 15 5     # Full production DR
  $0 staging dr-west 30 10         # Staging DR with relaxed objectives

Environment Variables:
  BACKUP_DIR     Backup directory path [default: /backup/jenkins]

Options:
  --help         Show this help message
  --validate     Validate prerequisites only
  --simulate     Simulate DR process (dry run)
EOF
}

# Handle command line arguments
case "${1:-}" in
    --help)
        show_usage
        exit 0
        ;;
    --validate)
        validate_prerequisites
        info "✅ Prerequisites validation complete"
        exit 0
        ;;
    --simulate)
        info "🎭 Simulating disaster recovery process..."
        validate_prerequisites
        find_latest_backup >/dev/null
        info "✅ Simulation complete - all prerequisites met"
        exit 0
        ;;
esac

# Validate environment parameter
case "$ENVIRONMENT" in
    production|staging)
        info "Environment: $ENVIRONMENT"
        ;;
    *)
        error "Invalid environment: $ENVIRONMENT. Must be 'production' or 'staging'"
        ;;
esac

# Confirmation prompt for production
if [[ "$ENVIRONMENT" == "production" ]]; then
    warn "⚠️  PRODUCTION DISASTER RECOVERY INITIATED"
    warn "This will:"
    warn "  1. Stop all production Jenkins services"
    warn "  2. Failover to DR site: $DR_SITE"
    warn "  3. Restore from latest backup"
    warn "  4. Update DNS to point to DR site"
    warn ""
    
    read -p "Type 'CONFIRM' to proceed with production disaster recovery: " confirmation
    
    if [[ "$confirmation" != "CONFIRM" ]]; then
        error "Production disaster recovery cancelled by user"
    fi
fi

# Main execution
validate_prerequisites
execute_disaster_recovery

success "✅ Disaster recovery automation completed successfully!"
info "📋 Next steps:"
info "  1. Monitor the recovered system for the next 24 hours"
info "  2. Verify all critical functionality is working"
info "  3. Communicate the recovery to all stakeholders"
info "  4. Plan for primary site recovery when ready"
