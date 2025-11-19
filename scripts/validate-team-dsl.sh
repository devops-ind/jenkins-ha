#!/bin/bash

###############################################################################
# Jenkins DSL Validation Framework
# 
# This script provides comprehensive validation for Jenkins Job DSL scripts
# to ensure security, compliance, and team boundary enforcement.
#
# Usage:
#   ./scripts/validate-team-dsl.sh --team TEAM_NAME --dsl-dir DSL_DIRECTORY [OPTIONS]
#
# Options:
#   --team TEAM_NAME      Team name for boundary validation (required)
#   --dsl-dir DIR         Directory containing DSL scripts (required)
#   --repo-url URL        Repository URL for reference (optional)
#   --strict              Enable strict validation mode
#   --report-file FILE    Output validation report to file (optional)
#   --security-only       Run only security checks
#   --syntax-only         Run only syntax checks
#   --help                Show this help message
#
# Exit codes:
#   0 - All validations passed
#   1 - Validation errors found
#   2 - Security violations found  
#   3 - Script usage error
###############################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
LOG_PREFIX="[DSL-VALIDATOR]"

# Default values
TEAM_NAME=""
DSL_DIRECTORY=""
REPO_URL=""
STRICT_MODE=false
REPORT_FILE=""
SECURITY_ONLY=false
SYNTAX_ONLY=false
VERBOSE=false

# Validation counters
TOTAL_FILES=0
SYNTAX_ERRORS=0
SECURITY_VIOLATIONS=0
WARNING_COUNT=0
PROCESSED_FILES=0

# Colors for output (if supported)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    WHITE=''
    NC=''
fi

# Logging functions
log_info() {
    echo -e "${BLUE}${LOG_PREFIX}${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}${LOG_PREFIX}${NC} ✅ $*" >&2
}

log_warn() {
    echo -e "${YELLOW}${LOG_PREFIX}${NC} ⚠️  $*" >&2
    ((WARNING_COUNT++))
}

log_error() {
    echo -e "${RED}${LOG_PREFIX}${NC} ❌ $*" >&2
}

log_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${CYAN}${LOG_PREFIX}${NC} 🔍 $*" >&2
    fi
}

# Usage information
show_usage() {
    cat << EOF
Jenkins DSL Validation Framework

USAGE:
    ${SCRIPT_NAME} --team TEAM_NAME --dsl-dir DSL_DIRECTORY [OPTIONS]

REQUIRED PARAMETERS:
    --team TEAM_NAME      Team name for boundary validation
    --dsl-dir DIR         Directory containing DSL scripts to validate

OPTIONAL PARAMETERS:
    --repo-url URL        Repository URL for reference in reports
    --strict              Enable strict validation mode (fail on warnings)
    --report-file FILE    Output detailed validation report to file
    --security-only       Run only security validation checks
    --syntax-only         Run only syntax validation checks
    --verbose             Enable verbose debug logging
    --help                Show this help message

EXAMPLES:
    # Basic validation
    ${SCRIPT_NAME} --team devops --dsl-dir ./dsl

    # Strict validation with report
    ${SCRIPT_NAME} --team devops --dsl-dir ./dsl --strict --report-file validation-report.txt

    # Security-only validation
    ${SCRIPT_NAME} --team devops --dsl-dir ./dsl --security-only

EXIT CODES:
    0 - All validations passed
    1 - Validation errors found
    2 - Security violations found
    3 - Script usage error

VALIDATION CHECKS:
    • Groovy syntax validation
    • Security policy compliance (no dangerous system calls)
    • Team boundary enforcement (folder/job naming)
    • Credential hardcoding detection
    • File system access detection
    • Best practices compliance

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --team)
                TEAM_NAME="$2"
                shift 2
                ;;
            --dsl-dir)
                DSL_DIRECTORY="$2"
                shift 2
                ;;
            --repo-url)
                REPO_URL="$2"
                shift 2
                ;;
            --strict)
                STRICT_MODE=true
                shift
                ;;
            --report-file)
                REPORT_FILE="$2"
                shift 2
                ;;
            --security-only)
                SECURITY_ONLY=true
                shift
                ;;
            --syntax-only)
                SYNTAX_ONLY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                show_usage
                exit 3
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "${TEAM_NAME}" ]]; then
        log_error "Team name is required. Use --team TEAM_NAME"
        show_usage
        exit 3
    fi

    if [[ -z "${DSL_DIRECTORY}" ]]; then
        log_error "DSL directory is required. Use --dsl-dir DIRECTORY"
        show_usage
        exit 3
    fi

    if [[ ! -d "${DSL_DIRECTORY}" ]]; then
        log_error "DSL directory does not exist: ${DSL_DIRECTORY}"
        exit 3
    fi

    # Cannot combine security-only and syntax-only
    if [[ "${SECURITY_ONLY}" == "true" && "${SYNTAX_ONLY}" == "true" ]]; then
        log_error "Cannot combine --security-only and --syntax-only options"
        exit 3
    fi
}

# Initialize validation report
initialize_report() {
    if [[ -n "${REPORT_FILE}" ]]; then
        cat > "${REPORT_FILE}" << EOF
Jenkins DSL Validation Report
============================
Generated: $(date)
Team: ${TEAM_NAME}
DSL Directory: ${DSL_DIRECTORY}
Repository: ${REPO_URL:-"Not specified"}
Validation Mode: $(if [[ "${STRICT_MODE}" == "true" ]]; then echo "Strict"; else echo "Normal"; fi)
Check Type: $(if [[ "${SECURITY_ONLY}" == "true" ]]; then echo "Security Only"; elif [[ "${SYNTAX_ONLY}" == "true" ]]; then echo "Syntax Only"; else echo "Full Validation"; fi)

EOF
        log_info "Validation report will be written to: ${REPORT_FILE}"
    fi
}

# Find all DSL files
find_dsl_files() {
    log_info "Scanning for DSL files in: ${DSL_DIRECTORY}"
    
    local dsl_files
    dsl_files=$(find "${DSL_DIRECTORY}" -name "*.groovy" -type f 2>/dev/null | sort)
    
    if [[ -z "${dsl_files}" ]]; then
        log_warn "No DSL files found in directory: ${DSL_DIRECTORY}"
        TOTAL_FILES=0
        return 0
    fi
    
    TOTAL_FILES=$(echo "${dsl_files}" | wc -l)
    log_info "Found ${TOTAL_FILES} DSL files to validate"
    
    if [[ "${VERBOSE}" == "true" ]]; then
        echo "${dsl_files}" | while read -r file; do
            log_debug "Found DSL file: ${file}"
        done
    fi
    
    echo "${dsl_files}"
}

# Validate individual DSL file syntax
validate_syntax() {
    local file="$1"
    local filename=$(basename "${file}")
    
    log_debug "Validating syntax for: ${filename}"
    
    # Check if file exists and is readable
    if [[ ! -r "${file}" ]]; then
        log_error "Cannot read file: ${file}"
        ((SYNTAX_ERRORS++))
        return 1
    fi
    
    # Check if file is empty
    if [[ ! -s "${file}" ]]; then
        log_warn "DSL file is empty: ${filename}"
        return 0
    fi
    
    # Basic Groovy syntax validation
    # Note: This is simplified - in production, you might want to use groovyc or other tools
    local content
    if ! content=$(cat "${file}"); then
        log_error "Failed to read content of: ${filename}"
        ((SYNTAX_ERRORS++))
        return 1
    fi
    
    # Check for basic Groovy syntax issues
    local syntax_issues=0
    
    # Check for unmatched braces (basic check)
    local open_braces=$(echo "${content}" | grep -o '{' | wc -l)
    local close_braces=$(echo "${content}" | grep -o '}' | wc -l)
    if [[ "${open_braces}" -ne "${close_braces}" ]]; then
        log_error "Unmatched braces in ${filename}: ${open_braces} opening, ${close_braces} closing"
        ((syntax_issues++))
    fi
    
    # Check for unmatched parentheses (basic check)
    local open_parens=$(echo "${content}" | grep -o '(' | wc -l)
    local close_parens=$(echo "${content}" | grep -o ')' | wc -l)
    if [[ "${open_parens}" -ne "${close_parens}" ]]; then
        log_error "Unmatched parentheses in ${filename}: ${open_parens} opening, ${close_parens} closing"
        ((syntax_issues++))
    fi
    
    # Check for basic DSL structure
    if ! echo "${content}" | grep -q -E "(job|pipelineJob|folder|freeStyleJob|multibranchPipelineJob)\s*\("; then
        log_warn "No DSL job definitions found in ${filename} - may not be a valid Job DSL file"
    fi
    
    if [[ "${syntax_issues}" -gt 0 ]]; then
        ((SYNTAX_ERRORS++))
        return 1
    fi
    
    log_debug "Syntax validation passed for: ${filename}"
    return 0
}

