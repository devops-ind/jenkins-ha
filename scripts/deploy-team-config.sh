#!/bin/bash
# Team Configuration Deployment Script
# Deploys Jenkins team configuration to standby environment

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
Usage: $0 --team TEAM_NAME --config CONFIG_FILE [OPTIONS]

Deploys Jenkins team configuration to standby environment.

Required Arguments:
  --team TEAM_NAME      Team name (e.g., devops, developer)
  --config CONFIG_FILE  Path to JCasC configuration file

Options:
  --environment ENV     Target environment (auto|blue|green). Default: auto (deploys to standby)
  --skip-backup         Skip backing up existing configuration
  --restart             Restart Jenkins container after deployment
  --validate            Run health checks after deployment
  --help                Show this help message

Examples:
  # Deploy to standby environment (auto-detected)
  $0 --team devops --config jenkins-configs/devops.yml

  # Deploy to specific environment
  $0 --team devops --config jenkins-configs/devops.yml --environment green

  # Deploy, restart, and validate
  $0 --team devops --config jenkins-configs/devops.yml --restart --validate

Exit codes:
  0 - Deployment successful
  1 - Deployment failed
  2 - Usage error
  3 - Team or config not found
EOF
    exit 2
}

get_standby_environment() {
    local team=$1
    local state_file="/var/jenkins/${team}/blue-green-state.json"

    if [[ ! -f "$state_file" ]]; then
        warn "State file not found: $state_file"
        warn "Defaulting to green as standby"
        echo "green"
        return 0
    fi

    local active_env
    active_env=$(grep -o '"active_environment":\s*"[^"]*"' "$state_file" | cut -d'"' -f4)

    if [[ -z "$active_env" ]]; then
        warn "Could not determine active environment from state file"
        warn "Defaulting to green as standby"
        echo "green"
        return 0
    fi

    if [[ "$active_env" == "blue" ]]; then
        echo "green"
    else
        echo "blue"
    fi
}

deploy_config() {
    local team=$1
    local config_file=$2
    local target_env=$3
    local skip_backup=$4

    log "=========================================="
    log "Deploying Configuration"
    log "=========================================="
    log "Team: $team"
    log "Target Environment: $target_env"
    log "Config File: $config_file"
    log ""

    # Verify config file exists
    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
        return 3
    fi

    # Create config directory
    local config_dir="/var/jenkins/${team}/${target_env}/casc_configs"

    log "Creating config directory: $config_dir"
    mkdir -p "$config_dir"

    # Backup existing config
    if [[ "$skip_backup" == "false" ]] && [[ -f "${config_dir}/jenkins.yaml" ]]; then
        local backup_file="${config_dir}/jenkins.yaml.backup.$(date +%Y%m%d_%H%M%S)"
        log "Backing up existing config to: $backup_file"
        cp "${config_dir}/jenkins.yaml" "$backup_file"

        # Keep only last 10 backups
        log "Cleaning up old backups (keeping last 10)..."
        ls -t "${config_dir}"/jenkins.yaml.backup.* 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
    fi

    # Deploy new config
    log "Deploying new configuration..."
    cp "$config_file" "${config_dir}/jenkins.yaml"

    # Set permissions
    log "Setting permissions..."
    chown -R 1000:1000 "$config_dir"
    chmod 644 "${config_dir}/jenkins.yaml"

    # Verify deployment
    if [[ -f "${config_dir}/jenkins.yaml" ]]; then
        local file_size
        file_size=$(stat -f%z "${config_dir}/jenkins.yaml" 2>/dev/null || stat -c%s "${config_dir}/jenkins.yaml" 2>/dev/null)
        success "Configuration deployed successfully (${file_size} bytes)"

        log "Config location: ${config_dir}/jenkins.yaml"
        return 0
    else
        error "Configuration deployment failed"
        return 1
    fi
}

restart_container() {
    local team=$1
    local environment=$2

    local container_name="jenkins-${team}-${environment}"

    log "=========================================="
    log "Restarting Container"
    log "=========================================="
    log "Container: $container_name"
    log ""

    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        error "Container not found: $container_name"
        error "Available containers:"
        docker ps -a --format 'table {{.Names}}\t{{.Status}}'
        return 1
    fi

    # Check container status before restart
    local status
    status=$(docker inspect "$container_name" --format='{{.State.Status}}')
    log "Current status: $status"

    # Restart container
    log "Restarting container..."
    if docker restart "$container_name" &>/dev/null; then
        success "Container restarted successfully"

        log "Waiting for Jenkins to start (30 seconds)..."
        sleep 30

        # Check if container is running
        status=$(docker inspect "$container_name" --format='{{.State.Status}}')
        if [[ "$status" == "running" ]]; then
            success "Container is running"
            return 0
        else
            error "Container is not running after restart (status: $status)"
            return 1
        fi
    else
        error "Failed to restart container"
        return 1
    fi
}

validate_deployment() {
    local team=$1
    local environment=$2

    log "=========================================="
    log "Validating Deployment"
    log "=========================================="

    local container_name="jenkins-${team}-${environment}"
    local health_script="/var/jenkins/scripts/blue-green-healthcheck-${team}.sh"

    # Use dedicated health check script if available
    if [[ -f "$health_script" ]]; then
        log "Running health check script: $health_script"
        if bash "$health_script" "$environment"; then
            success "Health check passed"
            return 0
        else
            error "Health check failed"
            return 1
        fi
    fi

    # Basic validation if health script not available
    log "Running basic validation..."

    # Check 1: Container running
    local status
    status=$(docker inspect "$container_name" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")

    if [[ "$status" != "running" ]]; then
        error "Container is not running (status: $status)"
        return 1
    fi
    log "✓ Container is running"

    # Check 2: Get exposed port
    local port
    port=$(docker port "$container_name" 8080 2>/dev/null | cut -d: -f2 || echo "")

    if [[ -z "$port" ]]; then
        error "Could not determine exposed port"
        return 1
    fi
    log "✓ Exposed on port: $port"

    # Check 3: API accessibility
    log "Checking API accessibility (timeout: 5 minutes)..."
    for i in {1..30}; do
        if curl -sf "http://localhost:${port}/api/json" >/dev/null 2>&1; then
            success "Jenkins API is accessible"
            return 0
        fi
        log "Attempt $i/30: Waiting for Jenkins..."
        sleep 10
    done

    error "Jenkins API not accessible after 5 minutes"
    return 1
}

main() {
    local team=""
    local config_file=""
    local target_env="auto"
    local skip_backup="false"
    local should_restart="false"
    local should_validate="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --team)
                team="$2"
                shift 2
                ;;
            --config)
                config_file="$2"
                shift 2
                ;;
            --environment)
                target_env="$2"
                shift 2
                ;;
            --skip-backup)
                skip_backup="true"
                shift
                ;;
            --restart)
                should_restart="true"
                shift
                ;;
            --validate)
                should_validate="true"
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                error "Unknown argument: $1"
                usage
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$team" ]]; then
        error "Team name is required"
        usage
    fi

    if [[ -z "$config_file" ]]; then
        error "Config file is required"
        usage
    fi

    # Determine target environment
    if [[ "$target_env" == "auto" ]]; then
        log "Auto-detecting standby environment..."
        target_env=$(get_standby_environment "$team")
        log "Standby environment: $target_env"
    fi

    # Validate environment
    if [[ "$target_env" != "blue" ]] && [[ "$target_env" != "green" ]]; then
        error "Invalid environment: $target_env (must be blue or green)"
        exit 2
    fi

    # Execute deployment
    if ! deploy_config "$team" "$config_file" "$target_env" "$skip_backup"; then
        error "Configuration deployment failed"
        exit 1
    fi

    # Restart if requested
    if [[ "$should_restart" == "true" ]]; then
        if ! restart_container "$team" "$target_env"; then
            error "Container restart failed"
            exit 1
        fi
    fi

    # Validate if requested
    if [[ "$should_validate" == "true" ]]; then
        if ! validate_deployment "$team" "$target_env"; then
            error "Deployment validation failed"
            exit 1
        fi
    fi

    log ""
    success "=========================================="
    success "Deployment completed successfully!"
    success "=========================================="
    log "Team: $team"
    log "Environment: $target_env"
    log "Config: $config_file"
    log ""

    if [[ "$should_restart" == "false" ]]; then
        warn "Container was not restarted. Changes will take effect on next restart."
        log "To restart: docker restart jenkins-${team}-${target_env}"
    fi

    if [[ "$should_validate" == "false" ]]; then
        warn "Validation was skipped. Recommend running health checks manually."
        log "To validate: /var/jenkins/scripts/blue-green-healthcheck-${team}.sh ${target_env}"
    fi

    exit 0
}

main "$@"
