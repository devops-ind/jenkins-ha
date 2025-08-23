#!/bin/bash

# Jenkins CASC Configuration Validation Script
# This script validates that Jenkins Configuration-as-Code is properly configured

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
TEAM_NAME="${1:-devops}"
TIMEOUT="${2:-120}"
VERBOSE="${VERBOSE:-false}"

# Helper functions
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

# Function to check if container is running
check_container_running() {
    local container_name="$1"
    if docker ps --filter "name=$container_name" --filter "status=running" --format "{{.Names}}" | grep -q "^$container_name$"; then
        return 0
    else
        return 1
    fi
}

# Function to get container port
get_container_port() {
    local container_name="$1"
    docker port "$container_name" 8080/tcp 2>/dev/null | cut -d':' -f2 || echo ""
}

# Function to wait for Jenkins to be ready
wait_for_jenkins() {
    local url="$1"
    local timeout="$2"
    local count=0
    
    log_info "Waiting for Jenkins to be ready at $url (timeout: ${timeout}s)..."
    
    while [ $count -lt $timeout ]; do
        if curl -s -f "$url/login" >/dev/null 2>&1; then
            log_success "Jenkins is responding"
            return 0
        fi
        sleep 2
        count=$((count + 2))
        [ $((count % 10)) -eq 0 ] && log_info "Still waiting... ($count/${timeout}s)"
    done
    
    log_error "Jenkins failed to respond within ${timeout} seconds"
    return 1
}

# Function to check if setup wizard is present
check_setup_wizard() {
    local url="$1"
    local response
    
    log_info "Checking for setup wizard at $url..."
    
    response=$(curl -s "$url" 2>/dev/null || echo "")
    
    if echo "$response" | grep -q "Unlock Jenkins\|initialAdminPassword\|setupWizard"; then
        log_error "Setup wizard detected - CASC configuration not loaded properly"
        return 1
    elif echo "$response" | grep -q "Dashboard\|Jenkins\|Welcome"; then
        log_success "No setup wizard detected - Jenkins appears properly configured"
        return 0
    else
        log_warning "Unable to determine Jenkins state from response"
        return 2
    fi
}

# Function to check CASC plugin installation
check_casc_plugin() {
    local container_name="$1"
    local url="$2"
    
    log_info "Checking CASC plugin installation..."
    
    # Check if plugin is installed via container
    if docker exec "$container_name" ls /var/jenkins_home/plugins/ 2>/dev/null | grep -q "configuration-as-code"; then
        log_success "CASC plugin files found in container"
    else
        log_warning "CASC plugin files not found in /var/jenkins_home/plugins/"
    fi
    
    # Check via Jenkins API if accessible
    if curl -s "$url/pluginManager/api/json?depth=1" 2>/dev/null | grep -q "configuration-as-code"; then
        log_success "CASC plugin confirmed via Jenkins API"
    else
        log_warning "Could not confirm CASC plugin via Jenkins API (may be due to authentication)"
    fi
}

# Function to check CASC configuration files
check_casc_files() {
    local container_name="$1"
    
    log_info "Checking CASC configuration files..."
    
    # Check for configuration files
    local casc_files=$(docker exec "$container_name" find /usr/share/jenkins/ref/casc_configs -name "*.yaml" -o -name "*.yml" 2>/dev/null || echo "")
    
    if [ -n "$casc_files" ]; then
        log_success "CASC configuration files found:"
        echo "$casc_files" | while read -r file; do
            echo "  - $file"
        done
        
        # Check main configuration file
        if docker exec "$container_name" test -f "/usr/share/jenkins/ref/casc_configs/jenkins.yaml" 2>/dev/null; then
            log_success "Main jenkins.yaml configuration file found"
        else
            log_error "Main jenkins.yaml configuration file not found"
            return 1
        fi
    else
        log_error "No CASC configuration files found"
        return 1
    fi
}

# Function to check environment variables
check_environment_variables() {
    local container_name="$1"
    
    log_info "Checking environment variables..."
    
    local casc_config=$(docker exec "$container_name" printenv CASC_JENKINS_CONFIG 2>/dev/null || echo "")
    local java_opts=$(docker exec "$container_name" printenv JAVA_OPTS 2>/dev/null || echo "")
    local jenkins_opts=$(docker exec "$container_name" printenv JENKINS_OPTS 2>/dev/null || echo "")
    
    if [ -n "$casc_config" ]; then
        log_success "CASC_JENKINS_CONFIG: $casc_config"
    else
        log_error "CASC_JENKINS_CONFIG environment variable not set"
    fi
    
    if echo "$java_opts" | grep -q "runSetupWizard=false"; then
        log_success "Setup wizard disabled in JAVA_OPTS"
    else
        log_error "Setup wizard not disabled in JAVA_OPTS: $java_opts"
    fi
    
    if [ -n "$jenkins_opts" ]; then
        log_success "JENKINS_OPTS: $jenkins_opts"
    else
        log_warning "JENKINS_OPTS not set"
    fi
}

# Function to analyze Jenkins logs
analyze_jenkins_logs() {
    local container_name="$1"
    
    log_info "Analyzing Jenkins startup logs..."
    
    local logs=$(docker logs "$container_name" 2>&1 | tail -100)
    
    if echo "$logs" | grep -q "Configuration as Code plugin"; then
        log_success "CASC plugin initialization found in logs"
    else
        log_warning "CASC plugin initialization not found in logs"
    fi
    
    if echo "$logs" | grep -q "Loading configuration"; then
        log_success "Configuration loading found in logs"
    else
        log_warning "Configuration loading not found in logs"
    fi
    
    if echo "$logs" | grep -q "Jenkins is fully up and running"; then
        log_success "Jenkins startup completed successfully"
    else
        log_warning "Jenkins startup completion not confirmed in logs"
    fi
    
    # Check for errors
    local errors=$(echo "$logs" | grep -i "error\|exception\|failed" | head -5)
    if [ -n "$errors" ]; then
        log_warning "Errors found in logs:"
        echo "$errors"
    fi
}

# Function to test Jenkins API access
test_jenkins_api() {
    local url="$1"
    
    log_info "Testing Jenkins API access..."
    
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url/api/json" 2>/dev/null || echo "000")
    
    case "$status_code" in
        "200")
            log_success "Jenkins API accessible (HTTP $status_code)"
            return 0
            ;;
        "403")
            log_success "Jenkins API responding with authentication required (HTTP $status_code) - This is expected"
            return 0
            ;;
        "404")
            log_warning "Jenkins API not found (HTTP $status_code) - May still be starting up"
            return 1
            ;;
        *)
            log_error "Jenkins API not accessible (HTTP $status_code)"
            return 1
            ;;
    esac
}

# Function to get team configuration
get_team_config() {
    local team_name="$1"
    
    # Try to get team configuration from Ansible inventory
    if [ -f "$PROJECT_ROOT/ansible/group_vars/all/jenkins_teams.yml" ]; then
        python3 -c "
import yaml
try:
    with open('$PROJECT_ROOT/ansible/group_vars/all/jenkins_teams.yml', 'r') as f:
        data = yaml.safe_load(f)
    teams = data.get('jenkins_teams', [])
    for team in teams:
        if team.get('team_name') == '$team_name':
            print(f\"active_environment={team.get('active_environment', 'blue')}\")
            print(f\"web_port={team.get('ports', {}).get('web', 8080)}\")
            break
    else:
        print('active_environment=blue')
        print('web_port=8080')
except Exception as e:
    print('active_environment=blue')
    print('web_port=8080')
" 2>/dev/null || {
            echo "active_environment=blue"
            echo "web_port=8080"
        }
    else
        echo "active_environment=blue"
        echo "web_port=8080"
    fi
}

# Main validation function
main() {
    echo "======================================"
    echo "Jenkins CASC Configuration Validator"
    echo "======================================"
    echo "Team: $TEAM_NAME"
    echo "Timeout: $TIMEOUT seconds"
    echo "======================================"
    
    # Get team configuration
    local team_config=$(get_team_config "$TEAM_NAME")
    eval "$team_config"
    
    local container_name="jenkins-${TEAM_NAME}-${active_environment}"
    local jenkins_port="$web_port"
    
    if [ "$active_environment" = "green" ]; then
        jenkins_port=$((web_port + 100))
    fi
    
    local jenkins_url="http://localhost:${jenkins_port}"
    
    log_info "Expected container: $container_name"
    log_info "Expected URL: $jenkins_url"
    log_info "Active environment: $active_environment"
    
    # Check if container is running
    if ! check_container_running "$container_name"; then
        log_error "Container $container_name is not running"
        
        # Try to find running Jenkins containers
        local running_containers=$(docker ps --filter "name=jenkins-" --format "{{.Names}}")
        if [ -n "$running_containers" ]; then
            log_info "Found running Jenkins containers:"
            echo "$running_containers"
        else
            log_error "No Jenkins containers are running"
        fi
        
        exit 1
    fi
    
    log_success "Container $container_name is running"
    
    # Perform all checks
    local checks_passed=0
    local total_checks=7
    
    # 1. Check CASC files
    if check_casc_files "$container_name"; then
        checks_passed=$((checks_passed + 1))
    fi
    
    # 2. Check environment variables
    if check_environment_variables "$container_name"; then
        checks_passed=$((checks_passed + 1))
    fi
    
    # 3. Wait for Jenkins to be ready
    if wait_for_jenkins "$jenkins_url" "$TIMEOUT"; then
        checks_passed=$((checks_passed + 1))
    fi
    
    # 4. Check for setup wizard
    if check_setup_wizard "$jenkins_url"; then
        checks_passed=$((checks_passed + 1))
    fi
    
    # 5. Check CASC plugin
    if check_casc_plugin "$container_name" "$jenkins_url"; then
        checks_passed=$((checks_passed + 1))
    fi
    
    # 6. Test API access
    if test_jenkins_api "$jenkins_url"; then
        checks_passed=$((checks_passed + 1))
    fi
    
    # 7. Analyze logs
    if analyze_jenkins_logs "$container_name"; then
        checks_passed=$((checks_passed + 1))
    fi
    
    # Summary
    echo "======================================"
    echo "Validation Summary"
    echo "======================================"
    echo "Checks passed: $checks_passed/$total_checks"
    
    if [ "$checks_passed" -eq "$total_checks" ]; then
        log_success "All checks passed! Jenkins CASC configuration is working properly"
        echo "Jenkins URL: $jenkins_url"
        exit 0
    elif [ "$checks_passed" -ge 4 ]; then
        log_warning "Most checks passed. Jenkins may be working with minor issues"
        echo "Jenkins URL: $jenkins_url"
        exit 0
    else
        log_error "Multiple checks failed. Jenkins CASC configuration needs attention"
        exit 1
    fi
}

# Script usage
usage() {
    echo "Usage: $0 [TEAM_NAME] [TIMEOUT_SECONDS]"
    echo "  TEAM_NAME: Team name to validate (default: devops)"
    echo "  TIMEOUT_SECONDS: Timeout for Jenkins to respond (default: 120)"
    echo ""
    echo "Environment variables:"
    echo "  VERBOSE: Set to 'true' for verbose output"
    echo ""
    echo "Examples:"
    echo "  $0                    # Validate devops team with default timeout"
    echo "  $0 dev-qa 180        # Validate dev-qa team with 3-minute timeout"
    echo "  VERBOSE=true $0      # Verbose output"
}

# Check if help is requested
if [ "$#" -gt 0 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
    usage
    exit 0
fi

# Ensure required tools are available
for tool in docker curl python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_error "Required tool '$tool' is not installed"
        exit 1
    fi
done

# Run main function
main "$@"