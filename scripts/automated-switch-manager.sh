#!/bin/bash

# automated-switch-manager.sh - Intelligent Automated Blue-Green Switch Manager
# Integrates with multi-source health monitoring for zero-downtime auto-healing
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Core configuration files
HEALTH_CONFIG="${PROJECT_ROOT}/config/health-engine.json"
TEAM_CONFIG="${PROJECT_ROOT}/ansible/inventories/production/group_vars/all/main.yml"
AUTOMATION_STATE_FILE="${PROJECT_ROOT}/data/automation-state.json"
SWITCH_LOG_FILE="${PROJECT_ROOT}/logs/automated-switch.log"

# Safety and circuit breaker configurations
AUTOMATION_LOCK_DIR="/tmp/jenkins-switch-automation"
MAX_SWITCHES_PER_HOUR=3
MAX_SWITCHES_PER_DAY=10
STABILIZATION_PERIOD=300  # 5 minutes
VALIDATION_TIMEOUT=180    # 3 minutes
FLAPPING_THRESHOLD=5      # State changes in detection window
FLAPPING_DETECTION_WINDOW=1800  # 30 minutes

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${SWITCH_LOG_FILE}"
}

log_info() {
    log "INFO" "$*"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$*"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$*"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$*"
    echo -e "${RED}❌ $*${NC}"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$*"
        echo -e "${PURPLE}🔍 $*${NC}"
    fi
}

# Initialize required directories and files
initialize_automation() {
    mkdir -p "$(dirname "$SWITCH_LOG_FILE")"
    mkdir -p "$(dirname "$AUTOMATION_STATE_FILE")"
    mkdir -p "$AUTOMATION_LOCK_DIR"
    
    # Initialize state file if it doesn't exist
    if [[ ! -f "$AUTOMATION_STATE_FILE" ]]; then
        cat > "$AUTOMATION_STATE_FILE" << 'EOF'
{
  "automation_stats": {},
  "circuit_breakers": {},
  "switch_history": [],
  "team_automation_config": {},
  "last_update": ""
}
EOF
    fi
}

# Lock management for safe automation
acquire_switch_lock() {
    local team="$1"
    local operation="${2:-switch}"
    local max_wait="${3:-600}"  # 10 minutes default
    
    local lock_file="${AUTOMATION_LOCK_DIR}/${operation}-${team}.lock"
    local waited=0
    
    while [[ -f "$lock_file" ]] && (( waited < max_wait )); do
        log_debug "Waiting for lock: $lock_file"
        sleep 5
        waited=$((waited + 5))
    done
    
    if (( waited >= max_wait )); then
        log_error "Failed to acquire lock $lock_file after ${max_wait}s"
        return 1
    fi
    
    echo "$$:$(date +%s)" > "$lock_file"
    log_debug "Acquired lock: $lock_file"
}

release_switch_lock() {
    local team="$1"
    local operation="${2:-switch}"
    local lock_file="${AUTOMATION_LOCK_DIR}/${operation}-${team}.lock"
    
    if [[ -f "$lock_file" ]]; then
        rm -f "$lock_file"
        log_debug "Released lock: $lock_file"
    fi
}

# Cleanup function for safe exit
cleanup_locks() {
    log_debug "Cleaning up automation locks..."
    find "$AUTOMATION_LOCK_DIR" -name "*.lock" -user "$(whoami)" -delete 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup_locks EXIT

# Team configuration management
get_team_config() {
    local team="$1"
    
    if [[ -f "$HEALTH_CONFIG" ]]; then
        jq -r --arg team "$team" '.teams[$team] // {}' "$HEALTH_CONFIG" 2>/dev/null
    else
        echo '{}'
    fi
}

get_team_ansible_config() {
    local team="$1"
    
    if [[ -f "$TEAM_CONFIG" ]]; then
        python3 -c "
import yaml
import json
import sys

try:
    with open('$TEAM_CONFIG', 'r') as f:
        config = yaml.safe_load(f)
    
    teams = config.get('jenkins_teams_config', [])
    for team_cfg in teams:
        if team_cfg.get('team_name') == '$team':
            print(json.dumps(team_cfg))
            sys.exit(0)
    
    print('{}')
except Exception as e:
    print('{}')
" 2>/dev/null || echo '{}'
    else
        echo '{}'
    fi
}

get_current_active_environment() {
    local team="$1"
    local ansible_config
    ansible_config=$(get_team_ansible_config "$team")
    
    echo "$ansible_config" | jq -r '.active_environment // "blue"'
}

get_target_environment() {
    local current_env="$1"
    if [[ "$current_env" == "blue" ]]; then
        echo "green"
    else
        echo "blue"
    fi
}

# Automation state management
load_automation_state() {
    if [[ -f "$AUTOMATION_STATE_FILE" ]]; then
        cat "$AUTOMATION_STATE_FILE"
    else
        echo '{}'
    fi
}

save_automation_state() {
    local state="$1"
    echo "$state" | jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.last_update = $timestamp' > "$AUTOMATION_STATE_FILE"
}

update_switch_history() {
    local team="$1"
    local from_env="$2"
    local to_env="$3"
    local trigger_reason="$4"
    local result="$5"
    local duration="$6"
    
    local state
    state=$(load_automation_state)
    
    local switch_entry
    switch_entry=$(jq -n \
        --arg team "$team" \
        --arg from_env "$from_env" \
        --arg to_env "$to_env" \
        --arg trigger_reason "$trigger_reason" \
        --arg result "$result" \
        --arg duration "$duration" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            team: $team,
            from_environment: $from_env,
            to_environment: $to_env,
            trigger_reason: $trigger_reason,
            result: $result,
            duration_seconds: ($duration | tonumber),
            timestamp: $timestamp
        }')
    
    state=$(echo "$state" | jq --argjson entry "$switch_entry" '.switch_history += [$entry]')
    
    # Keep only last 100 entries per team
    state=$(echo "$state" | jq '.switch_history = (.switch_history | sort_by(.timestamp) | .[-100:])')
    
    save_automation_state "$state"
}

update_automation_stats() {
    local team="$1"
    local operation="$2"
    local result="$3"
    
    local state
    state=$(load_automation_state)
    
    local hour_key=$(date +%Y%m%d_%H)
    local day_key=$(date +%Y%m%d)
    
    # Update hourly stats
    state=$(echo "$state" | jq \
        --arg team "$team" \
        --arg hour "$hour_key" \
        --arg operation "$operation" \
        --arg result "$result" \
        '
        .automation_stats[$team] //= {} |
        .automation_stats[$team].hourly //= {} |
        .automation_stats[$team].hourly[$hour] //= {"switches": 0, "successes": 0, "failures": 0} |
        .automation_stats[$team].hourly[$hour].switches += 1 |
        if $result == "success" then
            .automation_stats[$team].hourly[$hour].successes += 1
        else
            .automation_stats[$team].hourly[$hour].failures += 1
        end
        ')
    
    # Update daily stats
    state=$(echo "$state" | jq \
        --arg team "$team" \
        --arg day "$day_key" \
        --arg operation "$operation" \
        --arg result "$result" \
        '
        .automation_stats[$team] //= {} |
        .automation_stats[$team].daily //= {} |
        .automation_stats[$team].daily[$day] //= {"switches": 0, "successes": 0, "failures": 0} |
        .automation_stats[$team].daily[$day].switches += 1 |
        if $result == "success" then
            .automation_stats[$team].daily[$day].successes += 1
        else
            .automation_stats[$team].daily[$day].failures += 1
        end
        ')
    
    save_automation_state "$state"
}

# Circuit breaker pattern implementation
check_circuit_breaker() {
    local team="$1"
    local operation="${2:-switch}"
    
    local state
    state=$(load_automation_state)
    
    local circuit_status
    circuit_status=$(echo "$state" | jq -r --arg team "$team" --arg op "$operation" '.circuit_breakers[$team][$op].status // "closed"')
    
    local last_failure
    last_failure=$(echo "$state" | jq -r --arg team "$team" --arg op "$operation" '.circuit_breakers[$team][$op].last_failure // "1970-01-01T00:00:00Z"')
    
    local failure_count
    failure_count=$(echo "$state" | jq -r --arg team "$team" --arg op "$operation" '.circuit_breakers[$team][$op].failure_count // 0')
    
    case "$circuit_status" in
        "open")
            # Check if enough time has passed to attempt half-open
            local last_failure_timestamp=$(date -d "$last_failure" +%s 2>/dev/null || echo 0)
            local current_timestamp=$(date +%s)
            local time_since_failure=$((current_timestamp - last_failure_timestamp))
            
            if (( time_since_failure > STABILIZATION_PERIOD )); then
                log_info "Circuit breaker transitioning to half-open for team $team"
                update_circuit_breaker "$team" "$operation" "half-open" "$failure_count"
                return 0  # Allow attempt
            else
                local remaining=$((STABILIZATION_PERIOD - time_since_failure))
                log_warning "Circuit breaker open for team $team - $remaining seconds remaining"
                return 1  # Block attempt
            fi
            ;;
        "half-open")
            log_info "Circuit breaker half-open for team $team - allowing test attempt"
            return 0  # Allow single attempt
            ;;
        "closed"|*)
            return 0  # Normal operation
            ;;
    esac
}

update_circuit_breaker() {
    local team="$1"
    local operation="$2"
    local status="$3"
    local failure_count="${4:-0}"
    
    local state
    state=$(load_automation_state)
    
    state=$(echo "$state" | jq \
        --arg team "$team" \
        --arg op "$operation" \
        --arg status "$status" \
        --arg count "$failure_count" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '
        .circuit_breakers[$team] //= {} |
        .circuit_breakers[$team][$op] = {
            status: $status,
            failure_count: ($count | tonumber),
            last_failure: (if $status == "open" then $timestamp else .circuit_breakers[$team][$op].last_failure end),
            last_update: $timestamp
        }
        ')
    
    save_automation_state "$state"
}

handle_circuit_breaker_failure() {
    local team="$1"
    local operation="${2:-switch}"
    
    local state
    state=$(load_automation_state)
    
    local failure_count
    failure_count=$(echo "$state" | jq -r --arg team "$team" --arg op "$operation" '.circuit_breakers[$team][$op].failure_count // 0')
    
    failure_count=$((failure_count + 1))
    
    if (( failure_count >= 3 )); then
        log_warning "Opening circuit breaker for team $team after $failure_count failures"
        update_circuit_breaker "$team" "$operation" "open" "$failure_count"
    else
        log_warning "Circuit breaker failure $failure_count/3 for team $team"
        update_circuit_breaker "$team" "$operation" "closed" "$failure_count"
    fi
}

handle_circuit_breaker_success() {
    local team="$1"
    local operation="${2:-switch}"
    
    log_success "Closing circuit breaker for team $team after successful operation"
    update_circuit_breaker "$team" "$operation" "closed" 0
}

# Flapping detection
detect_flapping() {
    local team="$1"
    
    local state
    state=$(load_automation_state)
    
    local cutoff_time=$(date -u -d "$FLAPPING_DETECTION_WINDOW seconds ago" +%Y-%m-%dT%H:%M:%SZ)
    
    local recent_switches
    recent_switches=$(echo "$state" | jq \
        --arg team "$team" \
        --arg cutoff "$cutoff_time" \
        '.switch_history | map(select(.team == $team and .timestamp > $cutoff)) | length')
    
    if (( recent_switches >= FLAPPING_THRESHOLD )); then
        log_warning "Flapping detected for team $team: $recent_switches switches in last $((FLAPPING_DETECTION_WINDOW/60)) minutes"
        return 0  # Flapping detected
    fi
    
    return 1  # No flapping
}

# Safety checks
check_rate_limits() {
    local team="$1"
    
    local state
    state=$(load_automation_state)
    
    local hour_key=$(date +%Y%m%d_%H)
    local day_key=$(date +%Y%m%d)
    
    local hourly_switches
    hourly_switches=$(echo "$state" | jq -r --arg team "$team" --arg hour "$hour_key" '.automation_stats[$team].hourly[$hour].switches // 0')
    
    local daily_switches
    daily_switches=$(echo "$state" | jq -r --arg team "$team" --arg day "$day_key" '.automation_stats[$team].daily[$day].switches // 0')
    
    if (( hourly_switches >= MAX_SWITCHES_PER_HOUR )); then
        log_error "Hourly rate limit exceeded for team $team: $hourly_switches/$MAX_SWITCHES_PER_HOUR"
        return 1
    fi
    
    if (( daily_switches >= MAX_SWITCHES_PER_DAY )); then
        log_error "Daily rate limit exceeded for team $team: $daily_switches/$MAX_SWITCHES_PER_DAY"
        return 1
    fi
    
    return 0
}

check_business_hours() {
    local team="$1"
    
    local team_config
    team_config=$(get_team_config "$team")
    
    local business_hours_only
    business_hours_only=$(echo "$team_config" | jq -r '.auto_healing.safety_checks.business_hours_only // false')
    
    if [[ "$business_hours_only" == "true" ]]; then
        local current_hour=$(date +%H)
        local current_day=$(date +%u)  # 1=Monday, 7=Sunday
        
        if (( current_day > 5 || current_hour < 8 || current_hour > 18 )); then
            log_warning "Business hours restriction active for team $team"
            return 1
        fi
    fi
    
    return 0
}

check_maintenance_window() {
    local team="$1"
    
    # Check if team is in maintenance window
    # This could be enhanced to check with external systems
    local maintenance_file="/tmp/maintenance-${team}.flag"
    
    if [[ -f "$maintenance_file" ]]; then
        log_warning "Team $team is in maintenance window"
        return 1
    fi
    
    return 0
}

# Health monitoring integration
check_health_engine_decision() {
    local team="$1"
    local health_engine_script="${SCRIPT_DIR}/health-engine.sh"
    
    if [[ ! -f "$health_engine_script" ]]; then
        log_warning "Health engine script not found: $health_engine_script"
        return 1
    fi
    
    log_info "Checking health engine decision for team $team"
    
    local health_result
    if ! health_result=$("$health_engine_script" assess "$team" json 2>/dev/null); then
        log_error "Health engine assessment failed for team $team"
        return 1
    fi
    
    local status
    status=$(echo "$health_result" | jq -r '.assessments[0].status // "unknown"')
    
    local score
    score=$(echo "$health_result" | jq -r '.assessments[0].score // 0')
    
    log_info "Health engine status for team $team: $status (score: $score)"
    
    case "$status" in
        "critical"|"failed")
            log_warning "Health engine recommends intervention for team $team"
            return 0  # Switch recommended
            ;;
        "warning")
            local team_config
            team_config=$(get_team_config "$team")
            local warning_threshold
            warning_threshold=$(echo "$team_config" | jq -r '.health_score_thresholds.warning // 70')
            
            if (( $(echo "$score < $warning_threshold" | bc -l) )); then
                log_warning "Health score below warning threshold for team $team"
                return 0  # Switch recommended
            fi
            ;;
        "healthy"|*)
            log_info "Team $team is healthy - no switch needed"
            return 1  # No switch needed
            ;;
    esac
    
    return 1
}

# SLI threshold monitoring
check_sli_thresholds() {
    local team="$1"
    local prometheus_url="${PROMETHEUS_URL:-http://localhost:9090}"
    
    local team_config
    team_config=$(get_team_config "$team")
    
    local error_rate_max
    error_rate_max=$(echo "$team_config" | jq -r '.thresholds.error_rate_max // 5.0')
    
    local response_time_max
    response_time_max=$(echo "$team_config" | jq -r '.thresholds.response_time_p95_max // 2000')
    
    local availability_min
    availability_min=$(echo "$team_config" | jq -r '.thresholds.service_availability_min // 99.0')
    
    log_debug "Checking SLI thresholds for team $team"
    
    # Check error rate
    local error_rate_query="rate(jenkins_http_requests_total{team=\"$team\",status=~\"5..\"}[5m]) / rate(jenkins_http_requests_total{team=\"$team\"}[5m]) * 100"
    local error_rate
    if error_rate=$(curl -s "${prometheus_url}/api/v1/query?query=${error_rate_query}" | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null); then
        if (( $(echo "$error_rate > $error_rate_max" | bc -l) )); then
            log_warning "Error rate threshold exceeded for team $team: ${error_rate}% > ${error_rate_max}%"
            return 0  # Switch recommended
        fi
    fi
    
    # Check response time
    local response_time_query="histogram_quantile(0.95, rate(jenkins_http_request_duration_seconds_bucket{team=\"$team\"}[5m])) * 1000"
    local response_time
    if response_time=$(curl -s "${prometheus_url}/api/v1/query?query=${response_time_query}" | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null); then
        if (( $(echo "$response_time > $response_time_max" | bc -l) )); then
            log_warning "Response time threshold exceeded for team $team: ${response_time}ms > ${response_time_max}ms"
            return 0  # Switch recommended
        fi
    fi
    
    # Check availability
    local availability_query="avg_over_time(up{team=\"$team\"}[5m]) * 100"
    local availability
    if availability=$(curl -s "${prometheus_url}/api/v1/query?query=${availability_query}" | jq -r '.data.result[0].value[1] // "100"' 2>/dev/null); then
        if (( $(echo "$availability < $availability_min" | bc -l) )); then
            log_warning "Availability threshold exceeded for team $team: ${availability}% < ${availability_min}%"
            return 0  # Switch recommended
        fi
    fi
    
    log_debug "All SLI thresholds OK for team $team"
    return 1  # No switch needed
}

# Log-based error pattern detection
check_log_patterns() {
    local team="$1"
    local loki_url="${LOKI_URL:-http://localhost:3100}"
    
    local team_config
    team_config=$(get_team_config "$team")
    
    # Extract critical patterns
    local critical_patterns
    critical_patterns=$(echo "$team_config" | jq -r '.log_patterns.critical_patterns[]?' 2>/dev/null)
    
    if [[ -z "$critical_patterns" ]]; then
        log_debug "No critical log patterns configured for team $team"
        return 1
    fi
    
    log_debug "Checking log patterns for team $team"
    
    # Query logs for critical patterns in last 5 minutes
    local query_time=$(date -u -d "5 minutes ago" +%s)000000000
    local current_time=$(date +%s)000000000
    
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        
        local loki_query="{team=\"$team\"} |~ \"$pattern\""
        local log_query_url="${loki_url}/loki/api/v1/query_range?query=${loki_query}&start=${query_time}&end=${current_time}"
        
        local log_result
        if log_result=$(curl -s "$log_query_url" 2>/dev/null); then
            local log_count
            log_count=$(echo "$log_result" | jq -r '.data.result | length' 2>/dev/null || echo "0")
            
            if (( log_count > 0 )); then
                log_warning "Critical log pattern detected for team $team: $pattern"
                return 0  # Switch recommended
            fi
        fi
    done <<< "$critical_patterns"
    
    log_debug "No critical log patterns found for team $team"
    return 1  # No switch needed
}

# Pre-switch validation and preparation
pre_switch_validation() {
    local team="$1"
    local target_env="$2"
    
    log_info "Starting pre-switch validation for team $team -> $target_env"
    
    # Check target environment health
    local target_container="jenkins-${team}-${target_env}"
    
    # Verify target container exists or can be created
    if ! docker container inspect "$target_container" >/dev/null 2>&1; then
        log_warning "Target container $target_container does not exist - will be created during switch"
    else
        # Check if target is healthy
        local target_status=$(docker container inspect "$target_container" --format '{{.State.Status}}')
        if [[ "$target_status" != "running" ]]; then
            log_warning "Target container $target_container is not running (status: $target_status)"
        fi
    fi
    
    # Validate HAProxy configuration
    local haproxy_container="haproxy-loadbalancer"
    if docker container inspect "$haproxy_container" >/dev/null 2>&1; then
        local haproxy_status=$(docker container inspect "$haproxy_container" --format '{{.State.Status}}')
        if [[ "$haproxy_status" != "running" ]]; then
            log_error "HAProxy is not running - cannot perform safe switch"
            return 1
        fi
    else
        log_error "HAProxy container not found - cannot perform safe switch"
        return 1
    fi
    
    # Check shared storage availability
    if ! mount | grep -q "/nfs\|/shared"; then
        log_warning "No shared storage detected - switch may lose data"
    fi
    
    log_success "Pre-switch validation completed for team $team"
    return 0
}

# Backup before switch
perform_pre_switch_backup() {
    local team="$1"
    local current_env="$2"
    
    log_info "Performing pre-switch backup for team $team"
    
    local backup_script="${SCRIPT_DIR}/backup-active-to-nfs.sh"
    
    if [[ ! -f "$backup_script" ]]; then
        log_error "Backup script not found: $backup_script"
        return 1
    fi
    
    # Run backup for specific team
    if JENKINS_TEAMS="$team" "$backup_script"; then
        log_success "Pre-switch backup completed for team $team"
        return 0
    else
        log_error "Pre-switch backup failed for team $team"
        return 1
    fi
}

# Data synchronization
perform_data_sync() {
    local team="$1"
    local target_env="$2"
    
    log_info "Performing data sync for team $team -> $target_env"
    
    local sync_script="${SCRIPT_DIR}/sync-for-bluegreen-switch.sh"
    
    if [[ ! -f "$sync_script" ]]; then
        log_error "Sync script not found: $sync_script"
        return 1
    fi
    
    # Run sync for specific team to target environment
    if "$sync_script" team "$team" "$target_env"; then
        log_success "Data sync completed for team $team"
        return 0
    else
        log_error "Data sync failed for team $team"
        return 1
    fi
}

# HAProxy runtime API integration
update_haproxy_backend() {
    local team="$1"
    local new_active_env="$2"
    
    log_info "Updating HAProxy backend for team $team -> $new_active_env"
    
    local haproxy_container="haproxy-loadbalancer"
    local haproxy_stats_port="8404"
    
    # Get backend configuration
    local backend_name="jenkins_${team}"
    
    # Enable new backend server
    local new_server="${team}_${new_active_env}"
    local enable_cmd="echo 'enable server ${backend_name}/${new_server}' | socat stdio tcp4-connect:127.0.0.1:${haproxy_stats_port}"
    
    if docker exec "$haproxy_container" sh -c "$enable_cmd" 2>/dev/null; then
        log_info "Enabled HAProxy server: ${backend_name}/${new_server}"
    else
        log_warning "Failed to enable HAProxy server - continuing anyway"
    fi
    
    # Wait for new backend to be ready
    sleep 10
    
    # Disable old backend server
    local old_env
    if [[ "$new_active_env" == "blue" ]]; then
        old_env="green"
    else
        old_env="blue"
    fi
    
    local old_server="${team}_${old_env}"
    local disable_cmd="echo 'disable server ${backend_name}/${old_server}' | socat stdio tcp4-connect:127.0.0.1:${haproxy_stats_port}"
    
    if docker exec "$haproxy_container" sh -c "$disable_cmd" 2>/dev/null; then
        log_info "Disabled HAProxy server: ${backend_name}/${old_server}"
    else
        log_warning "Failed to disable HAProxy server - manual intervention may be needed"
    fi
    
    log_success "HAProxy backend updated for team $team"
    return 0
}

# Post-switch validation
post_switch_validation() {
    local team="$1"
    local new_active_env="$2"
    
    log_info "Starting post-switch validation for team $team"
    
    local validation_timeout="$VALIDATION_TIMEOUT"
    local start_time=$(date +%s)
    
    # Test Jenkins accessibility
    local jenkins_port
    case "$team" in
        "devops") jenkins_port="8080" ;;
        "ma") jenkins_port="8081" ;;
        "ba") jenkins_port="8082" ;;
        "tw") jenkins_port="8083" ;;
        *) jenkins_port="8080" ;;
    esac
    
    local jenkins_url="http://localhost:${jenkins_port}"
    
    # Wait for Jenkins to respond
    while (( $(date +%s) - start_time < validation_timeout )); do
        if curl -s --max-time 10 "${jenkins_url}/api/json" >/dev/null 2>&1; then
            log_success "Jenkins is responding for team $team"
            break
        fi
        
        log_debug "Waiting for Jenkins to respond for team $team..."
        sleep 10
    done
    
    # Final connectivity test
    if ! curl -s --max-time 10 "${jenkins_url}/api/json" >/dev/null 2>&1; then
        log_error "Jenkins is not responding after switch for team $team"
        return 1
    fi
    
    # Test through HAProxy
    local haproxy_url="http://${team}jenkins.local.dev"
    if curl -s --max-time 10 "${haproxy_url}/api/json" >/dev/null 2>&1; then
        log_success "HAProxy routing is working for team $team"
    else
        log_warning "HAProxy routing test failed for team $team"
    fi
    
    log_success "Post-switch validation completed for team $team"
    return 0
}

# Rollback capability
perform_rollback() {
    local team="$1"
    local original_env="$2"
    local reason="${3:-validation_failed}"
    
    log_warning "Performing rollback for team $team -> $original_env (reason: $reason)"
    
    # Update ansible configuration back to original
    local ansible_config_script="${SCRIPT_DIR}/update-team-environment.py"
    
    if [[ -f "$ansible_config_script" ]]; then
        if python3 "$ansible_config_script" "$team" "$original_env"; then
            log_info "Ansible configuration rolled back for team $team"
        else
            log_error "Failed to rollback ansible configuration for team $team"
        fi
    fi
    
    # Update HAProxy back to original backend
    update_haproxy_backend "$team" "$original_env"
    
    # Wait for stabilization
    sleep 30
    
    # Validate rollback
    if post_switch_validation "$team" "$original_env"; then
        log_success "Rollback completed successfully for team $team"
        return 0
    else
        log_error "Rollback validation failed for team $team - manual intervention required"
        return 1
    fi
}

# Notification system
send_switch_notification() {
    local team="$1"
    local action="$2"
    local result="$3"
    local details="$4"
    
    local notification_script="${SCRIPT_DIR}/health-engine-integration.sh"
    
    if [[ -f "$notification_script" ]]; then
        "$notification_script" send_notification "$team" "$action" "$result" "$details" || true
    fi
    
    # Create Grafana annotation
    if [[ -f "$notification_script" ]]; then
        "$notification_script" create_grafana_annotation "$team" "automated_switch" \
            "Automated switch $action for team $team: $result" \
            "automated-switch,$team,$action" || true
    fi
}

# Main switch orchestration
execute_automated_switch() {
    local team="$1"
    local trigger_reason="${2:-health_engine_decision}"
    local force="${3:-false}"
    
    local start_time=$(date +%s)
    
    log_info "Starting automated switch orchestration for team $team"
    log_info "Trigger reason: $trigger_reason"
    log_info "Force mode: $force"
    
    # Get current configuration
    local current_env
    current_env=$(get_current_active_environment "$team")
    
    local target_env
    target_env=$(get_target_environment "$current_env")
    
    log_info "Current environment: $current_env, Target environment: $target_env"
    
    # Safety checks (unless forced)
    if [[ "$force" != "true" ]]; then
        # Check circuit breaker
        if ! check_circuit_breaker "$team"; then
            send_switch_notification "$team" "switch_blocked" "circuit_breaker" "Circuit breaker open"
            return 1
        fi
        
        # Check rate limits
        if ! check_rate_limits "$team"; then
            send_switch_notification "$team" "switch_blocked" "rate_limit" "Rate limit exceeded"
            return 1
        fi
        
        # Check business hours
        if ! check_business_hours "$team"; then
            send_switch_notification "$team" "switch_blocked" "business_hours" "Outside business hours"
            return 1
        fi
        
        # Check maintenance window
        if ! check_maintenance_window "$team"; then
            send_switch_notification "$team" "switch_blocked" "maintenance" "In maintenance window"
            return 1
        fi
        
        # Check flapping
        if detect_flapping "$team"; then
            send_switch_notification "$team" "switch_blocked" "flapping" "Flapping detected"
            return 1
        fi
    fi
    
    # Acquire switch lock
    if ! acquire_switch_lock "$team" "switch" 600; then
        send_switch_notification "$team" "switch_failed" "lock_timeout" "Failed to acquire switch lock"
        return 1
    fi
    
    local switch_result=1
    local rollback_performed=false
    
    {
        echo "=== Automated Switch Started ==="
        echo "Team: $team"
        echo "From: $current_env"
        echo "To: $target_env"
        echo "Trigger: $trigger_reason"
        echo "Force: $force"
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        
        # Step 1: Pre-switch validation
        if pre_switch_validation "$team" "$target_env"; then
            echo "✅ Pre-switch validation passed"
        else
            echo "❌ Pre-switch validation failed"
            send_switch_notification "$team" "switch_failed" "pre_validation_failed" "Pre-switch validation failed"
            echo "=== Switch Aborted ==="
            return 1
        fi
        
        # Step 2: Pre-switch backup
        if perform_pre_switch_backup "$team" "$current_env"; then
            echo "✅ Pre-switch backup completed"
        else
            echo "❌ Pre-switch backup failed"
            send_switch_notification "$team" "switch_failed" "backup_failed" "Pre-switch backup failed"
            echo "=== Switch Aborted ==="
            return 1
        fi
        
        # Step 3: Data synchronization
        if perform_data_sync "$team" "$target_env"; then
            echo "✅ Data synchronization completed"
        else
            echo "❌ Data synchronization failed"
            send_switch_notification "$team" "switch_failed" "sync_failed" "Data synchronization failed"
            echo "=== Switch Aborted ==="
            return 1
        fi
        
        # Step 4: Execute the switch
        echo "🔄 Executing blue-green switch..."
        
        # Update ansible configuration
        local update_script="${SCRIPT_DIR}/update-team-environment.py"
        if [[ -f "$update_script" ]]; then
            if python3 "$update_script" "$team" "$target_env"; then
                echo "✅ Ansible configuration updated"
            else
                echo "❌ Ansible configuration update failed"
                send_switch_notification "$team" "switch_failed" "config_update_failed" "Ansible configuration update failed"
                echo "=== Switch Failed ==="
                return 1
            fi
        fi
        
        # Step 5: Update HAProxy routing
        if update_haproxy_backend "$team" "$target_env"; then
            echo "✅ HAProxy backend updated"
        else
            echo "❌ HAProxy backend update failed"
            send_switch_notification "$team" "switch_failed" "haproxy_failed" "HAProxy backend update failed"
            echo "=== Initiating Rollback ==="
            if perform_rollback "$team" "$current_env" "haproxy_failed"; then
                rollback_performed=true
                echo "✅ Rollback completed"
            else
                echo "❌ Rollback failed - manual intervention required"
            fi
            return 1
        fi
        
        # Step 6: Wait for stabilization
        echo "⏳ Waiting for stabilization (${STABILIZATION_PERIOD}s)..."
        sleep "$STABILIZATION_PERIOD"
        
        # Step 7: Post-switch validation
        if post_switch_validation "$team" "$target_env"; then
            echo "✅ Post-switch validation passed"
            switch_result=0
        else
            echo "❌ Post-switch validation failed"
            send_switch_notification "$team" "switch_failed" "post_validation_failed" "Post-switch validation failed"
            echo "=== Initiating Rollback ==="
            if perform_rollback "$team" "$current_env" "post_validation_failed"; then
                rollback_performed=true
                echo "✅ Rollback completed"
            else
                echo "❌ Rollback failed - manual intervention required"
            fi
            return 1
        fi
        
        echo "=== Switch Completed Successfully ==="
        
    } >> "$SWITCH_LOG_FILE"
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Update statistics and history
    local result_text
    if [[ $switch_result -eq 0 ]]; then
        result_text="success"
        update_automation_stats "$team" "switch" "success"
        handle_circuit_breaker_success "$team" "switch"
        send_switch_notification "$team" "switch_completed" "success" "Switch completed in ${duration}s"
    else
        result_text="failed"
        update_automation_stats "$team" "switch" "failed"
        handle_circuit_breaker_failure "$team" "switch"
        if [[ "$rollback_performed" == "true" ]]; then
            send_switch_notification "$team" "switch_failed_rolled_back" "failed" "Switch failed, rollback completed in ${duration}s"
        else
            send_switch_notification "$team" "switch_failed" "failed" "Switch failed in ${duration}s"
        fi
    fi
    
    # Update switch history
    if [[ "$rollback_performed" == "true" ]]; then
        update_switch_history "$team" "$current_env" "$target_env" "$trigger_reason" "failed_rolled_back" "$duration"
    else
        update_switch_history "$team" "$current_env" "$target_env" "$trigger_reason" "$result_text" "$duration"
    fi
    
    # Release lock
    release_switch_lock "$team" "switch"
    
    log_info "Switch orchestration completed for team $team: $result_text (${duration}s)"
    
    return $switch_result
}

# Team automation level management
get_team_automation_level() {
    local team="$1"
    
    local state
    state=$(load_automation_state)
    
    local automation_level
    automation_level=$(echo "$state" | jq -r --arg team "$team" '.team_automation_config[$team].automation_level // "assisted"')
    
    echo "$automation_level"
}

set_team_automation_level() {
    local team="$1"
    local level="$2"  # manual, assisted, automatic
    
    case "$level" in
        "manual"|"assisted"|"automatic")
            ;;
        *)
            log_error "Invalid automation level: $level. Must be manual, assisted, or automatic"
            return 1
            ;;
    esac
    
    local state
    state=$(load_automation_state)
    
    state=$(echo "$state" | jq \
        --arg team "$team" \
        --arg level "$level" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '
        .team_automation_config[$team] = {
            automation_level: $level,
            last_updated: $timestamp
        }
        ')
    
    save_automation_state "$state"
    
    log_success "Set automation level for team $team to $level"
}

# Intelligence layer - decides whether to switch
intelligent_switch_decision() {
    local team="$1"
    local force="${2:-false}"
    
    log_info "Making intelligent switch decision for team $team"
    
    # Check team automation level
    local automation_level
    automation_level=$(get_team_automation_level "$team")
    
    log_info "Team $team automation level: $automation_level"
    
    case "$automation_level" in
        "manual")
            if [[ "$force" == "true" ]]; then
                log_info "Manual mode but force flag set - proceeding"
                return 0
            else
                log_info "Team $team is in manual mode - no automatic switches"
                return 1
            fi
            ;;
        "assisted")
            # In assisted mode, require strong indicators
            local indicators=0
            
            if check_health_engine_decision "$team"; then
                log_info "Health engine recommends switch for team $team"
                ((indicators++))
            fi
            
            if check_sli_thresholds "$team"; then
                log_info "SLI thresholds exceeded for team $team"
                ((indicators++))
            fi
            
            if check_log_patterns "$team"; then
                log_info "Critical log patterns detected for team $team"
                ((indicators++))
            fi
            
            if (( indicators >= 2 )); then
                log_info "Multiple indicators suggest switch for team $team (assisted mode)"
                return 0
            else
                log_info "Insufficient indicators for assisted switch for team $team"
                return 1
            fi
            ;;
        "automatic")
            # In automatic mode, any single strong indicator is sufficient
            if check_health_engine_decision "$team"; then
                log_info "Health engine recommends switch for team $team (automatic mode)"
                return 0
            fi
            
            if check_sli_thresholds "$team"; then
                log_info "SLI thresholds exceeded for team $team (automatic mode)"
                return 0
            fi
            
            if check_log_patterns "$team"; then
                log_info "Critical log patterns detected for team $team (automatic mode)"
                return 0
            fi
            
            log_info "No switch indicators found for team $team"
            return 1
            ;;
        *)
            log_error "Unknown automation level for team $team: $automation_level"
            return 1
            ;;
    esac
}

# Status and reporting functions
show_team_status() {
    local team="$1"
    
    echo "=== Team $team Status ==="
    
    # Current configuration
    local current_env
    current_env=$(get_current_active_environment "$team")
    echo "Current Active Environment: $current_env"
    
    # Automation level
    local automation_level
    automation_level=$(get_team_automation_level "$team")
    echo "Automation Level: $automation_level"
    
    # Circuit breaker status
    local state
    state=$(load_automation_state)
    
    local circuit_status
    circuit_status=$(echo "$state" | jq -r --arg team "$team" '.circuit_breakers[$team].switch.status // "closed"')
    echo "Circuit Breaker: $circuit_status"
    
    # Recent switches
    local recent_switches
    recent_switches=$(echo "$state" | jq -r --arg team "$team" '.switch_history | map(select(.team == $team)) | sort_by(.timestamp) | .[-5:] | length')
    echo "Recent Switches (last 5): $recent_switches"
    
    # Rate limits
    local hour_key=$(date +%Y%m%d_%H)
    local day_key=$(date +%Y%m%d)
    
    local hourly_switches
    hourly_switches=$(echo "$state" | jq -r --arg team "$team" --arg hour "$hour_key" '.automation_stats[$team].hourly[$hour].switches // 0')
    
    local daily_switches
    daily_switches=$(echo "$state" | jq -r --arg team "$team" --arg day "$day_key" '.automation_stats[$team].daily[$day].switches // 0')
    
    echo "Rate Limits: ${hourly_switches}/${MAX_SWITCHES_PER_HOUR} hourly, ${daily_switches}/${MAX_SWITCHES_PER_DAY} daily"
    
    # Flapping check
    if detect_flapping "$team"; then
        echo "Flapping: DETECTED"
    else
        echo "Flapping: None"
    fi
    
    echo ""
}

show_global_status() {
    local teams="${1:-devops ma ba tw}"
    
    echo "=== Automated Switch Manager Global Status ==="
    echo "Timestamp: $(date)"
    echo ""
    
    for team in $teams; do
        show_team_status "$team"
    done
    
    # Show recent activity
    echo "=== Recent Switch Activity ==="
    local state
    state=$(load_automation_state)
    
    echo "$state" | jq -r '.switch_history | sort_by(.timestamp) | .[-10:] | .[] | "\(.timestamp) \(.team) \(.from_environment)->\(.to_environment) \(.result) (\(.trigger_reason))"' 2>/dev/null || echo "No recent activity"
}

# Main command interface
main() {
    local command="${1:-}"
    shift || true
    
    initialize_automation
    
    case "$command" in
        "assess")
            local team="${1:-all}"
            if [[ "$team" == "all" ]]; then
                local teams="devops ma ba tw"
                for t in $teams; do
                    echo "=== Assessing team $t ==="
                    if intelligent_switch_decision "$t"; then
                        echo "✅ Switch recommended for team $t"
                    else
                        echo "ℹ️  No switch needed for team $t"
                    fi
                    echo ""
                done
            else
                if intelligent_switch_decision "$team"; then
                    echo "✅ Switch recommended for team $team"
                    exit 0
                else
                    echo "ℹ️  No switch needed for team $team"
                    exit 1
                fi
            fi
            ;;
        "switch")
            local team="${1:-}"
            local reason="${2:-manual_trigger}"
            local force="${3:-false}"
            
            if [[ -z "$team" ]]; then
                log_error "Team name required for switch command"
                exit 1
            fi
            
            execute_automated_switch "$team" "$reason" "$force"
            ;;
        "auto-heal")
            local team="${1:-all}"
            
            if [[ "$team" == "all" ]]; then
                local teams="devops ma ba tw"
                for t in $teams; do
                    if intelligent_switch_decision "$t"; then
                        log_info "Executing automated switch for team $t"
                        execute_automated_switch "$t" "auto_healing_triggered" "false"
                    fi
                done
            else
                if intelligent_switch_decision "$team"; then
                    execute_automated_switch "$team" "auto_healing_triggered" "false"
                else
                    log_info "No auto-healing switch needed for team $team"
                fi
            fi
            ;;
        "set-automation")
            local team="${1:-}"
            local level="${2:-}"
            
            if [[ -z "$team" || -z "$level" ]]; then
                echo "Usage: $0 set-automation <team> <level>"
                echo "Levels: manual, assisted, automatic"
                exit 1
            fi
            
            set_team_automation_level "$team" "$level"
            ;;
        "status")
            local team="${1:-all}"
            
            if [[ "$team" == "all" ]]; then
                show_global_status
            else
                show_team_status "$team"
            fi
            ;;
        "reset-circuit-breaker")
            local team="${1:-}"
            
            if [[ -z "$team" ]]; then
                log_error "Team name required for reset-circuit-breaker command"
                exit 1
            fi
            
            update_circuit_breaker "$team" "switch" "closed" 0
            log_success "Circuit breaker reset for team $team"
            ;;
        "maintenance")
            local team="${1:-}"
            local action="${2:-enable}"
            
            if [[ -z "$team" ]]; then
                log_error "Team name required for maintenance command"
                exit 1
            fi
            
            local maintenance_file="/tmp/maintenance-${team}.flag"
            
            case "$action" in
                "enable")
                    touch "$maintenance_file"
                    log_success "Maintenance mode enabled for team $team"
                    ;;
                "disable")
                    rm -f "$maintenance_file"
                    log_success "Maintenance mode disabled for team $team"
                    ;;
                *)
                    log_error "Invalid maintenance action: $action. Use enable or disable"
                    exit 1
                    ;;
            esac
            ;;
        "cleanup")
            cleanup_locks
            log_success "Automation locks cleaned up"
            ;;
        *)
            cat << 'EOF'
Usage: automated-switch-manager.sh <command> [options]

COMMANDS:
    assess [team]                           - Assess if team needs switch (all teams if not specified)
    switch <team> [reason] [force]          - Execute automated switch for team
    auto-heal [team]                        - Run automated healing for team (all teams if not specified)
    set-automation <team> <level>           - Set automation level (manual/assisted/automatic)
    status [team]                           - Show status for team (all teams if not specified)
    reset-circuit-breaker <team>            - Reset circuit breaker for team
    maintenance <team> <enable|disable>     - Enable/disable maintenance mode for team
    cleanup                                 - Clean up automation locks

AUTOMATION LEVELS:
    manual      - No automatic switches, manual intervention required
    assisted    - Automatic switches only with multiple strong indicators
    automatic   - Automatic switches on any strong indicator

EXAMPLES:
    # Assess if devops team needs switch
    $0 assess devops

    # Execute switch for ma team due to health issues
    $0 switch ma health_degradation

    # Force switch for ba team (bypass safety checks)
    $0 switch ba emergency_fix true

    # Set devops team to automatic mode
    $0 set-automation devops automatic

    # Run auto-healing for all teams
    $0 auto-heal

    # Show status for all teams
    $0 status

    # Enable maintenance mode for tw team
    $0 maintenance tw enable

SAFETY FEATURES:
    - Circuit breaker patterns (max 3 failures before opening)
    - Rate limiting (max 3 switches/hour, 10/day)
    - Flapping detection (5 switches in 30 minutes)
    - Business hours restrictions (configurable per team)
    - Maintenance window awareness
    - Pre/post switch validation
    - Automatic rollback on validation failure
    - Comprehensive audit logging

TRIGGERS:
    - Health engine decisions (critical/failed status)
    - SLI threshold violations (error rate, latency, availability)
    - Log pattern detection (critical error patterns)
    - Multi-source health monitoring integration

INTEGRATION:
    - Jenkins HA blue-green infrastructure
    - HAProxy runtime API for zero-downtime switching
    - Prometheus metrics monitoring
    - Loki log analysis
    - Grafana dashboards and annotations
    - Backup and sync systems
    - Notification systems (Slack, PagerDuty)

EOF
            exit 1
            ;;
    esac
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi