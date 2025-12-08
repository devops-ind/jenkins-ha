#!/bin/bash
# YAML Syntax Validation Script
# Validates YAML syntax for Jenkins team configuration files

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

usage() {
    cat <<EOF
Usage: $0 <config-file>

Validates YAML syntax for Jenkins team configuration files.

Arguments:
  config-file    Path to the YAML config file (e.g., jenkins-configs/devops.yml)

Examples:
  $0 jenkins-configs/devops.yml
  $0 /path/to/developer.yml

Exit codes:
  0 - Validation successful
  1 - Validation failed
  2 - Usage error
EOF
    exit 2
}

validate_yaml_syntax() {
    local config_file="$1"

    log "Validating YAML syntax for: $config_file"

    # Check if file exists
    if [[ ! -f "$config_file" ]]; then
        error "Config file not found: $config_file"
        return 1
    fi

    # Check file is readable
    if [[ ! -r "$config_file" ]]; then
        error "Config file is not readable: $config_file"
        return 1
    fi

    # Check file is not empty
    if [[ ! -s "$config_file" ]]; then
        error "Config file is empty: $config_file"
        return 1
    fi

    # Method 1: Use Python (most reliable)
    if command -v python3 &>/dev/null; then
        log "Using Python YAML parser..."
        if python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            success "Python YAML validation passed"
        else
            error "Python YAML validation failed"
            python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>&1 | head -20
            return 1
        fi
    else
        warn "Python3 not found, skipping Python validation"
    fi

    # Method 2: Use yamllint if available
    if command -v yamllint &>/dev/null; then
        log "Using yamllint..."
        if yamllint -d "{extends: default, rules: {line-length: {max: 200}}}" "$config_file" 2>&1; then
            success "yamllint validation passed"
        else
            error "yamllint validation failed"
            return 1
        fi
    else
        warn "yamllint not found, skipping yamllint validation"
    fi

    # Method 3: Use yq if available
    if command -v yq &>/dev/null; then
        log "Using yq..."
        if yq eval '.' "$config_file" >/dev/null 2>&1; then
            success "yq validation passed"
        else
            error "yq validation failed"
            yq eval '.' "$config_file" 2>&1 | head -20
            return 1
        fi
    else
        warn "yq not found, skipping yq validation"
    fi

    # Basic syntax checks
    log "Running basic syntax checks..."

    # Check for tabs (YAML should use spaces)
    if grep -P '\t' "$config_file" &>/dev/null; then
        warn "File contains tabs - YAML should use spaces for indentation"
        error "Found tabs at lines:"
        grep -n -P '\t' "$config_file" | head -5
        return 1
    fi

    # Check for common syntax issues
    if grep -E '^\s*-\s*$' "$config_file" &>/dev/null; then
        warn "Found empty list items (dangling dashes)"
        grep -n -E '^\s*-\s*$' "$config_file" | head -5
    fi

    # Check for unquoted special characters in values
    if grep -E ':\s*[^"'\'']*[{}[\]&*#?|<>=!%@]' "$config_file" &>/dev/null; then
        warn "Found potentially unquoted special characters"
        log "Consider quoting values with special characters"
    fi

    success "All YAML syntax validations passed"
    return 0
}

# Main execution
main() {
    if [[ $# -ne 1 ]]; then
        usage
    fi

    local config_file="$1"

    log "=========================================="
    log "YAML Syntax Validation"
    log "=========================================="
    log "File: $config_file"
    log ""

    if validate_yaml_syntax "$config_file"; then
        log ""
        success "✅ YAML syntax validation successful"
        exit 0
    else
        log ""
        error "❌ YAML syntax validation failed"
        exit 1
    fi
}

main "$@"
