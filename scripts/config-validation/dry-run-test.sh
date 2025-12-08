#!/bin/bash
# Dry-run Test Script
# Starts a temporary Jenkins container with the new configuration
# and validates that Jenkins starts successfully

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
Usage: $0 <config-file> [--image IMAGE] [--timeout SECONDS] [--keep-container]

Performs a dry-run test by starting a temporary Jenkins container
with the provided configuration and validating it starts successfully.

Arguments:
  config-file         Path to the YAML config file (required)

Options:
  --image IMAGE       Jenkins Docker image to use (default: jenkins/jenkins:lts)
  --timeout SECONDS   Timeout for Jenkins startup (default: 300 seconds / 5 minutes)
  --keep-container    Keep the test container running after test (for debugging)
  --container-name    Custom container name (default: jenkins-dryrun-test-<timestamp>)

Environment Variables:
  JENKINS_IMAGE       Jenkins Docker image
  DRY_RUN_TIMEOUT     Startup timeout in seconds
  KEEP_TEST_CONTAINER Set to 'true' to keep container after test

Examples:
  $0 jenkins-configs/devops.yml
  $0 jenkins-configs/devops.yml --timeout 600
  $0 jenkins-configs/devops.yml --keep-container  # For debugging

Exit codes:
  0 - Dry-run test passed (Jenkins started successfully)
  1 - Dry-run test failed
  2 - Usage error
  3 - Docker not available
EOF
    exit 2
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        error "Docker is not installed or not in PATH"
        exit 3
    fi

    if ! docker info &>/dev/null; then
        error "Docker daemon is not running or not accessible"
        exit 3
    fi

    success "Docker is available"
}

cleanup_container() {
    local container_name="$1"
    local keep_container="$2"

    if [[ "$keep_container" == "true" ]]; then
        warn "Keeping test container: $container_name"
        log "To access: docker exec -it $container_name bash"
        log "To view logs: docker logs $container_name"
        log "To stop: docker stop $container_name"
        log "To remove: docker rm -f $container_name"
        return 0
    fi

    log "Cleaning up test container: $container_name"

    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        docker rm -f "$container_name" &>/dev/null || true
        success "Test container removed"
    fi
}

start_test_container() {
    local config_file="$1"
    local container_name="$2"
    local jenkins_image="$3"

    log "Starting test container: $container_name"
    log "Using image: $jenkins_image"

    # Get absolute path to config file
    local config_abs_path
    config_abs_path="$(cd "$(dirname "$config_file")" && pwd)/$(basename "$config_file")"

    log "Config file: $config_abs_path"

    # Start Jenkins container with the config mounted
    if docker run -d \
        --name "$container_name" \
        -p 0:8080 \
        -v "$config_abs_path:/var/jenkins_home/casc_configs/jenkins.yaml:ro" \
        -e CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs \
        -e JENKINS_ADMIN_PASSWORD=test123 \
        -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
        "$jenkins_image" &>/dev/null; then
        success "Test container started: $container_name"
        return 0
    else
        error "Failed to start test container"
        return 1
    fi
}

wait_for_jenkins() {
    local container_name="$1"
    local timeout="$2"

    log "Waiting for Jenkins to start (timeout: ${timeout}s)..."

    local elapsed=0
    local interval=5

    while [[ $elapsed -lt $timeout ]]; do
        # Check if container is still running
        if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            error "Container stopped unexpectedly"
            log "Container logs:"
            docker logs "$container_name" 2>&1 | tail -50
            return 1
        fi

        # Get the exposed port
        local exposed_port
        exposed_port=$(docker port "$container_name" 8080 | cut -d: -f2)

        if [[ -n "$exposed_port" ]]; then
            # Try to access Jenkins API
            if curl -s -f "http://localhost:${exposed_port}/api/json" &>/dev/null; then
                success "Jenkins is up and responding!"
                log "Accessible at: http://localhost:${exposed_port}"
                return 0
            fi
        fi

        log "Waiting... (${elapsed}s / ${timeout}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    error "Jenkins did not start within ${timeout} seconds"
    log "Container logs (last 50 lines):"
    docker logs "$container_name" 2>&1 | tail -50
    return 1
}

validate_jenkins_health() {
    local container_name="$1"

    log "Performing health checks..."

    local exposed_port
    exposed_port=$(docker port "$container_name" 8080 | cut -d: -f2)

    # Check 1: API accessible
    log "Check 1: API accessibility"
    if curl -s -f "http://localhost:${exposed_port}/api/json" >/dev/null; then
        success "API is accessible"
    else
        error "API is not accessible"
        return 1
    fi

    # Check 2: JCasC plugin loaded
    log "Check 2: JCasC plugin status"
    if docker exec "$container_name" test -f /var/jenkins_home/casc_configs/jenkins.yaml; then
        success "JCasC config file is present in container"
    else
        error "JCasC config file not found in container"
        return 1
    fi

    # Check 3: No startup errors in logs
    log "Check 3: Checking for errors in logs"
    if docker logs "$container_name" 2>&1 | grep -qi "ERROR"; then
        warn "Found ERROR entries in logs:"
        docker logs "$container_name" 2>&1 | grep -i "ERROR" | tail -10
    else
        success "No errors found in logs"
    fi

    # Check 4: JCasC configuration applied
    log "Check 4: JCasC configuration application"
    if docker logs "$container_name" 2>&1 | grep -q "Configuration as Code"; then
        success "JCasC plugin is active"
    else
        warn "Could not confirm JCasC plugin activity"
    fi

    # Check 5: Container health
    log "Check 5: Container health status"
    local container_status
    container_status=$(docker inspect "$container_name" --format='{{.State.Status}}')
    if [[ "$container_status" == "running" ]]; then
        success "Container is running"
    else
        error "Container status: $container_status"
        return 1
    fi

    success "All health checks passed"
    return 0
}

run_dry_run_test() {
    local config_file="$1"
    local jenkins_image="$2"
    local timeout="$3"
    local keep_container="$4"
    local container_name="$5"

    log "=========================================="
    log "Dry-run Test"
    log "=========================================="
    log "Config: $config_file"
    log "Image: $jenkins_image"
    log "Timeout: ${timeout}s"
    log ""

    # Check Docker availability
    check_docker

    # Cleanup any existing test container with same name
    cleanup_container "$container_name" "false"

    # Start test container
    if ! start_test_container "$config_file" "$container_name" "$jenkins_image"; then
        error "Failed to start test container"
        return 1
    fi

    # Wait for Jenkins to start
    local startup_result=0
    if ! wait_for_jenkins "$container_name" "$timeout"; then
        error "Jenkins failed to start"
        startup_result=1
    fi

    # Validate Jenkins health (only if startup succeeded)
    local health_result=0
    if [[ $startup_result -eq 0 ]]; then
        if ! validate_jenkins_health "$container_name"; then
            error "Health validation failed"
            health_result=1
        fi
    fi

    # Cleanup or keep container
    if [[ $startup_result -eq 0 ]] && [[ $health_result -eq 0 ]]; then
        success "Dry-run test passed"
        cleanup_container "$container_name" "$keep_container"
        return 0
    else
        error "Dry-run test failed"
        cleanup_container "$container_name" "$keep_container"
        return 1
    fi
}

main() {
    local config_file=""
    local jenkins_image="${JENKINS_IMAGE:-jenkins/jenkins:lts}"
    local timeout="${DRY_RUN_TIMEOUT:-300}"
    local keep_container="${KEEP_TEST_CONTAINER:-false}"
    local container_name="jenkins-dryrun-test-$(date +%s)"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --image)
                jenkins_image="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --keep-container)
                keep_container="true"
                shift
                ;;
            --container-name)
                container_name="$2"
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

    if [[ ! -f "$config_file" ]]; then
        error "Config file not found: $config_file"
        exit 1
    fi

    if run_dry_run_test "$config_file" "$jenkins_image" "$timeout" "$keep_container" "$container_name"; then
        log ""
        success "✅ Dry-run test successful"
        log "Configuration is ready for deployment to standby environment"
        exit 0
    else
        log ""
        error "❌ Dry-run test failed"
        log "Please review the errors above and fix the configuration"
        exit 1
    fi
}

main "$@"
