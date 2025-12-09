#!/bin/bash
#
# config-file-switch.sh - Switch JCasC configuration by copying files
#
# This script switches the active configuration by copying blue.yaml or green.yaml
# to current.yaml (the file mounted in Jenkins container for hot-reload).
#
# Usage: ./config-file-switch.sh <team_name> <target_config>
#   team_name: Name of the team (e.g., devops, developer)
#   target_config: Target configuration (blue or green)
#
# Example: ./config-file-switch.sh devops green

set -euo pipefail

# Constants
readonly SCRIPT_NAME="$(basename "$0")"
readonly JENKINS_BASE_DIR="/var/jenkins"
readonly LOG_FILE="/var/log/jenkins-config-switch.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

# Usage information
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <team_name> <target_config>

Switch JCasC configuration by copying config files.

Arguments:
  team_name      Name of the team (e.g., devops, developer)
  target_config  Target configuration (blue or green)

Examples:
  $SCRIPT_NAME devops green
  $SCRIPT_NAME developer blue

Environment Variables:
  JENKINS_BASE_DIR   Base directory for Jenkins data (default: /var/jenkins)

EOF
    exit 1
}

# Validate arguments
if [[ $# -ne 2 ]]; then
    error "Invalid number of arguments"
    usage
fi

TEAM_NAME="$1"
TARGET_CONFIG="$2"

# Validate target config
if [[ "$TARGET_CONFIG" != "blue" && "$TARGET_CONFIG" != "green" ]]; then
    error "Invalid target config: $TARGET_CONFIG (must be 'blue' or 'green')"
    exit 1
fi

# Directories
TEAM_DIR="${JENKINS_BASE_DIR}/${TEAM_NAME}"
CONFIG_DIR="${TEAM_DIR}/configs"
SOURCE_FILE="${CONFIG_DIR}/${TARGET_CONFIG}.yaml"
TARGET_FILE="${CONFIG_DIR}/current.yaml"
BACKUP_DIR="${TEAM_DIR}/backups"
STATE_FILE="${TEAM_DIR}/config-state.json"

# Validate directories exist
if [[ ! -d "$TEAM_DIR" ]]; then
    error "Team directory does not exist: $TEAM_DIR"
    exit 1
fi

if [[ ! -d "$CONFIG_DIR" ]]; then
    error "Config directory does not exist: $CONFIG_DIR"
    exit 1
fi

if [[ ! -f "$SOURCE_FILE" ]]; then
    error "Source config file does not exist: $SOURCE_FILE"
    exit 1
fi

log "=========================================="
log "Starting config file switch"
log "Team: $TEAM_NAME"
log "Target: $TARGET_CONFIG"
log "=========================================="

# Get current config (if exists)
if [[ -f "$TARGET_FILE" ]]; then
    # Determine current config from state file
    if [[ -f "$STATE_FILE" ]]; then
        CURRENT_TARGET=$(jq -r '.active_config // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
        log "Current active config: $CURRENT_TARGET"
    else
        CURRENT_TARGET="unknown"
        warning "State file does not exist"
    fi

    # Check if already pointing to target
    if [[ "$CURRENT_TARGET" == "$TARGET_CONFIG" ]]; then
        warning "Current config is already $TARGET_CONFIG"
        exit 0
    fi
else
    warning "Current config file does not exist, creating new one"
    CURRENT_TARGET="none"
fi

# Create backup of current config
if [[ -f "$TARGET_FILE" ]]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    log "Backing up current config..."
    mkdir -p "$BACKUP_DIR"
    cp "$TARGET_FILE" "${BACKUP_DIR}/current.yaml.${TIMESTAMP}"
    success "Backup created: ${BACKUP_DIR}/current.yaml.${TIMESTAMP}"
fi

# Copy new config to current.yaml
log "Copying config: ${SOURCE_FILE} -> ${TARGET_FILE}"
cp "$SOURCE_FILE" "$TARGET_FILE"

# Verify copy succeeded
if [[ ! -f "$TARGET_FILE" ]]; then
    error "Config copy failed!"

    # Rollback if backup exists
    if [[ -f "${BACKUP_DIR}/current.yaml.${TIMESTAMP}" ]]; then
        warning "Rolling back to previous config..."
        cp "${BACKUP_DIR}/current.yaml.${TIMESTAMP}" "$TARGET_FILE"
    fi
    exit 1
fi

# Verify file content
if ! diff -q "$SOURCE_FILE" "$TARGET_FILE" >/dev/null 2>&1; then
    error "Config verification failed - files don't match!"
    exit 1
fi

# Update state file
if [[ -f "$STATE_FILE" ]]; then
    # Update existing state file
    jq --arg config "$TARGET_CONFIG" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --arg prev "$CURRENT_TARGET" \
       '.active_config = $config | .last_update = $timestamp | .previous_config = $prev' \
       "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    success "State file updated"
else
    warning "State file does not exist: $STATE_FILE"
fi

# Cleanup old backups (keep last 10)
if [[ -d "$BACKUP_DIR" ]]; then
    log "Cleaning up old backups (keeping last 10)..."
    ls -t "${BACKUP_DIR}"/current.yaml.* 2>/dev/null | tail -n +11 | xargs -r rm -f
fi

# Set correct ownership
chown 1000:1000 "$TARGET_FILE" 2>/dev/null || true

success "=========================================="
success "Config file switch completed successfully!"
success "Previous: ${CURRENT_TARGET}"
success "Current: ${TARGET_CONFIG}"
success "File: ${TARGET_FILE}"
success "=========================================="
success "NOTE: You must trigger a hot reload for changes to take effect:"
success "  curl -X POST -u admin:TOKEN http://localhost:8080/configuration-as-code/reload"

exit 0
