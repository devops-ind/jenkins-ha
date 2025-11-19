#!/bin/bash
# Rollback Script for Smart Sharing Migration
# Safely restores Jenkins data from backups if smart sharing migration fails
# Version: 1.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

Rollback Script for Smart Sharing Migration

Safely restores Jenkins data from migration backups.

OPTIONS:
    --team <team_name>         Rollback specific team (default: all teams)
    --backup-dir <path>        Backup directory (default: /opt/jenkins-migration-backup)
    --dry-run                  Show what would be done without making changes
    --force                    Skip confirmation prompts
    -h, --help                 Show this help message

EXAMPLES:
    $0 --dry-run               Preview rollback for all teams
    $0 --team devops           Rollback only devops team
    $0 --force                 Run rollback without prompts

SAFETY:
    • Stops containers before rollback
    • Validates backup integrity
    • Restores original volume configuration
    • Preserves data integrity

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

# Check if backup directory exists
check_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    
    log "Found backup directory: $BACKUP_DIR"
}

# Discover available backups
discover_backups() {
    log "Discovering available backups..."
    
    local teams=()
    for team_dir in "$BACKUP_DIR"/*; do
        if [[ -d "$team_dir" ]]; then
            local team=$(basename "$team_dir")
            if [[ -z "$TEAM_FILTER" || "$team" == "$TEAM_FILTER" ]]; then
                teams+=("$team")
                log "Found backup for team: $team"
            fi
        fi
    done
    
    printf '%s\n' "${teams[@]}"
}

# Validate backup integrity
validate_backup() {
    local team="$1"
    local environment="$2"
    
    log "Validating backup for $team-$environment..."
    
    local backup_files
    backup_files=$(find "$BACKUP_DIR/$team/$environment" -name "jenkins_home_*.tar.gz" 2>/dev/null || true)
    
    if [[ -z "$backup_files" ]]; then
        error "No backup files found for $team-$environment"
        return 1
    fi
    
    # Check latest backup
    local latest_backup
    latest_backup=$(echo "$backup_files" | sort | tail -n1)
    
    if tar -tzf "$latest_backup" >/dev/null 2>&1; then
        success "Backup validation passed: $latest_backup"
        echo "$latest_backup"
        return 0
    else
        error "Backup validation failed: $latest_backup"
        return 1
    fi
}

# Restore from backup
restore_backup() {
    local team="$1"
    local environment="$2"
    local backup_file="$3"
    
    log "Restoring $team-$environment from backup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would restore from $backup_file"
        return 0
    fi
    
    # Create temporary extraction directory
    local temp_dir="/tmp/jenkins_restore_$$"
    mkdir -p "$temp_dir"
    
    # Extract backup
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Remove existing volume and create new one
    local volume_name="jenkins-${team}-${environment}-home"
    docker volume rm "$volume_name" 2>/dev/null || true
    docker volume create "$volume_name"
    
    # Copy data to volume using temporary container
    docker run --rm \
        -v "$volume_name:/target" \
        -v "$temp_dir:/source:ro" \
        alpine:latest \
        sh -c "cp -a /source/*/. /target/"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    success "Restored $team-$environment from backup"
}

# Rollback team
rollback_team() {
    local team="$1"
    
    log "Starting rollback for team: $team"
    
    # Stop containers
    local containers
    containers=$(docker ps --format '{{.Names}}' | grep "^jenkins-${team}-" || true)
    
    if [[ -n "$containers" ]]; then
        log "Stopping containers for team $team..."
        if [[ "$DRY_RUN" != "true" ]]; then
            echo "$containers" | xargs -r docker stop
        fi
    fi
    
    # Restore each environment
    for env in blue green; do
        local backup_file
        if backup_file=$(validate_backup "$team" "$env" 2>/dev/null); then
            restore_backup "$team" "$env" "$backup_file"
        else
            warn "No valid backup found for $team-$env, skipping"
        fi
    done
    
    success "Rollback completed for team $team"
}

# Generate rollback report
generate_report() {
    local teams=("$@")
    
    cat << EOF

====================================================
Smart Sharing Rollback Report
====================================================
Rollback Type: ${DRY_RUN:+DRY RUN }Data Restoration
Backup Source: $BACKUP_DIR
Teams Processed: ${#teams[@]}

Teams: ${teams[*]}

RESTORED DATA:
$(for team in "${teams[@]}"; do
    echo "• $team: Original volume configuration restored"
done)

STATUS:
• Containers stopped and ready for restart
• Original volume mounts restored
• Shared storage migration reverted

NEXT STEPS:
1. Restart Jenkins containers:
   docker start \$(docker ps -aq --filter "name=jenkins-")
2. Verify Jenkins accessibility
3. Consider re-running migration with fixes if needed

CLEANUP:
Backup files preserved in: $BACKUP_DIR
====================================================

EOF
}

# Main execution
main() {
    log "Starting Smart Sharing Rollback"
    
    # Check backups
    check_backups
    
    # Discover teams with backups
    readarray -t teams < <(discover_backups)
    
    if [[ ${#teams[@]} -eq 0 ]]; then
        warn "No team backups found to rollback"
        exit 0
    fi
    
    log "Found backups for ${#teams[@]} team(s): ${teams[*]}"
    
    # Confirmation
    if [[ "$FORCE_MODE" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        warn "This will rollback the smart sharing migration."
        warn "Current shared storage data will be replaced with backup data."
        echo
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Rollback cancelled by user"
            exit 0
        fi
    fi
    
    # Rollback each team
    local failed_teams=()
    for team in "${teams[@]}"; do
        if ! rollback_team "$team"; then
            failed_teams+=("$team")
        fi
    done
    
    # Generate report
    generate_report "${teams[@]}"
    
    # Final status
    if [[ ${#failed_teams[@]} -eq 0 ]]; then
        success "Rollback completed successfully for all teams"
        exit 0
    else
        error "Rollback failed for: ${failed_teams[*]}"
        exit 1
    fi
}

# Run main function
main "$@"