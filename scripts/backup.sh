#!/bin/bash
# Jenkins HA backup automation script

set -e

# Configuration
ENVIRONMENT=${1:-production}
BACKUP_TYPE=${2:-full}  # full, incremental, config-only
INVENTORY="ansible/inventories/$ENVIRONMENT/hosts.yml"
VAULT_PASSWORD_FILE="environments/vault-passwords/.vault_pass_$ENVIRONMENT"
BACKUP_DIR="/backup/jenkins/$ENVIRONMENT"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="logs/backup_${ENVIRONMENT}_${DATE}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

# Create directories
mkdir -p logs
mkdir -p "$BACKUP_DIR"

log "Starting Jenkins backup for $ENVIRONMENT environment (type: $BACKUP_TYPE)"

# Validate environment
case "$ENVIRONMENT" in
    production|staging)
        log "Running backup for $ENVIRONMENT environment"
        ;;
    *)
        error "Unknown environment: $ENVIRONMENT. Use 'production' or 'staging'"
        ;;
esac

# Validate backup type
case "$BACKUP_TYPE" in
    full|incremental|config-only)
        log "Backup type: $BACKUP_TYPE"
        ;;
    *)
        error "Unknown backup type: $BACKUP_TYPE. Use 'full', 'incremental', or 'config-only'"
        ;;
esac

# Load environment variables
if [ -f "environments/$ENVIRONMENT.env" ]; then
    # shellcheck source=environments/production.env
    source "environments/$ENVIRONMENT.env"
fi

# Pre-backup checks
log "Running pre-backup checks..."

[ ! -f "$INVENTORY" ] && error "Inventory file not found: $INVENTORY"

# Check connectivity
log "Testing connectivity to Jenkins masters..."
if [ -f "$VAULT_PASSWORD_FILE" ]; then
    ansible jenkins_masters -i "$INVENTORY" --vault-password-file="$VAULT_PASSWORD_FILE" -m ping || error "Cannot connect to Jenkins masters"
else
    ansible jenkins_masters -i "$INVENTORY" -m ping || error "Cannot connect to Jenkins masters"
fi

# Execute backup playbook
log "Executing backup playbook..."

BACKUP_CMD="ansible-playbook -i $INVENTORY ansible/deploy-backup.yml"

# Add vault password file if exists
if [ -f "$VAULT_PASSWORD_FILE" ]; then
    BACKUP_CMD="$BACKUP_CMD --vault-password-file=$VAULT_PASSWORD_FILE"
fi

# Add extra vars
BACKUP_CMD="$BACKUP_CMD -e backup_type=$BACKUP_TYPE"
BACKUP_CMD="$BACKUP_CMD -e backup_destination=$BACKUP_DIR"
BACKUP_CMD="$BACKUP_CMD -e backup_timestamp=$DATE"
BACKUP_CMD="$BACKUP_CMD -e deployment_environment=$ENVIRONMENT"

# Execute backup
log "Executing: $BACKUP_CMD"
if eval "$BACKUP_CMD"; then
    success "Backup completed successfully!"
else
    error "Backup failed. Check logs for details."
fi

# Verify backup
log "Verifying backup integrity..."

BACKUP_FILE="$BACKUP_DIR/jenkins_${BACKUP_TYPE}_${DATE}.tar.gz"
if [ -f "$BACKUP_FILE" ]; then
    # Test archive integrity
    if tar -tzf "$BACKUP_FILE" > /dev/null 2>&1; then
        success "Backup archive integrity verified"

        # Get backup size
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        log "Backup size: $BACKUP_SIZE"

        # List backup contents
        log "Backup contents summary:"
        tar -tzf "$BACKUP_FILE" | head -20 | while read -r line; do
            log "  $line"
        done

        if [ "$(tar -tzf "$BACKUP_FILE" | wc -l)" -gt 20 ]; then
            log "  ... and $(( $(tar -tzf "$BACKUP_FILE" | wc -l) - 20 )) more files"
        fi
    else
        error "Backup archive is corrupted"
    fi
else
    error "Backup file not found: $BACKUP_FILE"
fi

# Cleanup old backups
log "Cleaning up old backups..."
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
find "$BACKUP_DIR" -name "jenkins_*.tar.gz" -mtime +$RETENTION_DAYS -delete
log "Removed backups older than $RETENTION_DAYS days"

# Generate backup report
REPORT_FILE="$BACKUP_DIR/backup_report_${DATE}.txt"
cat > "$REPORT_FILE" << EOF
Jenkins Backup Report
====================
Environment: $ENVIRONMENT
Backup Type: $BACKUP_TYPE
Timestamp: $DATE
Backup File: $BACKUP_FILE
Backup Size: $BACKUP_SIZE
Status: SUCCESS
Log File: $LOG_FILE

Backup Contents:
$(tar -tzf "$BACKUP_FILE" | head -50)
EOF

success "Backup report generated: $REPORT_FILE"
success "Backup process completed successfully!"

# Display summary
log "\n=== BACKUP SUMMARY ==="
log "Environment: $ENVIRONMENT"
log "Backup Type: $BACKUP_TYPE"
log "Backup File: $BACKUP_FILE"
log "Backup Size: $BACKUP_SIZE"
log "Report File: $REPORT_FILE"
log "Log File: $LOG_FILE"
log "======================="
