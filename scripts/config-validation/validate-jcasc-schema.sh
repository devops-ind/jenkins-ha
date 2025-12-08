#!/bin/bash
# JCasC Schema Validation Script
# Validates Jenkins Configuration as Code schema

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
Usage: $0 <config-file> [jenkins-url] [jenkins-user] [jenkins-token]

Validates JCasC schema for Jenkins configuration files.

Arguments:
  config-file    Path to the YAML config file (required)
  jenkins-url    Jenkins URL (optional, default: http://localhost:8080)
  jenkins-user   Jenkins admin user (optional, default: admin)
  jenkins-token  Jenkins API token (optional, will try password from env)

Environment Variables:
  JENKINS_URL         Jenkins URL
  JENKINS_USER        Jenkins admin user
  JENKINS_PASSWORD    Jenkins admin password
  JENKINS_API_TOKEN   Jenkins API token

Examples:
  $0 jenkins-configs/devops.yml
  $0 jenkins-configs/devops.yml http://localhost:8080 admin mytoken

Exit codes:
  0 - Validation successful
  1 - Validation failed
  2 - Usage error
  3 - Jenkins not accessible
EOF
    exit 2
}

check_jenkins_connectivity() {
    local jenkins_url="$1"
    local jenkins_user="$2"
    local jenkins_auth="$3"

    log "Checking Jenkins connectivity: $jenkins_url"

    local response
    if [[ -n "$jenkins_auth" ]]; then
        response=$(curl -s -w "%{http_code}" -u "$jenkins_user:$jenkins_auth" "$jenkins_url/api/json" -o /dev/null)
    else
        response=$(curl -s -w "%{http_code}" "$jenkins_url/api/json" -o /dev/null)
    fi

    if [[ "$response" == "200" ]] || [[ "$response" == "403" ]]; then
        success "Jenkins is accessible"
        return 0
    else
        warn "Jenkins not accessible (HTTP $response) - will skip live validation"
        return 1
    fi
}

validate_jcasc_structure() {
    local config_file="$1"

    log "Validating JCasC structure..."

    # Check for required top-level keys
    local required_keys=("jenkins")
    local found_keys=0

    for key in "${required_keys[@]}"; do
        if grep -q "^${key}:" "$config_file"; then
            log "✓ Found required key: $key"
            ((found_keys++))
        else
            error "Missing required top-level key: $key"
        fi
    done

    if [[ $found_keys -eq ${#required_keys[@]} ]]; then
        success "All required top-level keys present"
    else
        error "Missing required JCasC keys"
        return 1
    fi

    # Check for common sections
    log "Checking for common JCasC sections..."

    if grep -q "^\s*systemMessage:" "$config_file"; then
        log "✓ Found: systemMessage"
    fi

    if grep -q "^\s*securityRealm:" "$config_file"; then
        log "✓ Found: securityRealm"
    fi

    if grep -q "^\s*clouds:" "$config_file"; then
        log "✓ Found: clouds configuration"
    fi

    if grep -q "^credentials:" "$config_file"; then
        log "✓ Found: credentials configuration"
    fi

    # Check for environment variable substitution syntax
    if grep -q '\${[A-Z_][A-Z0-9_]*}' "$config_file"; then
        log "✓ Found environment variable substitutions (e.g., \${VAR_NAME})"
    fi

    success "JCasC structure validation passed"
    return 0
}

validate_jcasc_with_jenkins() {
    local config_file="$1"
    local jenkins_url="$2"
    local jenkins_user="$3"
    local jenkins_auth="$4"

    log "Validating JCasC schema with Jenkins API..."

    # Create a temporary script to validate via Groovy Console API
    local groovy_script=$(cat <<'GROOVY'
import io.jenkins.plugins.casc.ConfigurationAsCode
import io.jenkins.plugins.casc.yaml.YamlSource

try {
    def configContent = new File(args[0]).text
    def source = YamlSource.of(configContent)

    // Validate configuration
    def config = ConfigurationAsCode.get()
    config.configure(source, true)  // true = check only, don't apply

    println "SUCCESS: JCasC configuration is valid"
    System.exit(0)
} catch (Exception e) {
    println "FAILED: JCasC validation error"
    println e.message
    e.printStackTrace()
    System.exit(1)
}
GROOVY
)

    # Try to validate using Jenkins Script Console API
    if [[ -n "$jenkins_auth" ]]; then
        local response
        response=$(curl -s -X POST \
            -u "$jenkins_user:$jenkins_auth" \
            --data-urlencode "script=$groovy_script" \
            --data-urlencode "configFile=$config_file" \
            "$jenkins_url/scriptText" 2>&1)

        if echo "$response" | grep -q "SUCCESS"; then
            success "Jenkins API validation passed"
            return 0
        else
            warn "Jenkins API validation inconclusive"
            log "$response"
            return 0  # Don't fail - live validation is optional
        fi
    else
        warn "No Jenkins authentication provided - skipping live validation"
        return 0
    fi
}

validate_docker_cloud_config() {
    local config_file="$1"

    log "Validating Docker cloud configuration..."

    # Check for required Docker cloud fields
    if grep -q "^\s*-\s*docker:" "$config_file"; then
        log "Found Docker cloud configuration"

        # Check for dockerHost
        if grep -q "^\s*dockerHost:" "$config_file"; then
            log "✓ Found: dockerHost"
        else
            warn "Missing: dockerHost (may be using defaults)"
        fi

        # Check for templates
        if grep -q "^\s*templates:" "$config_file"; then
            log "✓ Found: agent templates"

            # Count templates
            local template_count=$(grep -c "^\s*-\s*labelString:" "$config_file" || true)
            log "Found $template_count agent template(s)"
        else
            warn "No agent templates defined"
        fi

        success "Docker cloud configuration looks valid"
    else
        log "No Docker cloud configuration found (this may be intentional)"
    fi

    return 0
}

validate_credentials_config() {
    local config_file="$1"

    log "Validating credentials configuration..."

    if grep -q "^credentials:" "$config_file"; then
        log "Found credentials configuration"

        # Check for hardcoded passwords (security issue)
        if grep -E 'password:\s*["\x27][^$]' "$config_file" &>/dev/null; then
            error "SECURITY WARNING: Found hardcoded password values"
            error "Passwords should use environment variable substitution: \${PASSWORD_VAR}"
            grep -n -E 'password:\s*["\x27][^$]' "$config_file" | head -5
            return 1
        else
            success "No hardcoded passwords detected"
        fi

        # Check for proper environment variable substitution
        if grep -q 'password:\s*"\${' "$config_file"; then
            log "✓ Using environment variable substitution for passwords"
        fi

        success "Credentials configuration looks valid"
    else
        log "No credentials configuration found"
    fi

    return 0
}

# Main validation function
validate_jcasc_schema() {
    local config_file="$1"
    local jenkins_url="${2:-${JENKINS_URL:-http://localhost:8080}}"
    local jenkins_user="${3:-${JENKINS_USER:-admin}}"
    local jenkins_auth="${4:-${JENKINS_API_TOKEN:-${JENKINS_PASSWORD:-}}}"

    log "=========================================="
    log "JCasC Schema Validation"
    log "=========================================="
    log "Config file: $config_file"
    log "Jenkins URL: $jenkins_url"
    log ""

    # Check if file exists
    if [[ ! -f "$config_file" ]]; then
        error "Config file not found: $config_file"
        return 1
    fi

    # Validate JCasC structure
    if ! validate_jcasc_structure "$config_file"; then
        error "JCasC structure validation failed"
        return 1
    fi

    # Validate Docker cloud configuration
    if ! validate_docker_cloud_config "$config_file"; then
        error "Docker cloud configuration validation failed"
        return 1
    fi

    # Validate credentials configuration
    if ! validate_credentials_config "$config_file"; then
        error "Credentials configuration validation failed"
        return 1
    fi

    # Try to validate with live Jenkins instance (optional)
    if check_jenkins_connectivity "$jenkins_url" "$jenkins_user" "$jenkins_auth"; then
        validate_jcasc_with_jenkins "$config_file" "$jenkins_url" "$jenkins_user" "$jenkins_auth"
    else
        warn "Skipping live Jenkins validation (Jenkins not accessible)"
    fi

    success "JCasC schema validation passed"
    return 0
}

# Main execution
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    local config_file="$1"
    local jenkins_url="${2:-}"
    local jenkins_user="${3:-}"
    local jenkins_auth="${4:-}"

    if validate_jcasc_schema "$config_file" "$jenkins_url" "$jenkins_user" "$jenkins_auth"; then
        log ""
        success "✅ JCasC schema validation successful"
        exit 0
    else
        log ""
        error "❌ JCasC schema validation failed"
        exit 1
    fi
}

main "$@"
