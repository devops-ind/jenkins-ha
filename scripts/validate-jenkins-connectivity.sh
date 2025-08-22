#!/bin/bash
# Jenkins Connectivity Validation Script
# Validates that Jenkins containers are properly accessible after health check fixes

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default teams and ports (can be overridden)
declare -A TEAMS=(
    ["devops"]="8080:50000:blue"
    ["dev-qa"]="8089:50009:green"
)

# Logging functions
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

# Test host connectivity
test_host_connectivity() {
    local host="$1"
    local port="$2"
    local team="$3"
    local timeout="${4:-5}"
    
    log_info "Testing connectivity to $host:$port for team $team"
    
    # Test with netcat if available
    if command -v nc >/dev/null 2>&1; then
        if timeout "$timeout" nc -z "$host" "$port" 2>/dev/null; then
            log_success "Port $host:$port is reachable (netcat)"
            return 0
        else
            log_warning "Port $host:$port is not reachable (netcat)"
        fi
    fi
    
    # Test with curl
    if curl -s --connect-timeout "$timeout" --max-time "$((timeout + 2))" "http://$host:$port/login" >/dev/null 2>&1; then
        log_success "Jenkins web interface accessible at $host:$port"
        return 0
    else
        log_warning "Jenkins web interface not accessible at $host:$port"
        return 1
    fi
}

# Test Jenkins API response
test_jenkins_api() {
    local host="$1"
    local port="$2"
    local team="$3"
    
    log_info "Testing Jenkins API for team $team at $host:$port"
    
    local response
    response=$(curl -s --connect-timeout 10 --max-time 15 "http://$host:$port/api/json" 2>/dev/null || echo "failed")
    
    if [[ "$response" == "failed" ]]; then
        log_error "Failed to connect to Jenkins API at $host:$port"
        return 1
    fi
    
    # Check if response contains Jenkins-specific content
    if echo "$response" | grep -qi "jenkins\|hudson\|mode\|description"; then
        log_success "Jenkins API responding correctly at $host:$port"
        return 0
    else
        log_warning "Unexpected API response from $host:$port"
        echo "Response preview: ${response:0:200}"
        return 1
    fi
}

# Check container status
check_container_status() {
    local team="$1"
    local environment="$2"
    local container_name="jenkins-$team-$environment"
    
    log_info "Checking container status for $container_name"
    
    if ! docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
        log_error "Container $container_name is not running"
        log_info "Available Jenkins containers:"
        docker ps --filter "name=jenkins" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No Jenkins containers found"
        return 1
    fi
    
    # Check container health
    local health_status
    health_status=$(docker inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    
    case "$health_status" in
        "healthy")
            log_success "Container $container_name is healthy"
            ;;
        "unhealthy")
            log_error "Container $container_name is unhealthy"
            log_info "Container logs (last 10 lines):"
            docker logs "$container_name" --tail 10
            return 1
            ;;
        "starting")
            log_warning "Container $container_name is still starting up"
            ;;
        *)
            log_warning "Container $container_name health status: $health_status"
            ;;
    esac
    
    # Check port mappings
    log_info "Port mappings for $container_name:"
    docker port "$container_name" 2>/dev/null || log_warning "No port mappings found for $container_name"
    
    return 0
}

# Test internal container connectivity
test_internal_connectivity() {
    local team="$1"
    local environment="$2"
    local container_name="jenkins-$team-$environment"
    
    log_info "Testing internal connectivity for $container_name"
    
    # Test internal Jenkins port
    if docker exec "$container_name" curl -f -s "http://localhost:8080/login" >/dev/null 2>&1; then
        log_success "Internal Jenkins web interface is accessible in $container_name"
        return 0
    else
        log_error "Internal Jenkins web interface is not accessible in $container_name"
        
        # Show Java processes
        log_info "Java processes in container:"
        docker exec "$container_name" ps aux 2>/dev/null | grep -i java || echo "No Java processes found"
        
        return 1
    fi
}

# Main validation function
validate_team_deployment() {
    local team="$1"
    local web_port="$2"
    local agent_port="$3"
    local environment="$4"
    
    echo
    echo "=============================================="
    echo "Validating $team team deployment"
    echo "Environment: $environment"
    echo "Web Port: $web_port, Agent Port: $agent_port"
    echo "=============================================="
    
    local success_count=0
    local total_tests=0
    
    # Test 1: Container status
    ((total_tests++))
    if check_container_status "$team" "$environment"; then
        ((success_count++))
    fi
    
    # Test 2: Internal container connectivity
    ((total_tests++))
    if test_internal_connectivity "$team" "$environment"; then
        ((success_count++))
    fi
    
    # Test 3: External connectivity - multiple hosts
    local hosts=("localhost" "127.0.0.1")
    
    # Add ansible_default_ipv4 if available
    if command -v ansible >/dev/null 2>&1; then
        local ansible_ip
        ansible_ip=$(ansible localhost -m setup -a 'filter=ansible_default_ipv4' 2>/dev/null | grep -o '"address": "[^"]*"' | cut -d'"' -f4 || echo "")
        if [[ -n "$ansible_ip" && "$ansible_ip" != "localhost" && "$ansible_ip" != "127.0.0.1" ]]; then
            hosts+=("$ansible_ip")
        fi
    fi
    
    local web_accessible=false
    for host in "${hosts[@]}"; do
        ((total_tests++))
        if test_host_connectivity "$host" "$web_port" "$team"; then
            web_accessible=true
            ((success_count++))
            break
        fi
    done
    
    # Test 4: Jenkins API accessibility
    if $web_accessible; then
        for host in "${hosts[@]}"; do
            ((total_tests++))
            if test_jenkins_api "$host" "$web_port" "$team"; then
                ((success_count++))
                break
            fi
        done
    else
        log_error "Skipping API test for $team - no web connectivity"
    fi
    
    # Test 5: Agent port accessibility
    local agent_accessible=false
    for host in "${hosts[@]}"; do
        ((total_tests++))
        if command -v nc >/dev/null 2>&1 && timeout 5 nc -z "$host" "$agent_port" 2>/dev/null; then
            log_success "Agent port $host:$agent_port is accessible for team $team"
            agent_accessible=true
            ((success_count++))
            break
        fi
    done
    
    if ! $agent_accessible; then
        log_warning "Agent port $agent_port not accessible for team $team"
    fi
    
    # Summary for team
    echo
    if [[ $success_count -eq $total_tests ]]; then
        log_success "Team $team: ALL TESTS PASSED ($success_count/$total_tests)"
        return 0
    elif [[ $success_count -gt 0 ]]; then
        log_warning "Team $team: PARTIAL SUCCESS ($success_count/$total_tests tests passed)"
        return 1
    else
        log_error "Team $team: ALL TESTS FAILED (0/$total_tests tests passed)"
        return 2
    fi
}

# Main execution
main() {
    echo "Jenkins Connectivity Validation Script"
    echo "======================================"
    echo "Validating Jenkins health check fixes"
    echo
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or not accessible"
        exit 1
    fi
    
    # Parse command line arguments for team configuration
    if [[ $# -gt 0 ]]; then
        # Custom team configuration provided
        log_info "Using custom team configuration from command line"
        # Format: team1:web_port:agent_port:environment team2:web_port:agent_port:environment
        TEAMS=()
        for arg in "$@"; do
            IFS=':' read -r team web_port agent_port environment <<< "$arg"
            TEAMS["$team"]="$web_port:$agent_port:$environment"
        done
    else
        log_info "Using default team configuration"
    fi
    
    local overall_success=true
    local team_count=0
    local success_count=0
    
    # Validate each team
    for team in "${!TEAMS[@]}"; do
        ((team_count++))
        IFS=':' read -r web_port agent_port environment <<< "${TEAMS[$team]}"
        
        if validate_team_deployment "$team" "$web_port" "$agent_port" "$environment"; then
            ((success_count++))
        else
            overall_success=false
        fi
    done
    
    # Final summary
    echo
    echo "=============================================="
    echo "FINAL VALIDATION SUMMARY"
    echo "=============================================="
    
    if $overall_success; then
        log_success "ALL TEAMS VALIDATED SUCCESSFULLY ($success_count/$team_count)"
        echo
        echo "🎉 Jenkins health check fixes are working correctly!"
        echo
        echo "Team access URLs:"
        for team in "${!TEAMS[@]}"; do
            IFS=':' read -r web_port agent_port environment <<< "${TEAMS[$team]}"
            echo "  • $team: http://localhost:$web_port ($environment environment)"
        done
        exit 0
    else
        log_error "VALIDATION FAILED for some teams ($success_count/$team_count successful)"
        echo
        echo "❌ Some Jenkins instances are not accessible"
        echo
        echo "Troubleshooting steps:"
        echo "1. Check container status: docker ps --filter 'name=jenkins'"
        echo "2. Check container logs: docker logs jenkins-{team}-{environment}"
        echo "3. Verify port mappings: docker port jenkins-{team}-{environment}"
        echo "4. Test internal access: docker exec jenkins-{team}-{environment} curl -f http://localhost:8080/login"
        echo "5. Check host networking: ss -tuln | grep :{port}"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"