# Validate security compliance
validate_security() {
    local file="$1"
    local filename=$(basename "${file}")
    
    log_debug "Validating security for: ${filename}"
    
    local security_issues=0
    local content
    content=$(cat "${file}")
    
    # Check for dangerous system calls
    if echo "${content}" | grep -q -E "(System\.exit|Runtime\.getRuntime|ProcessBuilder)"; then
        log_error "SECURITY VIOLATION: Dangerous system calls found in ${filename}"
        ((security_issues++))
    fi
    
    # Check for file system access
    if echo "${content}" | grep -q -E "(new File\(|FileWriter|FileReader|Files\.|Paths\.)"; then
        log_warn "File system access detected in ${filename} - ensure this is necessary"
    fi
    
    # Check for hardcoded credentials
    if echo "${content}" | grep -q -iE "(password|secret|token|key)\s*=\s*['\"][^'\"]+['\"]"; then
        log_error "SECURITY VIOLATION: Potential hardcoded credentials found in ${filename}"
        ((security_issues++))
    fi
    
    # Check for team boundary violations
    if echo "${content}" | grep -q -E "folder\s*\(\s*['\"][^'\"]*['\"]" && ! echo "${content}" | grep -q "${TEAM_NAME}"; then
        # More sophisticated check: look for folders that don't contain the team name
        local folder_matches
        folder_matches=$(echo "${content}" | grep -oE "folder\s*\(\s*['\"]([^'\"]*)['\"]" | sed -E "s/folder\s*\(\s*['\"]([^'\"]*)['\"].*/\1/")
        
        while IFS= read -r folder_name; do
            if [[ -n "${folder_name}" && "${folder_name}" != *"${TEAM_NAME}"* ]]; then
                log_warn "Potential team boundary violation in ${filename}: folder '${folder_name}' does not contain team name '${TEAM_NAME}'"
            fi
        done <<< "${folder_matches}"
    fi
    
    # Check for script approvals that might be needed
    if echo "${content}" | grep -q -E "(sh\s*['\"]|bat\s*['\"]|powershell\s*['\"])"; then
        log_debug "Shell commands found in ${filename} - may require script approval"
    fi
    
    # Check for external repository access
    if echo "${content}" | grep -q -E "(git\s*\{|url\s*:\s*['\"]https?://)"; then
        log_debug "External repository access found in ${filename}"
    fi
    
    if [[ "${security_issues}" -gt 0 ]]; then
        ((SECURITY_VIOLATIONS++))
        return 1
    fi
    
    log_debug "Security validation passed for: ${filename}"
    return 0
}

# Validate team boundaries and naming conventions
validate_team_compliance() {
    local file="$1"
    local filename=$(basename "${file}")
    
    log_debug "Validating team compliance for: ${filename}"
    
    local content
    content=$(cat "${file}")
    
    # Check if jobs are properly namespaced to the team
    local job_patterns=("job" "pipelineJob" "freeStyleJob" "multibranchPipelineJob")
    
    for pattern in "${job_patterns[@]}"; do
        local job_matches
        job_matches=$(echo "${content}" | grep -oE "${pattern}\s*\(\s*['\"]([^'\"]*)['\"]" | sed -E "s/${pattern}\s*\(\s*['\"]([^'\"]*)['\"].*/\1/")
        
        while IFS= read -r job_name; do
            if [[ -n "${job_name}" ]]; then
                # Check if job name starts with team name or contains team folder structure
                if [[ "${job_name}" != "${TEAM_NAME}/"* && "${job_name}" != *"${TEAM_NAME}"* ]]; then
                    log_warn "Job '${job_name}' in ${filename} should be namespaced to team '${TEAM_NAME}'"
                fi
            fi
        done <<< "${job_matches}"
    done
    
    log_debug "Team compliance validation completed for: ${filename}"
    return 0
}

# Write validation report entry
write_report_entry() {
    local file="$1"
    local status="$2"
    local details="$3"
    
    if [[ -n "${REPORT_FILE}" ]]; then
        echo "File: ${file}" >> "${REPORT_FILE}"
        echo "Status: ${status}" >> "${REPORT_FILE}"
        if [[ -n "${details}" ]]; then
            echo "Details: ${details}" >> "${REPORT_FILE}"
        fi
        echo "---" >> "${REPORT_FILE}"
    fi
}

# Main validation function
validate_dsl_files() {
    local dsl_files
    dsl_files=$(find_dsl_files)
    
    if [[ "${TOTAL_FILES}" -eq 0 ]]; then
        return 0
    fi
    
    log_info "Starting validation of ${TOTAL_FILES} DSL files..."
    
    while IFS= read -r file; do
        local filename=$(basename "${file}")
        local file_errors=0
        local file_warnings=0
        
        log_info "Validating: ${filename}"
        ((PROCESSED_FILES++))
        
        # Syntax validation
        if [[ "${SECURITY_ONLY}" != "true" ]]; then
            if ! validate_syntax "${file}"; then
                ((file_errors++))
                write_report_entry "${file}" "SYNTAX ERROR" "Failed syntax validation"
            fi
        fi
        
        # Security validation
        if [[ "${SYNTAX_ONLY}" != "true" ]]; then
            if ! validate_security "${file}"; then
                ((file_errors++))
                write_report_entry "${file}" "SECURITY VIOLATION" "Failed security validation"
            fi
            
            # Team compliance check
            validate_team_compliance "${file}"
        fi
        
        if [[ "${file_errors}" -eq 0 ]]; then
            log_success "Validation passed for: ${filename}"
            write_report_entry "${file}" "PASSED" ""
        else
            log_error "Validation failed for: ${filename} (${file_errors} errors)"
        fi
        
    done <<< "${dsl_files}"
}

# Generate final report
generate_final_report() {
    local exit_code=0
    
    echo
    log_info "======================================"
    log_info "DSL VALIDATION SUMMARY"
    log_info "======================================"
    log_info "Team: ${TEAM_NAME}"
    log_info "Directory: ${DSL_DIRECTORY}"
    log_info "Files Processed: ${PROCESSED_FILES}/${TOTAL_FILES}"
    log_info "Syntax Errors: ${SYNTAX_ERRORS}"
    log_info "Security Violations: ${SECURITY_VIOLATIONS}"
    log_info "Warnings: ${WARNING_COUNT}"
    
    # Determine exit code
    if [[ "${SECURITY_VIOLATIONS}" -gt 0 ]]; then
        exit_code=2
        log_error "Validation FAILED due to security violations"
    elif [[ "${SYNTAX_ERRORS}" -gt 0 ]]; then
        exit_code=1
        log_error "Validation FAILED due to syntax errors"
    elif [[ "${STRICT_MODE}" == "true" && "${WARNING_COUNT}" -gt 0 ]]; then
        exit_code=1
        log_error "Validation FAILED in strict mode due to warnings"
    else
        log_success "All validations PASSED"
        exit_code=0
    fi
    
    # Write summary to report file
    if [[ -n "${REPORT_FILE}" ]]; then
        cat >> "${REPORT_FILE}" << EOF

VALIDATION SUMMARY
=================
Files Processed: ${PROCESSED_FILES}/${TOTAL_FILES}
Syntax Errors: ${SYNTAX_ERRORS}
Security Violations: ${SECURITY_VIOLATIONS}  
Warnings: ${WARNING_COUNT}
Final Status: $(if [[ "${exit_code}" -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)
EOF
        log_info "Detailed report written to: ${REPORT_FILE}"
    fi
    
    return "${exit_code}"
}

# Main execution function
main() {
    log_info "Starting Jenkins DSL Validation Framework"
    log_info "Team: ${TEAM_NAME}, Directory: ${DSL_DIRECTORY}"
    
    if [[ "${VERBOSE}" == "true" ]]; then
        log_debug "Verbose mode enabled"
        log_debug "Strict mode: ${STRICT_MODE}"
        log_debug "Security only: ${SECURITY_ONLY}"
        log_debug "Syntax only: ${SYNTAX_ONLY}"
    fi
    
    initialize_report
    validate_dsl_files
    generate_final_report
    
    return $?
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse arguments
    parse_arguments "$@"
    
    # Run main function
    main
    exit $?
fi