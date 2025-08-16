#!/bin/bash
# DSL Syntax Validator for Jenkins HA Infrastructure
# Validates Job DSL scripts for syntax and security compliance

set -euo pipefail

# Configuration
GROOVY_TIMEOUT=60
SECURITY_SCAN_TIMEOUT=120
MAX_DSL_FILE_SIZE=1048576  # 1MB
MAX_DSL_COMPLEXITY=1000    # lines

# Colors and formatting
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

# Security patterns to detect
SECURITY_PATTERNS=(
    "System\\.exit"
    "Runtime\\.getRuntime"
    "ProcessBuilder"
    "exec\\("
    "\\$\\{.*\\}"
    "new\\s+File\\("
    "FileInputStream"
    "FileOutputStream"
    "Process\\s*=\\s*"
    "javax\\.script"
    "Unsafe"
    "sun\\.misc"
    "java\\.lang\\.reflect"
    "ClassLoader"
    "URLClassLoader"
    "System\\.getProperty"
    "System\\.setProperty"
    "Environment\\.getEnvironment"
)

# Complexity patterns
COMPLEXITY_PATTERNS=(
    "for\\s*\\("
    "while\\s*\\("
    "if\\s*\\("
    "switch\\s*\\("
    "try\\s*\\{"
    "catch\\s*\\("
    "def\\s+\\w+\\s*\\("
    "class\\s+\\w+"
)

# Display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --dsl-path PATH             Path to DSL files or directory
    --team TEAM                 Team name for context
    --security-check            Enable security compliance check
    --complexity-check          Enable complexity analysis
    --output-format FORMAT      Output format: text, json (default: text)
    --max-file-size BYTES       Maximum DSL file size (default: $MAX_DSL_FILE_SIZE)
    --max-complexity LINES      Maximum complexity threshold (default: $MAX_DSL_COMPLEXITY)
    --exclude-patterns FILE     File with patterns to exclude from validation
    --help                      Show this help

EXAMPLES:
    # Validate DSL syntax only
    $0 --dsl-path /path/to/dsl --team devops
    
    # Full validation with security and complexity checks
    $0 --dsl-path /path/to/dsl --team devops --security-check --complexity-check
    
    # JSON output for automation
    $0 --dsl-path /path/to/dsl --team devops --security-check --output-format json

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dsl-path)
                DSL_PATH="$2"
                shift 2
                ;;
            --team)
                TEAM_NAME="$2"
                shift 2
                ;;
            --security-check)
                SECURITY_CHECK=true
                shift
                ;;
            --complexity-check)
                COMPLEXITY_CHECK=true
                shift
                ;;
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --max-file-size)
                MAX_DSL_FILE_SIZE="$2"
                shift 2
                ;;
            --max-complexity)
                MAX_DSL_COMPLEXITY="$2"
                shift 2
                ;;
            --exclude-patterns)
                EXCLUDE_PATTERNS_FILE="$2"
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
    
    # Validate required parameters
    if [[ -z "${DSL_PATH:-}" ]]; then
        error "DSL path is required"
        usage
        exit 1
    fi
    
    OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"
    TEAM_NAME="${TEAM_NAME:-unknown}"
}

# Validation results tracking
declare -a VALIDATION_RESULTS
declare -a SYNTAX_ERRORS
declare -a SECURITY_VIOLATIONS
declare -a COMPLEXITY_ISSUES

# Add validation result
add_validation_result() {
    local file="$1"
    local check_type="$2"
    local status="$3"
    local message="$4"
    local line_number="${5:-0}"
    
    local result=$(cat <<EOF
{
    "file": "$file",
    "check_type": "$check_type",
    "status": "$status",
    "message": "$message",
    "line_number": $line_number,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    VALIDATION_RESULTS+=("$result")
    
    case "$check_type" in
        "syntax")
            if [[ "$status" == "error" ]]; then
                SYNTAX_ERRORS+=("$file")
            fi
            ;;
        "security")
            if [[ "$status" == "violation" ]]; then
                SECURITY_VIOLATIONS+=("$file")
            fi
            ;;
        "complexity")
            if [[ "$status" == "warning" ]]; then
                COMPLEXITY_ISSUES+=("$file")
            fi
            ;;
    esac
}

# Find DSL files
find_dsl_files() {
    local path="$1"
    
    if [[ -f "$path" ]]; then
        if [[ "$path" == *.groovy ]]; then
            echo "$path"
        fi
    elif [[ -d "$path" ]]; then
        find "$path" -name "*.groovy" -type f
    else
        error "DSL path does not exist: $path"
        return 1
    fi
}

# Validate file size
validate_file_size() {
    local file="$1"
    
    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
    
    if [[ "$file_size" -gt "$MAX_DSL_FILE_SIZE" ]]; then
        add_validation_result "$file" "file_size" "error" "File size ${file_size} exceeds maximum ${MAX_DSL_FILE_SIZE}"
        return 1
    fi
    
    return 0
}

# Validate Groovy syntax
validate_groovy_syntax() {
    local file="$1"
    
    log "Validating Groovy syntax: $(basename "$file")"
    
    # Check if groovy command is available
    if ! command -v groovy &>/dev/null; then
        warn "Groovy command not available, skipping syntax check"
        add_validation_result "$file" "syntax" "skipped" "Groovy command not available"
        return 0
    fi
    
    # Run syntax check with timeout
    local syntax_output
    local syntax_exit_code
    
    syntax_output=$(timeout "$GROOVY_TIMEOUT" groovy -c "$file" 2>&1 || echo "SYNTAX_ERROR")
    syntax_exit_code=$?
    
    if [[ $syntax_exit_code -eq 0 && "$syntax_output" != *"SYNTAX_ERROR"* ]]; then
        add_validation_result "$file" "syntax" "pass" "Groovy syntax is valid"
        return 0
    else
        # Extract line number from error message if available
        local line_number=0
        if [[ "$syntax_output" =~ line:?\ ?([0-9]+) ]]; then
            line_number="${BASH_REMATCH[1]}"
        fi
        
        add_validation_result "$file" "syntax" "error" "Syntax error: $syntax_output" "$line_number"
        return 1
    fi
}

# Check for security violations
check_security_violations() {
    local file="$1"
    
    if [[ "${SECURITY_CHECK:-false}" != "true" ]]; then
        return 0
    fi
    
    log "Checking security compliance: $(basename "$file")"
    
    local violations_found=false
    local line_number=1
    
    while IFS= read -r line; do
        for pattern in "${SECURITY_PATTERNS[@]}"; do
            if echo "$line" | grep -qE "$pattern"; then
                add_validation_result "$file" "security" "violation" "Security violation: matches pattern '$pattern' - Line: $line" "$line_number"
                violations_found=true
            fi
        done
        ((line_number++))
    done < "$file"
    
    # Additional security checks
    
    # Check for hardcoded credentials patterns
    if grep -qE "(password|token|secret|key)\s*=\s*['\"][^'\"]+['\"]" "$file"; then
        add_validation_result "$file" "security" "violation" "Potential hardcoded credentials detected"
        violations_found=true
    fi
    
    # Check for external URL access
    if grep -qE "http[s]?://[^'\"\s]+" "$file"; then
        add_validation_result "$file" "security" "warning" "External URL access detected - review required"
    fi
    
    # Check for shell command execution
    if grep -qE "sh\s*['\"]|bash\s*['\"]|/bin/" "$file"; then
        add_validation_result "$file" "security" "violation" "Shell command execution detected"
        violations_found=true
    fi
    
    # Check for file system access
    if grep -qE "new\s+File\s*\(|Files\.|Paths\.|FileUtils\." "$file"; then
        add_validation_result "$file" "security" "warning" "File system access detected - review required"
    fi
    
    if [[ "$violations_found" == "false" ]]; then
        add_validation_result "$file" "security" "pass" "No security violations detected"
    fi
    
    return 0
}

# Analyze complexity
analyze_complexity() {
    local file="$1"
    
    if [[ "${COMPLEXITY_CHECK:-false}" != "true" ]]; then
        return 0
    fi
    
    log "Analyzing complexity: $(basename "$file")"
    
    local line_count=$(wc -l < "$file")
    local complexity_score=0
    
    # Count complexity indicators
    for pattern in "${COMPLEXITY_PATTERNS[@]}"; do
        local pattern_count=$(grep -cE "$pattern" "$file" || echo "0")
        complexity_score=$((complexity_score + pattern_count))
    done
    
    # Calculate complexity metrics
    local cyclomatic_complexity=$((complexity_score + 1))
    local complexity_ratio=$(echo "scale=2; $complexity_score / $line_count * 100" | bc -l 2>/dev/null || echo "0")
    
    # Evaluate complexity
    if [[ "$line_count" -gt "$MAX_DSL_COMPLEXITY" ]]; then
        add_validation_result "$file" "complexity" "warning" "File length ${line_count} exceeds threshold ${MAX_DSL_COMPLEXITY}"
    elif [[ "$cyclomatic_complexity" -gt 20 ]]; then
        add_validation_result "$file" "complexity" "warning" "High cyclomatic complexity: ${cyclomatic_complexity}"
    elif [[ $(echo "$complexity_ratio > 30" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
        add_validation_result "$file" "complexity" "warning" "High complexity ratio: ${complexity_ratio}%"
    else
        add_validation_result "$file" "complexity" "pass" "Complexity within acceptable limits (score: ${complexity_score}, lines: ${line_count})"
    fi
}

# Check for DSL best practices
check_dsl_best_practices() {
    local file="$1"
    
    log "Checking DSL best practices: $(basename "$file")"
    
    local issues_found=false
    
    # Check for proper job naming conventions
    if ! grep -q "name\s*[=:]\s*['\"][a-zA-Z0-9._-]+['\"]" "$file"; then
        add_validation_result "$file" "best_practices" "warning" "No explicit job name found - consider using proper naming"
        issues_found=true
    fi
    
    # Check for description
    if ! grep -q "description\s*[=:]" "$file"; then
        add_validation_result "$file" "best_practices" "info" "No job description found - consider adding documentation"
    fi
    
    # Check for proper folder structure
    if ! grep -q "folder\s*['\"]" "$file" && ! grep -q "freeStyleJob\|pipelineJob\|multibranchPipelineJob" "$file"; then
        add_validation_result "$file" "best_practices" "info" "Consider organizing jobs in folders"
    fi
    
    # Check for hardcoded values that should be parameterized
    if grep -qE "['\"][^'\"]*/(dev|test|staging|prod|production)[^'\"]*['\"]" "$file"; then
        add_validation_result "$file" "best_practices" "warning" "Environment-specific hardcoded values detected - consider parameterization"
        issues_found=true
    fi
    
    # Check for proper error handling in pipeline scripts
    if grep -q "pipelineJob" "$file" && ! grep -q "try\s*{\|catchError" "$file"; then
        add_validation_result "$file" "best_practices" "info" "Consider adding error handling to pipeline jobs"
    fi
    
    if [[ "$issues_found" == "false" ]]; then
        add_validation_result "$file" "best_practices" "pass" "DSL follows best practices"
    fi
}

# Validate single DSL file
validate_dsl_file() {
    local file="$1"
    
    log "Validating DSL file: $file"
    
    # Check file size
    if ! validate_file_size "$file"; then
        return 1
    fi
    
    # Validate syntax
    validate_groovy_syntax "$file"
    
    # Security checks
    check_security_violations "$file"
    
    # Complexity analysis
    analyze_complexity "$file"
    
    # Best practices
    check_dsl_best_practices "$file"
    
    return 0
}

# Generate text report
generate_text_report() {
    echo "="*80
    echo "DSL Validation Report - Team: $TEAM_NAME"
    echo "DSL Path: $DSL_PATH"
    echo "Validation Time: $(date)"
    echo "="*80
    echo
    
    local total_files=$(echo "${VALIDATION_RESULTS[@]}" | jq -s 'map(.file) | unique | length' 2>/dev/null || echo "0")
    local syntax_errors=${#SYNTAX_ERRORS[@]}
    local security_violations=${#SECURITY_VIOLATIONS[@]}
    local complexity_issues=${#COMPLEXITY_ISSUES[@]}
    
    echo "SUMMARY:"
    echo "  Total files validated: $total_files"
    echo "  Syntax errors: $syntax_errors"
    echo "  Security violations: $security_violations"
    echo "  Complexity issues: $complexity_issues"
    echo
    
    # Display errors and violations
    if [[ $syntax_errors -gt 0 ]]; then
        echo "SYNTAX ERRORS:"
        for result in "${VALIDATION_RESULTS[@]}"; do
            local check_type=$(echo "$result" | jq -r '.check_type')
            local status=$(echo "$result" | jq -r '.status')
            if [[ "$check_type" == "syntax" && "$status" == "error" ]]; then
                local file=$(echo "$result" | jq -r '.file')
                local message=$(echo "$result" | jq -r '.message')
                local line_number=$(echo "$result" | jq -r '.line_number')
                echo "  - $file:$line_number - $message"
            fi
        done
        echo
    fi
    
    if [[ $security_violations -gt 0 ]]; then
        echo "SECURITY VIOLATIONS:"
        for result in "${VALIDATION_RESULTS[@]}"; do
            local check_type=$(echo "$result" | jq -r '.check_type')
            local status=$(echo "$result" | jq -r '.status')
            if [[ "$check_type" == "security" && "$status" == "violation" ]]; then
                local file=$(echo "$result" | jq -r '.file')
                local message=$(echo "$result" | jq -r '.message')
                echo "  - $file - $message"
            fi
        done
        echo
    fi
    
    if [[ $complexity_issues -gt 0 ]]; then
        echo "COMPLEXITY ISSUES:"
        for result in "${VALIDATION_RESULTS[@]}"; do
            local check_type=$(echo "$result" | jq -r '.check_type')
            local status=$(echo "$result" | jq -r '.status')
            if [[ "$check_type" == "complexity" && "$status" == "warning" ]]; then
                local file=$(echo "$result" | jq -r '.file')
                local message=$(echo "$result" | jq -r '.message')
                echo "  - $file - $message"
            fi
        done
        echo
    fi
    
    # Overall result
    if [[ $syntax_errors -eq 0 && $security_violations -eq 0 ]]; then
        echo "RESULT: VALIDATION PASSED"
        if [[ $complexity_issues -gt 0 ]]; then
            echo "WARNING: Complexity issues detected but not blocking"
        fi
    else
        echo "RESULT: VALIDATION FAILED"
    fi
}

# Generate JSON report
generate_json_report() {
    local total_files=$(echo "${VALIDATION_RESULTS[@]}" | jq -s 'map(.file) | unique | length' 2>/dev/null || echo "0")
    local syntax_errors=${#SYNTAX_ERRORS[@]}
    local security_violations=${#SECURITY_VIOLATIONS[@]}
    local complexity_issues=${#COMPLEXITY_ISSUES[@]}
    
    local validation_passed=true
    if [[ $syntax_errors -gt 0 || $security_violations -gt 0 ]]; then
        validation_passed=false
    fi
    
    cat <<EOF
{
    "validation_summary": {
        "team": "$TEAM_NAME",
        "dsl_path": "$DSL_PATH",
        "validation_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "total_files": $total_files,
        "syntax_errors": $syntax_errors,
        "security_violations": $security_violations,
        "complexity_issues": $complexity_issues,
        "validation_passed": $validation_passed,
        "checks_enabled": {
            "security_check": ${SECURITY_CHECK:-false},
            "complexity_check": ${COMPLEXITY_CHECK:-false}
        }
    },
    "validation_results": [
        $(IFS=','; echo "${VALIDATION_RESULTS[*]}")
    ]
}
EOF
}

# Main validation function
main() {
    parse_args "$@"
    
    log "Starting DSL validation for team: $TEAM_NAME"
    log "DSL path: $DSL_PATH"
    
    # Find DSL files
    local dsl_files
    dsl_files=$(find_dsl_files "$DSL_PATH")
    
    if [[ -z "$dsl_files" ]]; then
        error "No DSL files found in: $DSL_PATH"
        exit 1
    fi
    
    local file_count=$(echo "$dsl_files" | wc -l)
    log "Found $file_count DSL files to validate"
    
    # Validate each file
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            validate_dsl_file "$file"
        fi
    done <<< "$dsl_files"
    
    # Generate report
    case "$OUTPUT_FORMAT" in
        "json")
            generate_json_report
            ;;
        "text")
            generate_text_report
            ;;
        *)
            error "Unknown output format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
    
    # Exit with appropriate code
    local syntax_errors=${#SYNTAX_ERRORS[@]}
    local security_violations=${#SECURITY_VIOLATIONS[@]}
    
    if [[ $syntax_errors -gt 0 || $security_violations -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi