#!/bin/bash
# Architecture Detector for Jenkins HA Infrastructure
# Detects deployment architecture and provides configuration recommendations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FORMAT="json"
VERBOSE=false
ANSIBLE_INVENTORY=""
CHECK_CONTAINERS=true
CHECK_SERVICES=true

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
    --inventory PATH        Path to Ansible inventory file
    --format FORMAT         Output format (json, yaml, text)
    --no-containers        Skip container detection
    --no-services          Skip service detection
    --verbose              Enable verbose output
    --help                 Show this help

EXAMPLES:
    # Auto-detect architecture
    $0 --format json

    # Detect with specific inventory
    $0 --inventory /path/to/hosts.yml --format text

    # Skip container checks
    $0 --no-containers --format yaml

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --inventory)
                ANSIBLE_INVENTORY="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --no-containers)
                CHECK_CONTAINERS=false
                shift
                ;;
            --no-services)
                CHECK_SERVICES=false
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

# Detect Ansible inventory
detect_inventory() {
    local inventory_paths=(
        "ansible/inventories/production/hosts.yml"
        "ansible/inventories/local/hosts.yml"
        "inventories/production/hosts.yml"
        "inventories/local/hosts.yml"
        "hosts.yml"
        "inventory.yml"
    )
    
    if [[ -n "$ANSIBLE_INVENTORY" && -f "$ANSIBLE_INVENTORY" ]]; then
        echo "$ANSIBLE_INVENTORY"
        return 0
    fi
    
    # Search for inventory files
    for path in "${inventory_paths[@]}"; do
        if [[ -f "$path" ]]; then
            [[ "$VERBOSE" == "true" ]] && log "Found inventory: $path"
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Analyze Ansible inventory
analyze_inventory() {
    local inventory_file="$1"
    
    [[ "$VERBOSE" == "true" ]] && log "Analyzing inventory: $inventory_file"
    
    # Count jenkins_masters hosts
    local jenkins_masters_count=0
    local deployment_mode="unknown"
    local environment="unknown"
    
    if command -v ansible-inventory &>/dev/null && [[ -f "$inventory_file" ]]; then
        # Use ansible-inventory to parse
        local inventory_json
        inventory_json=$(ansible-inventory -i "$inventory_file" --list 2>/dev/null || echo '{}')
        
        jenkins_masters_count=$(echo "$inventory_json" | jq -r '.jenkins_masters.hosts | length' 2>/dev/null || echo "0")
        
        # Try to get deployment mode from variables
        deployment_mode=$(echo "$inventory_json" | jq -r '._meta.hostvars | to_entries | .[0].value.deployment_mode // "unknown"' 2>/dev/null || echo "unknown")
        environment=$(echo "$inventory_json" | jq -r '._meta.hostvars | to_entries | .[0].value.environment // "unknown"' 2>/dev/null || echo "unknown")
    else
        # Fallback: parse YAML manually (basic parsing)
        if command -v yq &>/dev/null; then
            jenkins_masters_count=$(yq eval '.jenkins_masters.hosts | length' "$inventory_file" 2>/dev/null || echo "0")
            deployment_mode=$(yq eval '.all.vars.deployment_mode // "unknown"' "$inventory_file" 2>/dev/null || echo "unknown")
            environment=$(yq eval '.all.vars.environment // "unknown"' "$inventory_file" 2>/dev/null || echo "unknown")
        else
            # Very basic grep-based parsing
            jenkins_masters_count=$(grep -A 10 "jenkins_masters:" "$inventory_file" | grep -c "ansible_host:" || echo "0")
            deployment_mode=$(grep "deployment_mode:" "$inventory_file" | head -1 | awk '{print $2}' | tr -d '"' || echo "unknown")
            environment=$(grep "environment:" "$inventory_file" | head -1 | awk '{print $2}' | tr -d '"' || echo "unknown")
        fi
    fi
    
    # Determine deployment mode based on host count
    if [[ "$jenkins_masters_count" -eq 1 ]]; then
        deployment_mode="container"
    elif [[ "$jenkins_masters_count" -gt 1 ]]; then
        deployment_mode="multi_vm"
    fi
    
    cat <<EOF
{
    "inventory_file": "$inventory_file",
    "jenkins_masters_count": $jenkins_masters_count,
    "deployment_mode": "$deployment_mode",
    "environment": "$environment"
}
EOF
}

# Detect container runtime
detect_container_runtime() {
    [[ "$VERBOSE" == "true" ]] && log "Detecting container runtime"
    
    local docker_available=false
    local podman_available=false
    local preferred_runtime="none"
    
    # Check Docker
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        docker_available=true
        preferred_runtime="docker"
    fi
    
    # Check Podman
    if command -v podman &>/dev/null && podman info &>/dev/null; then
        podman_available=true
        if [[ "$preferred_runtime" == "none" ]]; then
            preferred_runtime="podman"
        fi
    fi
    
    cat <<EOF
{
    "docker_available": $docker_available,
    "podman_available": $podman_available,
    "preferred_runtime": "$preferred_runtime"
}
EOF
}

# Detect containers
detect_containers() {
    local runtime="$1"
    
    [[ "$VERBOSE" == "true" ]] && log "Detecting Jenkins containers with runtime: $runtime"
    
    if [[ "$runtime" == "none" ]]; then
        echo '{"containers": [], "networks": [], "volumes": []}'
        return 0
    fi
    
    # Get Jenkins containers
    local containers
    containers=$($runtime ps -a --format "{{.Names}}" | grep "jenkins" || echo "")
    
    # Get Jenkins networks
    local networks
    networks=$($runtime network ls --format "{{.Name}}" | grep "jenkins" || echo "")
    
    # Get Jenkins volumes
    local volumes
    volumes=$($runtime volume ls --format "{{.Name}}" | grep "jenkins" || echo "")
    
    # Format as JSON array
    local containers_json="[]"
    local networks_json="[]"
    local volumes_json="[]"
    
    if [[ -n "$containers" ]]; then
        containers_json=$(echo "$containers" | jq -R . | jq -s .)
    fi
    
    if [[ -n "$networks" ]]; then
        networks_json=$(echo "$networks" | jq -R . | jq -s .)
    fi
    
    if [[ -n "$volumes" ]]; then
        volumes_json=$(echo "$volumes" | jq -R . | jq -s .)
    fi
    
    cat <<EOF
{
    "containers": $containers_json,
    "networks": $networks_json,
    "volumes": $volumes_json
}
EOF
}

# Detect systemd services
detect_services() {
    [[ "$VERBOSE" == "true" ]] && log "Detecting systemd services"
    
    local jenkins_services="[]"
    local haproxy_services="[]"
    
    if command -v systemctl &>/dev/null; then
        # Get Jenkins services
        local jenkins_service_list
        jenkins_service_list=$(systemctl list-units --type=service --all | grep jenkins | awk '{print $1}' || echo "")
        
        if [[ -n "$jenkins_service_list" ]]; then
            jenkins_services=$(echo "$jenkins_service_list" | jq -R . | jq -s .)
        fi
        
        # Get HAProxy services
        local haproxy_service_list
        haproxy_service_list=$(systemctl list-units --type=service --all | grep haproxy | awk '{print $1}' || echo "")
        
        if [[ -n "$haproxy_service_list" ]]; then
            haproxy_services=$(echo "$haproxy_service_list" | jq -R . | jq -s .)
        fi
    fi
    
    cat <<EOF
{
    "jenkins_services": $jenkins_services,
    "haproxy_services": $haproxy_services
}
EOF
}

# Analyze network configuration
analyze_network() {
    [[ "$VERBOSE" == "true" ]] && log "Analyzing network configuration"
    
    local listening_ports="[]"
    local jenkins_ports="[]"
    
    # Get listening ports
    if command -v ss &>/dev/null; then
        local ports
        ports=$(ss -tulpn | grep LISTEN | awk '{print $5}' | cut -d: -f2 | sort -n | uniq || echo "")
        
        if [[ -n "$ports" ]]; then
            listening_ports=$(echo "$ports" | jq -R . | jq -s .)
        fi
        
        # Filter Jenkins-related ports (8080-8099 range)
        local jenkins_port_list
        jenkins_port_list=$(echo "$ports" | grep -E "^80[8-9][0-9]$" || echo "")
        
        if [[ -n "$jenkins_port_list" ]]; then
            jenkins_ports=$(echo "$jenkins_port_list" | jq -R . | jq -s .)
        fi
    fi
    
    cat <<EOF
{
    "listening_ports": $listening_ports,
    "jenkins_ports": $jenkins_ports
}
EOF
}

# Detect shared storage
detect_shared_storage() {
    [[ "$VERBOSE" == "true" ]] && log "Detecting shared storage configuration"
    
    local nfs_mounts="[]"
    local jenkins_volumes="[]"
    local storage_type="local"
    
    # Check for NFS mounts
    if command -v mount &>/dev/null; then
        local nfs_mount_list
        nfs_mount_list=$(mount | grep nfs | awk '{print $3}' || echo "")
        
        if [[ -n "$nfs_mount_list" ]]; then
            nfs_mounts=$(echo "$nfs_mount_list" | jq -R . | jq -s .)
            storage_type="nfs"
        fi
    fi
    
    # Check for Jenkins-specific volumes/directories
    local jenkins_paths=(
        "/var/jenkins_home"
        "/opt/jenkins-shared"
        "/jenkins_home"
        "/data/jenkins"
    )
    
    local existing_paths=""
    for path in "${jenkins_paths[@]}"; do
        if [[ -d "$path" ]]; then
            existing_paths="${existing_paths}${path}\n"
        fi
    done
    
    if [[ -n "$existing_paths" ]]; then
        jenkins_volumes=$(echo -e "$existing_paths" | grep -v "^$" | jq -R . | jq -s .)
    fi
    
    cat <<EOF
{
    "storage_type": "$storage_type",
    "nfs_mounts": $nfs_mounts,
    "jenkins_volumes": $jenkins_volumes
}
EOF
}

# Generate architecture recommendations
generate_recommendations() {
    local detection_result="$1"
    
    [[ "$VERBOSE" == "true" ]] && log "Generating architecture recommendations"
    
    local deployment_mode=$(echo "$detection_result" | jq -r '.deployment_mode')
    local jenkins_masters_count=$(echo "$detection_result" | jq -r '.jenkins_masters_count')
    local container_runtime=$(echo "$detection_result" | jq -r '.container_runtime.preferred_runtime')
    local has_containers=$(echo "$detection_result" | jq -r '.containers.containers | length > 0')
    
    local recommendations="[]"
    local upgrade_strategy="blue_green"
    local coordination_method="local"
    
    case "$deployment_mode" in
        "container")
            recommendations=$(cat <<'EOF'
[
    "Use container-based blue-green deployment strategy",
    "Configure HAProxy for container traffic routing",
    "Implement container health monitoring",
    "Use shared volumes for persistent data",
    "Consider systemd for container lifecycle management"
]
EOF
)
            upgrade_strategy="container_blue_green"
            coordination_method="container_local"
            ;;
        "multi_vm")
            recommendations=$(cat <<'EOF'
[
    "Implement multi-VM consensus coordination",
    "Configure cross-VM health monitoring",
    "Setup distributed shared storage (NFS/GlusterFS)",
    "Use load balancer clustering",
    "Implement network partition handling"
]
EOF
)
            upgrade_strategy="distributed_blue_green"
            coordination_method="multi_vm_consensus"
            ;;
        *)
            recommendations=$(cat <<'EOF'
[
    "Review inventory configuration",
    "Ensure jenkins_masters group is properly defined",
    "Verify container runtime installation",
    "Check network connectivity between hosts"
]
EOF
)
            ;;
    esac
    
    cat <<EOF
{
    "deployment_mode": "$deployment_mode",
    "recommended_upgrade_strategy": "$upgrade_strategy",
    "coordination_method": "$coordination_method",
    "recommendations": $recommendations,
    "configuration_template": {
        "multi_vm_coordination": {
            "enabled": $(if [[ "$deployment_mode" == "multi_vm" ]]; then echo "true"; else echo "false"; fi),
            "deployment_mode": "$deployment_mode"
        },
        "container_coordination": {
            "enabled": $(if [[ "$deployment_mode" == "container" ]]; then echo "true"; else echo "false"; fi),
            "container_runtime": "$container_runtime"
        }
    }
}
EOF
}

# Main detection function
perform_detection() {
    [[ "$VERBOSE" == "true" ]] && log "Starting architecture detection"
    
    local detection_result="{"
    detection_result+='"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    detection_result+='"hostname": "'$(hostname)'",'
    
    # Detect inventory
    local inventory_file
    if inventory_file=$(detect_inventory); then
        local inventory_info=$(analyze_inventory "$inventory_file")
        detection_result+='"inventory": '$inventory_info','
        
        # Extract deployment mode for later use
        local deployment_mode=$(echo "$inventory_info" | jq -r '.deployment_mode')
        local jenkins_masters_count=$(echo "$inventory_info" | jq -r '.jenkins_masters_count')
    else
        warn "No Ansible inventory found, using runtime detection"
        detection_result+='"inventory": {"error": "No inventory file found"},'
        deployment_mode="unknown"
        jenkins_masters_count=0
    fi
    
    # Detect container runtime
    local container_info=$(detect_container_runtime)
    detection_result+='"container_runtime": '$container_info','
    
    local preferred_runtime=$(echo "$container_info" | jq -r '.preferred_runtime')
    
    # Detect containers if enabled
    if [[ "$CHECK_CONTAINERS" == "true" ]]; then
        local container_details=$(detect_containers "$preferred_runtime")
        detection_result+='"containers": '$container_details','
    fi
    
    # Detect services if enabled
    if [[ "$CHECK_SERVICES" == "true" ]]; then
        local service_info=$(detect_services)
        detection_result+='"services": '$service_info','
    fi
    
    # Analyze network
    local network_info=$(analyze_network)
    detection_result+='"network": '$network_info','
    
    # Detect shared storage
    local storage_info=$(detect_shared_storage)
    detection_result+='"shared_storage": '$storage_info','
    
    # Determine final deployment mode if unknown
    if [[ "$deployment_mode" == "unknown" ]]; then
        # Heuristic detection based on containers and services
        local container_count=$(echo "$container_details" | jq -r '.containers | length' 2>/dev/null || echo "0")
        local jenkins_service_count=$(echo "$service_info" | jq -r '.jenkins_services | length' 2>/dev/null || echo "0")
        
        if [[ "$container_count" -gt 0 ]]; then
            deployment_mode="container"
            jenkins_masters_count=1
        elif [[ "$jenkins_service_count" -gt 1 ]]; then
            deployment_mode="multi_vm"
            jenkins_masters_count="$jenkins_service_count"
        else
            deployment_mode="unknown"
        fi
    fi
    
    detection_result+='"deployment_mode": "'$deployment_mode'",'
    detection_result+='"jenkins_masters_count": '$jenkins_masters_count
    detection_result+='}'
    
    # Generate recommendations
    local recommendations=$(generate_recommendations "$detection_result")
    
    # Combine results
    local final_result=$(echo "$detection_result" | jq --argjson rec "$recommendations" '. + {recommendations: $rec}')
    
    echo "$final_result"
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
            local hostname=$(echo "$data" | jq -r '.hostname' 2>/dev/null || echo "unknown")
            local deployment_mode=$(echo "$data" | jq -r '.deployment_mode' 2>/dev/null || echo "unknown")
            local masters_count=$(echo "$data" | jq -r '.jenkins_masters_count' 2>/dev/null || echo "0")
            local container_runtime=$(echo "$data" | jq -r '.container_runtime.preferred_runtime' 2>/dev/null || echo "none")
            local upgrade_strategy=$(echo "$data" | jq -r '.recommendations.recommended_upgrade_strategy' 2>/dev/null || echo "unknown")
            
            echo "Jenkins HA Architecture Detection Report"
            echo "========================================"
            echo "Timestamp: $timestamp"
            echo "Hostname: $hostname"
            echo "Deployment Mode: $deployment_mode"
            echo "Jenkins Masters: $masters_count"
            echo "Container Runtime: $container_runtime"
            echo "Recommended Upgrade Strategy: $upgrade_strategy"
            echo ""
            
            # Recommendations
            echo "Recommendations:"
            local rec_count=$(echo "$data" | jq -r '.recommendations.recommendations | length' 2>/dev/null || echo "0")
            for ((i=0; i<rec_count; i++)); do
                local recommendation=$(echo "$data" | jq -r ".recommendations.recommendations[$i]" 2>/dev/null || echo "")
                echo "  • $recommendation"
            done
            echo ""
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
    
    # Perform detection
    local detection_result
    detection_result=$(perform_detection)
    
    # Format and output results
    format_output "$detection_result"
    
    # Exit successfully
    exit 0
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi