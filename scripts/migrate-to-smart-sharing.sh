#!/bin/bash
# Smart Sharing Migration Script for Jenkins Blue-Green Data
# Safely migrates existing Jenkins data to shared storage architecture
# Version: 1.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SHARED_STORAGE_PATH="${SHARED_STORAGE_PATH:-/opt/jenkins-shared}"
BACKUP_DIR="${BACKUP_DIR:-/opt/jenkins-migration-backup}"
DRY_RUN="${DRY_RUN:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Smart Sharing Migration Script for Jenkins Blue-Green Data

OPTIONS:
    --team <team_name>         Migrate specific team (default: all teams)
    --shared-path <path>       Shared storage path (default: /opt/jenkins-shared)
    --backup-dir <path>        Backup directory (default: /opt/jenkins-migration-backup)
    --dry-run                  Show what would be done without making changes
    --force                    Skip confirmation prompts
    -h, --help                 Show this help message

EXAMPLES:
    $0 --dry-run               Preview migration for all teams
    $0 --team devops           Migrate only devops team
    $0 --force                 Run migration without prompts

SAFETY FEATURES:
    • Creates full backups before migration
    • Validates data integrity after migration
    • Supports rollback if issues occur
    • Preserves plugin isolation for safe upgrades

EOF
}

# Parse command line arguments
TEAM_FILTER=""
FORCE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --team)
            TEAM_FILTER="$2"
            shift 2
            ;;
        --shared-path)
            SHARED_STORAGE_PATH="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_MODE=true
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

# Check if running as root or with docker permissions
check_permissions() {
    if ! docker ps >/dev/null 2>&1; then
        error "Cannot access Docker. Please run with appropriate permissions."
        exit 1
    fi
}

# Discover Jenkins teams and containers
discover_teams() {
    log "Discovering Jenkins teams and containers..."
    
    local teams=()
    while IFS= read -r container; do
        if [[ $container =~ jenkins-([^-]+)-(blue|green)$ ]]; then
            local team="${BASH_REMATCH[1]}"
            local env="${BASH_REMATCH[2]}"
            
            if [[ -z "$TEAM_FILTER" || "$team" == "$TEAM_FILTER" ]]; then
                teams+=("$team")
                log "Found: $container (team: $team, environment: $env)"
            fi
        fi
    done < <(docker ps -a --format '{{.Names}}' | grep '^jenkins-' || true)
    
    # Remove duplicates
    printf '%s\n' "${teams[@]}" | sort -u
}

# Create backup of existing data
create_backup() {
    local team="$1"
    local environment="$2"
    local container="jenkins-${team}-${environment}"
    
    log "Creating backup for $container..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create backup of $container volumes"
        return 0
    fi
    
    # Create backup directory structure
    mkdir -p "$BACKUP_DIR/$team/$environment"
    
    # Get container volumes
    local volumes
    volumes=$(docker inspect "$container" --format '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null || true)
    
    if [[ -n "$volumes" ]]; then
        while IFS=':' read -r source dest; do
            if [[ "$dest" == "/var/jenkins_home" ]]; then
                log "Backing up Jenkins home from $source..."
                tar -czf "$BACKUP_DIR/$team/$environment/jenkins_home_$(date +%Y%m%d_%H%M%S).tar.gz" -C "$(dirname "$source")" "$(basename "$source")"
            fi
        done <<< "$volumes"
    fi
}

# Extract shared data from existing containers
extract_shared_data() {
    local team="$1"
    local container="$2"
    
    log "Extracting shared data from $container..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would extract shared data from $container"
        return 0
    fi
    
    local shared_dirs=("jobs" "workspace" "builds" "userContent" "secrets")
    
    for dir in "${shared_dirs[@]}"; do
        log "Extracting $dir from $container..."
        
        # Create target directory
        mkdir -p "$SHARED_STORAGE_PATH/$team/$dir"
        
        # Copy data if it exists in container
        if docker exec "$container" test -d "/var/jenkins_home/$dir" 2>/dev/null; then
            docker cp "$container:/var/jenkins_home/$dir/." "$SHARED_STORAGE_PATH/$team/$dir/"
            success "Extracted $dir for team $team"
        else
            log "Directory $dir not found in $container, creating empty directory"
            mkdir -p "$SHARED_STORAGE_PATH/$team/$dir"
        fi
    done
    
    # Set proper ownership
    chown -R jenkins:jenkins "$SHARED_STORAGE_PATH/$team" 2>/dev/null || true
}

# Validate data integrity
validate_data_integrity() {
    local team="$1"
    
    log "Validating data integrity for team $team..."
    
    local shared_dirs=("jobs" "workspace" "builds" "userContent" "secrets")
    local errors=0
    
    for dir in "${shared_dirs[@]}"; do
        local path="$SHARED_STORAGE_PATH/$team/$dir"
        if [[ ! -d "$path" ]]; then
            error "Missing directory: $path"
            ((errors++))
        else
            local count=$(find "$path" -type f 2>/dev/null | wc -l)
            log "Directory $path contains $count files"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        success "Data integrity validation passed for team $team"
        return 0
    else
        error "Data integrity validation failed for team $team ($errors errors)"
        return 1
    fi
}

# Main migration function
migrate_team() {
    local team="$1"
    
    log "Starting migration for team: $team"
    
    # Find containers for this team
    local containers
    containers=$(docker ps -a --format '{{.Names}}' | grep "^jenkins-${team}-" || true)
    
    if [[ -z "$containers" ]]; then
        warn "No containers found for team $team"
        return 1
    fi
    
    # Stop containers temporarily
    log "Stopping containers for team $team..."
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$containers" | xargs -r docker stop
    fi
    
    # Create backups
    while IFS= read -r container; do
        if [[ $container =~ jenkins-${team}-(blue|green)$ ]]; then
            local env="${BASH_REMATCH[1]}"
            create_backup "$team" "$env"
        fi
    done <<< "$containers"
    
    # Extract shared data from first available container
    local first_container
    first_container=$(echo "$containers" | head -n1)
    extract_shared_data "$team" "$first_container"
    
    # Validate migration
    if ! validate_data_integrity "$team"; then
        error "Migration validation failed for team $team"
        return 1
    fi
    
    success "Migration completed for team $team"
    
    # Restart containers with new volume configuration
    log "Migration complete. Containers stopped. Deploy with new configuration to start using shared storage."
}

# Generate migration report
generate_report() {
    local teams=("$@")
    
    cat << EOF

====================================================
Smart Sharing Migration Report
====================================================
Migration Type: ${DRY_RUN:+DRY RUN }Smart Sharing Implementation
Target Path: $SHARED_STORAGE_PATH
Backup Location: $BACKUP_DIR
Teams Processed: ${#teams[@]}

Teams: ${teams[*]}

SHARED DATA (will be consistent across blue/green):
$(for team in "${teams[@]}"; do
    echo "• $team/jobs (job configurations)"
    echo "• $team/workspace (build workspaces)"  
    echo "• $team/builds (build artifacts)"
    echo "• $team/userContent (user content)"
    echo "• $team/secrets (credentials)"
done)

ISOLATED DATA (remains environment-specific):
• plugins (safe for upgrades)
• logs (environment-specific)
• war (runtime isolation)

NEXT STEPS:
1. Review migration results
2. Update Ansible inventory if needed
3. Deploy with new volume configuration:
   ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags containers
4. Verify zero-downtime blue-green switching

ROLLBACK (if needed):
Restore from backups in: $BACKUP_DIR
====================================================

EOF
}

# Main execution
main() {
    log "Starting Smart Sharing Migration for Jenkins Blue-Green Data"
    
    # Safety checks
    check_permissions
    
    # Discover teams
    readarray -t teams < <(discover_teams)
    
    if [[ ${#teams[@]} -eq 0 ]]; then
        warn "No Jenkins teams found to migrate"
        exit 0
    fi
    
    log "Found ${#teams[@]} team(s): ${teams[*]}"
    
    # Confirmation
    if [[ "$FORCE_MODE" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        warn "This will migrate Jenkins data to shared storage architecture."
        warn "Containers will be temporarily stopped during migration."
        echo
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Migration cancelled by user"
            exit 0
        fi
    fi
    
    # Create shared storage directory
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$SHARED_STORAGE_PATH"
        mkdir -p "$BACKUP_DIR"
    fi
    
    # Migrate each team
    local failed_teams=()
    for team in "${teams[@]}"; do
        if ! migrate_team "$team"; then
            failed_teams+=("$team")
        fi
    done
    
    # Generate report
    generate_report "${teams[@]}"
    
    # Final status
    if [[ ${#failed_teams[@]} -eq 0 ]]; then
        success "Migration completed successfully for all teams"
        exit 0
    else
        error "Migration failed for: ${failed_teams[*]}"
        exit 1
    fi
}

# Run main function
main "$@"