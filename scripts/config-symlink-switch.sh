#!/bin/bash
#
# config-symlink-switch.sh - Switch JCasC configuration symlink
#
# This script switches the active configuration symlink from blue to green or vice versa
# without restarting the Jenkins container. Hot reload is triggered separately.
#
# Usage: ./config-symlink-switch.sh <team_name> <target_config>
#   team_name: Name of the team (e.g., devops, developer)
#   target_config: Target configuration (blue or green)
#
# Example: ./config-symlink-switch.sh devops green

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

Switch JCasC configuration symlink for a Jenkins team.

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
ACTIVE_SYMLINK="${CONFIG_DIR}/active"
TARGET_DIR="${CONFIG_DIR}/${TARGET_CONFIG}"
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

if [[ ! -d "$TARGET_DIR" ]]; then
    error "Target config directory does not exist: $TARGET_DIR"
    exit 1
fi

if [[ ! -f "${TARGET_DIR}/jenkins.yaml" ]]; then
    error "Target config file does not exist: ${TARGET_DIR}/jenkins.yaml"
    exit 1
fi

log "=========================================="
log "Starting config symlink switch"
log "Team: $TEAM_NAME"
log "Target: $TARGET_CONFIG"
log "=========================================="

# Get current symlink target
if [[ -L "$ACTIVE_SYMLINK" ]]; then
    CURRENT_TARGET=$(readlink "$ACTIVE_SYMLINK")
    log "Current active config: $CURRENT_TARGET"

    # Check if already pointing to target
    if [[ "$CURRENT_TARGET" == "$TARGET_CONFIG" ]]; then
        warning "Symlink already points to $TARGET_CONFIG"
        exit 0
    fi
else
    warning "Active symlink does not exist, creating new one"
    CURRENT_TARGET="none"
fi

# Create backup of current state
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [[ "$CURRENT_TARGET" != "none" && -f "${CONFIG_DIR}/${CURRENT_TARGET}/jenkins.yaml" ]]; then
    log "Backing up current config..."
    mkdir -p "$BACKUP_DIR"
    cp "${CONFIG_DIR}/${CURRENT_TARGET}/jenkins.yaml" "${BACKUP_DIR}/jenkins.yaml.${TIMESTAMP}"
    success "Backup created: ${BACKUP_DIR}/jenkins.yaml.${TIMESTAMP}"
fi

# Switch symlink atomically
log "Switching symlink: active -> $TARGET_CONFIG"
ln -sfn "$TARGET_CONFIG" "$ACTIVE_SYMLINK"

# Verify symlink
NEW_TARGET=$(readlink "$ACTIVE_SYMLINK")
if [[ "$NEW_TARGET" != "$TARGET_CONFIG" ]]; then
    error "Symlink switch failed! Expected: $TARGET_CONFIG, Got: $NEW_TARGET"

    # Rollback if previous target exists
    if [[ "$CURRENT_TARGET" != "none" ]]; then
        warning "Rolling back to previous config: $CURRENT_TARGET"
        ln -sfn "$CURRENT_TARGET" "$ACTIVE_SYMLINK"
    fi
    exit 1
fi

# Update state file
if [[ -f "$STATE_FILE" ]]; then
    # Update existing state file
    jq --arg config "$TARGET_CONFIG" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.active_config = $config | .last_update = $timestamp | .previous_config = .active_config' \
       "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    success "State file updated"
else
    warning "State file does not exist: $STATE_FILE"
fi

# Cleanup old backups (keep last 10)
if [[ -d "$BACKUP_DIR" ]]; then
    log "Cleaning up old backups (keeping last 10)..."
    ls -t "${BACKUP_DIR}"/jenkins.yaml.* 2>/dev/null | tail -n +11 | xargs -r rm -f
fi

success "=========================================="
success "Config symlink switch completed successfully!"
success "Previous: ${CURRENT_TARGET}"
success "Current: ${TARGET_CONFIG}"
success "=========================================="
success "NOTE: You must trigger a hot reload for changes to take effect:"
success "  curl -X POST -u admin:TOKEN http://localhost:8080/configuration-as-code/reload"

exit 0
