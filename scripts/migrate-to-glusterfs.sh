#!/bin/bash
# Migration Script: Local/NFS Storage to GlusterFS
# Purpose: Migrate existing Jenkins data to GlusterFS replicated storage
# Usage: ./migrate-to-glusterfs.sh [--dry-run] [--team TEAM_NAME] [--backup-path PATH]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DRY_RUN=false
TARGET_TEAM=""
BACKUP_PATH="/opt/jenkins-migration-backup"
SOURCE_STORAGE_TYPE="local"
SOURCE_STORAGE_PATH="/opt/jenkins-shared"
GLUSTERFS_MOUNT_BASE="/var/jenkins"
ANSIBLE_INVENTORY="ansible/inventories/production/hosts.yml"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --team)
            TARGET_TEAM="$2"
            shift 2
            ;;
        --backup-path)
            BACKUP_PATH="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run              Preview migration without making changes"
            echo "  --team TEAM_NAME       Migrate specific team only"
            echo "  --backup-path PATH     Custom backup location (default: /opt/jenkins-migration-backup)"
            echo "  --help                 Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --dry-run                    # Preview migration"
            echo "  $0 --team devops                # Migrate devops team only"
            echo "  $0 --backup-path /backup/jenkins # Use custom backup path"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Check if ansible is available
    if ! command -v ansible &> /dev/null; then
        log_error "Ansible is not installed"
        exit 1
    fi

    # Check if gluster is available
    if ! command -v gluster &> /dev/null; then
        log_warning "GlusterFS client not installed - will be installed during migration"
    fi

    # Check source storage exists
    if [[ ! -d "$SOURCE_STORAGE_PATH" ]]; then
        log_error "Source storage path does not exist: $SOURCE_STORAGE_PATH"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

get_jenkins_teams() {
    log_info "Discovering Jenkins teams..."

    # Extract team names from ansible inventory
    TEAMS=$(ansible-inventory -i "$ANSIBLE_INVENTORY" --list | \
            python3 -c "import sys, json; data=json.load(sys.stdin); \
            teams = data.get('_meta', {}).get('hostvars', {}).get('localhost', {}).get('jenkins_teams', []); \
            print(' '.join([t['team_name'] for t in teams]))" 2>/dev/null || echo "")

    if [[ -z "$TEAMS" ]]; then
        # Fallback: discover from directory structure
        TEAMS=$(find "$SOURCE_STORAGE_PATH" -maxdepth 1 -type d -printf '%f\n' | grep -v "^\\." | grep -v "backup" | grep -v "scripts" || echo "")
    fi

    if [[ -z "$TEAMS" ]]; then
        log_error "No teams found in $SOURCE_STORAGE_PATH"
        exit 1
    fi

    log_info "Found teams: $TEAMS"
    echo "$TEAMS"
}

calculate_disk_usage() {
    local path=$1
    du -sh "$path" 2>/dev/null | awk '{print $1}' || echo "unknown"
}

backup_existing_data() {
    local team=$1
    local source_path="$SOURCE_STORAGE_PATH/$team"

    if [[ ! -d "$source_path" ]]; then
        log_warning "Source path does not exist: $source_path"
        return
    fi

    log_info "Backing up $team data..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would backup: $source_path -> $BACKUP_PATH/${team}_${TIMESTAMP}.tar.gz"
        return
    fi

    mkdir -p "$BACKUP_PATH"

    local backup_file="$BACKUP_PATH/${team}_${TIMESTAMP}.tar.gz"
    tar -czf "$backup_file" -C "$SOURCE_STORAGE_PATH" "$team" 2>&1 | grep -v "Removing leading" || true

    if [[ -f "$backup_file" ]]; then
        local backup_size=$(du -sh "$backup_file" | awk '{print $1}')
        log_success "Backup created: $backup_file (Size: $backup_size)"
    else
        log_error "Backup failed for $team"
        exit 1
    fi
}

setup_glusterfs() {
    log_info "Setting up GlusterFS infrastructure..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ansible-playbook ansible/site.yml --tags glusterfs"
        return
    fi

    log_info "Running GlusterFS setup via Ansible..."
    ansible-playbook -i "$ANSIBLE_INVENTORY" ansible/site.yml --tags glusterfs -e "shared_storage_type=glusterfs"

    if [[ $? -eq 0 ]]; then
        log_success "GlusterFS setup completed"
    else
        log_error "GlusterFS setup failed"
        exit 1
    fi
}

migrate_team_data() {
    local team=$1
    local source_path="$SOURCE_STORAGE_PATH/$team"
    local target_path="$GLUSTERFS_MOUNT_BASE/$team/data"

    log_info "Migrating $team data..."
    log_info "  Source: $source_path"
    log_info "  Target: $target_path"

    if [[ ! -d "$source_path" ]]; then
        log_warning "No data to migrate for team: $team"
        return
    fi

    local source_size=$(calculate_disk_usage "$source_path")
    log_info "  Size: $source_size"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would migrate: $source_path -> $target_path"
        log_info "[DRY-RUN] Would set ownership: 1000:1000"
        return
    fi

    # Ensure target directory exists
    mkdir -p "$target_path"

    # Sync data using rsync for reliability
    log_info "Syncing data (this may take a while)..."
    rsync -avz --progress "$source_path/" "$target_path/" 2>&1 | tail -n 5

    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        log_success "Data synced successfully"
    else
        log_error "Data sync failed"
        exit 1
    fi

    # Set correct ownership
    chown -R 1000:1000 "$target_path"
    log_success "Ownership set to jenkins (1000:1000)"

    # Verify migration
    local target_size=$(calculate_disk_usage "$target_path")
    log_info "Target size after migration: $target_size"

    log_success "Migration completed for team: $team"
}

stop_jenkins_containers() {
    log_info "Stopping Jenkins containers..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would stop Jenkins containers"
        return
    fi

    docker ps --filter "name=jenkins-" --format "{{.Names}}" | while read -r container; do
        log_info "Stopping container: $container"
        docker stop "$container" || true
    done

    log_success "Jenkins containers stopped"
}

start_jenkins_containers() {
    log_info "Starting Jenkins containers with GlusterFS storage..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would start Jenkins containers"
        return
    fi

    log_info "Running Jenkins deployment via Ansible..."
    ansible-playbook -i "$ANSIBLE_INVENTORY" ansible/site.yml --tags jenkins -e "shared_storage_type=glusterfs"

    if [[ $? -eq 0 ]]; then
        log_success "Jenkins containers started"
    else
        log_error "Jenkins startup failed"
        exit 1
    fi
}

validate_migration() {
    local team=$1
    local target_path="$GLUSTERFS_MOUNT_BASE/$team/data"

    log_info "Validating migration for team: $team..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate: $target_path"
        return
    fi

    # Check if mount exists
    if ! mountpoint -q "$GLUSTERFS_MOUNT_BASE/$team/data"; then
        log_error "GlusterFS mount not found: $target_path"
        return 1
    fi

    # Check if data exists
    if [[ ! -d "$target_path/jobs" ]] && [[ ! -d "$target_path/workspace" ]]; then
        log_warning "Jenkins data directories not found in $target_path"
        return 1
    fi

    log_success "Validation passed for team: $team"
    return 0
}

generate_rollback_script() {
    local rollback_script="$BACKUP_PATH/rollback_${TIMESTAMP}.sh"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create rollback script: $rollback_script"
        return
    fi

    cat > "$rollback_script" << 'EOF'
#!/bin/bash
# GlusterFS Migration Rollback Script
# Auto-generated - Use to revert to previous storage configuration

set -euo pipefail

BACKUP_PATH="__BACKUP_PATH__"
SOURCE_STORAGE_PATH="__SOURCE_STORAGE_PATH__"
TIMESTAMP="__TIMESTAMP__"

echo "Rolling back GlusterFS migration..."

# Stop Jenkins containers
docker ps --filter "name=jenkins-" --format "{{.Names}}" | xargs -r docker stop

# Restore from backup
for backup_file in "$BACKUP_PATH"/*_${TIMESTAMP}.tar.gz; do
    if [[ -f "$backup_file" ]]; then
        echo "Restoring: $backup_file"
        tar -xzf "$backup_file" -C "$SOURCE_STORAGE_PATH"
    fi
done

# Update ansible inventory to use local storage
sed -i 's/shared_storage_type: "glusterfs"/shared_storage_type: "local"/' ansible/inventories/production/group_vars/all/main.yml

# Restart Jenkins with local storage
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags jenkins

echo "Rollback completed"
EOF

    sed -i "s|__BACKUP_PATH__|$BACKUP_PATH|g" "$rollback_script"
    sed -i "s|__SOURCE_STORAGE_PATH__|$SOURCE_STORAGE_PATH|g" "$rollback_script"
    sed -i "s|__TIMESTAMP__|$TIMESTAMP|g" "$rollback_script"

    chmod +x "$rollback_script"
    log_success "Rollback script created: $rollback_script"
}

# Main execution
main() {
    echo "=========================================="
    echo "GlusterFS Migration Script"
    echo "=========================================="
    echo "Timestamp: $TIMESTAMP"
    echo "Dry Run: $DRY_RUN"
    echo "Target Team: ${TARGET_TEAM:-All teams}"
    echo "Backup Path: $BACKUP_PATH"
    echo "=========================================="
    echo ""

    # Prerequisites check
    check_prerequisites

    # Get teams to migrate
    if [[ -n "$TARGET_TEAM" ]]; then
        TEAMS_TO_MIGRATE="$TARGET_TEAM"
    else
        TEAMS_TO_MIGRATE=$(get_jenkins_teams)
    fi

    log_info "Teams to migrate: $TEAMS_TO_MIGRATE"
    echo ""

    # Backup existing data
    for team in $TEAMS_TO_MIGRATE; do
        backup_existing_data "$team"
    done
    echo ""

    # Setup GlusterFS
    setup_glusterfs
    echo ""

    # Stop Jenkins containers
    stop_jenkins_containers
    echo ""

    # Migrate data for each team
    for team in $TEAMS_TO_MIGRATE; do
        migrate_team_data "$team"
        echo ""
    done

    # Start Jenkins with GlusterFS
    start_jenkins_containers
    echo ""

    # Validate migration
    VALIDATION_PASSED=true
    for team in $TEAMS_TO_MIGRATE; do
        if ! validate_migration "$team"; then
            VALIDATION_PASSED=false
        fi
    done
    echo ""

    # Generate rollback script
    generate_rollback_script
    echo ""

    # Final summary
    echo "=========================================="
    echo "Migration Summary"
    echo "=========================================="
    echo "Status: ${VALIDATION_PASSED:-false}"
    echo "Teams Migrated: $TEAMS_TO_MIGRATE"
    echo "Backup Location: $BACKUP_PATH"
    echo "Rollback Script: $BACKUP_PATH/rollback_${TIMESTAMP}.sh"
    echo "=========================================="

    if [[ "$VALIDATION_PASSED" == "true" ]]; then
        log_success "Migration completed successfully!"
        log_info "Next steps:"
        log_info "1. Verify Jenkins is accessible and data is intact"
        log_info "2. Run GlusterFS tests: ansible-playbook ansible/playbooks/test-glusterfs.yml"
        log_info "3. If issues occur, use rollback script: $BACKUP_PATH/rollback_${TIMESTAMP}.sh"
    else
        log_warning "Migration completed with validation warnings"
        log_info "Review the logs above and verify Jenkins functionality"
    fi
}

# Run main function
main
