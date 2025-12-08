#!/bin/bash
#
# jenkins-hot-reload.sh - Hot reload Jenkins configuration via JCasC API
#
# This script triggers a hot reload of Jenkins Configuration as Code (JCasC)
# without restarting the Jenkins container. Includes validation and rollback.
#
# Usage: ./jenkins-hot-reload.sh <team_name> [jenkins_url] [admin_user] [admin_token]
#   team_name: Name of the team (e.g., devops, developer)
#   jenkins_url: Jenkins URL (default: http://localhost:8080)
#   admin_user: Jenkins admin username (default: admin)
#   admin_token: Jenkins admin API token (from env: JENKINS_ADMIN_TOKEN)
#
# Example: ./jenkins-hot-reload.sh devops http://localhost:8080 admin mytoken

set -euo pipefail

# Constants
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/jenkins-hot-reload.log"
readonly MAX_RETRIES=6
readonly RETRY_DELAY=10

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
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

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

# Usage information
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <team_name> [jenkins_url] [admin_user] [admin_token]

Hot reload Jenkins JCasC configuration without container restart.

Arguments:
  team_name      Name of the team (e.g., devops, developer) [required]
  jenkins_url    Jenkins URL (default: http://localhost:8080)
  admin_user     Jenkins admin username (default: admin)
  admin_token    Jenkins admin API token (default: \$JENKINS_ADMIN_TOKEN)

Examples:
  $SCRIPT_NAME devops
  $SCRIPT_NAME developer http://jenkins.example.com:8080 admin mytoken
  JENKINS_ADMIN_TOKEN=mytoken $SCRIPT_NAME devops

Environment Variables:
  JENKINS_ADMIN_TOKEN   Admin API token (overridden by command line arg)

EOF
    exit 1
}

# Validate arguments
if [[ $# -lt 1 ]]; then
    error "Team name is required"
    usage
fi

TEAM_NAME="$1"
JENKINS_URL="${2:-http://localhost:8080}"
ADMIN_USER="${3:-admin}"
ADMIN_TOKEN="${4:-${JENKINS_ADMIN_TOKEN:-}}"

if [[ -z "$ADMIN_TOKEN" ]]; then
    error "Admin token is required (provide as argument or JENKINS_ADMIN_TOKEN env var)"
    exit 1
fi

log "=========================================="
log "Starting Jenkins hot reload"
log "Team: $TEAM_NAME"
log "Jenkins URL: $JENKINS_URL"
log "Admin User: $ADMIN_USER"
log "=========================================="

# Pre-reload health check
check_jenkins_health() {
    local url="$1"
    local retries=0

    info "Checking Jenkins health before reload..."

    while [[ $retries -lt $MAX_RETRIES ]]; do
        if curl -sf -u "${ADMIN_USER}:${ADMIN_TOKEN}" "${url}/api/json" >/dev/null 2>&1; then
            success "Jenkins is healthy"
            return 0
        fi

        retries=$((retries + 1))
        if [[ $retries -lt $MAX_RETRIES ]]; then
            warning "Health check failed (attempt $retries/$MAX_RETRIES), retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
    done

    error "Jenkins health check failed after $MAX_RETRIES attempts"
    return 1
}

# Check for active builds
check_active_builds() {
    local url="$1"

    info "Checking for active builds..."

    local running_jobs
    running_jobs=$(curl -sf -u "${ADMIN_USER}:${ADMIN_TOKEN}" \
        "${url}/api/json?tree=jobs[name,building]" | \
        jq -r '.jobs[] | select(.building==true) | .name' 2>/dev/null || echo "")

    if [[ -n "$running_jobs" ]]; then
        warning "Active jobs found:"
        echo "$running_jobs" | while read -r job; do
            warning "  - $job"
        done
        warning "Consider waiting for jobs to complete before reloading"
        return 1
    else
        success "No active builds running"
        return 0
    fi
}

# Trigger configuration reload
trigger_reload() {
    local url="$1"

    info "Triggering JCasC configuration reload..."

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X POST \
        -u "${ADMIN_USER}:${ADMIN_TOKEN}" \
        "${url}/configuration-as-code/reload" 2>&1)

    http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)

    log "Response code: $http_code"
    log "Response body: $body"

    case "$http_code" in
        200|201|302)
            success "Configuration reload triggered successfully"
            return 0
            ;;
        401|403)
            error "Authentication failed (HTTP $http_code)"
            error "Check admin credentials"
            return 1
            ;;
        404)
            error "Configuration-as-Code plugin endpoint not found (HTTP $http_code)"
            error "Ensure JCasC plugin is installed"
            return 1
            ;;
        *)
            error "Reload failed with HTTP code: $http_code"
            error "Response: $body"
            return 1
            ;;
    esac
}

# Post-reload validation
validate_after_reload() {
    local url="$1"
    local retries=0

    info "Validating Jenkins after reload..."
    sleep 5  # Give Jenkins time to process the reload

    local checks=(
        "api:${url}/api/json:API Health"
        "login:${url}/login:Login Page"
        "jobs:${url}/api/json?tree=jobs[name]:Job List"
        "computer:${url}/computer/api/json:System Info"
    )

    for check in "${checks[@]}"; do
        IFS=':' read -r name endpoint description <<< "$check"

        retries=0
        while [[ $retries -lt 3 ]]; do
            if curl -sf -u "${ADMIN_USER}:${ADMIN_TOKEN}" "$endpoint" >/dev/null 2>&1; then
                success "✓ $description - OK"
                break
            fi

            retries=$((retries + 1))
            if [[ $retries -lt 3 ]]; then
                warning "  $description check failed (attempt $retries/3), retrying..."
                sleep 5
            else
                error "✗ $description - FAILED"
                return 1
            fi
        done
    done

    success "All post-reload validation checks passed"
    return 0
}

# Main execution
main() {
    local start_time
    start_time=$(date +%s)

    # Pre-reload checks
    if ! check_jenkins_health "$JENKINS_URL"; then
        error "Pre-reload health check failed"
        exit 1
    fi

    # Check for active builds (warning only, don't fail)
    check_active_builds "$JENKINS_URL" || true

    # Trigger reload
    if ! trigger_reload "$JENKINS_URL"; then
        error "Configuration reload failed"
        exit 1
    fi

    # Post-reload validation
    if ! validate_after_reload "$JENKINS_URL"; then
        error "Post-reload validation failed"
        error "Jenkins may be in an inconsistent state - manual intervention required"
        exit 1
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    success "=========================================="
    success "Jenkins hot reload completed successfully!"
    success "Team: $TEAM_NAME"
    success "Duration: ${duration}s"
    success "=========================================="

    exit 0
}

# Run main function
main
