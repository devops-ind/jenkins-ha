#!/bin/bash

# sync-for-bluegreen-switch.sh - Intelligent sync of critical data between blue-green environments
# This script is called before environment switches to ensure data consistency

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_FILE:-/var/log/jenkins-bluegreen-sync.log}"
DRY_RUN="${DRY_RUN:-false}"

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

# Function to get team configuration
get_team_config() {
    local team="$1"
    local config_file="${SCRIPT_DIR}/../ansible/inventories/production/group_vars/all/main.yml"
    
    if [[ -f "$config_file" ]]; then
        # Extract team configuration as JSON
        python3 -c "
import yaml
import json
import sys

with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

teams = config.get('jenkins_teams_config', [])
for team in teams:
    if team.get('team_name') == '$team':
        print(json.dumps(team))
        sys.exit(0)
        
print(json.dumps({'team_name': '$team', 'active_environment': 'blue', 'ports': {'web': 8080}}))
" 2>/dev/null || echo '{"team_name": "'$team'", "active_environment": "blue", "ports": {"web": 8080}}'
    else
        echo '{"team_name": "'$team'", "active_environment": "blue", "ports": {"web": 8080}}'
    fi
}

# Function to determine target environment (opposite of current active)
get_target_environment() {
    local current_active="$1"
    if [[ "$current_active" == "blue" ]]; then
        echo "green"
    else
        echo "blue"
    fi
}

# Function to check container status
check_container_status() {
    local container_name="$1"
    local required_status="${2:-running}"
    
    if ! docker container inspect "$container_name" >/dev/null 2>&1; then
        if [[ "$required_status" == "exists" ]]; then
            return 1
        fi
        log_warning "Container $container_name does not exist"
        return 1
    fi
    
    local status=$(docker container inspect "$container_name" --format '{{.State.Status}}')
    if [[ "$status" != "$required_status" && "$required_status" != "exists" ]]; then
        log_warning "Container $container_name status: $status (expected: $required_status)"
        return 1
    fi
    
    return 0
}

# Function to create temporary sync container
create_sync_container() {
    local team="$1"
    local source_container="$2"
    local target_container="$3"
    local sync_container="jenkins-sync-${team}-${SYNC_DATE}"
    
    log_info "Creating temporary sync container: $sync_container"
    
    # Get the Jenkins image used by the source container
    local jenkins_image=$(docker container inspect "$source_container" --format '{{.Config.Image}}' 2>/dev/null || echo "jenkins/jenkins:lts")
    
    # Create sync container with volumes from both environments
    if docker run -d \
        --name "$sync_container" \
        --volumes-from "$source_container" \
        --volumes-from "$target_container" \
        --entrypoint="" \
        "$jenkins_image" \
        tail -f /dev/null >/dev/null 2>&1; then
        
        log_success "Sync container created: $sync_container"
        echo "$sync_container"
        return 0
    else
        log_error "Failed to create sync container"
        return 1
    fi
}

# Function to sync critical data between containers
sync_critical_data() {
    local team="$1"
    local source_container="$2"
    local target_container="$3"
    local direction="$4"  # "to_target" or "from_target"
    
    log_info "Syncing critical data for team $team ($direction)"
    
    # Create temporary sync container
    local sync_container
    if ! sync_container=$(create_sync_container "$team" "$source_container" "$target_container"); then
        return 1
    fi
    
    # Define critical data paths to sync
    local critical_paths=(
        "secrets"
        "userContent"
        "credentials.xml"
        "users"
    )
    
    # Define sync direction paths
    local source_base target_base
    if [[ "$direction" == "to_target" ]]; then
        source_base="/var/jenkins_home"
        target_base="/var/jenkins_home"
    else
        source_base="/var/jenkins_home"
        target_base="/var/jenkins_home"
    fi
    
    # Create sync script inside container
    local sync_script="/tmp/sync_critical_data.sh"
    cat > "${sync_script}" << 'SYNC_EOF'
#!/bin/bash
set -e

SOURCE_BASE="$1"
TARGET_BASE="$2"
DIRECTION="$3"
shift 3
PATHS=("$@")

echo "Starting sync: $DIRECTION"
echo "Source base: $SOURCE_BASE"
echo "Target base: $TARGET_BASE"
echo "Paths to sync: ${PATHS[@]}"

for path in "${PATHS[@]}"; do
    source_path="$SOURCE_BASE/$path"
    target_path="$TARGET_BASE/$path"
    
    if [[ -e "$source_path" ]]; then
        echo "Syncing: $path"
        
        # Create target directory if needed
        mkdir -p "$(dirname "$target_path")"
        
        # Sync the path
        if [[ -d "$source_path" ]]; then
            rsync -av --delete "$source_path/" "$target_path/"
        elif [[ -f "$source_path" ]]; then
            cp "$source_path" "$target_path"
        fi
        
        echo "✓ Synced: $path"
    else
        echo "⚠ Skipping missing path: $path"
    fi
done

echo "Sync completed successfully"
SYNC_EOF
    
    # Copy sync script to container and execute
    if docker cp "$sync_script" "$sync_container:/tmp/sync_script.sh" && \
       docker exec "$sync_container" chmod +x /tmp/sync_script.sh; then
        
        local sync_command="/tmp/sync_script.sh \"$source_base\" \"$target_base\" \"$direction\""
        for path in "${critical_paths[@]}"; do
            sync_command="$sync_command \"$path\""
        done
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Would execute sync for paths: ${critical_paths[*]}"
        else
            if docker exec "$sync_container" bash -c "$sync_command"; then
                log_success "Critical data sync completed for team $team"
            else
                log_error "Sync failed for team $team"
                return 1
            fi
        fi
    else
        log_error "Failed to prepare sync script for team $team"
        return 1
    fi
    
    # Cleanup
    docker container rm -f "$sync_container" >/dev/null 2>&1 || true
    rm -f "$sync_script"
    
    return 0
}

# Function to validate sync integrity
validate_sync() {
    local team="$1"
    local source_container="$2"
    local target_container="$3"
    
    log_info "Validating sync integrity for team $team"
    
    # Check critical files exist in target
    local validation_script="/tmp/validate_sync.sh"
    cat > "$validation_script" << 'VALIDATE_EOF'
#!/bin/bash
cd /var/jenkins_home

# Check critical paths
CRITICAL_PATHS=("secrets" "userContent" "credentials.xml")
VALIDATION_PASSED=true

for path in "${CRITICAL_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
        echo "✓ Found: $path"
    else
        echo "✗ Missing: $path"
        VALIDATION_PASSED=false
    fi
done

if [[ "$VALIDATION_PASSED" == "true" ]]; then
    echo "Validation PASSED"
    exit 0
else
    echo "Validation FAILED"
    exit 1
fi
VALIDATE_EOF
    
    # Run validation in target container
    if docker cp "$validation_script" "$target_container:/tmp/validate.sh" && \
       docker exec "$target_container" chmod +x /tmp/validate.sh && \
       docker exec "$target_container" /tmp/validate.sh; then
        
        log_success "Sync validation passed for team $team"
        docker exec "$target_container" rm -f /tmp/validate.sh >/dev/null 2>&1 || true
        rm -f "$validation_script"
        return 0
    else
        log_error "Sync validation failed for team $team"
        rm -f "$validation_script"
        return 1
    fi
}

# Function to sync team data before blue-green switch
sync_team_for_switch() {
    local team="$1"
    local target_env="$2"  # Environment we're switching TO
    
    log_info "Processing blue-green sync for team: $team"
    log_info "Target environment: $target_env"
    
    # Get current team configuration
    local team_config
    team_config=$(get_team_config "$team")
    local current_active=$(echo "$team_config" | python3 -c "import sys,json; print(json.load(sys.stdin)['active_environment'])")
    
    log_info "Current active environment: $current_active"
    
    # Validate target environment
    if [[ "$current_active" == "$target_env" ]]; then
        log_warning "Target environment ($target_env) is already active for team $team"
        return 0
    fi
    
    # Define container names
    local source_container="jenkins-${team}-${current_active}"
    local target_container="jenkins-${team}-${target_env}"
    
    # Check source container is running
    if ! check_container_status "$source_container" "running"; then
        log_error "Source container $source_container is not running"
        return 1
    fi
    
    # Check if target container exists (it might not be running yet)
    if ! check_container_status "$target_container" "exists"; then
        log_warning "Target container $target_container does not exist - will be created during switch"
        return 0
    fi
    
    # Perform the sync
    if sync_critical_data "$team" "$source_container" "$target_container" "to_target"; then
        # Validate the sync
        if validate_sync "$team" "$source_container" "$target_container"; then
            log_success "Blue-green sync completed successfully for team $team"
            
            # Create sync metadata
            local metadata_file="/tmp/sync-metadata-${team}-${SYNC_DATE}.json"
            cat > "$metadata_file" << EOF
{
    "team": "$team",
    "sync_date": "$SYNC_DATE",
    "source_environment": "$current_active",
    "target_environment": "$target_env",
    "source_container": "$source_container",
    "target_container": "$target_container",
    "sync_status": "completed",
    "validation_status": "passed"
}
EOF
            log_info "Sync metadata saved: $metadata_file"
            
        else
            log_error "Sync validation failed for team $team"
            return 1
        fi
    else
        log_error "Sync failed for team $team"
        return 1
    fi
    
    return 0
}

# Function to sync all teams for a global switch
sync_all_teams() {
    local target_env="$1"
    local teams="${2:-devops ma ba tw}"
    
    log_info "Starting global blue-green sync to environment: $target_env"
    log_info "Teams to sync: $teams"
    
    local success_count=0
    local total_count=0
    local failed_teams=()
    
    for team in $teams; do
        total_count=$((total_count + 1))
        
        if sync_team_for_switch "$team" "$target_env"; then
            success_count=$((success_count + 1))
            log_success "Team $team sync completed"
        else
            failed_teams+=("$team")
            log_error "Team $team sync failed"
        fi
        
        echo "---"
    done
    
    # Summary
    log_info "Global sync summary:"
    log_info "Successful syncs: $success_count/$total_count"
    
    if [[ ${#failed_teams[@]} -gt 0 ]]; then
        log_error "Failed teams: ${failed_teams[*]}"
        return 1
    else
        log_success "All team syncs completed successfully"
        return 0
    fi
}

# Main function
main() {
    local operation="${1:-}"
    local team="${2:-}"
    local target_env="${3:-}"
    
    case "$operation" in
        "team")
            if [[ -z "$team" || -z "$target_env" ]]; then
                echo "Usage: $0 team <team_name> <target_environment>"
                exit 1
            fi
            sync_team_for_switch "$team" "$target_env"
            ;;
        "all")
            if [[ -z "$target_env" ]]; then
                echo "Usage: $0 all <target_environment> [team_list]"
                exit 1
            fi
            local teams="${team:-devops ma ba tw}"
            sync_all_teams "$target_env" "$teams"
            ;;
        *)
            cat << EOF
Usage: $0 <operation> [options]

Operations:
    team <team_name> <target_env>           Sync single team to target environment
    all <target_env> [team_list]            Sync all teams to target environment

Environment Variables:
    DRY_RUN=true                           Show what would be synced without doing it
    LOG_FILE=/path/to/log                  Custom log file location

Examples:
    $0 team devops green                   Sync devops team to green environment
    $0 all blue                           Sync all teams to blue environment
    $0 all green "devops ma"              Sync specific teams to green environment
    
    DRY_RUN=true $0 team devops green     Preview sync without executing
    
Critical Data Synced:
    - secrets/                            Encrypted credentials
    - userContent/                        User-uploaded files  
    - credentials.xml                     Credential configurations
    - users/                              User configurations

Data NOT Synced (recreatable from code):
    - jobs/                               Recreated from seed jobs
    - workspace/                          Ephemeral build workspaces
    - builds/                             Build history
    - plugins/                            Managed via code
    - logs/                               Environment-specific logs

EOF
            exit 1
            ;;
    esac
}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Run main function with all arguments
main "$@"