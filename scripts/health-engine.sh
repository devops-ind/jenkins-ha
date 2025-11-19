#!/bin/bash
# Multi-Source Health Engine for Jenkins HA Zero-Downtime Auto-Healing
# Integrates Prometheus metrics, Loki logs, and health checks for intelligent decision making
# Part of Jenkins HA infrastructure automation

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/health-engine.json"
LOG_FILE="${PROJECT_ROOT}/logs/health-engine.log"
STATE_FILE="${PROJECT_ROOT}/logs/health-engine-state.json"

# Default configuration
DEFAULT_PROMETHEUS_URL="http://localhost:9090"
DEFAULT_LOKI_URL="http://localhost:3100"
DEFAULT_GRAFANA_URL="http://localhost:9300"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log() { 
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}]${NC} $1" | tee -a "$LOG_FILE"
}

error() { 
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] [ERROR]${NC} $1" | tee -a "$LOG_FILE" >&2
}

success() { 
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warn() { 
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] [WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${PURPLE}[${timestamp}] [DEBUG]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

# Initialize directories
init_dirs() {
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    mkdir -p "$(dirname "$STATE_FILE")"
}

# Load configuration
load_config() {
    local config_data="{}"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        config_data=$(cat "$CONFIG_FILE")
    else
        # Create default configuration
        cat > "$CONFIG_FILE" << 'EOF'
{
  "global": {
    "prometheus_url": "http://localhost:9090",
    "loki_url": "http://localhost:3100",
    "grafana_url": "http://localhost:9300",
    "health_check_timeout": 30,
    "circuit_breaker_threshold": 3,
    "circuit_breaker_timeout": 300,
    "evaluation_window": "5m",
    "trend_analysis_window": "30m"
  },
  "teams": {
    "devops": {
      "enabled": true,
      "weights": {
        "prometheus_metrics": 40,
        "loki_logs": 30,
        "health_checks": 30
      },
      "thresholds": {
        "error_rate_max": 5.0,
        "response_time_p95_max": 2000,
        "service_availability_min": 99.0,
        "memory_usage_max": 85.0,
        "cpu_usage_max": 80.0,
        "disk_usage_max": 85.0
      },
      "log_patterns": {
        "error_patterns": [
          "ERROR",
          "Exception",
          "java.lang.*Exception",
          "OutOfMemoryError",
          "Connection refused",
          "Timeout"
        ],
        "critical_patterns": [
          "FATAL",
          "OutOfMemoryError",
          "Connection reset",
          "Service unavailable",
          "502 Bad Gateway",
          "503 Service Unavailable"
        ]
      },
      "health_score_thresholds": {
        "healthy": 85,
        "warning": 70,
        "critical": 50
      },
      "auto_healing": {
        "enabled": true,
        "actions": ["restart", "switch_environment"],
        "max_attempts": 3,
        "backoff_multiplier": 2
      }
    },
    "ma": {
      "enabled": true,
      "weights": {
        "prometheus_metrics": 45,
        "loki_logs": 25,
        "health_checks": 30
      },
      "thresholds": {
        "error_rate_max": 3.0,
        "response_time_p95_max": 1500,
        "service_availability_min": 99.5,
        "memory_usage_max": 80.0,
        "cpu_usage_max": 75.0,
        "disk_usage_max": 80.0
      },
      "log_patterns": {
        "error_patterns": [
          "ERROR",
          "Exception",
          "Failed to process",
          "Connection timeout"
        ],
        "critical_patterns": [
          "FATAL",
          "Service down",
          "Database connection failed"
        ]
      },
      "health_score_thresholds": {
        "healthy": 90,
        "warning": 75,
        "critical": 60
      },
      "auto_healing": {
        "enabled": true,
        "actions": ["restart"],
        "max_attempts": 2,
        "backoff_multiplier": 1.5
      }
    },
    "ba": {
      "enabled": true,
      "weights": {
        "prometheus_metrics": 50,
        "loki_logs": 20,
        "health_checks": 30
      },
      "thresholds": {
        "error_rate_max": 2.0,
        "response_time_p95_max": 1000,
        "service_availability_min": 99.8,
        "memory_usage_max": 75.0,
        "cpu_usage_max": 70.0,
        "disk_usage_max": 75.0
      },
      "log_patterns": {
        "error_patterns": [
          "ERROR",
          "Exception",
          "Analytics processing failed"
        ],
        "critical_patterns": [
          "FATAL",
          "Data corruption",
          "Analytics service down"
        ]
      },
      "health_score_thresholds": {
        "healthy": 95,
        "warning": 80,
        "critical": 65
      },
      "auto_healing": {
        "enabled": true,
        "actions": ["restart"],
        "max_attempts": 2,
        "backoff_multiplier": 2
      }
    },
    "tw": {
      "enabled": true,
      "weights": {
        "prometheus_metrics": 35,
        "loki_logs": 35,
        "health_checks": 30
      },
      "thresholds": {
        "error_rate_max": 8.0,
        "response_time_p95_max": 3000,
        "service_availability_min": 98.0,
        "memory_usage_max": 90.0,
        "cpu_usage_max": 85.0,
        "disk_usage_max": 90.0
      },
      "log_patterns": {
        "error_patterns": [
          "ERROR",
          "Test failed",
          "Build failed",
          "Exception"
        ],
        "critical_patterns": [
          "FATAL",
          "Test suite crashed",
          "CI/CD pipeline failed"
        ]
      },
      "health_score_thresholds": {
        "healthy": 80,
        "warning": 65,
        "critical": 45
      },
      "auto_healing": {
        "enabled": true,
        "actions": ["restart", "switch_environment"],
        "max_attempts": 4,
        "backoff_multiplier": 1.8
      }
    }
  }
}
EOF
        config_data=$(cat "$CONFIG_FILE")
    fi
    
    echo "$config_data"
}

# Query Prometheus metrics
query_prometheus() {
    local team="$1"
    local metric="$2"
    local prometheus_url="$3"
    local window="${4:-5m}"
    
    debug "Querying Prometheus: $metric for team $team (window: $window)"
    
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
        *)
            error "Unknown metric: $metric"
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
    
    debug "No data found for metric $metric (team: $team)"
    echo "null"
    return 1
}

# Query Loki logs
query_loki() {
    local team="$1"
    local pattern="$2"
    local loki_url="$3"
    local window="${4:-5m}"
    
    debug "Querying Loki: $pattern for team $team (window: $window)"
    
    local query_url="${loki_url}/loki/api/v1/query_range"
    local start_time=$(($(date +%s) - 300))  # 5 minutes ago
    local end_time=$(date +%s)
    
    # Construct LogQL query
    local logql_query="{jenkins_team=\"${team}\"} |~ \"${pattern}\""
    local encoded_query=$(printf '%s' "$logql_query" | jq -sRr @uri)
    
    local response
    response=$(curl -s --max-time 10 "${query_url}?query=${encoded_query}&start=${start_time}000000000&end=${end_time}000000000" 2>/dev/null || echo '{"status":"error"}')
    
    if echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        local count
        count=$(echo "$response" | jq '.data.result | length')
        echo "$count"
        return 0
    fi
    
    debug "No logs found for pattern $pattern (team: $team)"
    echo "0"
    return 1
}

# Run health checks
run_health_checks() {
    local team="$1"
    local config="$2"
    
    debug "Running health checks for team: $team"
    
    local health_script="${PROJECT_ROOT}/ansible/roles/jenkins-master-v2/templates/blue-green-healthcheck.sh.j2"
    
    # Check if team-specific health check script exists
    local team_health_script="/opt/jenkins/scripts/health-check-${team}.sh"
    if [[ -f "$team_health_script" ]]; then
        health_script="$team_health_script"
    fi
    
    if [[ ! -f "$health_script" ]]; then
        warn "Health check script not found: $health_script"
        return 1
    fi
    
    # Run health check and capture exit code
    local health_result=0
    if timeout 30 bash "$health_script" health >/dev/null 2>&1; then
        health_result=100  # 100% healthy
    else
        health_result=0    # 0% healthy
    fi
    
    echo "$health_result"
    return 0
}

# Calculate health score
calculate_health_score() {
    local team="$1"
    local metrics_data="$2"
    local logs_data="$3"
    local health_data="$4"
    local config="$5"
    
    local weights=$(echo "$config" | jq -r ".teams.${team}.weights")
    local thresholds=$(echo "$config" | jq -r ".teams.${team}.thresholds")
    
    local prometheus_weight=$(echo "$weights" | jq -r '.prometheus_metrics')
    local loki_weight=$(echo "$weights" | jq -r '.loki_logs')
    local health_weight=$(echo "$weights" | jq -r '.health_checks')
    
    # Calculate metrics score (0-100)
    local metrics_score=100
    
    # Error rate (lower is better)
    local error_rate=$(echo "$metrics_data" | jq -r '.error_rate // 0')
    local error_rate_max=$(echo "$thresholds" | jq -r '.error_rate_max')
    if (( $(echo "$error_rate > $error_rate_max" | bc -l) )); then
        metrics_score=$((metrics_score - 20))
    fi
    
    # Response time (lower is better)
    local response_time=$(echo "$metrics_data" | jq -r '.response_time_p95 // 0')
    local response_time_max=$(echo "$thresholds" | jq -r '.response_time_p95_max')
    if (( $(echo "$response_time > $response_time_max" | bc -l) )); then
        metrics_score=$((metrics_score - 15))
    fi
    
    # Service availability (higher is better)
    local availability=$(echo "$metrics_data" | jq -r '.service_availability // 100')
    local availability_min=$(echo "$thresholds" | jq -r '.service_availability_min')
    if (( $(echo "$availability < $availability_min" | bc -l) )); then
        metrics_score=$((metrics_score - 25))
    fi
    
    # Memory usage (lower is better)
    local memory_usage=$(echo "$metrics_data" | jq -r '.memory_usage // 0')
    local memory_usage_max=$(echo "$thresholds" | jq -r '.memory_usage_max')
    if (( $(echo "$memory_usage > $memory_usage_max" | bc -l) )); then
        metrics_score=$((metrics_score - 15))
    fi
    
    # CPU usage (lower is better)
    local cpu_usage=$(echo "$metrics_data" | jq -r '.cpu_usage // 0')
    local cpu_usage_max=$(echo "$thresholds" | jq -r '.cpu_usage_max')
    if (( $(echo "$cpu_usage > $cpu_usage_max" | bc -l) )); then
        metrics_score=$((metrics_score - 10))
    fi
    
    # Disk usage (lower is better)
    local disk_usage=$(echo "$metrics_data" | jq -r '.disk_usage // 0')
    local disk_usage_max=$(echo "$thresholds" | jq -r '.disk_usage_max')
    if (( $(echo "$disk_usage > $disk_usage_max" | bc -l) )); then
        metrics_score=$((metrics_score - 15))
    fi
    
    # Ensure metrics score is not negative
    if (( metrics_score < 0 )); then
        metrics_score=0
    fi
    
    # Calculate logs score (0-100, based on error patterns)
    local logs_score=100
    local error_count=$(echo "$logs_data" | jq -r '.error_count // 0')
    local critical_count=$(echo "$logs_data" | jq -r '.critical_count // 0')
    
    # Deduct points for errors and critical issues
    logs_score=$((logs_score - (error_count * 2) - (critical_count * 10)))
    if (( logs_score < 0 )); then
        logs_score=0
    fi
    
    # Health checks score is already 0-100
    local health_score=$(echo "$health_data" | jq -r '.health_score // 0')
    
    # Calculate weighted total score
    local total_score
    total_score=$(echo "scale=2; ($metrics_score * $prometheus_weight + $logs_score * $loki_weight + $health_score * $health_weight) / 100" | bc -l)
    
    printf "%.0f" "$total_score"
}

# Assess team health
assess_team_health() {
    local team="$1"
    local config="$2"
    local prometheus_url="$3"
    local loki_url="$4"
    
    log "Assessing health for team: $team"
    
    # Check if team is enabled
    local enabled=$(echo "$config" | jq -r ".teams.${team}.enabled // false")
    if [[ "$enabled" != "true" ]]; then
        warn "Team $team is disabled, skipping assessment"
        return 0
    fi
    
    # Collect Prometheus metrics
    local metrics_data="{}"
    local evaluation_window=$(echo "$config" | jq -r '.global.evaluation_window')
    
    debug "Collecting Prometheus metrics for $team"
    for metric in error_rate response_time_p95 service_availability memory_usage cpu_usage disk_usage deployment_success_rate blue_green_switch_success_rate; do
        local value
        value=$(query_prometheus "$team" "$metric" "$prometheus_url" "$evaluation_window")
        metrics_data=$(echo "$metrics_data" | jq --arg metric "$metric" --arg value "$value" '. + {($metric): ($value | tonumber? // 0)}')
    done
    
    # Collect Loki log data
    local logs_data="{}"
    local log_patterns=$(echo "$config" | jq -r ".teams.${team}.log_patterns")
    
    debug "Collecting Loki log data for $team"
    local error_patterns=$(echo "$log_patterns" | jq -r '.error_patterns[]' | tr '\n' '|' | sed 's/|$//')
    local critical_patterns=$(echo "$log_patterns" | jq -r '.critical_patterns[]' | tr '\n' '|' | sed 's/|$//')
    
    local error_count=0
    local critical_count=0
    
    if [[ -n "$error_patterns" ]]; then
        error_count=$(query_loki "$team" "$error_patterns" "$loki_url" "$evaluation_window")
    fi
    
    if [[ -n "$critical_patterns" ]]; then
        critical_count=$(query_loki "$team" "$critical_patterns" "$loki_url" "$evaluation_window")
    fi
    
    logs_data=$(echo "$logs_data" | jq --arg error_count "$error_count" --arg critical_count "$critical_count" '. + {error_count: ($error_count | tonumber), critical_count: ($critical_count | tonumber)}')
    
    # Run health checks
    debug "Running health checks for $team"
    local health_score
    health_score=$(run_health_checks "$team" "$config")
    local health_data="{\"health_score\": $health_score}"
    
    # Calculate overall health score
    local overall_score
    overall_score=$(calculate_health_score "$team" "$metrics_data" "$logs_data" "$health_data" "$config")
    
    # Determine health status
    local health_thresholds=$(echo "$config" | jq -r ".teams.${team}.health_score_thresholds")
    local healthy_threshold=$(echo "$health_thresholds" | jq -r '.healthy')
    local warning_threshold=$(echo "$health_thresholds" | jq -r '.warning')
    local critical_threshold=$(echo "$health_thresholds" | jq -r '.critical')
    
    local status="unknown"
    if (( overall_score >= healthy_threshold )); then
        status="healthy"
    elif (( overall_score >= warning_threshold )); then
        status="warning"
    elif (( overall_score >= critical_threshold )); then
        status="critical"
    else
        status="failed"
    fi
    
    # Create assessment result
    local assessment
    assessment=$(jq -n \
        --arg team "$team" \
        --arg status "$status" \
        --arg score "$overall_score" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson metrics "$metrics_data" \
        --argjson logs "$logs_data" \
        --argjson health "$health_data" \
        '{
            team: $team,
            status: $status,
            score: ($score | tonumber),
            timestamp: $timestamp,
            metrics: $metrics,
            logs: $logs,
            health: $health,
            assessment_details: {
                error_rate: $metrics.error_rate,
                response_time_p95: $metrics.response_time_p95,
                service_availability: $metrics.service_availability,
                memory_usage: $metrics.memory_usage,
                cpu_usage: $metrics.cpu_usage,
                disk_usage: $metrics.disk_usage,
                error_count: $logs.error_count,
                critical_count: $logs.critical_count,
                health_score: $health.health_score
            }
        }')
    
    # Log assessment result
    case "$status" in
        "healthy")
            success "Team $team is healthy (score: $overall_score)"
            ;;
        "warning")
            warn "Team $team needs attention (score: $overall_score)"
            ;;
        "critical")
            error "Team $team is in critical state (score: $overall_score)"
            ;;
        "failed")
            error "Team $team has failed health assessment (score: $overall_score)"
            ;;
    esac
    
    echo "$assessment"
}

# Load historical data for trend analysis
load_historical_data() {
    local team="$1"
    local lookback_hours="${2:-24}"
    
    if [[ -f "$STATE_FILE" ]]; then
        local historical_data
        historical_data=$(cat "$STATE_FILE" | jq --arg team "$team" --arg cutoff_time "$(date -u -d "${lookback_hours} hours ago" +%Y-%m-%dT%H:%M:%SZ)" '
            .historical_assessments[$team] // [] | 
            map(select(.timestamp > $cutoff_time)) |
            sort_by(.timestamp)
        ')
        echo "$historical_data"
    else
        echo "[]"
    fi
}

# Perform trend analysis
analyze_trends() {
    local team="$1"
    local current_assessment="$2"
    local config="$3"
    
    local trend_window=$(echo "$config" | jq -r '.global.trend_analysis_window // "30m"')
    local lookback_hours=1  # Default to 1 hour for 30m window
    
    case "$trend_window" in
        *h) lookback_hours=${trend_window%h} ;;
        *m) lookback_hours=1 ;;  # Convert minutes to 1 hour minimum
    esac
    
    local historical_data
    historical_data=$(load_historical_data "$team" "$lookback_hours")
    
    local historical_count
    historical_count=$(echo "$historical_data" | jq 'length')
    
    if (( historical_count < 3 )); then
        debug "Insufficient historical data for trend analysis (team: $team, count: $historical_count)"
        echo "{\"trend\": \"insufficient_data\", \"confidence\": 0}"
        return 0
    fi
    
    # Calculate trend metrics
    local scores
    scores=$(echo "$historical_data" | jq '[.[].score]')
    local current_score
    current_score=$(echo "$current_assessment" | jq '.score')
    
    # Calculate average of recent scores
    local recent_avg
    recent_avg=$(echo "$scores" | jq 'add / length')
    
    # Determine trend direction
    local trend="stable"
    local confidence=50
    
    if (( $(echo "$current_score > ($recent_avg + 10)" | bc -l) )); then
        trend="improving"
        confidence=75
    elif (( $(echo "$current_score < ($recent_avg - 10)" | bc -l) )); then
        trend="degrading"
        confidence=75
    fi
    
    # Check for consistent pattern
    local last_three_scores
    last_three_scores=$(echo "$historical_data" | jq '.[-3:] | [.[].score]')
    if (( $(echo "$last_three_scores" | jq 'length') == 3 )); then
        local score1 score2 score3
        score1=$(echo "$last_three_scores" | jq '.[0]')
        score2=$(echo "$last_three_scores" | jq '.[1]')
        score3=$(echo "$last_three_scores" | jq '.[2]')
        
        if (( $(echo "$score1 < $score2 && $score2 < $score3" | bc -l) )); then
            trend="improving"
            confidence=90
        elif (( $(echo "$score1 > $score2 && $score2 > $score3" | bc -l) )); then
            trend="degrading"
            confidence=90
        fi
    fi
    
    local trend_analysis
    trend_analysis=$(jq -n \
        --arg trend "$trend" \
        --arg confidence "$confidence" \
        --arg recent_avg "$recent_avg" \
        --arg historical_count "$historical_count" \
        '{
            trend: $trend,
            confidence: ($confidence | tonumber),
            recent_average: ($recent_avg | tonumber),
            data_points: ($historical_count | tonumber)
        }')
    
    debug "Trend analysis for $team: $trend (confidence: $confidence%)"
    echo "$trend_analysis"
}

# Check circuit breaker status
check_circuit_breaker() {
    local team="$1"
    local config="$2"
    
    local threshold=$(echo "$config" | jq -r '.global.circuit_breaker_threshold')
    local timeout=$(echo "$config" | jq -r '.global.circuit_breaker_timeout')
    
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "{\"status\": \"closed\", \"failure_count\": 0}"
        return 0
    fi
    
    local circuit_state
    circuit_state=$(cat "$STATE_FILE" | jq --arg team "$team" '.circuit_breakers[$team] // {status: "closed", failure_count: 0, last_failure: null}')
    
    local status=$(echo "$circuit_state" | jq -r '.status')
    local failure_count=$(echo "$circuit_state" | jq -r '.failure_count')
    local last_failure=$(echo "$circuit_state" | jq -r '.last_failure')
    
    # Check if circuit breaker should be reset
    if [[ "$status" == "open" && -n "$last_failure" && "$last_failure" != "null" ]]; then
        local failure_time
        failure_time=$(date -d "$last_failure" +%s 2>/dev/null || echo 0)
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - failure_time))
        
        if (( elapsed > timeout )); then
            debug "Circuit breaker timeout reached for $team, resetting to half-open"
            status="half-open"
            failure_count=0
        fi
    fi
    
    echo "{\"status\": \"$status\", \"failure_count\": $failure_count, \"threshold\": $threshold}"
}

# Update circuit breaker state
update_circuit_breaker() {
    local team="$1"
    local assessment="$2"
    local config="$3"
    
    local current_status=$(echo "$assessment" | jq -r '.status')
    local circuit_state
    circuit_state=$(check_circuit_breaker "$team" "$config")
    
    local cb_status=$(echo "$circuit_state" | jq -r '.status')
    local failure_count=$(echo "$circuit_state" | jq -r '.failure_count')
    local threshold=$(echo "$circuit_state" | jq -r '.threshold')
    
    local new_status="$cb_status"
    local new_failure_count="$failure_count"
    local last_failure="null"
    
    if [[ "$current_status" == "critical" || "$current_status" == "failed" ]]; then
        new_failure_count=$((failure_count + 1))
        last_failure=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        
        if (( new_failure_count >= threshold )); then
            new_status="open"
            warn "Circuit breaker opened for team $team (failures: $new_failure_count)"
        fi
    elif [[ "$current_status" == "healthy" ]]; then
        if [[ "$cb_status" == "half-open" ]]; then
            new_status="closed"
            new_failure_count=0
            debug "Circuit breaker closed for team $team"
        fi
    fi
    
    # Update state file
    local updated_state
    if [[ -f "$STATE_FILE" ]]; then
        updated_state=$(cat "$STATE_FILE")
    else
        updated_state="{\"circuit_breakers\": {}, \"historical_assessments\": {}}"
    fi
    
    updated_state=$(echo "$updated_state" | jq \
        --arg team "$team" \
        --arg status "$new_status" \
        --arg failure_count "$new_failure_count" \
        --arg last_failure "$last_failure" \
        '.circuit_breakers[$team] = {
            status: $status,
            failure_count: ($failure_count | tonumber),
            last_failure: (if $last_failure == "null" then null else $last_failure end),
            updated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }')
    
    echo "$updated_state" > "$STATE_FILE"
    
    echo "{\"status\": \"$new_status\", \"failure_count\": $new_failure_count}"
}

# Store assessment in historical data
store_assessment() {
    local assessment="$1"
    local team
    team=$(echo "$assessment" | jq -r '.team')
    
    local updated_state
    if [[ -f "$STATE_FILE" ]]; then
        updated_state=$(cat "$STATE_FILE")
    else
        updated_state="{\"circuit_breakers\": {}, \"historical_assessments\": {}}"
    fi
    
    # Keep only last 100 assessments per team
    updated_state=$(echo "$updated_state" | jq \
        --argjson assessment "$assessment" \
        --arg team "$team" \
        '.historical_assessments[$team] = ((.historical_assessments[$team] // []) + [$assessment])[-100:]')
    
    echo "$updated_state" > "$STATE_FILE"
}

# Generate health report
generate_health_report() {
    local assessments="$1"
    local config="$2"
    local output_format="${3:-json}"
    
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    local report
    report=$(jq -n \
        --argjson assessments "$assessments" \
        --arg timestamp "$timestamp" \
        --arg format "$output_format" \
        '{
            timestamp: $timestamp,
            engine_version: "1.0.0",
            total_teams: ($assessments | length),
            summary: {
                healthy: ($assessments | map(select(.status == "healthy")) | length),
                warning: ($assessments | map(select(.status == "warning")) | length),
                critical: ($assessments | map(select(.status == "critical")) | length),
                failed: ($assessments | map(select(.status == "failed")) | length)
            },
            assessments: $assessments
        }')
    
    case "$output_format" in
        "json")
            echo "$report"
            ;;
        "text")
            echo "=== Multi-Source Health Engine Report ==="
            echo "Timestamp: $timestamp"
            echo ""
            echo "Summary:"
            echo "  Healthy: $(echo "$report" | jq -r '.summary.healthy')"
            echo "  Warning: $(echo "$report" | jq -r '.summary.warning')"
            echo "  Critical: $(echo "$report" | jq -r '.summary.critical')"
            echo "  Failed: $(echo "$report" | jq -r '.summary.failed')"
            echo ""
            echo "Team Details:"
            echo "$assessments" | jq -r '.[] | "  \(.team): \(.status) (score: \(.score))"'
            ;;
        "prometheus")
            # Generate Prometheus metrics format
            echo "# HELP jenkins_health_engine_score Overall health score for Jenkins teams"
            echo "# TYPE jenkins_health_engine_score gauge"
            echo "$assessments" | jq -r '.[] | "jenkins_health_engine_score{team=\"\(.team)\",status=\"\(.status)\"} \(.score)"'
            echo ""
            echo "# HELP jenkins_health_engine_assessment_timestamp Last assessment timestamp"
            echo "# TYPE jenkins_health_engine_assessment_timestamp gauge"
            echo "$assessments" | jq -r '.[] | "jenkins_health_engine_assessment_timestamp{team=\"\(.team)\"} \(.timestamp | fromdate)"'
            ;;
    esac
}

# Main assessment function
run_assessment() {
    local teams="${1:-all}"
    local output_format="${2:-json}"
    local config
    
    log "Starting multi-source health assessment"
    
    config=$(load_config)
    
    local prometheus_url=$(echo "$config" | jq -r '.global.prometheus_url')
    local loki_url=$(echo "$config" | jq -r '.global.loki_url')
    
    # Validate connectivity to monitoring systems
    if ! curl -s --max-time 5 "${prometheus_url}/-/healthy" >/dev/null; then
        error "Cannot connect to Prometheus at $prometheus_url"
        return 1
    fi
    
    if ! curl -s --max-time 5 "${loki_url}/ready" >/dev/null; then
        warn "Cannot connect to Loki at $loki_url, log analysis will be limited"
    fi
    
    local assessments="[]"
    local team_list
    
    if [[ "$teams" == "all" ]]; then
        team_list=$(echo "$config" | jq -r '.teams | keys[]')
    else
        team_list=$(echo "$teams" | tr ',' '\n')
    fi
    
    for team in $team_list; do
        debug "Processing team: $team"
        
        # Check circuit breaker
        local circuit_state
        circuit_state=$(check_circuit_breaker "$team" "$config")
        local cb_status=$(echo "$circuit_state" | jq -r '.status')
        
        if [[ "$cb_status" == "open" ]]; then
            warn "Circuit breaker is open for team $team, skipping assessment"
            local circuit_assessment
            circuit_assessment=$(jq -n \
                --arg team "$team" \
                --arg status "circuit_open" \
                --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                '{
                    team: $team,
                    status: $status,
                    score: 0,
                    timestamp: $timestamp,
                    circuit_breaker: {status: "open"}
                }')
            assessments=$(echo "$assessments" | jq --argjson assessment "$circuit_assessment" '. + [$assessment]')
            continue
        fi
        
        # Perform assessment
        local assessment
        assessment=$(assess_team_health "$team" "$config" "$prometheus_url" "$loki_url")
        
        # Perform trend analysis
        local trend_analysis
        trend_analysis=$(analyze_trends "$team" "$assessment" "$config")
        assessment=$(echo "$assessment" | jq --argjson trends "$trend_analysis" '. + {trends: $trends}')
        
        # Update circuit breaker
        local updated_circuit
        updated_circuit=$(update_circuit_breaker "$team" "$assessment" "$config")
        assessment=$(echo "$assessment" | jq --argjson circuit "$updated_circuit" '. + {circuit_breaker: $circuit}')
        
        # Store assessment
        store_assessment "$assessment"
        
        # Add to results
        assessments=$(echo "$assessments" | jq --argjson assessment "$assessment" '. + [$assessment]')
    done
    
    # Generate and output report
    local report
    report=$(generate_health_report "$assessments" "$config" "$output_format")
    
    success "Health assessment completed for $(echo "$assessments" | jq 'length') teams"
    echo "$report"
}

# Auto-healing trigger
trigger_auto_healing() {
    local team="$1"
    local assessment="$2"
    local config="$3"
    
    local auto_healing_config
    auto_healing_config=$(echo "$config" | jq -r ".teams.${team}.auto_healing")
    
    local enabled=$(echo "$auto_healing_config" | jq -r '.enabled')
    if [[ "$enabled" != "true" ]]; then
        debug "Auto-healing disabled for team $team"
        return 0
    fi
    
    local status=$(echo "$assessment" | jq -r '.status')
    if [[ "$status" != "critical" && "$status" != "failed" ]]; then
        debug "Team $team status ($status) does not require auto-healing"
        return 0
    fi
    
    local actions=$(echo "$auto_healing_config" | jq -r '.actions[]')
    local max_attempts=$(echo "$auto_healing_config" | jq -r '.max_attempts')
    local backoff_multiplier=$(echo "$auto_healing_config" | jq -r '.backoff_multiplier')
    
    log "Triggering auto-healing for team $team (status: $status)"
    
    # Check recent auto-healing attempts
    local attempts_today=0
    if [[ -f "$STATE_FILE" ]]; then
        local today=$(date +%Y-%m-%d)
        attempts_today=$(cat "$STATE_FILE" | jq --arg team "$team" --arg today "$today" '
            .auto_healing_attempts[$team] // [] | 
            map(select(.date == $today)) | 
            length
        ')
    fi
    
    if (( attempts_today >= max_attempts )); then
        error "Maximum auto-healing attempts reached for team $team today ($attempts_today/$max_attempts)"
        return 1
    fi
    
    # Execute auto-healing actions
    for action in $actions; do
        case "$action" in
            "restart")
                log "Executing restart action for team $team"
                if [[ -f "${PROJECT_ROOT}/scripts/restart-jenkins.sh" ]]; then
                    "${PROJECT_ROOT}/scripts/restart-jenkins.sh" "$team"
                else
                    error "Restart script not found"
                fi
                ;;
            "switch_environment")
                log "Executing environment switch for team $team"
                if [[ -f "${PROJECT_ROOT}/scripts/blue-green-switch.sh" ]]; then
                    "${PROJECT_ROOT}/scripts/blue-green-switch.sh" "$team"
                else
                    error "Blue-green switch script not found"
                fi
                ;;
            "scale_up")
                log "Executing scale up action for team $team"
                # Implementation depends on your scaling mechanism
                warn "Scale up action not implemented yet"
                ;;
            *)
                warn "Unknown auto-healing action: $action"
                ;;
        esac
        
        # Wait between actions with backoff
        sleep $((attempts_today * backoff_multiplier + 1))
    done
    
    # Record auto-healing attempt
    local updated_state
    if [[ -f "$STATE_FILE" ]]; then
        updated_state=$(cat "$STATE_FILE")
    else
        updated_state="{\"auto_healing_attempts\": {}}"
    fi
    
    local attempt_record
    attempt_record=$(jq -n \
        --arg team "$team" \
        --arg action "$actions" \
        --arg date "$(date +%Y-%m-%d)" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg trigger_status "$status" \
        '{
            team: $team,
            actions: $action,
            date: $date,
            timestamp: $timestamp,
            trigger_status: $trigger_status
        }')
    
    updated_state=$(echo "$updated_state" | jq \
        --arg team "$team" \
        --argjson attempt "$attempt_record" \
        '.auto_healing_attempts[$team] = ((.auto_healing_attempts[$team] // []) + [$attempt])[-10:]')
    
    echo "$updated_state" > "$STATE_FILE"
    
    success "Auto-healing actions completed for team $team"
}

# Show usage
show_usage() {
    cat << 'EOF'
Multi-Source Health Engine for Jenkins HA

USAGE:
    health-engine.sh [command] [options]

COMMANDS:
    assess [teams] [format]     - Run health assessment
                                  teams: comma-separated list or 'all' (default: all)
                                  format: json|text|prometheus (default: json)
    
    trends <team>              - Show trend analysis for specific team
    
    circuit-breaker [team]     - Show circuit breaker status
                                 team: specific team or 'all' (default: all)
    
    auto-heal <team>           - Trigger auto-healing for team
    
    config                     - Show current configuration
    
    validate                   - Validate configuration and connectivity
    
    monitor [interval]         - Continuous monitoring mode
                                 interval: seconds between assessments (default: 300)

OPTIONS:
    --debug                    - Enable debug logging
    --config-file <path>       - Override config file location
    --log-file <path>          - Override log file location
    --prometheus-url <url>     - Override Prometheus URL
    --loki-url <url>           - Override Loki URL

EXAMPLES:
    # Run assessment for all teams
    ./health-engine.sh assess
    
    # Run assessment for specific teams in text format
    ./health-engine.sh assess devops,ma text
    
    # Show trends for devops team
    ./health-engine.sh trends devops
    
    # Check circuit breaker status
    ./health-engine.sh circuit-breaker
    
    # Trigger auto-healing for critical team
    ./health-engine.sh auto-heal devops
    
    # Start continuous monitoring
    ./health-engine.sh monitor 120
    
    # Enable debug mode
    DEBUG=true ./health-engine.sh assess all json

INTEGRATION:
    The health engine integrates with:
    - Prometheus metrics (jenkins:* metrics)
    - Loki log analysis (error pattern detection)
    - Container health checks (via team-specific scripts)
    - Blue-green deployment system
    - Auto-healing mechanisms

CONFIGURATION:
    Configuration is stored in: config/health-engine.json
    Team-specific thresholds, weights, and policies can be customized.
    
    State and historical data: logs/health-engine-state.json
    
OUTPUT FORMATS:
    - json: Structured data for automation
    - text: Human-readable summary
    - prometheus: Metrics format for Prometheus ingestion

EOF
}

# Validate configuration and connectivity
validate_setup() {
    log "Validating health engine setup"
    
    local config
    config=$(load_config)
    
    local prometheus_url=$(echo "$config" | jq -r '.global.prometheus_url')
    local loki_url=$(echo "$config" | jq -r '.global.loki_url')
    local grafana_url=$(echo "$config" | jq -r '.global.grafana_url')
    
    local validation_errors=0
    
    # Test Prometheus connectivity
    if curl -s --max-time 5 "${prometheus_url}/-/healthy" >/dev/null; then
        success "Prometheus connectivity: OK ($prometheus_url)"
    else
        error "Prometheus connectivity: FAILED ($prometheus_url)"
        ((validation_errors++))
    fi
    
    # Test Loki connectivity
    if curl -s --max-time 5 "${loki_url}/ready" >/dev/null; then
        success "Loki connectivity: OK ($loki_url)"
    else
        warn "Loki connectivity: FAILED ($loki_url) - log analysis will be limited"
    fi
    
    # Test Grafana connectivity
    if curl -s --max-time 5 "${grafana_url}/api/health" >/dev/null; then
        success "Grafana connectivity: OK ($grafana_url)"
    else
        warn "Grafana connectivity: FAILED ($grafana_url)"
    fi
    
    # Validate team configurations
    local teams=$(echo "$config" | jq -r '.teams | keys[]')
    for team in $teams; do
        local team_config=$(echo "$config" | jq -r ".teams.${team}")
        local enabled=$(echo "$team_config" | jq -r '.enabled')
        
        if [[ "$enabled" == "true" ]]; then
            success "Team configuration: $team (enabled)"
            
            # Check health check script
            local health_script="/opt/jenkins/scripts/health-check-${team}.sh"
            if [[ -f "$health_script" ]]; then
                success "Health check script: $team (found)"
            else
                warn "Health check script: $team (not found at $health_script)"
            fi
        else
            debug "Team configuration: $team (disabled)"
        fi
    done
    
    # Test metric queries
    local test_team="devops"  # Use devops as test team
    log "Testing metric queries for team: $test_team"
    
    for metric in error_rate response_time_p95 service_availability; do
        local value
        value=$(query_prometheus "$test_team" "$metric" "$prometheus_url" "5m")
        if [[ "$value" != "null" ]]; then
            success "Metric query: $metric (value: $value)"
        else
            warn "Metric query: $metric (no data)"
        fi
    done
    
    if (( validation_errors == 0 )); then
        success "Validation completed successfully"
        return 0
    else
        error "Validation completed with $validation_errors errors"
        return 1
    fi
}

# Continuous monitoring mode
monitor_continuous() {
    local interval="${1:-300}"  # Default 5 minutes
    
    log "Starting continuous monitoring mode (interval: ${interval}s)"
    
    while true; do
        log "Running scheduled health assessment"
        
        local assessment_result
        assessment_result=$(run_assessment "all" "json")
        
        # Check for teams requiring auto-healing
        local critical_teams
        critical_teams=$(echo "$assessment_result" | jq -r '.assessments[] | select(.status == "critical" or .status == "failed") | .team')
        
        if [[ -n "$critical_teams" ]]; then
            warn "Critical teams detected: $critical_teams"
            
            local config
            config=$(load_config)
            
            for team in $critical_teams; do
                local team_assessment
                team_assessment=$(echo "$assessment_result" | jq --arg team "$team" '.assessments[] | select(.team == $team)')
                
                # Trigger auto-healing if enabled
                trigger_auto_healing "$team" "$team_assessment" "$config"
            done
        fi
        
        # Output assessment in Prometheus format for metric collection
        local prometheus_metrics
        prometheus_metrics=$(generate_health_report "$(echo "$assessment_result" | jq '.assessments')" "$(load_config)" "prometheus")
        echo "$prometheus_metrics" > "${PROJECT_ROOT}/logs/health-engine-metrics.prom"
        
        log "Next assessment in ${interval} seconds"
        sleep "$interval"
    done
}

# Show trend analysis for specific team
show_trends() {
    local team="$1"
    
    if [[ -z "$team" ]]; then
        error "Team name is required for trend analysis"
        return 1
    fi
    
    log "Showing trend analysis for team: $team"
    
    local historical_data
    historical_data=$(load_historical_data "$team" "24")
    
    local count
    count=$(echo "$historical_data" | jq 'length')
    
    if (( count == 0 )); then
        warn "No historical data available for team $team"
        return 1
    fi
    
    echo "=== Trend Analysis for Team: $team ==="
    echo "Data points: $count (last 24 hours)"
    echo ""
    
    # Show recent assessments
    echo "Recent assessments:"
    echo "$historical_data" | jq -r '.[-10:] | .[] | "\(.timestamp): \(.status) (score: \(.score))"'
    
    echo ""
    
    # Show score statistics
    local scores
    scores=$(echo "$historical_data" | jq '[.[].score]')
    local min_score max_score avg_score
    min_score=$(echo "$scores" | jq 'min')
    max_score=$(echo "$scores" | jq 'max')
    avg_score=$(echo "$scores" | jq 'add / length | floor')
    
    echo "Score statistics:"
    echo "  Minimum: $min_score"
    echo "  Maximum: $max_score"
    echo "  Average: $avg_score"
    
    # Show status distribution
    echo ""
    echo "Status distribution:"
    echo "$historical_data" | jq -r 'group_by(.status) | .[] | "\(.[0].status): \(length) occurrences"'
}

# Show circuit breaker status
show_circuit_breaker() {
    local team="${1:-all}"
    
    log "Showing circuit breaker status"
    
    if [[ ! -f "$STATE_FILE" ]]; then
        warn "No state file found, all circuit breakers are closed"
        return 0
    fi
    
    local config
    config=$(load_config)
    
    if [[ "$team" == "all" ]]; then
        local teams
        teams=$(echo "$config" | jq -r '.teams | keys[]')
        
        echo "=== Circuit Breaker Status ==="
        for t in $teams; do
            local cb_state
            cb_state=$(check_circuit_breaker "$t" "$config")
            local status=$(echo "$cb_state" | jq -r '.status')
            local failure_count=$(echo "$cb_state" | jq -r '.failure_count')
            local threshold=$(echo "$cb_state" | jq -r '.threshold')
            
            echo "  $t: $status (failures: $failure_count/$threshold)"
        done
    else
        local cb_state
        cb_state=$(check_circuit_breaker "$team" "$config")
        echo "=== Circuit Breaker Status for Team: $team ==="
        echo "$cb_state" | jq '.'
    fi
}

# Main function
main() {
    init_dirs
    
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug)
                export DEBUG=true
                shift
                ;;
            --config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            --prometheus-url)
                export OVERRIDE_PROMETHEUS_URL="$2"
                shift 2
                ;;
            --loki-url)
                export OVERRIDE_LOKI_URL="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done
    
    local command="${1:-assess}"
    shift || true
    
    case "$command" in
        assess)
            local teams="${1:-all}"
            local format="${2:-json}"
            run_assessment "$teams" "$format"
            ;;
        trends)
            local team="${1:-}"
            show_trends "$team"
            ;;
        circuit-breaker|cb)
            local team="${1:-all}"
            show_circuit_breaker "$team"
            ;;
        auto-heal)
            local team="${1:-}"
            if [[ -z "$team" ]]; then
                error "Team name is required for auto-healing"
                exit 1
            fi
            
            local config
            config=$(load_config)
            local assessment
            assessment=$(assess_team_health "$team" "$config" \
                "$(echo "$config" | jq -r '.global.prometheus_url')" \
                "$(echo "$config" | jq -r '.global.loki_url')")
            
            trigger_auto_healing "$team" "$assessment" "$config"
            ;;
        config)
            local config
            config=$(load_config)
            echo "$config" | jq '.'
            ;;
        validate)
            validate_setup
            ;;
        monitor)
            local interval="${1:-300}"
            monitor_continuous "$interval"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi