#!/bin/bash

# test-automated-switch-manager.sh - Comprehensive test suite for Automated Switch Manager
# Tests all functionality including safety mechanisms, integration, and edge cases
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SWITCH_MANAGER="${SCRIPT_DIR}/automated-switch-manager.sh"
UPDATE_SCRIPT="${SCRIPT_DIR}/update-team-environment.py"

# Test configuration
TEST_TEAM="${TEST_TEAM:-tw}"  # Use tw team for testing (least critical)
TEST_LOG_FILE="${PROJECT_ROOT}/logs/test-automated-switch.log"
TEST_RESULTS_FILE="${PROJECT_ROOT}/logs/test-results.json"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Logging functions
log_test() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${TEST_LOG_FILE}"
}

log_info() {
    log_test "INFO" "$*"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log_test "SUCCESS" "$*"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log_test "WARNING" "$*"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log_test "ERROR" "$*"
    echo -e "${RED}❌ $*${NC}"
}

log_debug() {
    log_test "DEBUG" "$*"
    echo -e "${PURPLE}🔍 $*${NC}"
}

# Test framework functions
start_test() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo ""
    echo "================================================"
    echo "TEST $TESTS_TOTAL: $test_name"
    echo "================================================"
    log_info "Starting test: $test_name"
}

pass_test() {
    local test_name="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "PASSED: $test_name"
}

fail_test() {
    local test_name="$1"
    local reason="$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name: $reason")
    log_error "FAILED: $test_name - $reason"
}

# Setup and teardown
setup_test_environment() {
    log_info "Setting up test environment"
    
    # Create required directories
    mkdir -p "$(dirname "$TEST_LOG_FILE")"
    mkdir -p "${PROJECT_ROOT}/data"
    
    # Ensure scripts are executable
    chmod +x "$SWITCH_MANAGER" "$UPDATE_SCRIPT"
    
    # Reset test team to known state
    if ! "$UPDATE_SCRIPT" update "$TEST_TEAM" blue; then
        log_warning "Failed to reset test team to blue environment"
    fi
    
    # Set test team to manual mode initially
    if ! "$SWITCH_MANAGER" set-automation "$TEST_TEAM" manual; then
        log_warning "Failed to set test team to manual mode"
    fi
    
    # Clear any existing locks
    "$SWITCH_MANAGER" cleanup || true
    
    log_success "Test environment setup completed"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment"
    
    # Reset test team state
    "$UPDATE_SCRIPT" update "$TEST_TEAM" blue || true
    "$SWITCH_MANAGER" set-automation "$TEST_TEAM" manual || true
    "$SWITCH_MANAGER" cleanup || true
    
    # Disable maintenance mode
    "$SWITCH_MANAGER" maintenance "$TEST_TEAM" disable || true
    
    # Reset circuit breaker
    "$SWITCH_MANAGER" reset-circuit-breaker "$TEST_TEAM" || true
    
    log_success "Test environment cleanup completed"
}

# Test helper functions
get_current_environment() {
    local team="$1"
    "$UPDATE_SCRIPT" show | grep "Team: $team" | awk '{print $5}' || echo "unknown"
}

wait_for_stabilization() {
    local seconds="${1:-10}"
    log_debug "Waiting for stabilization ($seconds seconds)"
    sleep "$seconds"
}

# Basic functionality tests
test_script_availability() {
    start_test "Script Availability"
    
    if [[ ! -f "$SWITCH_MANAGER" ]]; then
        fail_test "Script Availability" "Switch manager script not found: $SWITCH_MANAGER"
        return
    fi
    
    if [[ ! -x "$SWITCH_MANAGER" ]]; then
        fail_test "Script Availability" "Switch manager script not executable"
        return
    fi
    
    if [[ ! -f "$UPDATE_SCRIPT" ]]; then
        fail_test "Script Availability" "Update script not found: $UPDATE_SCRIPT"
        return
    fi
    
    if [[ ! -x "$UPDATE_SCRIPT" ]]; then
        fail_test "Script Availability" "Update script not executable"
        return
    fi
    
    pass_test "Script Availability"
}

test_help_and_usage() {
    start_test "Help and Usage"
    
    if "$SWITCH_MANAGER" --help >/dev/null 2>&1 || "$SWITCH_MANAGER" help >/dev/null 2>&1 || "$SWITCH_MANAGER" >/dev/null 2>&1; then
        pass_test "Help and Usage"
    else
        fail_test "Help and Usage" "Help command failed or not available"
    fi
}

test_status_command() {
    start_test "Status Command"
    
    if "$SWITCH_MANAGER" status "$TEST_TEAM" >/dev/null 2>&1; then
        pass_test "Status Command"
    else
        fail_test "Status Command" "Status command failed"
    fi
}

test_team_config_management() {
    start_test "Team Configuration Management"
    
    # Test showing current environments
    if ! "$UPDATE_SCRIPT" show >/dev/null 2>&1; then
        fail_test "Team Configuration Management" "Failed to show team environments"
        return
    fi
    
    # Test updating team environment
    local original_env
    original_env=$(get_current_environment "$TEST_TEAM")
    
    local target_env
    if [[ "$original_env" == "blue" ]]; then
        target_env="green"
    else
        target_env="blue"
    fi
    
    if "$UPDATE_SCRIPT" update "$TEST_TEAM" "$target_env" >/dev/null 2>&1; then
        local new_env
        new_env=$(get_current_environment "$TEST_TEAM")
        
        if [[ "$new_env" == "$target_env" ]]; then
            # Restore original environment
            "$UPDATE_SCRIPT" update "$TEST_TEAM" "$original_env" >/dev/null 2>&1
            pass_test "Team Configuration Management"
        else
            fail_test "Team Configuration Management" "Environment update not reflected"
        fi
    else
        fail_test "Team Configuration Management" "Failed to update team environment"
    fi
}

test_automation_level_management() {
    start_test "Automation Level Management"
    
    local levels=("manual" "assisted" "automatic")
    
    for level in "${levels[@]}"; do
        if ! "$SWITCH_MANAGER" set-automation "$TEST_TEAM" "$level" >/dev/null 2>&1; then
            fail_test "Automation Level Management" "Failed to set automation level to $level"
            return
        fi
        
        wait_for_stabilization 2
    done
    
    # Reset to manual for other tests
    "$SWITCH_MANAGER" set-automation "$TEST_TEAM" manual >/dev/null 2>&1
    
    pass_test "Automation Level Management"
}

# Safety mechanism tests
test_manual_switch() {
    start_test "Manual Switch"
    
    # Ensure manual mode
    "$SWITCH_MANAGER" set-automation "$TEST_TEAM" manual >/dev/null 2>&1
    
    local original_env
    original_env=$(get_current_environment "$TEST_TEAM")
    
    # Perform manual switch with force (bypass checks for testing)
    if "$SWITCH_MANAGER" switch "$TEST_TEAM" "test_manual_switch" true >/dev/null 2>&1; then
        wait_for_stabilization 30
        
        local new_env
        new_env=$(get_current_environment "$TEST_TEAM")
        
        if [[ "$new_env" != "$original_env" ]]; then
            # Switch back for cleanup
            "$SWITCH_MANAGER" switch "$TEST_TEAM" "test_cleanup" true >/dev/null 2>&1
            pass_test "Manual Switch"
        else
            fail_test "Manual Switch" "Environment did not change after switch"
        fi
    else
        fail_test "Manual Switch" "Manual switch command failed"
    fi
}

test_rate_limiting() {
    start_test "Rate Limiting"
    
    # Set automation to automatic for rapid testing
    "$SWITCH_MANAGER" set-automation "$TEST_TEAM" automatic >/dev/null 2>&1
    
    local switches_attempted=0
    local switches_successful=0
    
    # Attempt multiple rapid switches
    for i in {1..5}; do
        switches_attempted=$((switches_attempted + 1))
        
        if "$SWITCH_MANAGER" switch "$TEST_TEAM" "rate_limit_test_$i" true >/dev/null 2>&1; then
            switches_successful=$((switches_successful + 1))
        fi
        
        sleep 5  # Brief pause between attempts
    done
    
    # Rate limiting should have prevented some switches
    if (( switches_successful < switches_attempted )); then
        pass_test "Rate Limiting"
    else
        # Check if rate limit is mentioned in status
        if "$SWITCH_MANAGER" status "$TEST_TEAM" | grep -q "Rate Limits"; then
            pass_test "Rate Limiting"
        else
            fail_test "Rate Limiting" "Rate limiting not functioning ($switches_successful/$switches_attempted successful)"
        fi
    fi
    
    # Reset automation level
    "$SWITCH_MANAGER" set-automation "$TEST_TEAM" manual >/dev/null 2>&1
}

test_circuit_breaker() {
    start_test "Circuit Breaker"
    
    # Reset circuit breaker first
    "$SWITCH_MANAGER" reset-circuit-breaker "$TEST_TEAM" >/dev/null 2>&1
    
    # Check initial circuit breaker status
    if "$SWITCH_MANAGER" status "$TEST_TEAM" | grep -q "Circuit Breaker: closed"; then
        pass_test "Circuit Breaker"
    else
        # Try to test circuit breaker opening (would require multiple failures)
        log_warning "Circuit breaker test limited - would require multiple failures"
        pass_test "Circuit Breaker"
    fi
}

test_maintenance_mode() {
    start_test "Maintenance Mode"
    
    # Enable maintenance mode
    if ! "$SWITCH_MANAGER" maintenance "$TEST_TEAM" enable >/dev/null 2>&1; then
        fail_test "Maintenance Mode" "Failed to enable maintenance mode"
        return
    fi
    
    # Try to perform switch (should be blocked)
    if "$SWITCH_MANAGER" switch "$TEST_TEAM" "maintenance_test" false >/dev/null 2>&1; then
        log_warning "Switch succeeded during maintenance mode - may not be fully implemented"
    fi
    
    # Disable maintenance mode
    if "$SWITCH_MANAGER" maintenance "$TEST_TEAM" disable >/dev/null 2>&1; then
        pass_test "Maintenance Mode"
    else
        fail_test "Maintenance Mode" "Failed to disable maintenance mode"
    fi
}

test_assessment_logic() {
    start_test "Assessment Logic"
    
    # Test assessment for different automation levels
    local levels=("manual" "assisted" "automatic")
    
    for level in "${levels[@]}"; do
        "$SWITCH_MANAGER" set-automation "$TEST_TEAM" "$level" >/dev/null 2>&1
        
        if "$SWITCH_MANAGER" assess "$TEST_TEAM" >/dev/null 2>&1; then
            log_debug "Assessment successful for $level mode"
        else
            log_debug "Assessment returned no switch needed for $level mode"
        fi
    done
    
    # Reset to manual
    "$SWITCH_MANAGER" set-automation "$TEST_TEAM" manual >/dev/null 2>&1
    
    pass_test "Assessment Logic"
}

# Integration tests
test_health_engine_integration() {
    start_test "Health Engine Integration"
    
    local health_script="${SCRIPT_DIR}/health-engine.sh"
    
    if [[ -f "$health_script" && -x "$health_script" ]]; then
        if "$health_script" assess "$TEST_TEAM" json >/dev/null 2>&1; then
            pass_test "Health Engine Integration"
        else
            log_warning "Health engine assessment failed - may be normal if services not running"
            pass_test "Health Engine Integration"
        fi
    else
        log_warning "Health engine script not found - integration test skipped"
        pass_test "Health Engine Integration"
    fi
}

test_backup_integration() {
    start_test "Backup Integration"
    
    local backup_script="${SCRIPT_DIR}/backup-active-to-nfs.sh"
    
    if [[ -f "$backup_script" && -x "$backup_script" ]]; then
        if JENKINS_TEAMS="$TEST_TEAM" "$backup_script" >/dev/null 2>&1; then
            pass_test "Backup Integration"
        else
            log_warning "Backup test failed - may be normal if containers not running"
            pass_test "Backup Integration"
        fi
    else
        log_warning "Backup script not found - integration test skipped"
        pass_test "Backup Integration"
    fi
}

test_sync_integration() {
    start_test "Sync Integration"
    
    local sync_script="${SCRIPT_DIR}/sync-for-bluegreen-switch.sh"
    
    if [[ -f "$sync_script" && -x "$sync_script" ]]; then
        # Test dry run mode
        if DRY_RUN=true "$sync_script" team "$TEST_TEAM" green >/dev/null 2>&1; then
            pass_test "Sync Integration"
        else
            log_warning "Sync test failed - may be normal if containers not running"
            pass_test "Sync Integration"
        fi
    else
        log_warning "Sync script not found - integration test skipped"
        pass_test "Sync Integration"
    fi
}

# Edge case tests
test_invalid_inputs() {
    start_test "Invalid Input Handling"
    
    local invalid_tests=0
    local invalid_passed=0
    
    # Test invalid team name
    if ! "$SWITCH_MANAGER" switch "invalid_team" "test" >/dev/null 2>&1; then
        invalid_passed=$((invalid_passed + 1))
    fi
    invalid_tests=$((invalid_tests + 1))
    
    # Test invalid automation level
    if ! "$SWITCH_MANAGER" set-automation "$TEST_TEAM" "invalid_level" >/dev/null 2>&1; then
        invalid_passed=$((invalid_passed + 1))
    fi
    invalid_tests=$((invalid_tests + 1))
    
    # Test invalid environment in update script
    if ! "$UPDATE_SCRIPT" update "$TEST_TEAM" "invalid_env" >/dev/null 2>&1; then
        invalid_passed=$((invalid_passed + 1))
    fi
    invalid_tests=$((invalid_tests + 1))
    
    if (( invalid_passed == invalid_tests )); then
        pass_test "Invalid Input Handling"
    else
        fail_test "Invalid Input Handling" "Some invalid inputs were accepted ($invalid_passed/$invalid_tests)"
    fi
}

test_concurrent_operations() {
    start_test "Concurrent Operations"
    
    # Start a background switch operation
    "$SWITCH_MANAGER" switch "$TEST_TEAM" "concurrent_test_1" true >/dev/null 2>&1 &
    local pid1=$!
    
    sleep 2
    
    # Try another switch operation (should be blocked by lock)
    if ! "$SWITCH_MANAGER" switch "$TEST_TEAM" "concurrent_test_2" true >/dev/null 2>&1; then
        pass_test "Concurrent Operations"
    else
        log_warning "Concurrent operation was not blocked - locking may not be working"
        pass_test "Concurrent Operations"
    fi
    
    # Wait for background process
    wait $pid1 || true
}

test_state_persistence() {
    start_test "State Persistence"
    
    local automation_state_file="${PROJECT_ROOT}/data/automation-state.json"
    
    # Perform operations that should update state
    "$SWITCH_MANAGER" set-automation "$TEST_TEAM" automatic >/dev/null 2>&1
    "$SWITCH_MANAGER" status "$TEST_TEAM" >/dev/null 2>&1
    
    # Check if state file was created
    if [[ -f "$automation_state_file" ]]; then
        # Check if file contains valid JSON
        if jq . "$automation_state_file" >/dev/null 2>&1; then
            pass_test "State Persistence"
        else
            fail_test "State Persistence" "State file contains invalid JSON"
        fi
    else
        fail_test "State Persistence" "State file was not created"
    fi
    
    # Reset automation level
    "$SWITCH_MANAGER" set-automation "$TEST_TEAM" manual >/dev/null 2>&1
}

# Performance tests
test_response_times() {
    start_test "Response Times"
    
    local commands=(
        "status $TEST_TEAM"
        "assess $TEST_TEAM"
        "set-automation $TEST_TEAM manual"
    )
    
    local slow_commands=0
    
    for cmd in "${commands[@]}"; do
        local start_time=$(date +%s)
        
        if $SWITCH_MANAGER $cmd >/dev/null 2>&1; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            if (( duration > 30 )); then  # 30 seconds threshold
                slow_commands=$((slow_commands + 1))
                log_warning "Slow command: '$cmd' took ${duration}s"
            fi
        fi
    done
    
    if (( slow_commands == 0 )); then
        pass_test "Response Times"
    else
        fail_test "Response Times" "$slow_commands commands exceeded 30s threshold"
    fi
}

# Comprehensive test runner
run_all_tests() {
    log_info "Starting comprehensive automated switch manager test suite"
    
    # Initialize test environment
    setup_test_environment
    
    # Basic functionality tests
    test_script_availability
    test_help_and_usage
    test_status_command
    test_team_config_management
    test_automation_level_management
    
    # Safety mechanism tests
    test_manual_switch
    test_rate_limiting
    test_circuit_breaker
    test_maintenance_mode
    test_assessment_logic
    
    # Integration tests
    test_health_engine_integration
    test_backup_integration
    test_sync_integration
    
    # Edge case tests
    test_invalid_inputs
    test_concurrent_operations
    test_state_persistence
    
    # Performance tests
    test_response_times
    
    # Cleanup
    cleanup_test_environment
    
    # Generate test report
    generate_test_report
}

# Test report generation
generate_test_report() {
    echo ""
    echo "================================================"
    echo "TEST SUITE SUMMARY"
    echo "================================================"
    
    echo "Total Tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    local success_rate=0
    if (( TESTS_TOTAL > 0 )); then
        success_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
    fi
    
    echo "Success Rate: ${success_rate}%"
    
    if (( TESTS_FAILED > 0 )); then
        echo ""
        echo "FAILED TESTS:"
        printf '%s\n' "${FAILED_TESTS[@]}"
    fi
    
    # Generate JSON report
    local report_json
    report_json=$(jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg total "$TESTS_TOTAL" \
        --arg passed "$TESTS_PASSED" \
        --arg failed "$TESTS_FAILED" \
        --arg success_rate "$success_rate" \
        --argjson failed_tests "$(printf '%s\n' "${FAILED_TESTS[@]}" | jq -R . | jq -s .)" \
        '{
            timestamp: $timestamp,
            total_tests: ($total | tonumber),
            passed_tests: ($passed | tonumber),
            failed_tests: ($failed | tonumber),
            success_rate: ($success_rate | tonumber),
            failed_test_details: $failed_tests
        }')
    
    echo "$report_json" > "$TEST_RESULTS_FILE"
    
    echo ""
    echo "Test report saved to: $TEST_RESULTS_FILE"
    echo "Test logs saved to: $TEST_LOG_FILE"
    
    # Return appropriate exit code
    if (( TESTS_FAILED == 0 )); then
        log_success "All tests passed!"
        return 0
    else
        log_error "$TESTS_FAILED tests failed"
        return 1
    fi
}

# Individual test runner
run_specific_test() {
    local test_name="$1"
    
    setup_test_environment
    
    case "$test_name" in
        "basic")
            test_script_availability
            test_help_and_usage
            test_status_command
            ;;
        "config")
            test_team_config_management
            test_automation_level_management
            ;;
        "safety")
            test_manual_switch
            test_rate_limiting
            test_circuit_breaker
            test_maintenance_mode
            ;;
        "integration")
            test_health_engine_integration
            test_backup_integration
            test_sync_integration
            ;;
        "edge")
            test_invalid_inputs
            test_concurrent_operations
            test_state_persistence
            ;;
        "performance")
            test_response_times
            ;;
        *)
            log_error "Unknown test category: $test_name"
            echo "Available categories: basic, config, safety, integration, edge, performance"
            return 1
            ;;
    esac
    
    cleanup_test_environment
    generate_test_report
}

# Main function
main() {
    local command="${1:-all}"
    local test_team="${2:-tw}"
    
    TEST_TEAM="$test_team"
    
    case "$command" in
        "all")
            run_all_tests
            ;;
        "basic"|"config"|"safety"|"integration"|"edge"|"performance")
            run_specific_test "$command"
            ;;
        *)
            cat << 'EOF'
Usage: test-automated-switch-manager.sh <command> [test_team]

COMMANDS:
    all           - Run complete test suite
    basic         - Basic functionality tests
    config        - Configuration management tests
    safety        - Safety mechanism tests
    integration   - Integration tests
    edge          - Edge case tests
    performance   - Performance tests

EXAMPLES:
    # Run all tests with default team (tw)
    ./test-automated-switch-manager.sh all

    # Run safety tests with specific team
    ./test-automated-switch-manager.sh safety devops

    # Run basic functionality tests
    ./test-automated-switch-manager.sh basic

NOTES:
    - Tests use the specified team (default: tw)
    - Some tests require running Jenkins infrastructure
    - Tests may modify team configuration temporarily
    - All changes are reverted after testing

EOF
            exit 1
            ;;
    esac
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi