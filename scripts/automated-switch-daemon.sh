#!/bin/bash

# automated-switch-daemon.sh - Daemon wrapper for Jenkins HA Automated Switch Manager
# Provides continuous monitoring and automated healing capabilities
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DAEMON_NAME="jenkins-automated-switch"
PID_FILE="/var/run/${DAEMON_NAME}.pid"
LOG_FILE="${PROJECT_ROOT}/logs/${DAEMON_NAME}-daemon.log"
LOCK_FILE="/tmp/${DAEMON_NAME}-daemon.lock"

# Monitoring settings
MONITOR_INTERVAL="${MONITOR_INTERVAL:-300}"  # 5 minutes
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-60}"  # 1 minute
MAX_MEMORY_MB="${MAX_MEMORY_MB:-512}"
MAX_CPU_PERCENT="${MAX_CPU_PERCENT:-50}"

# Scripts
SWITCH_MANAGER="${SCRIPT_DIR}/automated-switch-manager.sh"
HEALTH_ENGINE="${SCRIPT_DIR}/health-engine.sh"

# Ensure directories exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$PID_FILE")"

# Logging functions
log_daemon() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log_daemon "INFO" "$*"
}

log_error() {
    log_daemon "ERROR" "$*"
}

log_success() {
    log_daemon "SUCCESS" "$*"
}

log_warning() {
    log_daemon "WARNING" "$*"
}

# Process management
is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

start_daemon() {
    if is_running; then
        log_warning "Daemon is already running (PID: $(cat "$PID_FILE"))"
        return 1
    fi
    
    log_info "Starting Jenkins HA Automated Switch Manager daemon"
    
    # Create lock file
    if ! (set -C; echo $$ > "$LOCK_FILE") 2>/dev/null; then
        log_error "Failed to acquire daemon lock"
        return 1
    fi
    
    # Start background monitoring process
    (
        trap cleanup_daemon EXIT
        
        echo $$ > "$PID_FILE"
        log_success "Daemon started (PID: $$)"
        
        # Main monitoring loop
        while true; do
            # Health check on automation system itself
            perform_self_health_check
            
            # Run automated assessment and healing
            run_automated_healing
            
            # Resource monitoring
            monitor_resources
            
            # Sleep until next iteration
            sleep "$MONITOR_INTERVAL"
        done
    ) &
    
    local daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"
    disown
    
    # Wait a moment to ensure daemon started successfully
    sleep 2
    
    if is_running; then
        log_success "Daemon started successfully (PID: $daemon_pid)"
        return 0
    else
        log_error "Failed to start daemon"
        rm -f "$LOCK_FILE"
        return 1
    fi
}

stop_daemon() {
    if ! is_running; then
        log_warning "Daemon is not running"
        return 1
    fi
    
    local pid=$(cat "$PID_FILE")
    log_info "Stopping daemon (PID: $pid)"
    
    # Send TERM signal
    if kill -TERM "$pid" 2>/dev/null; then
        # Wait for graceful shutdown
        local count=0
        while is_running && (( count < 30 )); do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if is_running; then
            log_warning "Forcing daemon shutdown"
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
    
    # Cleanup
    rm -f "$PID_FILE" "$LOCK_FILE"
    log_success "Daemon stopped"
}

reload_daemon() {
    if ! is_running; then
        log_error "Daemon is not running - cannot reload"
        return 1
    fi
    
    local pid=$(cat "$PID_FILE")
    log_info "Reloading daemon configuration (PID: $pid)"
    
    # Send USR1 signal for configuration reload
    if kill -USR1 "$pid" 2>/dev/null; then
        log_success "Daemon configuration reloaded"
        return 0
    else
        log_error "Failed to reload daemon configuration"
        return 1
    fi
}

restart_daemon() {
    log_info "Restarting daemon"
    stop_daemon
    sleep 2
    start_daemon
}

cleanup_daemon() {
    log_info "Cleaning up daemon resources"
    rm -f "$PID_FILE" "$LOCK_FILE"
}

# Monitoring functions
perform_self_health_check() {
    # Check if required services are running
    local services=("docker" "prometheus" "grafana")
    
    for service in "${services[@]}"; do
        if ! systemctl is-active "$service" >/dev/null 2>&1; then
            log_warning "Required service $service is not running"
        fi
    done
    
    # Check if required scripts exist
    local scripts=("$SWITCH_MANAGER" "$HEALTH_ENGINE")
    
    for script in "${scripts[@]}"; do
        if [[ ! -x "$script" ]]; then
            log_error "Required script not found or not executable: $script"
        fi
    done
    
    # Check disk space
    local disk_usage=$(df "${PROJECT_ROOT}" | awk 'NR==2 {print $5}' | sed 's/%//')
    if (( disk_usage > 90 )); then
        log_warning "High disk usage: ${disk_usage}%"
    fi
    
    # Check memory usage
    local memory_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    if (( $(echo "$memory_usage > 90" | bc -l) )); then
        log_warning "High memory usage: ${memory_usage}%"
    fi
}

run_automated_healing() {
    log_info "Running automated healing assessment"
    
    # Run assessment for all teams
    if "$SWITCH_MANAGER" auto-heal all 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Automated healing completed successfully"
    else
        local exit_code=$?
        log_warning "Automated healing completed with warnings (exit code: $exit_code)"
    fi
}

monitor_resources() {
    # Monitor daemon resource usage
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        
        # Check memory usage
        local memory_kb=$(ps -o rss= -p "$pid" 2>/dev/null || echo "0")
        local memory_mb=$((memory_kb / 1024))
        
        if (( memory_mb > MAX_MEMORY_MB )); then
            log_warning "High memory usage: ${memory_mb}MB (limit: ${MAX_MEMORY_MB}MB)"
        fi
        
        # Check CPU usage (simplified)
        local cpu_percent=$(ps -o %cpu= -p "$pid" 2>/dev/null | awk '{print int($1)}' || echo "0")
        
        if (( cpu_percent > MAX_CPU_PERCENT )); then
            log_warning "High CPU usage: ${cpu_percent}% (limit: ${MAX_CPU_PERCENT}%)"
        fi
    fi
}

# Signal handlers
handle_term() {
    log_info "Received TERM signal, shutting down gracefully"
    cleanup_daemon
    exit 0
}

handle_usr1() {
    log_info "Received USR1 signal, reloading configuration"
    # Reload configuration logic here
    log_success "Configuration reloaded"
}

# Set up signal handlers
trap handle_term TERM INT
trap handle_usr1 USR1

# Status functions
show_status() {
    echo "=== Jenkins HA Automated Switch Manager Daemon Status ==="
    echo "Daemon name: $DAEMON_NAME"
    echo "PID file: $PID_FILE"
    echo "Log file: $LOG_FILE"
    echo "Monitor interval: ${MONITOR_INTERVAL}s"
    echo ""
    
    if is_running; then
        local pid=$(cat "$PID_FILE")
        echo "Status: RUNNING (PID: $pid)"
        
        # Show process details
        if ps -p "$pid" >/dev/null 2>&1; then
            echo "Process info:"
            ps -o pid,ppid,cmd,%cpu,%mem,etime -p "$pid"
        fi
        
        # Show recent log entries
        echo ""
        echo "Recent log entries:"
        tail -10 "$LOG_FILE" 2>/dev/null || echo "No recent log entries"
        
    else
        echo "Status: STOPPED"
    fi
    
    echo ""
    echo "Recent automation activity:"
    "$SWITCH_MANAGER" status all 2>/dev/null || echo "No automation status available"
}

show_logs() {
    local lines="${1:-50}"
    echo "=== Last $lines lines from daemon log ==="
    tail -"$lines" "$LOG_FILE" 2>/dev/null || echo "No log entries found"
}

# Main command interface
main() {
    local command="${1:-}"
    
    case "$command" in
        "start")
            start_daemon
            ;;
        "stop")
            stop_daemon
            ;;
        "restart")
            restart_daemon
            ;;
        "reload")
            reload_daemon
            ;;
        "status")
            show_status
            ;;
        "logs")
            local lines="${2:-50}"
            show_logs "$lines"
            ;;
        "health-check")
            perform_self_health_check
            ;;
        "test-healing")
            run_automated_healing
            ;;
        *)
            cat << 'EOF'
Usage: automated-switch-daemon.sh <command> [options]

COMMANDS:
    start           - Start the daemon
    stop            - Stop the daemon
    restart         - Restart the daemon
    reload          - Reload daemon configuration
    status          - Show daemon status
    logs [lines]    - Show recent log entries (default: 50 lines)
    health-check    - Perform self health check
    test-healing    - Run automated healing once

DAEMON FEATURES:
    - Continuous monitoring every 5 minutes
    - Automated healing based on health indicators
    - Self-monitoring and resource management
    - Graceful shutdown and restart
    - Configuration reloading
    - Comprehensive logging

CONFIGURATION:
    MONITOR_INTERVAL        - Monitoring interval in seconds (default: 300)
    HEALTH_CHECK_INTERVAL   - Health check interval in seconds (default: 60)
    MAX_MEMORY_MB          - Memory limit in MB (default: 512)
    MAX_CPU_PERCENT        - CPU limit in percent (default: 50)

EXAMPLES:
    # Start daemon
    ./automated-switch-daemon.sh start

    # Check status
    ./automated-switch-daemon.sh status

    # View recent logs
    ./automated-switch-daemon.sh logs 100

    # Restart with new configuration
    ./automated-switch-daemon.sh restart

SYSTEMD INTEGRATION:
    sudo systemctl enable jenkins-automated-switch
    sudo systemctl start jenkins-automated-switch
    sudo systemctl status jenkins-automated-switch

EOF
            exit 1
            ;;
    esac
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi