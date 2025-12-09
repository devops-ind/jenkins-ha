#!/bin/bash
# Container Readiness Assessor for Jenkins HA Infrastructure
# Assesses container health and readiness for upgrade operations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_RUNTIME="docker"
TEAMS=""
OUTPUT_FORMAT="json"
VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --teams TEAMS           Comma-separated list of teams to assess
    --runtime RUNTIME       Container runtime (docker, podman)
    --format FORMAT         Output format (json, yaml, text)
    --verbose              Enable verbose output
    --help                 Show this help

EXAMPLES:
    # Assess all containers for specific teams
    $0 --teams "devops,developer" --runtime docker

    # Verbose assessment with text output
    $0 --teams "devops" --format text --verbose

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --teams)
                TEAMS="$2"
                shift 2
                ;;
            --runtime)
                CONTAINER_RUNTIME="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
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

# Check container runtime availability
check_runtime() {
    if ! command -v "$CONTAINER_RUNTIME" &>/dev/null; then
        error "Container runtime '$CONTAINER_RUNTIME' not found"
        return 1
    fi
    
    if ! $CONTAINER_RUNTIME info &>/dev/null; then
        error "Container runtime '$CONTAINER_RUNTIME' is not running or accessible"
        return 1
    fi
    
    [[ "$VERBOSE" == "true" ]] && success "Container runtime '$CONTAINER_RUNTIME' is available"
    return 0
}

# Get container status
get_container_status() {
    local container_name="$1"
    
    if ! $CONTAINER_RUNTIME inspect "$container_name" &>/dev/null; then
        echo "not_found"
        return 0
    fi
    
    local status=$($CONTAINER_RUNTIME inspect "$container_name" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
    echo "$status"
}

# Get container health
get_container_health() {
    local container_name="$1"
    
    if ! $CONTAINER_RUNTIME inspect "$container_name" &>/dev/null; then
        echo "container_not_found"
        return 0
    fi
    
    # Check if container has health check defined
    local has_healthcheck=$($CONTAINER_RUNTIME inspect "$container_name" --format='{{if .Config.Healthcheck}}true{{else}}false{{end}}' 2>/dev/null || echo "false")
    
    if [[ "$has_healthcheck" == "true" ]]; then
        local health=$($CONTAINER_RUNTIME inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
        echo "$health"
    else
        # Fallback to basic connectivity check
        local status=$(get_container_status "$container_name")
        if [[ "$status" == "running" ]]; then
            # Try to get container port and test connectivity
            local port=$($CONTAINER_RUNTIME port "$container_name" 8080 2>/dev/null | cut -d: -f2 || echo "")
            if [[ -n "$port" ]] && curl -sf "http://localhost:${port}/login" &>/dev/null; then
                echo "healthy"
            else
                echo "unhealthy"
            fi
        else
            echo "unhealthy"
        fi
    fi
}

# Get container resource usage
get_container_resources() {
    local container_name="$1"
    
    if ! $CONTAINER_RUNTIME inspect "$container_name" &>/dev/null; then
        echo '{"cpu_usage": "N/A", "memory_usage": "N/A", "memory_limit": "N/A"}'
        return 0
    fi
    
    # Get container stats (single sample)
    local stats=$($CONTAINER_RUNTIME stats "$container_name" --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null | tail -n 1 || echo "N/A N/A N/A")
    
    local cpu_usage=$(echo "$stats" | awk '{print $1}' | sed 's/%//')
    local mem_usage=$(echo "$stats" | awk '{print $2}')
    local mem_percent=$(echo "$stats" | awk '{print $3}' | sed 's/%//')
    
    # Get memory limit from container inspect
    local mem_limit=$($CONTAINER_RUNTIME inspect "$container_name" --format='{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
    if [[ "$mem_limit" == "0" ]]; then
        mem_limit="unlimited"
    else
        mem_limit="$((mem_limit / 1024 / 1024))MB"
    fi
    
    cat <<EOF
{
    "cpu_usage": "${cpu_usage:-N/A}",
    "memory_usage": "${mem_usage:-N/A}",
    "memory_percent": "${mem_percent:-N/A}",
    "memory_limit": "$mem_limit"
}
EOF
}

# Assess team containers
assess_team_containers() {
    local team="$1"
    local blue_container="jenkins-${team}-blue"
    local green_container="jenkins-${team}-green"
    
    [[ "$VERBOSE" == "true" ]] && log "Assessing containers for team: $team"
    
    # Blue container assessment
    local blue_status=$(get_container_status "$blue_container")
    local blue_health=$(get_container_health "$blue_container")
    local blue_resources=$(get_container_resources "$blue_container")
    
    # Green container assessment
    local green_status=$(get_container_status "$green_container")
    local green_health=$(get_container_health "$green_container")
    local green_resources=$(get_container_resources "$green_container")
    
    # Determine active environment
    local active_env="unknown"
    if [[ "$blue_status" == "running" && "$blue_health" == "healthy" ]]; then
        if [[ "$green_status" == "running" && "$green_health" == "healthy" ]]; then
            # Both running, check which is receiving traffic (simplified check)
            active_env="blue"  # Default assumption
        else
            active_env="blue"
        fi
    elif [[ "$green_status" == "running" && "$green_health" == "healthy" ]]; then
        active_env="green"
    fi
    
    # Calculate readiness score
    local readiness_score=0
    
    # Blue container scoring
    case "$blue_status" in
        "running") ((readiness_score += 25)) ;;
        "exited") ((readiness_score += 10)) ;;
        *) ((readiness_score += 0)) ;;
    esac
    
    case "$blue_health" in
        "healthy") ((readiness_score += 15)) ;;
        "unhealthy") ((readiness_score += 5)) ;;
        *) ((readiness_score += 0)) ;;
    esac
    
    # Green container scoring
    case "$green_status" in
        "running") ((readiness_score += 25)) ;;
        "exited") ((readiness_score += 10)) ;;
        *) ((readiness_score += 0)) ;;
    esac
    
    case "$green_health" in
        "healthy") ((readiness_score += 15)) ;;
        "unhealthy") ((readiness_score += 5)) ;;
        *) ((readiness_score += 0)) ;;
    esac
    
    # Network and runtime scoring
    if $CONTAINER_RUNTIME network ls | grep -q "jenkins-network"; then
        ((readiness_score += 10))
    fi
    
    if $CONTAINER_RUNTIME volume ls | grep -q "jenkins_home"; then
        ((readiness_score += 10))
    fi
    
    cat <<EOF
{
    "team": "$team",
    "active_environment": "$active_env",
    "readiness_score": $readiness_score,
    "blue_container": {
        "name": "$blue_container",
        "status": "$blue_status",
        "health": "$blue_health",
        "resources": $blue_resources
    },
    "green_container": {
        "name": "$green_container",
        "status": "$green_status",
        "health": "$green_health",
        "resources": $green_resources
    }
}
EOF
}

# Check network connectivity
check_network_connectivity() {
    local network_name="jenkins-network"
    
    [[ "$VERBOSE" == "true" ]] && log "Checking container network connectivity"
    
    # Check if jenkins network exists
    local network_exists=false
    if $CONTAINER_RUNTIME network ls --format "{{.Name}}" | grep -q "^${network_name}$"; then
        network_exists=true
    fi
    
    # Get network details
    local network_subnet="unknown"
    local network_gateway="unknown"
    
    if [[ "$network_exists" == "true" ]]; then
        network_subnet=$($CONTAINER_RUNTIME network inspect "$network_name" --format='{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "unknown")
        network_gateway=$($CONTAINER_RUNTIME network inspect "$network_name" --format='{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "unknown")
    fi
    
    cat <<EOF
{
    "network_exists": $network_exists,
    "network_name": "$network_name",
    "subnet": "$network_subnet",
    "gateway": "$network_gateway"
}
EOF
}

# Check shared storage
check_shared_storage() {
    [[ "$VERBOSE" == "true" ]] && log "Checking shared storage configuration"
    
    # Check if jenkins_home volume exists
    local volume_exists=false
    if $CONTAINER_RUNTIME volume ls --format "{{.Name}}" | grep -q "jenkins_home"; then
        volume_exists=true
    fi
    
    # Check mount points
    local mount_point="/var/jenkins_home"
    local mount_available=false
    
    if [[ -d "$mount_point" ]] || [[ "$volume_exists" == "true" ]]; then
        mount_available=true
    fi
    
    # Get volume details
    local volume_driver="unknown"
    local volume_mountpoint="unknown"
    
    if [[ "$volume_exists" == "true" ]]; then
        volume_driver=$($CONTAINER_RUNTIME volume inspect jenkins_home --format='{{.Driver}}' 2>/dev/null || echo "unknown")
        volume_mountpoint=$($CONTAINER_RUNTIME volume inspect jenkins_home --format='{{.Mountpoint}}' 2>/dev/null || echo "unknown")
    fi
    
    cat <<EOF
{
    "volume_exists": $volume_exists,
    "mount_available": $mount_available,
    "volume_driver": "$volume_driver",
    "volume_mountpoint": "$volume_mountpoint",
    "mount_point": "$mount_point"
}
EOF
}

# Main assessment function
perform_assessment() {
    [[ "$VERBOSE" == "true" ]] && log "Starting container readiness assessment"
    
    # Parse teams
    IFS=',' read -ra TEAM_LIST <<< "$TEAMS"
    
    # Overall assessment data
    local assessment_data="{"
    assessment_data+='"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    assessment_data+='"container_runtime": "'$CONTAINER_RUNTIME'",'
    assessment_data+='"deployment_mode": "container",'
    
    # Runtime check
    if check_runtime; then
        assessment_data+='"runtime_available": true,'
    else
        assessment_data+='"runtime_available": false,'
    fi
    
    # Network connectivity
    local network_info=$(check_network_connectivity)
    assessment_data+='"network": '$network_info','
    
    # Shared storage
    local storage_info=$(check_shared_storage)
    assessment_data+='"shared_storage": '$storage_info','
    
    # Team assessments
    assessment_data+='"teams": ['
    
    local first_team=true
    for team in "${TEAM_LIST[@]}"; do
        if [[ "$first_team" == "false" ]]; then
            assessment_data+=','
        fi
        first_team=false
        
        local team_assessment=$(assess_team_containers "$team")
        assessment_data+="$team_assessment"
    done
    
    assessment_data+='],'
    
    # Overall readiness calculation
    local total_teams=${#TEAM_LIST[@]}
    local ready_teams=0
    local total_score=0
    
    # Calculate overall metrics (simplified)
    for team in "${TEAM_LIST[@]}"; do
        local team_score=$(assess_team_containers "$team" | jq -r '.readiness_score' 2>/dev/null || echo "0")
        total_score=$((total_score + team_score))
        if [[ "$team_score" -ge 70 ]]; then
            ((ready_teams++))
        fi
    done
    
    local average_score=$((total_teams > 0 ? total_score / total_teams : 0))
    local overall_ready=$((ready_teams == total_teams))
    
    assessment_data+='"overall_metrics": {'
    assessment_data+='"total_teams": '$total_teams','
    assessment_data+='"ready_teams": '$ready_teams','
    assessment_data+='"average_readiness_score": '$average_score','
    assessment_data+='"overall_ready": '$overall_ready','
    assessment_data+='"recommendation": "'
    
    if [[ "$overall_ready" == "1" && "$average_score" -ge 80 ]]; then
        assessment_data+='PROCEED"'
    elif [[ "$average_score" -ge 60 ]]; then
        assessment_data+='PROCEED_WITH_CAUTION"'
    else
        assessment_data+='ABORT"'
    fi
    
    assessment_data+='}'
    assessment_data+='}'
    
    echo "$assessment_data"
}

# Format output
format_output() {
    local data="$1"
    
    case "$OUTPUT_FORMAT" in
        "json")
            echo "$data" | jq . 2>/dev/null || echo "$data"
            ;;
        "yaml")
            echo "$data" | jq . | yq eval -P 2>/dev/null || echo "$data"
            ;;
        "text")
            # Convert JSON to readable text format
            local timestamp=$(echo "$data" | jq -r '.timestamp' 2>/dev/null || echo "unknown")
            local runtime=$(echo "$data" | jq -r '.container_runtime' 2>/dev/null || echo "unknown")
            local overall_ready=$(echo "$data" | jq -r '.overall_metrics.overall_ready' 2>/dev/null || echo "false")
            local recommendation=$(echo "$data" | jq -r '.overall_metrics.recommendation' 2>/dev/null || echo "UNKNOWN")
            
            echo "Container Readiness Assessment Report"
            echo "====================================="
            echo "Timestamp: $timestamp"
            echo "Container Runtime: $runtime"
            echo "Overall Ready: $([[ "$overall_ready" == "true" ]] && echo "YES" || echo "NO")"
            echo "Recommendation: $recommendation"
            echo ""
            
            # Team details
            local team_count=$(echo "$data" | jq -r '.teams | length' 2>/dev/null || echo "0")
            for ((i=0; i<team_count; i++)); do
                local team_name=$(echo "$data" | jq -r ".teams[$i].team" 2>/dev/null || echo "unknown")
                local team_score=$(echo "$data" | jq -r ".teams[$i].readiness_score" 2>/dev/null || echo "0")
                local active_env=$(echo "$data" | jq -r ".teams[$i].active_environment" 2>/dev/null || echo "unknown")
                
                echo "Team: $team_name"
                echo "  Readiness Score: $team_score/100"
                echo "  Active Environment: $active_env"
                echo ""
            done
            ;;
        *)
            error "Unknown output format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    parse_args "$@"
    
    if [[ -z "$TEAMS" ]]; then
        error "Teams parameter is required"
        usage
        exit 1
    fi
    
    # Perform assessment
    local assessment_result
    assessment_result=$(perform_assessment)
    
    # Format and output results
    format_output "$assessment_result"
    
    # Exit with appropriate code based on recommendation
    local recommendation=$(echo "$assessment_result" | jq -r '.overall_metrics.recommendation' 2>/dev/null || echo "ABORT")
    case "$recommendation" in
        "PROCEED")
            exit 0
            ;;
        "PROCEED_WITH_CAUTION")
            exit 0
            ;;
        "ABORT")
            exit 1
            ;;
        *)
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi