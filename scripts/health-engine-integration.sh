#!/bin/bash
# Health Engine Integration Script
# Bridges health engine with Jenkins HA automation systems

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/health-engine-utils.sh"

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HEALTH_ENGINE_SCRIPT="${SCRIPT_DIR}/health-engine.sh"

# Integration configuration
INTEGRATION_CONFIG="${PROJECT_ROOT}/config/health-engine.json"
AUTOMATION_LOCK_DIR="/tmp/jenkins-health-automation"
AUTOMATION_LOG="${PROJECT_ROOT}/logs/health-automation.log"

# Ensure directories exist
mkdir -p "$(dirname "$AUTOMATION_LOG")"
mkdir -p "$AUTOMATION_LOCK_DIR"

# Lock management for automation safety
acquire_automation_lock() {
    local operation="$1"
    local team="$2"
    local lock_file="${AUTOMATION_LOCK_DIR}/${operation}-${team}.lock"
    local max_wait="${3:-300}"  # 5 minutes default
    
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
    
    echo "$$" > "$lock_file"
    log_debug "Acquired lock: $lock_file"
}

release_automation_lock() {
    local operation="$1"
    local team="$2"
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

# Jenkins API interaction
jenkins_api_call() {
    local team="$1"
    local endpoint="$2"
    local method="${3:-GET}"
    local data="${4:-}"
    
    log_debug "Jenkins API call: $method $endpoint for team $team"
    
    # Get Jenkins URL for team from configuration
    local jenkins_url
    if ! jenkins_url=$(jq -r --arg team "$team" '.integration_settings.external_tools.jenkins_api.url_template' "$INTEGRATION_CONFIG" 2>/dev/null); then
        jenkins_url="http://${team}jenkins.local.dev:8080"
    fi
    
    # Replace template variables
    jenkins_url="${jenkins_url//\{team\}/$team}"
    
    local full_url="${jenkins_url}${endpoint}"
    local curl_opts=("-s" "--max-time" "30")
    
    # Add authentication if configured
    local auth_type
    auth_type=$(jq -r '.integration_settings.external_tools.jenkins_api.authentication // "none"' "$INTEGRATION_CONFIG" 2>/dev/null)
    
    case "$auth_type" in
        "api_token")
            # Would need to get token from vault or environment
            curl_opts+=("-H" "Authorization: Bearer ${JENKINS_API_TOKEN:-}")
            ;;
        "basic")
            curl_opts+=("-u" "${JENKINS_USER:-admin}:${JENKINS_PASSWORD:-admin}")
            ;;
    esac
    
    # Add method-specific options
    case "$method" in
        "POST")
            curl_opts+=("-X" "POST")
            if [[ -n "$data" ]]; then
                curl_opts+=("-H" "Content-Type: application/json" "-d" "$data")
            fi
            ;;
        "PUT")
            curl_opts+=("-X" "PUT")
            if [[ -n "$data" ]]; then
                curl_opts+=("-H" "Content-Type: application/json" "-d" "$data")
            fi
            ;;
    esac
    
    local response
    if response=$(curl "${curl_opts[@]}" "$full_url" 2>/dev/null); then
        echo "$response"
        return 0
    else
        log_error "Jenkins API call failed: $method $full_url"
        return 1
    fi
}

# Blue-green environment switching integration
trigger_blue_green_switch() {
    local team="$1"
    local reason="${2:-health_engine_triggered}"
    local force="${3:-false}"
    
    log_info "Triggering blue-green switch for team $team (reason: $reason)"
    
    if ! acquire_automation_lock "blue_green_switch" "$team" 600; then
        log_error "Failed to acquire blue-green switch lock for team $team"
        return 1
    fi
    
    local switch_script="${PROJECT_ROOT}/scripts/blue-green-switch.sh"
    if [[ ! -f "$switch_script" ]]; then
        log_error "Blue-green switch script not found: $switch_script"
        release_automation_lock "blue_green_switch" "$team"
        return 1
    fi
    
    local switch_opts=()
    if [[ "$force" == "true" ]]; then
        switch_opts+=("--force")
    fi
    
    # Add health check validation
    switch_opts+=("--health-check" "--timeout" "300")
    
    local switch_result=0
    local start_time=$(date +%s)
    
    {
        echo "=== Blue-Green Switch Started ==="
        echo "Team: $team"
        echo "Reason: $reason"
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Force: $force"
        
        if "$switch_script" "$team" "${switch_opts[@]}"; then
            echo "=== Blue-Green Switch Completed Successfully ==="
            switch_result=0
        else
            echo "=== Blue-Green Switch Failed ==="
            switch_result=1
        fi
        
        local duration=$(($(date +%s) - start_time))
        echo "Duration: ${duration}s"
        echo "End Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
    } >> "$AUTOMATION_LOG"
    
    release_automation_lock "blue_green_switch" "$team"
    
    # Send notification
    send_notification "$team" "blue_green_switch" "$switch_result" "$reason"
    
    return $switch_result
}

# Jenkins service restart integration
trigger_jenkins_restart() {
    local team="$1"
    local restart_type="${2:-graceful}"
    local reason="${3:-health_engine_triggered}"
    
    log_info "Triggering Jenkins restart for team $team (type: $restart_type, reason: $reason)"
    
    if ! acquire_automation_lock "restart" "$team" 300; then
        log_error "Failed to acquire restart lock for team $team"
        return 1
    fi
    
    local restart_result=0
    local start_time=$(date +%s)
    
    {
        echo "=== Jenkins Restart Started ==="
        echo "Team: $team"
        echo "Type: $restart_type"
        echo "Reason: $reason"
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        
        case "$restart_type" in
            "graceful")
                # Graceful restart via Jenkins API
                if jenkins_api_call "$team" "/safeRestart" "POST"; then
                    echo "Graceful restart initiated successfully"
                    restart_result=0
                else
                    echo "Graceful restart failed, falling back to container restart"
                    restart_type="container"
                fi
                ;;
        esac
        
        if [[ "$restart_type" == "container" ]]; then
            # Container restart via systemd or docker
            local container_name="jenkins-${team}-$(resolve_team_environment "$team" "$(cat "$INTEGRATION_CONFIG")")"
            
            if systemctl is-active "jenkins-${team}.service" >/dev/null 2>&1; then
                if systemctl restart "jenkins-${team}.service"; then
                    echo "Container restart via systemd successful"
                    restart_result=0
                else
                    echo "Container restart via systemd failed"
                    restart_result=1
                fi
            elif docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
                if docker restart "$container_name"; then
                    echo "Container restart via docker successful"
                    restart_result=0
                else
                    echo "Container restart via docker failed"
                    restart_result=1
                fi
            else
                echo "No active Jenkins service or container found for team $team"
                restart_result=1
            fi
        fi
        
        if [[ $restart_result -eq 0 ]]; then
            echo "=== Jenkins Restart Completed Successfully ==="
        else
            echo "=== Jenkins Restart Failed ==="
        fi
        
        local duration=$(($(date +%s) - start_time))
        echo "Duration: ${duration}s"
        echo "End Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
    } >> "$AUTOMATION_LOG"
    
    release_automation_lock "restart" "$team"
    
    # Send notification
    send_notification "$team" "restart" "$restart_result" "$reason"
    
    return $restart_result
}

# Notification system integration
send_notification() {
    local team="$1"
    local action="$2"
    local result="$3"
    local reason="${4:-automated_action}"
    
    local notification_config
    notification_config=$(jq -r '.integration_settings.external_tools' "$INTEGRATION_CONFIG" 2>/dev/null || echo '{}')
    
    local status_text
    if [[ $result -eq 0 ]]; then
        status_text="SUCCESS"
    else
        status_text="FAILED"
    fi
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local message="Health Engine Action: $action for team $team - $status_text (Reason: $reason) at $timestamp"
    
    # Slack notification
    local slack_enabled
    slack_enabled=$(echo "$notification_config" | jq -r '.slack.enabled // false')
    if [[ "$slack_enabled" == "true" ]]; then
        local webhook_url
        webhook_url=$(echo "$notification_config" | jq -r '.slack.webhook_url // ""')
        local channel
        channel=$(echo "$notification_config" | jq -r --arg team "$team" '.slack.channel_mapping[$team] // "#jenkins-alerts"')
        
        if [[ -n "$webhook_url" ]]; then
            local slack_payload
            slack_payload=$(jq -n \
                --arg channel "$channel" \
                --arg message "$message" \
                --arg status "$status_text" \
                '{
                    channel: $channel,
                    text: $message,
                    username: "Health Engine Bot",
                    icon_emoji: ":jenkins:",
                    attachments: [
                        {
                            color: (if $status == "SUCCESS" then "good" else "danger" end),
                            fields: [
                                {title: "Team", value: $ARGS.positional[0], short: true},
                                {title: "Action", value: $ARGS.positional[1], short: true},
                                {title: "Status", value: $status, short: true},
                                {title: "Reason", value: $ARGS.positional[3], short: true}
                            ]
                        }
                    ]
                }' --args "$team" "$action" "$result" "$reason")
            
            curl -s -X POST -H "Content-Type: application/json" \
                -d "$slack_payload" "$webhook_url" >/dev/null || true
        fi
    fi
    
    # PagerDuty notification for critical events
    local pagerduty_enabled
    pagerduty_enabled=$(echo "$notification_config" | jq -r '.pagerduty.enabled // false')
    if [[ "$pagerduty_enabled" == "true" && $result -ne 0 ]]; then
        local integration_key
        integration_key=$(echo "$notification_config" | jq -r '.pagerduty.integration_key // ""')
        
        if [[ -n "$integration_key" ]]; then
            local pagerduty_payload
            pagerduty_payload=$(jq -n \
                --arg key "$integration_key" \
                --arg summary "Jenkins Health Engine: $action failed for team $team" \
                --arg source "health-engine" \
                --arg severity "error" \
                --arg team "$team" \
                --arg action "$action" \
                --arg reason "$reason" \
                '{
                    routing_key: $key,
                    event_action: "trigger",
                    payload: {
                        summary: $summary,
                        source: $source,
                        severity: $severity,
                        custom_details: {
                            team: $team,
                            action: $action,
                            reason: $reason,
                            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
                        }
                    }
                }')
            
            curl -s -X POST -H "Content-Type: application/json" \
                -d "$pagerduty_payload" "https://events.pagerduty.com/v2/enqueue" >/dev/null || true
        fi
    fi
}

# Prometheus metrics integration
push_health_metrics() {
    local assessment_data="$1"
    local config="$2"
    
    local push_gateway_url
    push_gateway_url=$(echo "$config" | jq -r '.integration_settings.prometheus.push_gateway_url // ""')
    
    if [[ -z "$push_gateway_url" ]]; then
        log_debug "No Prometheus push gateway configured"
        return 0
    fi
    
    log_debug "Pushing health metrics to Prometheus push gateway"
    
    # Generate metrics in Prometheus format
    local metrics_data
    metrics_data=$(echo "$assessment_data" | jq -r '
        .assessments[] | 
        "jenkins_health_engine_score{team=\"\(.team)\",status=\"\(.status)\",tier=\"\(.tier // "unknown")\",environment=\"\(.environment // "unknown")\"} \(.score)\n" +
        "jenkins_health_engine_assessment_timestamp{team=\"\(.team)\"} \(.timestamp | fromdate)\n" +
        "jenkins_health_engine_metrics_score{team=\"\(.team)\"} \(.metrics.score // 0)\n" +
        "jenkins_health_engine_logs_score{team=\"\(.team)\"} \(.logs.score // 0)\n" +
        "jenkins_health_engine_health_checks_score{team=\"\(.team)\"} \(.health.health_score // 0)\n" +
        (if .circuit_breaker then "jenkins_health_engine_circuit_breaker_status{team=\"\(.team)\"} \(if .circuit_breaker.status == "open" then 1 else 0 end)\n" else "" end) +
        (if .trends then "jenkins_health_engine_trend_confidence{team=\"\(.team)\",trend=\"\(.trends.trend)\"} \(.trends.confidence)\n" else "" end)
    ')
    
    # Push metrics to gateway
    local job_name="health_engine"
    local instance_name="$(hostname)"
    
    echo "$metrics_data" | curl -s --data-binary @- \
        "${push_gateway_url}/metrics/job/${job_name}/instance/${instance_name}" >/dev/null || {
        log_warn "Failed to push metrics to Prometheus push gateway"
    }
}

# Grafana dashboard annotation
create_grafana_annotation() {
    local team="$1"
    local event="$2"
    local description="$3"
    local tags="${4:-health-engine,automation}"
    
    local grafana_url
    grafana_url=$(jq -r '.global.grafana_url // "http://localhost:9300"' "$INTEGRATION_CONFIG" 2>/dev/null)
    
    if [[ -z "$grafana_url" ]]; then
        log_debug "No Grafana URL configured for annotations"
        return 0
    fi
    
    local annotation_payload
    annotation_payload=$(jq -n \
        --arg text "$description" \
        --arg tags "$tags" \
        --arg team "$team" \
        --arg event "$event" \
        '{
            text: $text,
            tags: ($tags | split(",")),
            time: (now * 1000 | floor),
            timeEnd: (now * 1000 | floor)
        }')
    
    curl -s -X POST -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${GRAFANA_API_TOKEN:-}" \
        -d "$annotation_payload" \
        "${grafana_url}/api/annotations" >/dev/null || {
        log_debug "Failed to create Grafana annotation"
    }
}

# Main automation orchestrator
orchestrate_auto_healing() {
    local team="$1"
    local assessment="$2"
    local config="$3"
    
    local status=$(echo "$assessment" | jq -r '.status')
    local score=$(echo "$assessment" | jq -r '.score')
    local team_config=$(echo "$config" | jq -r ".teams.${team}")
    local auto_healing_config=$(echo "$team_config" | jq -r '.auto_healing')
    local enabled=$(echo "$auto_healing_config" | jq -r '.enabled // false')
    
    if [[ "$enabled" != "true" ]]; then
        log_debug "Auto-healing disabled for team $team"
        return 0
    fi
    
    # Check if team status requires intervention
    if [[ "$status" != "critical" && "$status" != "failed" ]]; then
        log_debug "Team $team status ($status) does not require auto-healing"
        return 0
    fi
    
    # Check flapping detection
    local flapping_info
    flapping_info=$(detect_flapping "$team" "$status" "$config")
    local is_flapping=$(echo "$flapping_info" | jq -r '.flapping')
    local is_suppressed=$(echo "$flapping_info" | jq -r '.suppressed')
    
    if [[ "$is_flapping" == "true" ]]; then
        if [[ "$is_suppressed" == "true" ]]; then
            log_warn "Auto-healing suppressed for team $team due to flapping detection"
            return 0
        else
            log_warn "Flapping detected for team $team but proceeding with auto-healing"
        fi
    fi
    
    # Check safety constraints
    local safety_checks=$(echo "$auto_healing_config" | jq -r '.safety_checks // {}')
    local max_restarts_per_hour=$(echo "$safety_checks" | jq -r '.max_restarts_per_hour // 3')
    local business_hours_only=$(echo "$safety_checks" | jq -r '.business_hours_only // false')
    
    # Business hours check
    if [[ "$business_hours_only" == "true" ]]; then
        local current_hour=$(date +%H)
        local current_day=$(date +%u)  # 1=Monday, 7=Sunday
        
        if (( current_day > 5 || current_hour < 8 || current_hour > 18 )); then
            log_warn "Auto-healing skipped for team $team (outside business hours)"
            return 0
        fi
    fi
    
    # Check recent restart attempts
    local recent_restarts=0
    if [[ -f "$HEALTH_ENGINE_STATE" ]]; then
        local one_hour_ago=$(date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%SZ)
        recent_restarts=$(cat "$HEALTH_ENGINE_STATE" | jq --arg team "$team" --arg cutoff "$one_hour_ago" '
            .auto_healing_attempts[$team] // [] |
            map(select(.timestamp > $cutoff and (.actions | contains("restart")))) |
            length
        ')
    fi
    
    if (( recent_restarts >= max_restarts_per_hour )); then
        log_warn "Auto-healing rate limit exceeded for team $team ($recent_restarts/$max_restarts_per_hour per hour)"
        return 0
    fi
    
    # Execute auto-healing actions
    local actions=$(echo "$auto_healing_config" | jq -r '.actions[]')
    local escalation_config=$(echo "$auto_healing_config" | jq -r '.escalation // {}')
    local escalation_levels=$(echo "$escalation_config" | jq -r '.levels[]' 2>/dev/null || echo "$actions")
    
    log_info "Starting auto-healing orchestration for team $team (status: $status, score: $score)"
    
    # Create Grafana annotation
    create_grafana_annotation "$team" "auto_healing_started" \
        "Auto-healing started for team $team due to $status status (score: $score)" \
        "health-engine,auto-healing,$team"
    
    local healing_success=false
    
    for action in $escalation_levels; do
        log_info "Executing auto-healing action: $action for team $team"
        
        local action_result=0
        case "$action" in
            "restart")
                trigger_jenkins_restart "$team" "graceful" "auto_healing_orchestrated" || action_result=$?
                ;;
            "switch_environment")
                trigger_blue_green_switch "$team" "auto_healing_orchestrated" "false" || action_result=$?
                ;;
            "scale_up")
                log_warn "Scale up action not implemented yet for team $team"
                action_result=1
                ;;
            "manual_intervention")
                log_warn "Manual intervention required for team $team"
                send_notification "$team" "manual_intervention_required" 1 "auto_healing_escalation"
                action_result=1
                ;;
            *)
                log_error "Unknown auto-healing action: $action"
                action_result=1
                ;;
        esac
        
        # Create action annotation
        create_grafana_annotation "$team" "auto_healing_action" \
            "Auto-healing action $action executed for team $team (result: $([[ $action_result -eq 0 ]] && echo "success" || echo "failed"))" \
            "health-engine,auto-healing,$team,$action"
        
        if [[ $action_result -eq 0 ]]; then
            log_success "Auto-healing action $action completed successfully for team $team"
            healing_success=true
            break
        else
            log_error "Auto-healing action $action failed for team $team"
            
            # Check if we should continue to next escalation level
            local escalation_time=$(echo "$escalation_config" | jq -r '.escalation_time // "10m"')
            case "$escalation_time" in
                *m) sleep_time=$((${escalation_time%m} * 60)) ;;
                *s) sleep_time=${escalation_time%s} ;;
                *) sleep_time=600 ;;  # Default 10 minutes
            esac
            
            log_info "Waiting ${escalation_time} before next escalation level..."
            sleep $sleep_time
        fi
    done
    
    # Final notification
    if [[ "$healing_success" == "true" ]]; then
        log_success "Auto-healing completed successfully for team $team"
        create_grafana_annotation "$team" "auto_healing_completed" \
            "Auto-healing completed successfully for team $team" \
            "health-engine,auto-healing,$team,success"
    else
        log_error "Auto-healing failed for team $team - manual intervention may be required"
        create_grafana_annotation "$team" "auto_healing_failed" \
            "Auto-healing failed for team $team - manual intervention required" \
            "health-engine,auto-healing,$team,failed"
        send_notification "$team" "auto_healing_failed" 1 "all_escalation_levels_failed"
    fi
    
    return $([[ "$healing_success" == "true" ]] && echo 0 || echo 1)
}

# Main integration function
main() {
    local command="${1:-assess_and_heal}"
    shift || true
    
    case "$command" in
        "assess_and_heal")
            local teams="${1:-all}"
            
            log_info "Running health assessment and auto-healing for teams: $teams"
            
            # Run health engine assessment
            local assessment_result
            if ! assessment_result=$("$HEALTH_ENGINE_SCRIPT" assess "$teams" json); then
                log_error "Health engine assessment failed"
                return 1
            fi
            
            # Push metrics to Prometheus
            push_health_metrics "$assessment_result" "$(cat "$INTEGRATION_CONFIG")"
            
            # Process each team assessment
            local critical_teams
            critical_teams=$(echo "$assessment_result" | jq -r '.assessments[] | select(.status == "critical" or .status == "failed") | .team')
            
            if [[ -n "$critical_teams" ]]; then
                local config
                config=$(cat "$INTEGRATION_CONFIG")
                
                for team in $critical_teams; do
                    local team_assessment
                    team_assessment=$(echo "$assessment_result" | jq --arg team "$team" '.assessments[] | select(.team == $team)')
                    
                    # Orchestrate auto-healing
                    orchestrate_auto_healing "$team" "$team_assessment" "$config"
                done
            else
                log_info "No teams require auto-healing intervention"
            fi
            ;;
        "blue_green_switch")
            local team="${1:-}"
            local reason="${2:-manual_trigger}"
            local force="${3:-false}"
            
            if [[ -z "$team" ]]; then
                log_error "Team name required for blue-green switch"
                return 1
            fi
            
            trigger_blue_green_switch "$team" "$reason" "$force"
            ;;
        "restart")
            local team="${1:-}"
            local restart_type="${2:-graceful}"
            local reason="${3:-manual_trigger}"
            
            if [[ -z "$team" ]]; then
                log_error "Team name required for restart"
                return 1
            fi
            
            trigger_jenkins_restart "$team" "$restart_type" "$reason"
            ;;
        "test_notifications")
            local team="${1:-devops}"
            send_notification "$team" "test" 0 "notification_test"
            log_info "Test notification sent for team $team"
            ;;
        "cleanup_locks")
            cleanup_locks
            log_info "Automation locks cleaned up"
            ;;
        *)
            echo "Usage: $0 {assess_and_heal|blue_green_switch|restart|test_notifications|cleanup_locks}"
            echo ""
            echo "Commands:"
            echo "  assess_and_heal [teams]           - Run assessment and auto-healing"
            echo "  blue_green_switch <team> [reason] [force] - Trigger blue-green switch"
            echo "  restart <team> [type] [reason]    - Trigger Jenkins restart"
            echo "  test_notifications [team]         - Test notification systems"
            echo "  cleanup_locks                     - Clean up automation locks"
            return 1
            ;;
    esac
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi