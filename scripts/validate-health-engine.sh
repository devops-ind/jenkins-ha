#!/bin/bash
# Health Engine Validation Script
# Validates the health engine setup and configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Validation results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_CHECKS++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check function wrapper
check() {
    local description="$1"
    local command="$2"
    ((TOTAL_CHECKS++))
    
    if eval "$command" >/dev/null 2>&1; then
        log_success "$description"
        return 0
    else
        log_fail "$description"
        return 1
    fi
}

# Validation functions
validate_files() {
    log_info "Validating required files..."
    
    check "Health engine main script exists" \
        "[[ -f '${SCRIPT_DIR}/health-engine.sh' ]]"
    
    check "Health engine utilities exist" \
        "[[ -f '${SCRIPT_DIR}/health-engine-utils.sh' ]]"
    
    check "Health engine integration script exists" \
        "[[ -f '${SCRIPT_DIR}/health-engine-integration.sh' ]]"
    
    check "Health engine configuration exists" \
        "[[ -f '${PROJECT_ROOT}/config/health-engine.json' ]]"
    
    check "Health engine scripts are executable" \
        "[[ -x '${SCRIPT_DIR}/health-engine.sh' ]]"
    
    check "Blue-green switch script exists" \
        "[[ -f '${SCRIPT_DIR}/blue-green-switch.sh' ]] || [[ -f '${PROJECT_ROOT}/ansible/roles/jenkins-master-v2/templates/blue-green-switch.sh.j2' ]]"
}

validate_configuration() {
    log_info "Validating configuration..."
    
    local config_file="${PROJECT_ROOT}/config/health-engine.json"
    
    check "Configuration file is valid JSON" \
        "jq '.' '$config_file' >/dev/null"
    
    check "Global configuration section exists" \
        "jq -e '.global' '$config_file' >/dev/null"
    
    check "Teams configuration section exists" \
        "jq -e '.teams' '$config_file' >/dev/null"
    
    check "DevOps team configuration exists" \
        "jq -e '.teams.devops' '$config_file' >/dev/null"
    
    check "Health policies section exists" \
        "jq -e '.health_policies' '$config_file' >/dev/null"
    
    check "Integration settings exist" \
        "jq -e '.integration_settings' '$config_file' >/dev/null"
    
    # Validate team configurations
    local teams
    teams=$(jq -r '.teams | keys[]' "$config_file" 2>/dev/null || echo "")
    
    for team in $teams; do
        check "Team $team has required weights configuration" \
            "jq -e '.teams.\"$team\".weights' '$config_file' >/dev/null"
        
        check "Team $team has required thresholds configuration" \
            "jq -e '.teams.\"$team\".thresholds' '$config_file' >/dev/null"
        
        check "Team $team has auto-healing configuration" \
            "jq -e '.teams.\"$team\".auto_healing' '$config_file' >/dev/null"
    done
}

validate_dependencies() {
    log_info "Validating dependencies..."
    
    check "jq is available" \
        "command -v jq"
    
    check "curl is available" \
        "command -v curl"
    
    check "bc is available" \
        "command -v bc"
    
    check "docker is available" \
        "command -v docker"
    
    check "systemctl is available" \
        "command -v systemctl"
}

validate_directories() {
    log_info "Validating directory structure..."
    
    check "Project root directory exists" \
        "[[ -d '$PROJECT_ROOT' ]]"
    
    check "Scripts directory exists" \
        "[[ -d '$SCRIPT_DIR' ]]"
    
    check "Config directory exists" \
        "[[ -d '${PROJECT_ROOT}/config' ]]"
    
    check "Logs directory can be created" \
        "mkdir -p '${PROJECT_ROOT}/logs'"
    
    check "Examples directory exists" \
        "[[ -d '${PROJECT_ROOT}/examples' ]]"
}

validate_monitoring_connectivity() {
    log_info "Validating monitoring system connectivity..."
    
    local config_file="${PROJECT_ROOT}/config/health-engine.json"
    local prometheus_url
    local loki_url
    local grafana_url
    
    prometheus_url=$(jq -r '.global.prometheus_url // "http://localhost:9090"' "$config_file")
    loki_url=$(jq -r '.global.loki_url // "http://localhost:3100"' "$config_file")
    grafana_url=$(jq -r '.global.grafana_url // "http://localhost:9300"' "$config_file")
    
    log_info "Testing connectivity to monitoring systems..."
    
    if curl -s --max-time 5 "${prometheus_url}/-/healthy" >/dev/null 2>&1; then
        log_success "Prometheus connectivity (${prometheus_url})"
        ((PASSED_CHECKS++))
    else
        log_warn "Prometheus not accessible at ${prometheus_url}"
    fi
    ((TOTAL_CHECKS++))
    
    if curl -s --max-time 5 "${loki_url}/ready" >/dev/null 2>&1; then
        log_success "Loki connectivity (${loki_url})"
        ((PASSED_CHECKS++))
    else
        log_warn "Loki not accessible at ${loki_url}"
    fi
    ((TOTAL_CHECKS++))
    
    if curl -s --max-time 5 "${grafana_url}/api/health" >/dev/null 2>&1; then
        log_success "Grafana connectivity (${grafana_url})"
        ((PASSED_CHECKS++))
    else
        log_warn "Grafana not accessible at ${grafana_url}"
    fi
    ((TOTAL_CHECKS++))
}

validate_health_engine_functionality() {
    log_info "Validating health engine functionality..."
    
    local health_engine_script="${SCRIPT_DIR}/health-engine.sh"
    
    check "Health engine script syntax is valid" \
        "bash -n '$health_engine_script'"
    
    check "Health engine can load configuration" \
        "'$health_engine_script' config >/dev/null"
    
    check "Health engine validation passes" \
        "'$health_engine_script' validate >/dev/null"
    
    # Test assessment for a specific team (dry run)
    log_info "Testing health assessment functionality..."
    
    if [[ -x "$health_engine_script" ]]; then
        local test_result
        if test_result=$("$health_engine_script" assess devops json 2>/dev/null); then
            if echo "$test_result" | jq -e '.assessments[0].team' >/dev/null 2>&1; then
                log_success "Health assessment returns valid JSON"
                ((PASSED_CHECKS++))
            else
                log_fail "Health assessment returns invalid JSON"
                ((FAILED_CHECKS++))
            fi
        else
            log_warn "Health assessment test failed (monitoring systems may not be available)"
        fi
        ((TOTAL_CHECKS++))
    fi
}

validate_integration_scripts() {
    log_info "Validating integration scripts..."
    
    local integration_script="${SCRIPT_DIR}/health-engine-integration.sh"
    local utils_script="${SCRIPT_DIR}/health-engine-utils.sh"
    
    check "Integration script syntax is valid" \
        "bash -n '$integration_script'"
    
    check "Utils script syntax is valid" \
        "bash -n '$utils_script'"
    
    check "Utils script can be sourced" \
        "source '$utils_script'"
}

validate_team_configurations() {
    log_info "Validating team-specific configurations..."
    
    local config_file="${PROJECT_ROOT}/config/health-engine.json"
    local teams_config="${PROJECT_ROOT}/ansible/group_vars/all/jenkins_teams.yml"
    
    if [[ -f "$teams_config" ]]; then
        check "Jenkins teams configuration file exists" \
            "[[ -f '$teams_config' ]]"
        
        # Extract team names from both files
        local health_teams
        local jenkins_teams
        
        health_teams=$(jq -r '.teams | keys[]' "$config_file" 2>/dev/null | sort)
        jenkins_teams=$(grep -E "^\s*-\s*team_name:" "$teams_config" 2>/dev/null | sed 's/.*team_name:\s*//' | sort)
        
        log_info "Comparing team configurations..."
        log_info "Health engine teams: $(echo "$health_teams" | tr '\n' ' ')"
        log_info "Jenkins teams: $(echo "$jenkins_teams" | tr '\n' ' ')"
        
        # Check if major teams are configured
        for team in devops dev-qa; do
            if echo "$health_teams" | grep -q "^$team$"; then
                log_success "Team $team is configured in health engine"
                ((PASSED_CHECKS++))
            else
                log_fail "Team $team is missing from health engine configuration"
                ((FAILED_CHECKS++))
            fi
            ((TOTAL_CHECKS++))
        done
    else
        log_warn "Jenkins teams configuration not found at $teams_config"
    fi
}

# Main validation function
main() {
    echo "================================================"
    echo "    Jenkins HA Health Engine Validation"
    echo "================================================"
    echo ""
    
    validate_files
    echo ""
    
    validate_directories
    echo ""
    
    validate_dependencies
    echo ""
    
    validate_configuration
    echo ""
    
    validate_team_configurations
    echo ""
    
    validate_integration_scripts
    echo ""
    
    validate_health_engine_functionality
    echo ""
    
    validate_monitoring_connectivity
    echo ""
    
    # Summary
    echo "================================================"
    echo "              Validation Summary"
    echo "================================================"
    echo "Total Checks: $TOTAL_CHECKS"
    echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
    
    local success_rate=0
    if (( TOTAL_CHECKS > 0 )); then
        success_rate=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))
    fi
    
    echo "Success Rate: ${success_rate}%"
    echo ""
    
    if (( FAILED_CHECKS == 0 )); then
        echo -e "${GREEN}✓ Health Engine validation completed successfully!${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Start monitoring systems (Prometheus, Loki, Grafana)"
        echo "2. Run initial health assessment: ./scripts/health-engine.sh assess"
        echo "3. Set up continuous monitoring: ./scripts/health-engine.sh monitor 300"
        echo "4. Configure notifications in config/health-engine.json"
        return 0
    else
        echo -e "${RED}✗ Health Engine validation found issues that need to be resolved.${NC}"
        echo ""
        echo "Common fixes:"
        echo "1. Install missing dependencies (jq, curl, bc)"
        echo "2. Fix configuration file syntax errors"
        echo "3. Ensure proper file permissions"
        echo "4. Start required monitoring services"
        return 1
    fi
}

# Execute validation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi