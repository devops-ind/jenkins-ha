#!/bin/bash
# Comprehensive Security Scanner for Jenkins HA Infrastructure
# Integrates multiple security tools for complete vulnerability assessment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPORT_DIR="$PROJECT_ROOT/security-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# Tool configuration
TOOLS=(
    "trufflehog:Secret Detection"
    "checkov:Infrastructure Security"
    "semgrep:SAST Scanning"
    "bandit:Python Security"
    "safety:Python Dependencies"
    "trivy:Container Security"
    "dependency-check.sh:OWASP Dependencies"
)

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Comprehensive Security Scanner for Jenkins HA Infrastructure

OPTIONS:
    --tools TOOLS          Comma-separated list of tools to run (default: all)
    --output-format FORMAT Output format: json, sarif, html, text (default: text)
    --fail-on-high        Fail on high severity vulnerabilities (default: true)
    --report-dir DIR      Directory for reports (default: security-reports)
    --exclude-dirs DIRS   Comma-separated directories to exclude
    --help                Show this help message

AVAILABLE TOOLS:
    trufflehog           - Secret detection and credential scanning
    checkov              - Infrastructure as code security
    semgrep              - Static application security testing
    bandit               - Python security linting
    safety               - Python dependency vulnerability checking
    trivy                - Container and filesystem vulnerability scanning
    dependency-check     - OWASP dependency vulnerability checking

EXAMPLES:
    $0                                    # Run all security tools
    $0 --tools trufflehog,semgrep         # Run specific tools only
    $0 --output-format json --report-dir /tmp/reports
    $0 --fail-on-high false               # Don't fail on high severity issues

EOF
}

# Initialize variables
SELECTED_TOOLS=""
OUTPUT_FORMAT="text"
FAIL_ON_HIGH=true
EXCLUDE_DIRS=".git,node_modules,.venv,__pycache__"
SCAN_RESULTS=()

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tools)
                SELECTED_TOOLS="$2"
                shift 2
                ;;
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --fail-on-high)
                FAIL_ON_HIGH="$2"
                shift 2
                ;;
            --report-dir)
                REPORT_DIR="$2"
                shift 2
                ;;
            --exclude-dirs)
                EXCLUDE_DIRS="$2"
                shift 2
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

# Setup report directory
setup_reports() {
    mkdir -p "$REPORT_DIR"
    info "Security reports will be saved to: $REPORT_DIR"
}

# Check tool availability
check_tool_available() {
    local tool="$1"
    if command -v "$tool" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Install Python tools if needed
install_python_tools() {
    local tools=("semgrep" "checkov" "bandit" "safety")
    for tool in "${tools[@]}"; do
        if ! check_tool_available "$tool"; then
            info "Installing $tool..."
            pip install "$tool" || warn "Failed to install $tool"
        fi
    done
}

# Run TruffleHog secret detection
run_trufflehog() {
    log "Running TruffleHog secret detection..."
    local output_file="$REPORT_DIR/trufflehog-${TIMESTAMP}"
    local exit_code=0
    
    if ! check_tool_available "trufflehog"; then
        warn "TruffleHog not installed. Install: curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh"
        return 1
    fi
    
    case "$OUTPUT_FORMAT" in
        "json")
            trufflehog filesystem "$PROJECT_ROOT" \
                --only-verified \
                --json > "${output_file}.json" || exit_code=$?
            ;;
        *)
            trufflehog filesystem "$PROJECT_ROOT" \
                --only-verified > "${output_file}.txt" || exit_code=$?
            ;;
    esac
    
    if [[ $exit_code -eq 0 ]]; then
        success "TruffleHog: No secrets detected"
        SCAN_RESULTS+=("trufflehog:PASS:No secrets detected")
    else
        error "TruffleHog: Secrets detected!"
        SCAN_RESULTS+=("trufflehog:FAIL:Secrets detected")
    fi
    
    return $exit_code
}

# Run Checkov infrastructure security
run_checkov() {
    log "Running Checkov infrastructure security scan..."
    local output_file="$REPORT_DIR/checkov-${TIMESTAMP}"
    local exit_code=0
    
    if ! check_tool_available "checkov"; then
        pip install checkov || { warn "Failed to install Checkov"; return 1; }
    fi
    
    case "$OUTPUT_FORMAT" in
        "json")
            checkov --directory "$PROJECT_ROOT" \
                --framework dockerfile,ansible,yaml_templates \
                --skip-check CKV_DOCKER_2,CKV_DOCKER_3 \
                --output json \
                --output-file-path "${output_file}.json" || exit_code=$?
            ;;
        "sarif")
            checkov --directory "$PROJECT_ROOT" \
                --framework dockerfile,ansible,yaml_templates \
                --skip-check CKV_DOCKER_2,CKV_DOCKER_3 \
                --output sarif \
                --output-file-path "${output_file}.sarif" || exit_code=$?
            ;;
        *)
            checkov --directory "$PROJECT_ROOT" \
                --framework dockerfile,ansible,yaml_templates \
                --skip-check CKV_DOCKER_2,CKV_DOCKER_3 > "${output_file}.txt" || exit_code=$?
            ;;
    esac
    
    if [[ $exit_code -eq 0 ]]; then
        success "Checkov: Infrastructure security passed"
        SCAN_RESULTS+=("checkov:PASS:Infrastructure security passed")
    else
        error "Checkov: Infrastructure security issues found"
        SCAN_RESULTS+=("checkov:FAIL:Security issues found")
    fi
    
    return $exit_code
}

# Run Semgrep SAST
run_semgrep() {
    log "Running Semgrep SAST scan..."
    local output_file="$REPORT_DIR/semgrep-${TIMESTAMP}"
    local exit_code=0
    
    if ! check_tool_available "semgrep"; then
        pip install semgrep || { warn "Failed to install Semgrep"; return 1; }
    fi
    
    case "$OUTPUT_FORMAT" in
        "json")
            semgrep --config=auto \
                --json \
                --output="${output_file}.json" \
                "$PROJECT_ROOT" || exit_code=$?
            ;;
        "sarif")
            semgrep --config=auto \
                --sarif \
                --output="${output_file}.sarif" \
                "$PROJECT_ROOT" || exit_code=$?
            ;;
        *)
            semgrep --config=auto \
                "$PROJECT_ROOT" > "${output_file}.txt" || exit_code=$?
            ;;
    esac
    
    if [[ $exit_code -eq 0 ]]; then
        success "Semgrep: SAST scan passed"
        SCAN_RESULTS+=("semgrep:PASS:SAST scan passed")
    else
        error "Semgrep: SAST issues found"
        SCAN_RESULTS+=("semgrep:FAIL:SAST issues found")
    fi
    
    return $exit_code
}

# Run Bandit Python security
run_bandit() {
    log "Running Bandit Python security scan..."
    local output_file="$REPORT_DIR/bandit-${TIMESTAMP}"
    local exit_code=0
    
    if ! check_tool_available "bandit"; then
        pip install bandit || { warn "Failed to install Bandit"; return 1; }
    fi
    
    # Find Python files
    local python_files
    python_files=$(find "$PROJECT_ROOT" -name "*.py" -type f | grep -v -E "(__pycache__|\.venv|\.git)" | head -20)
    
    if [[ -z "$python_files" ]]; then
        info "No Python files found for Bandit scan"
        SCAN_RESULTS+=("bandit:SKIP:No Python files found")
        return 0
    fi
    
    case "$OUTPUT_FORMAT" in
        "json")
            echo "$python_files" | xargs bandit -f json -o "${output_file}.json" || exit_code=$?
            ;;
        *)
            echo "$python_files" | xargs bandit > "${output_file}.txt" || exit_code=$?
            ;;
    esac
    
    if [[ $exit_code -eq 0 ]]; then
        success "Bandit: Python security passed"
        SCAN_RESULTS+=("bandit:PASS:Python security passed")
    else
        error "Bandit: Python security issues found"
        SCAN_RESULTS+=("bandit:FAIL:Security issues found")
    fi
    
    return $exit_code
}

# Run Safety Python dependency check
run_safety() {
    log "Running Safety Python dependency check..."
    local output_file="$REPORT_DIR/safety-${TIMESTAMP}"
    local exit_code=0
    
    if ! check_tool_available "safety"; then
        pip install safety || { warn "Failed to install Safety"; return 1; }
    fi
    
    if [[ ! -f "$PROJECT_ROOT/requirements.txt" ]]; then
        info "No requirements.txt found for Safety scan"
        SCAN_RESULTS+=("safety:SKIP:No requirements.txt found")
        return 0
    fi
    
    case "$OUTPUT_FORMAT" in
        "json")
            safety check --json --file="$PROJECT_ROOT/requirements.txt" > "${output_file}.json" || exit_code=$?
            ;;
        *)
            safety check --file="$PROJECT_ROOT/requirements.txt" > "${output_file}.txt" || exit_code=$?
            ;;
    esac
    
    if [[ $exit_code -eq 0 ]]; then
        success "Safety: Python dependencies secure"
        SCAN_RESULTS+=("safety:PASS:Dependencies secure")
    else
        error "Safety: Vulnerable Python dependencies found"
        SCAN_RESULTS+=("safety:FAIL:Vulnerable dependencies found")
    fi
    
    return $exit_code
}

# Run Trivy container security
run_trivy() {
    log "Running Trivy container security scan..."
    local output_file="$REPORT_DIR/trivy-${TIMESTAMP}"
    local exit_code=0
    
    if ! check_tool_available "trivy"; then
        warn "Trivy not installed. Install via package manager or: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh"
        SCAN_RESULTS+=("trivy:SKIP:Trivy not installed")
        return 1
    fi
    
    case "$OUTPUT_FORMAT" in
        "json")
            trivy fs --format json --output "${output_file}.json" "$PROJECT_ROOT" || exit_code=$?
            ;;
        *)
            trivy fs "$PROJECT_ROOT" > "${output_file}.txt" || exit_code=$?
            ;;
    esac
    
    if [[ $exit_code -eq 0 ]]; then
        success "Trivy: Filesystem scan passed"
        SCAN_RESULTS+=("trivy:PASS:Filesystem scan passed")
    else
        error "Trivy: Vulnerabilities found in filesystem"
        SCAN_RESULTS+=("trivy:FAIL:Vulnerabilities found")
    fi
    
    return $exit_code
}

# Run OWASP Dependency Check
run_dependency_check() {
    log "Running OWASP Dependency Check..."
    local output_file="$REPORT_DIR/dependency-check-${TIMESTAMP}"
    local exit_code=0
    
    if ! check_tool_available "dependency-check.sh"; then
        warn "OWASP Dependency-Check not installed. Install from: https://owasp.org/www-project-dependency-check/"
        SCAN_RESULTS+=("dependency-check:SKIP:Tool not installed")
        return 1
    fi
    
    dependency-check.sh \
        --project "Jenkins-HA-Infrastructure" \
        --scan "$PROJECT_ROOT" \
        --format JSON \
        --format HTML \
        --out "$output_file" \
        --failOnCVSS 7 \
        --exclude "**/*.git/**" \
        --exclude "**/node_modules/**" \
        --exclude "**/.venv/**" || exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        success "OWASP Dependency-Check: No critical vulnerabilities"
        SCAN_RESULTS+=("dependency-check:PASS:No critical vulnerabilities")
    else
        error "OWASP Dependency-Check: Critical vulnerabilities found"
        SCAN_RESULTS+=("dependency-check:FAIL:Critical vulnerabilities found")
    fi
    
    return $exit_code
}

# Generate summary report
generate_summary() {
    local summary_file="$REPORT_DIR/security-summary-${TIMESTAMP}.txt"
    
    {
        echo "=============================================="
        echo "Security Scan Summary Report"
        echo "=============================================="
        echo "Timestamp: $(date)"
        echo "Project: Jenkins HA Infrastructure"
        echo "Scan Directory: $PROJECT_ROOT"
        echo "Report Directory: $REPORT_DIR"
        echo ""
        echo "Tool Results:"
        echo "=============================================="
        
        local total_tools=0
        local passed_tools=0
        local failed_tools=0
        local skipped_tools=0
        
        for result in "${SCAN_RESULTS[@]}"; do
            IFS=':' read -r tool status message <<< "$result"
            total_tools=$((total_tools + 1))
            
            case "$status" in
                "PASS")
                    echo "✅ $tool: $message"
                    passed_tools=$((passed_tools + 1))
                    ;;
                "FAIL")
                    echo "❌ $tool: $message"
                    failed_tools=$((failed_tools + 1))
                    ;;
                "SKIP")
                    echo "⏭️  $tool: $message"
                    skipped_tools=$((skipped_tools + 1))
                    ;;
            esac
        done
        
        echo ""
        echo "Summary Statistics:"
        echo "=============================================="
        echo "Total Tools: $total_tools"
        echo "Passed: $passed_tools"
        echo "Failed: $failed_tools"
        echo "Skipped: $skipped_tools"
        echo ""
        
        if [[ $failed_tools -gt 0 ]]; then
            echo "🚨 OVERALL RESULT: SECURITY ISSUES FOUND"
            echo "Action required: Review failed scans and remediate issues"
        elif [[ $passed_tools -eq $total_tools ]]; then
            echo "✅ OVERALL RESULT: ALL SECURITY SCANS PASSED"
        else
            echo "⚠️  OVERALL RESULT: SCAN INCOMPLETE"
            echo "Some tools were skipped - install missing tools for complete coverage"
        fi
        
        echo ""
        echo "Detailed reports available in: $REPORT_DIR"
        echo "=============================================="
    } | tee "$summary_file"
}

# Main execution function
main() {
    parse_args "$@"
    
    log "Starting comprehensive security scan..."
    setup_reports
    install_python_tools
    
    # Determine which tools to run
    local tools_to_run=()
    if [[ -n "$SELECTED_TOOLS" ]]; then
        IFS=',' read -ra tools_to_run <<< "$SELECTED_TOOLS"
    else
        tools_to_run=("trufflehog" "checkov" "semgrep" "bandit" "safety" "trivy" "dependency-check")
    fi
    
    # Run selected security tools
    local overall_exit_code=0
    for tool in "${tools_to_run[@]}"; do
        case "$tool" in
            "trufflehog")
                run_trufflehog || overall_exit_code=1
                ;;
            "checkov")
                run_checkov || overall_exit_code=1
                ;;
            "semgrep")
                run_semgrep || overall_exit_code=1
                ;;
            "bandit")
                run_bandit || overall_exit_code=1
                ;;
            "safety")
                run_safety || overall_exit_code=1
                ;;
            "trivy")
                run_trivy || overall_exit_code=1
                ;;
            "dependency-check")
                run_dependency_check || overall_exit_code=1
                ;;
            *)
                warn "Unknown tool: $tool"
                ;;
        esac
    done
    
    # Generate summary
    generate_summary
    
    # Exit with appropriate code
    if [[ "$FAIL_ON_HIGH" == "true" && $overall_exit_code -ne 0 ]]; then
        error "Security scan failed - critical issues found"
        exit 1
    else
        success "Security scan completed - check reports for details"
        exit 0
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi