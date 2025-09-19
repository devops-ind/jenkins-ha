#!/bin/bash

# backup-active-to-nfs.sh - Simplified backup of critical data from active Jenkins volume to NFS
# This script eliminates shared storage complexity and focuses on critical data only

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/nfs/jenkins-backup}"
LOG_FILE="${LOG_FILE:-/var/log/jenkins-backup.log}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Team configuration - can be overridden via environment
JENKINS_TEAMS="${JENKINS_TEAMS:-devops ma ba tw}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$*"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$*"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$*"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$*"
    echo -e "${RED}❌ $*${NC}"
}

# Function to get active environment for a team
get_active_environment() {
    local team="$1"
    local inventory_file="${SCRIPT_DIR}/../ansible/inventories/production/group_vars/all/main.yml"
    
    if [[ -f "$inventory_file" ]]; then
        # Extract active environment from team configuration
        local active_env=$(grep -A 10 "team_name: \"$team\"" "$inventory_file" | \
                          grep "active_environment:" | \
                          head -1 | \
                          sed 's/.*active_environment: "\([^"]*\)".*/\1/')
        echo "${active_env:-blue}"
    else
        log_warning "Inventory file not found, defaulting to blue environment"
        echo "blue"
    fi
}

# Function to check if container exists and is running
check_container_status() {
    local container_name="$1"
    
    if ! docker container inspect "$container_name" >/dev/null 2>&1; then
        log_error "Container $container_name does not exist"
        return 1
    fi
    
    local status=$(docker container inspect "$container_name" --format '{{.State.Status}}')
    if [[ "$status" != "running" ]]; then
        log_error "Container $container_name is not running (status: $status)"
        return 1
    fi
    
    return 0
}

# Function to backup critical data for a team
backup_team_data() {
    local team="$1"
    local active_env
    active_env=$(get_active_environment "$team")
    
    local container_name="jenkins-${team}-${active_env}"
    local backup_dir="${BACKUP_BASE_DIR}/${team}/${BACKUP_DATE}"
    
    log_info "Starting backup for team: $team (active environment: $active_env)"
    
    # Check container status
    if ! check_container_status "$container_name"; then
        log_error "Skipping backup for team $team - container issues"
        return 1
    fi
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Define critical data paths (only data that cannot be recreated from code)
    local critical_paths=(
        "secrets"           # Encrypted credentials
        "userContent"       # User-uploaded files
        "config.xml"        # Jenkins system configuration
        "jenkins.model.JenkinsLocationConfiguration.xml"
        "credentials.xml"   # Credential configurations
        "users"            # User configurations
    )
    
    log_info "Creating backup archive for critical data..."
    
    # Create temporary script for container execution
    local temp_script="/tmp/backup_script_${team}_${BACKUP_DATE}.sh"
    cat > "$temp_script" << 'EOF'
#!/bin/bash
set -e
cd /var/jenkins_home
tar czf /tmp/critical-backup.tar.gz \
    --ignore-failed-read \
    secrets/ \
    userContent/ \
    config.xml \
    jenkins.model.JenkinsLocationConfiguration.xml \
    credentials.xml \
    users/ \
    2>/dev/null || true
EOF
    
    # Execute backup inside container
    if docker cp "$temp_script" "$container_name:/tmp/backup_script.sh" && \
       docker exec "$container_name" chmod +x /tmp/backup_script.sh && \
       docker exec "$container_name" /tmp/backup_script.sh; then
        
        # Copy backup file from container
        if docker cp "$container_name:/tmp/critical-backup.tar.gz" "$backup_dir/critical-data-${team}-${BACKUP_DATE}.tar.gz"; then
            log_success "Critical data backup completed for team $team"
            
            # Get backup file size
            local backup_size=$(du -h "$backup_dir/critical-data-${team}-${BACKUP_DATE}.tar.gz" | cut -f1)
            log_info "Backup size: $backup_size"
            
            # Create backup metadata
            cat > "$backup_dir/backup-metadata.json" << EOF
{
    "team": "$team",
    "active_environment": "$active_env",
    "backup_date": "$BACKUP_DATE",
    "backup_type": "critical-data",
    "container_name": "$container_name",
    "backup_size": "$backup_size",
    "script_version": "1.0.0"
}
EOF
            
            # Cleanup container temporary files
            docker exec "$container_name" rm -f /tmp/backup_script.sh /tmp/critical-backup.tar.gz
            
        else
            log_error "Failed to copy backup file from container for team $team"
            return 1
        fi
    else
        log_error "Failed to create backup inside container for team $team"
        return 1
    fi
    
    # Cleanup temporary script
    rm -f "$temp_script"
    
    return 0
}

# Function to cleanup old backups
cleanup_old_backups() {
    local team="$1"
    local team_backup_dir="${BACKUP_BASE_DIR}/${team}"
    
    if [[ -d "$team_backup_dir" ]]; then
        log_info "Cleaning up backups older than $RETENTION_DAYS days for team $team"
        find "$team_backup_dir" -type d -name "????????_??????" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
    fi
}

# Function to verify backup integrity
verify_backup() {
    local backup_file="$1"
    local team="$2"
    
    log_info "Verifying backup integrity for team $team"
    
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_success "Backup verification passed for team $team"
        return 0
    else
        log_error "Backup verification failed for team $team"
        return 1
    fi
}

# Main backup function
main() {
    log_info "Starting simplified Jenkins backup process"
    log_info "Backup date: $BACKUP_DATE"
    log_info "Target directory: $BACKUP_BASE_DIR"
    
    # Create base backup directory
    mkdir -p "$BACKUP_BASE_DIR"
    
    local success_count=0
    local total_count=0
    
    # Process each team
    for team in $JENKINS_TEAMS; do
        total_count=$((total_count + 1))
        
        log_info "Processing team: $team"
        
        if backup_team_data "$team"; then
            local backup_file="${BACKUP_BASE_DIR}/${team}/${BACKUP_DATE}/critical-data-${team}-${BACKUP_DATE}.tar.gz"
            
            if verify_backup "$backup_file" "$team"; then
                success_count=$((success_count + 1))
                cleanup_old_backups "$team"
            else
                log_error "Backup verification failed for team $team"
            fi
        else
            log_error "Backup failed for team $team"
        fi
        
        echo "---"
    done
    
    # Summary
    log_info "Backup process completed"
    log_info "Successful backups: $success_count/$total_count"
    
    if [[ $success_count -eq $total_count ]]; then
        log_success "All team backups completed successfully"
        exit 0
    else
        log_error "Some backups failed. Check logs for details."
        exit 1
    fi
}

# Script usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Simple backup script for Jenkins critical data to NFS storage.
Eliminates shared storage complexity and focuses on critical data only.

OPTIONS:
    -t, --teams TEAMS       Space-separated list of teams (default: $JENKINS_TEAMS)
    -d, --backup-dir DIR    Backup base directory (default: $BACKUP_BASE_DIR)
    -r, --retention DAYS    Retention period in days (default: $RETENTION_DAYS)
    -l, --log-file FILE     Log file path (default: $LOG_FILE)
    -h, --help              Show this help message

EXAMPLES:
    $0                                          # Backup all teams with defaults
    $0 -t "devops ma" -r 14                     # Backup specific teams with 14-day retention
    $0 -d /custom/backup/path                   # Use custom backup directory

CRITICAL DATA BACKED UP:
    - secrets/                 (Encrypted credentials)
    - userContent/             (User-uploaded files)
    - config.xml              (Jenkins system configuration)
    - credentials.xml         (Credential configurations)
    - users/                  (User configurations)

DATA NOT BACKED UP (recreatable from code):
    - jobs/                   (Recreated from seed jobs)
    - workspace/              (Ephemeral build workspaces)
    - builds/                 (Build history - acceptable loss)
    - plugins/                (Managed via code)
    - logs/                   (Historical logs)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--teams)
            JENKINS_TEAMS="$2"
            shift 2
            ;;
        -d|--backup-dir)
            BACKUP_BASE_DIR="$2"
            shift 2
            ;;
        -r|--retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        -l|--log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Run main function
main "$@"