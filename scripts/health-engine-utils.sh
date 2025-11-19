#!/bin/bash
# Health Engine Utility Functions
# Supporting functions for the multi-source health engine

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Global configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HEALTH_ENGINE_CONFIG="${PROJECT_ROOT}/config/health-engine.json"
HEALTH_ENGINE_STATE="${PROJECT_ROOT}/logs/health-engine-state.json"

# Utility logging functions
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}] [INFO]${NC} $1"
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $1"
}

log_warn() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] [WARNING]${NC} $1"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] [ERROR]${NC} $1" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${PURPLE}[${timestamp}] [DEBUG]${NC} $1"
    fi
}

# Enhanced Prometheus query function with retry logic
query_prometheus_with_retry() {
    local team="$1"
    local metric="$2"
    local prometheus_url="$3"
    local window="${4:-5m}"
    local max_retries="${5:-3}"
    local retry_delay="${6:-2}"
    
    local attempt=1
    local result
    
    while (( attempt <= max_retries )); do
        log_debug "Querying Prometheus: $metric for team $team (attempt $attempt/$max_retries)"
        
        if result=$(query_prometheus_metric "$team" "$metric" "$prometheus_url" "$window"); then
            echo "$result"
            return 0
        fi
        
        if (( attempt < max_retries )); then
            log_debug "Prometheus query failed, retrying in ${retry_delay}s..."
            sleep "$retry_delay"
            retry_delay=$((retry_delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to query Prometheus metric $metric for team $team after $max_retries attempts"
    echo "null"
    return 1
}

# Specific Prometheus metric query function
query_prometheus_metric() {
    local team="$1"
    local metric="$2"
    local prometheus_url="$3"
    local window="${4:-5m}"
    
    local query_url="${prometheus_url}/api/v1/query"
    local encoded_query
    
    case "$metric" in
        "error_rate")
            encoded_query="jenkins%3Aerror_rate_5m%7Bjenkins_team%3D%22${team}%22%7D"
            ;;
        "response_time_p95")
            encoded_query="jenkins%3Aresponse_time_p95%7Bjenkins_team%3D%22${team}%22%7D"
            ;;
        "service_availability")
            encoded_query="jenkins%3Aservice_availability_by_team%7Bjenkins_team%3D%22${team}%22%7D"
            ;;
        "memory_usage")
            encoded_query="(jenkins_memory_used_bytes%7Bjenkins_team%3D%22${team}%22%7D%20%2F%20jenkins_memory_total_bytes%7Bjenkins_team%3D%22${team}%22%7D)%20*%20100"
            ;;
        "cpu_usage")
            encoded_query="rate(jenkins_cpu_usage_seconds_total%7Bjenkins_team%3D%22${team}%22%7D%5B${window}%5D)%20*%20100"
            ;;
        "disk_usage")
            encoded_query="(1%20-%20(node_filesystem_free_bytes%7Bjenkins_team%3D%22${team}%22%2Cmountpoint%3D%22%2F%22%7D%20%2F%20node_filesystem_size_bytes%7Bjenkins_team%3D%22${team}%22%2Cmountpoint%3D%22%2F%22%7D))%20*%20100"
            ;;
        "deployment_success_rate")
            encoded_query="jenkins%3Adeployment_success_rate_5m%7Bjenkins_team%3D%22${team}%22%7D"
            ;;
        "blue_green_switch_success_rate")
            encoded_query="jenkins%3Ablue_green_switch_success_rate%7Bjenkins_team%3D%22${team}%22%7D"
            ;;
        "build_failure_rate")
            encoded_query="(rate(jenkins_builds_failure_total%7Bjenkins_team%3D%22${team}%22%7D%5B1h%5D)%20%2F%20rate(jenkins_builds_total%7Bjenkins_team%3D%22${team}%22%7D%5B1h%5D))%20*%20100"
            ;;
        "queue_size")
            encoded_query="jenkins_queue_size%7Bjenkins_team%3D%22${team}%22%7D"
            ;;
        "ssl_certificate_expiry_days")
            encoded_query="(jenkins_ssl_certificate_expiry_timestamp%7Bjenkins_team%3D%22${team}%22%7D%20-%20time())%20%2F%2086400"
            ;;
        *)
            log_error "Unknown metric: $metric"
            return 1
            ;;
    esac
    
    local response
    response=$(curl -s --max-time 10 "${query_url}?query=${encoded_query}" 2>/dev/null || echo '{"status":"error"}')
    
    if echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        local value
        value=$(echo "$response" | jq -r '.data.result[0].value[1] // "null"')
        if [[ "$value" != "null" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    return 1
}

# Enhanced Loki log query with pattern aggregation
query_loki_advanced() {
    local team="$1"
    local patterns="$2"
    local loki_url="$3"
    local window="${4:-5m}"
    local severity="${5:-error}"
    
    log_debug "Querying Loki: $patterns for team $team (window: $window, severity: $severity)"
    
    local query_url="${loki_url}/loki/api/v1/query_range"
    local start_time=$(($(date +%s) - 300))  # 5 minutes ago
    local end_time=$(date +%s)
    
    # Split patterns and create individual queries
    local total_count=0
    local pattern_array
    IFS='|' read -ra pattern_array <<< "$patterns"
    
    for pattern in "${pattern_array[@]}"; do
        if [[ -n "$pattern" ]]; then
            local logql_query="{jenkins_team=\"${team}\"} |~ \"${pattern}\""
            local encoded_query=$(printf '%s' "$logql_query" | jq -sRr @uri)
            
            local response
            response=$(curl -s --max-time 10 "${query_url}?query=${encoded_query}&start=${start_time}000000000&end=${end_time}000000000" 2>/dev/null || echo '{"status":"error"}')
            
            if echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
                local count
                count=$(echo "$response" | jq '.data.result | length')
                total_count=$((total_count + count))
                log_debug "Pattern '$pattern' found $count occurrences"
            fi
        fi
    done
    
    echo "$total_count"
    return 0
}

# Health check script executor with timeout and validation
execute_health_check() {
    local team="$1"
    local health_check_type="${2:-basic}"
    local timeout="${3:-30}"
    
    log_debug "Executing health check for team: $team (type: $health_check_type)"
    
    # Look for team-specific health check script
    local health_script="/opt/jenkins/scripts/health-check-${team}.sh"
    if [[ ! -f "$health_script" ]]; then
        # Fall back to generic health check
        health_script="${PROJECT_ROOT}/ansible/roles/jenkins-master-v2/templates/blue-green-healthcheck.sh.j2"
    fi
    
    if [[ ! -f "$health_script" ]]; then
        log_warn "No health check script found for team $team"
        return 1
    fi
    
    # Create temporary script if using template
    local temp_script=""
    if [[ "$health_script" == *.j2 ]]; then
        temp_script="/tmp/health-check-${team}-$$.sh"
        # Simple template processing (replace basic variables)
        sed -e "s/{{ jenkins_team }}/${team}/g" \
            -e "s/{{ deployment_mode }}/local/g" \
            "$health_script" > "$temp_script"
        chmod +x "$temp_script"
        health_script="$temp_script"
    fi
    
    local health_result=0
    local start_time=$(date +%s)
    
    # Execute health check with timeout
    if timeout "$timeout" bash "$health_script" "$health_check_type" >/dev/null 2>&1; then
        health_result=100  # 100% healthy
        local duration=$(($(date +%s) - start_time))
        log_debug "Health check for $team completed successfully in ${duration}s"
    else
        health_result=0    # 0% healthy
        log_debug "Health check for $team failed or timed out"
    fi
    
    # Cleanup temporary script
    if [[ -n "$temp_script" && -f "$temp_script" ]]; then
        rm -f "$temp_script"
    fi
    
    echo "$health_result"
    return 0
}

# Advanced health scoring with weighted algorithms
calculate_advanced_health_score() {
    local team="$1"
    local metrics_data="$2"
    local logs_data="$3"
    local health_data="$4"
    local config="$5"
    
    local weights=$(echo "$config" | jq -r ".teams.${team}.weights")
    local thresholds=$(echo "$config" | jq -r ".teams.${team}.thresholds")
    local sli_targets=$(echo "$config" | jq -r ".teams.${team}.sli_targets // {}")
    
    local prometheus_weight=$(echo "$weights" | jq -r '.prometheus_metrics')
    local loki_weight=$(echo "$weights" | jq -r '.loki_logs')
    local health_weight=$(echo "$weights" | jq -r '.health_checks')
    
    # Advanced metrics scoring with SLI integration
    local metrics_score=100
    
    # Calculate individual metric scores
    local error_rate=$(echo "$metrics_data" | jq -r '.error_rate // 0')
    local error_rate_max=$(echo "$thresholds" | jq -r '.error_rate_max')
    local error_rate_target=$(echo "$sli_targets" | jq -r '.error_rate // $error_rate_max')
    
    if (( $(echo "$error_rate > $error_rate_target" | bc -l) )); then
        local error_penalty=$(echo "scale=2; ($error_rate - $error_rate_target) / $error_rate_target * 25" | bc -l)
        metrics_score=$(echo "scale=0; $metrics_score - $error_penalty" | bc -l)
    fi
    
    # Response time scoring
    local response_time=$(echo "$metrics_data" | jq -r '.response_time_p95 // 0')
    local response_time_max=$(echo "$thresholds" | jq -r '.response_time_p95_max')
    local response_time_target=$(echo "$sli_targets" | jq -r '.response_time_p95 // $response_time_max')
    
    if (( $(echo "$response_time > $response_time_target" | bc -l) )); then
        local latency_penalty=$(echo "scale=2; ($response_time - $response_time_target) / $response_time_target * 20" | bc -l)
        metrics_score=$(echo "scale=0; $metrics_score - $latency_penalty" | bc -l)
    fi
    
    # Availability scoring (critical metric)
    local availability=$(echo "$metrics_data" | jq -r '.service_availability // 100')
    local availability_min=$(echo "$thresholds" | jq -r '.service_availability_min')
    local availability_target=$(echo "$sli_targets" | jq -r '.availability // $availability_min')
    
    if (( $(echo "$availability < $availability_target" | bc -l) )); then
        local availability_penalty=$(echo "scale=2; ($availability_target - $availability) * 2" | bc -l)
        metrics_score=$(echo "scale=0; $metrics_score - $availability_penalty" | bc -l)
    fi
    
    # Resource utilization scoring (combined)
    local memory_usage=$(echo "$metrics_data" | jq -r '.memory_usage // 0')
    local cpu_usage=$(echo "$metrics_data" | jq -r '.cpu_usage // 0')
    local disk_usage=$(echo "$metrics_data" | jq -r '.disk_usage // 0')
    
    local memory_max=$(echo "$thresholds" | jq -r '.memory_usage_max')
    local cpu_max=$(echo "$thresholds" | jq -r '.cpu_usage_max')
    local disk_max=$(echo "$thresholds" | jq -r '.disk_usage_max')
    
    local resource_penalty=0
    if (( $(echo "$memory_usage > $memory_max" | bc -l) )); then
        resource_penalty=$(echo "scale=2; $resource_penalty + 15" | bc -l)
    fi
    if (( $(echo "$cpu_usage > $cpu_max" | bc -l) )); then
        resource_penalty=$(echo "scale=2; $resource_penalty + 10" | bc -l)
    fi
    if (( $(echo "$disk_usage > $disk_max" | bc -l) )); then
        resource_penalty=$(echo "scale=2; $resource_penalty + 15" | bc -l)
    fi
    
    metrics_score=$(echo "scale=0; $metrics_score - $resource_penalty" | bc -l)
    
    # Ensure metrics score bounds
    if (( $(echo "$metrics_score < 0" | bc -l) )); then
        metrics_score=0
    elif (( $(echo "$metrics_score > 100" | bc -l) )); then
        metrics_score=100
    fi
    
    # Advanced logs scoring with severity weighting
    local logs_score=100
    local error_count=$(echo "$logs_data" | jq -r '.error_count // 0')
    local critical_count=$(echo "$logs_data" | jq -r '.critical_count // 0')
    local warning_count=$(echo "$logs_data" | jq -r '.warning_count // 0')
    
    # Weighted penalty based on log severity
    local log_penalty=$(echo "scale=2; ($warning_count * 1) + ($error_count * 3) + ($critical_count * 10)" | bc -l)
    logs_score=$(echo "scale=0; $logs_score - $log_penalty" | bc -l)
    
    if (( $(echo "$logs_score < 0" | bc -l) )); then
        logs_score=0
    fi
    
    # Health checks score (direct from health data)
    local health_score=$(echo "$health_data" | jq -r '.health_score // 0')
    
    # Calculate weighted total score with normalization
    local total_score
    total_score=$(echo "scale=2; ($metrics_score * $prometheus_weight + $logs_score * $loki_weight + $health_score * $health_weight) / 100" | bc -l)
    
    # Apply team tier adjustments
    local tier=$(echo "$config" | jq -r ".teams.${team}.tier // \"production\"")
    case "$tier" in
        "production")
            # More stringent scoring for production teams
            if (( $(echo "$total_score > 95" | bc -l) )); then
                total_score=$(echo "scale=2; $total_score * 1.0" | bc -l)
            elif (( $(echo "$total_score > 85" | bc -l) )); then
                total_score=$(echo "scale=2; $total_score * 0.95" | bc -l)
            else
                total_score=$(echo "scale=2; $total_score * 0.9" | bc -l)
            fi
            ;;
        "testing")
            # More lenient scoring for testing teams
            if (( $(echo "$total_score < 70" | bc -l) )); then
                total_score=$(echo "scale=2; $total_score * 1.1" | bc -l)
            fi
            ;;
    esac
    
    # Final bounds check
    if (( $(echo "$total_score > 100" | bc -l) )); then
        total_score=100
    elif (( $(echo "$total_score < 0" | bc -l) )); then
        total_score=0
    fi
    
    printf "%.0f" "$total_score"
}

# Flapping detection algorithm
detect_flapping() {
    local team="$1"
    local current_status="$2"
    local config="$3"
    
    local flapping_config=$(echo "$config" | jq -r '.global.flapping_prevention // {}')
    local enabled=$(echo "$flapping_config" | jq -r '.enabled // false')
    
    if [[ "$enabled" != "true" ]]; then
        echo '{"flapping": false, "suppressed": false}'
        return 0
    fi
    
    local threshold_changes=$(echo "$flapping_config" | jq -r '.threshold_changes // 3')
    local time_window=$(echo "$flapping_config" | jq -r '.time_window // "10m"')
    local stabilization_period=$(echo "$flapping_config" | jq -r '.stabilization_period // "5m"')
    
    # Convert time window to seconds
    local window_seconds
    case "$time_window" in
        *m) window_seconds=$((${time_window%m} * 60)) ;;
        *h) window_seconds=$((${time_window%h} * 3600)) ;;
        *) window_seconds=600 ;; # Default 10 minutes
    esac
    
    if [[ ! -f "$HEALTH_ENGINE_STATE" ]]; then
        echo '{"flapping": false, "suppressed": false}'
        return 0
    fi
    
    local now=$(date +%s)
    local cutoff_time=$((now - window_seconds))
    local cutoff_iso=$(date -u -d "@$cutoff_time" +%Y-%m-%dT%H:%M:%SZ)
    
    # Get recent status changes
    local recent_changes
    recent_changes=$(cat "$HEALTH_ENGINE_STATE" | jq --arg team "$team" --arg cutoff "$cutoff_iso" '
        .historical_assessments[$team] // [] |
        map(select(.timestamp > $cutoff)) |
        length
    ')
    
    local is_flapping=false
    local is_suppressed=false
    
    if (( recent_changes >= threshold_changes )); then
        is_flapping=true
        
        # Check if we should suppress actions during stabilization
        local last_change_time
        last_change_time=$(cat "$HEALTH_ENGINE_STATE" | jq -r --arg team "$team" '
            .historical_assessments[$team] // [] |
            map(.timestamp) |
            max // "1970-01-01T00:00:00Z"
        ')
        
        local last_change_seconds
        last_change_seconds=$(date -d "$last_change_time" +%s 2>/dev/null || echo 0)
        local stabilization_seconds
        case "$stabilization_period" in
            *m) stabilization_seconds=$((${stabilization_period%m} * 60)) ;;
            *h) stabilization_seconds=$((${stabilization_period%h} * 3600)) ;;
            *) stabilization_seconds=300 ;; # Default 5 minutes
        esac
        
        if (( (now - last_change_seconds) < stabilization_seconds )); then
            is_suppressed=true
        fi
    fi
    
    local result
    result=$(jq -n \
        --arg flapping "$is_flapping" \
        --arg suppressed "$is_suppressed" \
        --arg changes "$recent_changes" \
        --arg threshold "$threshold_changes" \
        '{
            flapping: ($flapping == "true"),
            suppressed: ($suppressed == "true"),
            recent_changes: ($changes | tonumber),
            threshold: ($threshold | tonumber)
        }')
    
    echo "$result"
}

# Team environment resolver
resolve_team_environment() {
    local team="$1"
    local config="$2"
    
    local active_env=$(echo "$config" | jq -r ".teams.${team}.active_environment // \"green\"")
    local blue_green_enabled=$(echo "$config" | jq -r ".teams.${team}.blue_green_enabled // false")
    
    if [[ "$blue_green_enabled" == "true" ]]; then
        echo "$active_env"
    else
        echo "default"
    fi
}

# SLI/SLO compliance checker
check_sli_compliance() {
    local team="$1"
    local metrics_data="$2"
    local config="$3"
    
    local sli_targets=$(echo "$config" | jq -r ".teams.${team}.sli_targets // {}")
    local compliance_results="{}"
    
    # Check each SLI target
    while IFS='=' read -r key value; do
        if [[ -n "$key" && -n "$value" ]]; then
            local actual_value=$(echo "$metrics_data" | jq -r ".${key} // null")
            if [[ "$actual_value" != "null" ]]; then
                local compliant=false
                
                # Determine compliance based on metric type
                case "$key" in
                    *"_min"|"availability"|"success_rate"*|"accuracy"*)
                        # Higher is better metrics
                        if (( $(echo "$actual_value >= $value" | bc -l) )); then
                            compliant=true
                        fi
                        ;;
                    *"_max"|"error_rate"|"response_time"*|"failure_rate"*)
                        # Lower is better metrics
                        if (( $(echo "$actual_value <= $value" | bc -l) )); then
                            compliant=true
                        fi
                        ;;
                esac
                
                compliance_results=$(echo "$compliance_results" | jq \
                    --arg key "$key" \
                    --arg target "$value" \
                    --arg actual "$actual_value" \
                    --arg compliant "$compliant" \
                    '.[$key] = {
                        target: ($target | tonumber),
                        actual: ($actual | tonumber),
                        compliant: ($compliant == "true")
                    }')
            fi
        fi
    done <<< "$(echo "$sli_targets" | jq -r 'to_entries[] | "\(.key)=\(.value)"')"
    
    # Calculate overall compliance percentage
    local total_slis=$(echo "$compliance_results" | jq 'length')
    local compliant_slis=$(echo "$compliance_results" | jq '[.[] | select(.compliant)] | length')
    local compliance_percentage
    
    if (( total_slis > 0 )); then
        compliance_percentage=$(echo "scale=2; $compliant_slis * 100 / $total_slis" | bc -l)
    else
        compliance_percentage=100
    fi
    
    local final_result
    final_result=$(echo "$compliance_results" | jq \
        --arg percentage "$compliance_percentage" \
        --arg total "$total_slis" \
        --arg compliant "$compliant_slis" \
        '{
            sli_details: .,
            summary: {
                total_slis: ($total | tonumber),
                compliant_slis: ($compliant | tonumber),
                compliance_percentage: ($percentage | tonumber)
            }
        }')
    
    echo "$final_result"
}

# Export utility functions for use in other scripts
export -f log_info log_success log_warn log_error log_debug
export -f query_prometheus_with_retry query_prometheus_metric
export -f query_loki_advanced execute_health_check
export -f calculate_advanced_health_score detect_flapping
export -f resolve_team_environment check_sli_compliance