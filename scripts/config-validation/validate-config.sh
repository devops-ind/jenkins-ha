#!/bin/bash
# Master Configuration Validation Script
# Runs all validation checks for Jenkins team configuration files

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

section() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

usage() {
    cat <<EOF
Usage: $0 <config-file> [--skip-dry-run] [--jenkins-url URL] [--jenkins-user USER] [--jenkins-token TOKEN]

Runs comprehensive validation for Jenkins team configuration files:
  1. YAML syntax validation
  2. JCasC schema validation
  3. Dry-run test in temporary container (optional)

Arguments:
  config-file         Path to the YAML config file (required)

Options:
  --skip-dry-run      Skip the dry-run test in temporary container
  --jenkins-url URL   Jenkins URL for live validation (default: http://localhost:8080)
  --jenkins-user USER Jenkins admin user (default: admin)
  --jenkins-token TOK Jenkins API token

Environment Variables:
  JENKINS_URL         Jenkins URL
  JENKINS_USER        Jenkins admin user
  JENKINS_PASSWORD    Jenkins admin password
  JENKINS_API_TOKEN   Jenkins API token
  SKIP_DRY_RUN        Set to 'true' to skip dry-run test

Examples:
  $0 jenkins-configs/devops.yml
  $0 jenkins-configs/devops.yml --skip-dry-run
  $0 jenkins-configs/devops.yml --jenkins-url http://localhost:8080 --jenkins-user admin --jenkins-token mytoken

Exit codes:
  0 - All validations passed
  1 - One or more validations failed
  2 - Usage error
EOF
    exit 2
}

run_validation_step() {
    local step_name="$1"
    local script_path="$2"
    shift 2
    local script_args=("$@")

    section "Step: $step_name"

    log "Running: $script_path ${script_args[*]}"

    if bash "$script_path" "${script_args[@]}"; then
        success "$step_name passed ✅"
        return 0
    else
        error "$step_name failed ❌"
        return 1
    fi
}

main() {
    local config_file=""
    local skip_dry_run="${SKIP_DRY_RUN:-false}"
    local jenkins_url="${JENKINS_URL:-http://localhost:8080}"
    local jenkins_user="${JENKINS_USER:-admin}"
    local jenkins_token="${JENKINS_API_TOKEN:-${JENKINS_PASSWORD:-}}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-dry-run)
                skip_dry_run="true"
                shift
                ;;
            --jenkins-url)
                jenkins_url="$2"
                shift 2
                ;;
            --jenkins-user)
                jenkins_user="$2"
                shift 2
                ;;
            --jenkins-token)
                jenkins_token="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                if [[ -z "$config_file" ]]; then
                    config_file="$1"
                else
                    error "Unknown argument: $1"
                    usage
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$config_file" ]]; then
        error "Config file is required"
        usage
    fi

    # Verify file exists
    if [[ ! -f "$config_file" ]]; then
        error "Config file not found: $config_file"
        exit 1
    fi

    # Banner
    echo ""
    section "Jenkins Configuration Validation"
    log "Config file: $config_file"
    log "Jenkins URL: $jenkins_url"
    log "Skip dry-run: $skip_dry_run"
    echo ""

    local failed_steps=0
    local total_steps=0

    # Step 1: YAML Syntax Validation
    ((total_steps++))
    if ! run_validation_step \
        "YAML Syntax Validation" \
        "$SCRIPT_DIR/validate-yaml-syntax.sh" \
        "$config_file"; then
        ((failed_steps++))
    fi

    # Step 2: JCasC Schema Validation
    ((total_steps++))
    if ! run_validation_step \
        "JCasC Schema Validation" \
        "$SCRIPT_DIR/validate-jcasc-schema.sh" \
        "$config_file" \
        "$jenkins_url" \
        "$jenkins_user" \
        "$jenkins_token"; then
        ((failed_steps++))
    fi

    # Step 3: Dry-run Test (optional)
    if [[ "$skip_dry_run" != "true" ]]; then
        ((total_steps++))
        if [[ -f "$SCRIPT_DIR/dry-run-test.sh" ]]; then
            if ! run_validation_step \
                "Dry-run Test in Temporary Container" \
                "$SCRIPT_DIR/dry-run-test.sh" \
                "$config_file"; then
                ((failed_steps++))
            fi
        else
            warn "Dry-run test script not found: $SCRIPT_DIR/dry-run-test.sh"
            warn "Skipping dry-run test"
        fi
    else
        log "Skipping dry-run test (--skip-dry-run flag set)"
    fi

    # Summary
    section "Validation Summary"
    log "Total steps: $total_steps"
    log "Passed: $((total_steps - failed_steps))"
    log "Failed: $failed_steps"

    if [[ $failed_steps -eq 0 ]]; then
        echo ""
        success "🎉 All validations passed! Config is ready for deployment."
        echo ""
        exit 0
    else
        echo ""
        error "❌ $failed_steps validation(s) failed. Please fix the errors and try again."
        echo ""
        exit 1
    fi
}

main "$@"
