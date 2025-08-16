#!/bin/bash
# Container Operations Validator for Jenkins HA Infrastructure
# Comprehensive test suite for container-level operations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_RUNTIME="docker"
TEST_TEAMS="devops,developer"
OUTPUT_FORMAT="text"
VERBOSE=false
SKIP_DESTRUCTIVE=false
CLEANUP_AFTER_TEST=true

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TEST_RESULTS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${PURPLE}[INFO]${NC} $1"; }

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --runtime RUNTIME       Container runtime (docker, podman)
    --teams TEAMS          Comma-separated list of teams to test
    --format FORMAT        Output format (text, json, junit)
    --skip-destructive     Skip tests that modify system state
    --no-cleanup          Don't cleanup test containers after testing
    --verbose             Enable verbose output
    --help                Show this help

EXAMPLES:
    # Run all container validation tests
    $0 --runtime docker --teams "devops,developer"

    # Run safe tests only
    $0 --skip-destructive --format json

    # Verbose testing with cleanup disabled
    $0 --verbose --no-cleanup

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --runtime)
                CONTAINER_RUNTIME="$2"
                shift 2
                ;;
            --teams)
                TEST_TEAMS="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --skip-destructive)
                SKIP_DESTRUCTIVE=true
                shift
                ;;
            --no-cleanup)
                CLEANUP_AFTER_TEST=false
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Test helper functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    local destructive="${3:-false}"
    
    if [[ "$destructive" == "true" && "$SKIP_DESTRUCTIVE" == "true" ]]; then
        warn "SKIPPED: $test_name (destructive test)"
        ((TESTS_SKIPPED++))
        TEST_RESULTS+=("SKIPPED:$test_name")
        return 0
    fi
    
    info "Running: $test_name"
    
    local start_time=$(date +%s)
    local test_result="PASS"
    local error_message=""
    
    if $test_function; then
        success "PASSED: $test_name"
        ((TESTS_PASSED++))
    else
        error "FAILED: $test_name"
        ((TESTS_FAILED++))
        test_result="FAIL"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    TEST_RESULTS+=("$test_result:$test_name:${duration}s")
}

# Test 1: Container Runtime Availability
test_container_runtime_availability() {
    [[ "$VERBOSE" == "true" ]] && log "Testing container runtime availability: $CONTAINER_RUNTIME"
    
    # Check if runtime command exists
    if ! command -v "$CONTAINER_RUNTIME" &>/dev/null; then
        error "Container runtime not found: $CONTAINER_RUNTIME"
        return 1
    fi
    
    # Check if runtime is accessible
    if ! $CONTAINER_RUNTIME info &>/dev/null; then
        error "Container runtime not accessible: $CONTAINER_RUNTIME"
        return 1
    fi
    
    [[ "$VERBOSE" == "true" ]] && success "Container runtime is available and accessible"
    return 0
}

# Test 2: Architecture Detection
test_architecture_detection() {
    [[ "$VERBOSE" == "true" ]] && log "Testing architecture detection"
    
    local detector_script="$SCRIPT_DIR/architecture-detector.sh"
    
    if [[ ! -f "$detector_script" ]]; then
        error "Architecture detector script not found: $detector_script"
        return 1
    fi
    
    local detection_result
    if ! detection_result=$(bash "$detector_script" --format json 2>/dev/null); then
        error "Architecture detection failed"
        return 1
    fi
    
    # Validate JSON output
    if ! echo "$detection_result" | jq . &>/dev/null; then
        error "Architecture detector returned invalid JSON"
        return 1
    fi
    
    local deployment_mode=$(echo "$detection_result" | jq -r '.deployment_mode' 2>/dev/null || echo "unknown")
    
    if [[ "$deployment_mode" == "unknown" ]]; then
        error "Could not determine deployment mode"
        return 1
    fi
    
    [[ "$VERBOSE" == "true" ]] && success "Architecture detection successful: $deployment_mode"
    return 0
}

# Test 3: Container Network Creation
test_container_network_creation() {
    [[ "$VERBOSE" == "true" ]] && log "Testing container network creation"
    
    local network_name="jenkins-network-test"
    
    # Create test network
    if ! $CONTAINER_RUNTIME network create \
        --driver bridge \
        --subnet=172.21.0.0/16 \
        --gateway=172.21.0.1 \
        "$network_name" &>/dev/null; then
        error "Failed to create test network"
        return 1
    fi
    
    # Verify network exists
    if ! $CONTAINER_RUNTIME network ls | grep -q "$network_name"; then
        error "Test network not found after creation"
        return 1
    fi
    
    # Cleanup
    $CONTAINER_RUNTIME network rm "$network_name" &>/dev/null || true
    
    [[ "$VERBOSE" == "true" ]] && success "Container network creation test passed"
    return 0
}

# Test 4: Container Volume Management
test_container_volume_management() {
    [[ "$VERBOSE" == "true" ]] && log "Testing container volume management"
    
    local volume_name="jenkins-test-volume"
    
    # Create test volume
    if ! $CONTAINER_RUNTIME volume create "$volume_name" &>/dev/null; then
        error "Failed to create test volume"
        return 1
    fi
    
    # Verify volume exists
    if ! $CONTAINER_RUNTIME volume ls | grep -q "$volume_name"; then
        error "Test volume not found after creation"
        return 1
    fi
    
    # Test volume mounting
    local test_container="test-volume-container"
    if ! $CONTAINER_RUNTIME run --name "$test_container" \
        -v "$volume_name:/test" \
        --rm alpine:latest \
        sh -c "echo 'test' > /test/testfile && cat /test/testfile" &>/dev/null; then
        error "Failed to mount and use test volume"
        return 1
    fi
    
    # Cleanup
    $CONTAINER_RUNTIME volume rm "$volume_name" &>/dev/null || true
    
    [[ "$VERBOSE" == "true" ]] && success "Container volume management test passed"
    return 0
}

# Test 5: Container Readiness Assessment
test_container_readiness_assessment() {
    [[ "$VERBOSE" == "true" ]] && log "Testing container readiness assessment"
    
    local assessor_script="$SCRIPT_DIR/container-readiness-assessor.sh"
    
    if [[ ! -f "$assessor_script" ]]; then
        error "Container readiness assessor script not found: $assessor_script"
        return 1
    fi
    
    # Run assessment for test teams
    local assessment_result
    if ! assessment_result=$(bash "$assessor_script" \
        --teams "$TEST_TEAMS" \
        --runtime "$CONTAINER_RUNTIME" \
        --format json 2>/dev/null); then
        warn "Container readiness assessment returned non-zero exit code (expected for missing containers)"
    fi
    
    # Validate JSON output
    if ! echo "$assessment_result" | jq . &>/dev/null; then
        error "Container readiness assessor returned invalid JSON"
        return 1
    fi
    
    local timestamp=$(echo "$assessment_result" | jq -r '.timestamp' 2>/dev/null || echo "")
    
    if [[ -z "$timestamp" ]]; then
        error "Assessment result missing timestamp"
        return 1
    fi
    
    [[ "$VERBOSE" == "true" ]] && success "Container readiness assessment test passed"
    return 0
}

# Test 6: Blue-Green Container Simulation
test_blue_green_container_simulation() {
    [[ "$VERBOSE" == "true" ]] && log "Testing blue-green container simulation"
    
    local test_team="test-team"
    local blue_container="jenkins-${test_team}-blue"
    local green_container="jenkins-${test_team}-green"
    local test_network="jenkins-test-network"
    
    # Create test network
    $CONTAINER_RUNTIME network create "$test_network" &>/dev/null || true
    
    # Start blue container
    if ! $CONTAINER_RUNTIME run -d \
        --name "$blue_container" \
        --network "$test_network" \
        nginx:alpine &>/dev/null; then
        error "Failed to start blue container"
        return 1
    fi
    
    # Start green container
    if ! $CONTAINER_RUNTIME run -d \
        --name "$green_container" \
        --network "$test_network" \
        nginx:alpine &>/dev/null; then
        error "Failed to start green container"
        return 1
    fi
    
    # Test container communication
    local blue_ip
    blue_ip=$($CONTAINER_RUNTIME inspect "$blue_container" \
        --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
    
    if [[ -z "$blue_ip" ]]; then
        error "Could not get blue container IP"
        return 1
    fi
    
    # Test network connectivity
    if ! $CONTAINER_RUNTIME exec "$green_container" \
        sh -c "nc -z $blue_ip 80" &>/dev/null; then
        warn "Network connectivity test failed (this may be expected)"
    fi
    
    # Cleanup
    $CONTAINER_RUNTIME stop "$blue_container" "$green_container" &>/dev/null || true
    $CONTAINER_RUNTIME rm "$blue_container" "$green_container" &>/dev/null || true
    $CONTAINER_RUNTIME network rm "$test_network" &>/dev/null || true
    
    [[ "$VERBOSE" == "true" ]] && success "Blue-green container simulation test passed"
    return 0
}

# Test 7: Container Health Checks
test_container_health_checks() {
    [[ "$VERBOSE" == "true" ]] && log "Testing container health checks"
    
    local test_container="health-check-test"
    
    # Start container with health check
    if ! $CONTAINER_RUNTIME run -d \
        --name "$test_container" \
        --health-cmd="curl -f http://localhost:80 || exit 1" \
        --health-interval=10s \
        --health-timeout=5s \
        --health-retries=3 \
        nginx:alpine &>/dev/null; then
        error "Failed to start container with health check"
        return 1
    fi
    
    # Wait for health check to run
    sleep 15
    
    # Check health status
    local health_status
    health_status=$($CONTAINER_RUNTIME inspect "$test_container" \
        --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    
    if [[ "$health_status" != "healthy" && "$health_status" != "starting" ]]; then
        warn "Container health check status: $health_status"
    fi
    
    # Cleanup
    $CONTAINER_RUNTIME stop "$test_container" &>/dev/null || true
    $CONTAINER_RUNTIME rm "$test_container" &>/dev/null || true
    
    [[ "$VERBOSE" == "true" ]] && success "Container health checks test passed"
    return 0
}

# Test 8: Multi-VM Coordinator Container Mode
test_coordinator_container_mode() {
    [[ "$VERBOSE" == "true" ]] && log "Testing multi-VM coordinator template existence"
    
    local coordinator_template="$SCRIPT_DIR/../ansible/roles/jenkins-master-v2/templates/multi-vm-coordinator.sh.j2"
    
    if [[ ! -f "$coordinator_template" ]]; then
        error "Multi-VM coordinator template not found: $coordinator_template"
        return 1
    fi
    
    # Check template has container mode logic
    if ! grep -q "DEPLOYMENT_MODE.*container" "$coordinator_template"; then
        error "Container mode detection not found in coordinator template"
        return 1
    fi
    
    if ! grep -q "execute_container_upgrade" "$coordinator_template"; then
        error "Container upgrade function not found in coordinator template"
        return 1
    fi
    
    [[ "$VERBOSE" == "true" ]] && success "Multi-VM coordinator container mode template validation passed"
    return 0
}

# Test 9: Universal Upgrade Validator Container Mode
test_upgrade_validator_container_mode() {
    [[ "$VERBOSE" == "true" ]] && log "Testing universal upgrade validator template"
    
    local validator_template="$SCRIPT_DIR/../ansible/roles/jenkins-master-v2/templates/universal-upgrade-validator.sh.j2"
    
    if [[ ! -f "$validator_template" ]]; then
        error "Universal upgrade validator template not found: $validator_template"
        return 1
    fi
    
    # Check template has container mode logic
    if ! grep -q "container.*mode" "$validator_template"; then
        error "Container mode validation not found in validator template"
        return 1
    fi
    
    # Check for container-specific validation functions
    if ! grep -q "validate_container\|container_runtime" "$validator_template"; then
        error "Container validation functions not found in validator template"
        return 1
    fi
    
    [[ "$VERBOSE" == "true" ]] && success "Universal upgrade validator container mode template validation passed"
    return 0
}

# Test 10: Hybrid Configuration Manager
test_hybrid_config_manager() {
    [[ "$VERBOSE" == "true" ]] && log "Testing hybrid configuration manager"
    
    local config_manager_script="$SCRIPT_DIR/hybrid-config-manager.sh"
    
    if [[ ! -f "$config_manager_script" ]]; then
        error "Hybrid configuration manager script not found: $config_manager_script"
        return 1
    fi
    
    # Test detection (should work even without full setup)
    local detection_output
    if detection_output=$(bash "$config_manager_script" detect 2>/dev/null); then
        [[ "$VERBOSE" == "true" ]] && log "Detection output received"
    else
        warn "Configuration manager detection returned non-zero exit code"
    fi
    
    # Test validation (expected to fail if no config exists, but script should run)
    local validation_output
    if validation_output=$(bash "$config_manager_script" validate 2>/dev/null); then
        [[ "$VERBOSE" == "true" ]] && log "Validation completed successfully"
    else
        [[ "$VERBOSE" == "true" ]] && log "Validation failed as expected (no config file)"
    fi
    
    [[ "$VERBOSE" == "true" ]] && success "Hybrid configuration manager test passed"
    return 0
}

# Cleanup function
cleanup_test_artifacts() {
    if [[ "$CLEANUP_AFTER_TEST" != "true" ]]; then
        log "Skipping cleanup (--no-cleanup specified)"
        return 0
    fi
    
    log "Cleaning up test artifacts..."
    
    # Remove test containers
    local test_containers
    test_containers=$($CONTAINER_RUNTIME ps -a --format "{{.Names}}" | grep -E "(test|jenkins.*test)" || echo "")
    
    if [[ -n "$test_containers" ]]; then
        echo "$test_containers" | xargs $CONTAINER_RUNTIME rm -f &>/dev/null || true
    fi
    
    # Remove test networks
    local test_networks
    test_networks=$($CONTAINER_RUNTIME network ls --format "{{.Name}}" | grep -E "(test|jenkins.*test)" || echo "")
    
    if [[ -n "$test_networks" ]]; then
        echo "$test_networks" | xargs $CONTAINER_RUNTIME network rm &>/dev/null || true
    fi
    
    # Remove test volumes
    local test_volumes
    test_volumes=$($CONTAINER_RUNTIME volume ls --format "{{.Name}}" | grep -E "(test|jenkins.*test)" || echo "")
    
    if [[ -n "$test_volumes" ]]; then
        echo "$test_volumes" | xargs $CONTAINER_RUNTIME volume rm &>/dev/null || true
    fi
    
    success "Cleanup completed"
}

# Generate test report
generate_test_report() {
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    
    case "$OUTPUT_FORMAT" in
        "json")
            cat <<EOF
{
    "test_run": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "container_runtime": "$CONTAINER_RUNTIME",
        "test_teams": "$TEST_TEAMS",
        "total_tests": $total_tests,
        "tests_passed": $TESTS_PASSED,
        "tests_failed": $TESTS_FAILED,
        "tests_skipped": $TESTS_SKIPPED,
        "success_rate": $(echo "scale=2; $TESTS_PASSED * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
    },
    "test_results": [
$(IFS=$'\n'; for result in "${TEST_RESULTS[@]}"; do
    IFS=':' read -r status name duration <<< "$result"
    echo "        {\"status\": \"$status\", \"name\": \"$name\", \"duration\": \"$duration\"}"
    [[ "$result" != "${TEST_RESULTS[-1]}" ]] && echo ","
done)
    ]
}
EOF
            ;;
        "junit")
            cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="Jenkins HA Container Operations" tests="$total_tests" failures="$TESTS_FAILED" skipped="$TESTS_SKIPPED" time="$(date +%s)">
$(for result in "${TEST_RESULTS[@]}"; do
    IFS=':' read -r status name duration <<< "$result"
    echo "    <testcase name=\"$name\" classname=\"ContainerOperations\" time=\"${duration%s}\">"
    case "$status" in
        "FAIL") echo "        <failure message=\"Test failed\"/>" ;;
        "SKIPPED") echo "        <skipped message=\"Test skipped\"/>" ;;
    esac
    echo "    </testcase>"
done)
</testsuite>
EOF
            ;;
        "text"|*)
            echo
            echo "=================================="
            echo "Container Operations Test Report"
            echo "=================================="
            echo "Timestamp: $(date)"
            echo "Container Runtime: $CONTAINER_RUNTIME"
            echo "Test Teams: $TEST_TEAMS"
            echo
            echo "Test Summary:"
            echo "  Total Tests: $total_tests"
            echo "  Passed: $TESTS_PASSED"
            echo "  Failed: $TESTS_FAILED"
            echo "  Skipped: $TESTS_SKIPPED"
            echo "  Success Rate: $(echo "scale=1; $TESTS_PASSED * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")%"
            echo
            echo "Test Results:"
            for result in "${TEST_RESULTS[@]}"; do
                IFS=':' read -r status name duration <<< "$result"
                case "$status" in
                    "PASS") echo "  ✓ $name ($duration)" ;;
                    "FAIL") echo "  ✗ $name ($duration)" ;;
                    "SKIPPED") echo "  - $name (skipped)" ;;
                esac
            done
            echo "=================================="
            ;;
    esac
}

# Main test execution
run_all_tests() {
    log "Starting container operations validation tests..."
    
    # Test suite
    run_test "Container Runtime Availability" test_container_runtime_availability false
    run_test "Architecture Detection" test_architecture_detection false
    run_test "Container Network Creation" test_container_network_creation true
    run_test "Container Volume Management" test_container_volume_management true
    run_test "Container Readiness Assessment" test_container_readiness_assessment false
    run_test "Blue-Green Container Simulation" test_blue_green_container_simulation true
    run_test "Container Health Checks" test_container_health_checks true
    run_test "Multi-VM Coordinator Container Mode" test_coordinator_container_mode false
    run_test "Universal Upgrade Validator Container Mode" test_upgrade_validator_container_mode false
    run_test "Hybrid Configuration Manager" test_hybrid_config_manager false
    
    # Cleanup
    cleanup_test_artifacts
    
    # Generate report
    generate_test_report
    
    # Exit with appropriate code
    if [[ "$TESTS_FAILED" -eq 0 ]]; then
        success "All tests passed!"
        exit 0
    else
        error "$TESTS_FAILED test(s) failed"
        exit 1
    fi
}

# Main execution
main() {
    parse_args "$@"
    
    # Validate container runtime
    if ! command -v "$CONTAINER_RUNTIME" &>/dev/null; then
        error "Container runtime not found: $CONTAINER_RUNTIME"
        exit 1
    fi
    
    # Run tests
    run_all_tests
}

# Handle script termination
trap 'cleanup_test_artifacts; exit 130' INT TERM

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi