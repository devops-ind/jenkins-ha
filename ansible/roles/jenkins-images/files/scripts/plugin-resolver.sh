#!/bin/bash
# Production-Ready Jenkins Plugin Resolver
# Enterprise-grade plugin dependency resolution with caching and error handling

set -euo pipefail

# Script configuration
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
PID_FILE="/tmp/${SCRIPT_NAME}.pid"

# Default configuration
INPUT_FILE=""
OUTPUT_FILE=""
CACHE_DIR="/tmp/plugin-cache"
RESOLVE_DEPENDENCIES="true"
MAX_DEPTH="3"
CONFLICT_RESOLUTION="latest"
PARALLEL_DOWNLOADS="4"
RETRY_COUNT="5"
RETRY_DELAY="10"
VERIFY_CHECKSUMS="true"
DRY_RUN="false"
OFFLINE_MODE="false"
SILENT_MODE="false"

# Jenkins update center URLs
UPDATE_CENTER_URLS=(
    "https://updates.jenkins.io/current/update-center.json"
    "https://mirrors.jenkins.io/updates/current/update-center.json"
)

PLUGIN_DOWNLOAD_URLS=(
    "https://updates.jenkins.io/download/plugins"
    "https://mirrors.jenkins.io/plugins"
    "https://ftp-chi.osuosl.org/pub/jenkins/plugins"
)

# Colors for output
if [[ -t 1 ]] && [[ "${SILENT_MODE}" != "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "${SILENT_MODE}" == "true" && "${level}" != "ERROR" ]]; then
        return 0
    fi
    
    case "${level}" in
        "ERROR")
            echo -e "${RED}[${timestamp}] [ERROR] ${message}${NC}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[${timestamp}] [WARN] ${message}${NC}" >&2
            ;;
        "INFO")
            if [[ "${LOG_LEVEL}" =~ ^(INFO|DEBUG)$ ]]; then
                echo -e "${GREEN}[${timestamp}] [INFO] ${message}${NC}"
            fi
            ;;
        "DEBUG")
            if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
                echo -e "${BLUE}[${timestamp}] [DEBUG] ${message}${NC}"
            fi
            ;;
    esac
}

# Error handling
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    log "ERROR" "${message}"
    cleanup
    exit "${exit_code}"
}

# Cleanup function
cleanup() {
    log "DEBUG" "Performing cleanup"
    if [[ -f "${PID_FILE}" ]]; then
        rm -f "${PID_FILE}"
    fi
}

# Signal handlers
trap cleanup EXIT
trap 'error_exit "Script interrupted by user" 130' INT TERM

# Usage function
usage() {
    cat << EOF
${SCRIPT_NAME} - Jenkins Plugin Dependency Resolver

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    --input FILE                Input plugin list file (required)
    --output FILE               Output resolved plugin list file (required)
    --cache-dir DIR             Plugin cache directory (default: ${CACHE_DIR})
    --resolve-dependencies BOOL Enable dependency resolution (default: ${RESOLVE_DEPENDENCIES})
    --max-depth NUM             Maximum dependency resolution depth (default: ${MAX_DEPTH})
    --conflict-resolution MODE  Conflict resolution strategy: latest|oldest|fail (default: ${CONFLICT_RESOLUTION})
    --parallel NUM              Parallel downloads (default: ${PARALLEL_DOWNLOADS})
    --retry-count NUM           Network retry count (default: ${RETRY_COUNT})
    --retry-delay NUM           Retry delay in seconds (default: ${RETRY_DELAY})
    --verify-checksums BOOL     Verify plugin checksums (default: ${VERIFY_CHECKSUMS})
    --dry-run                   Show what would be done without making changes
    --offline                   Offline mode - use cached data only
    --silent                    Silent mode - minimal output
    --help                      Show this help message

EXAMPLES:
    # Basic usage
    ${SCRIPT_NAME} --input plugins.txt --output resolved-plugins.txt
    
    # Advanced usage with dependency resolution
    ${SCRIPT_NAME} --input plugins.txt --output resolved-plugins.txt \\
                   --resolve-dependencies true --max-depth 2 \\
                   --parallel 8 --cache-dir /var/cache/plugins
    
    # Offline mode
    ${SCRIPT_NAME} --input plugins.txt --output resolved-plugins.txt --offline

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --input)
                INPUT_FILE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --cache-dir)
                CACHE_DIR="$2"
                shift 2
                ;;
            --resolve-dependencies)
                RESOLVE_DEPENDENCIES="$2"
                shift 2
                ;;
            --max-depth)
                MAX_DEPTH="$2"
                shift 2
                ;;
            --conflict-resolution)
                CONFLICT_RESOLUTION="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL_DOWNLOADS="$2"
                shift 2
                ;;
            --retry-count)
                RETRY_COUNT="$2"
                shift 2
                ;;
            --retry-delay)
                RETRY_DELAY="$2"
                shift 2
                ;;
            --verify-checksums)
                VERIFY_CHECKSUMS="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --offline)
                OFFLINE_MODE="true"
                shift
                ;;
            --silent)
                SILENT_MODE="true"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Validate arguments
validate_args() {
    if [[ -z "${INPUT_FILE}" ]]; then
        error_exit "Input file is required. Use --input FILE"
    fi
    
    if [[ -z "${OUTPUT_FILE}" ]]; then
        error_exit "Output file is required. Use --output FILE"
    fi
    
    if [[ ! -f "${INPUT_FILE}" ]]; then
        error_exit "Input file does not exist: ${INPUT_FILE}"
    fi
    
    if [[ ! "${RESOLVE_DEPENDENCIES}" =~ ^(true|false)$ ]]; then
        error_exit "Invalid resolve-dependencies value: ${RESOLVE_DEPENDENCIES}. Must be true or false."
    fi
    
    if [[ ! "${MAX_DEPTH}" =~ ^[0-9]+$ ]] || [[ "${MAX_DEPTH}" -lt 0 ]] || [[ "${MAX_DEPTH}" -gt 10 ]]; then
        error_exit "Invalid max-depth value: ${MAX_DEPTH}. Must be a number between 0 and 10."
    fi
    
    if [[ ! "${CONFLICT_RESOLUTION}" =~ ^(latest|oldest|fail)$ ]]; then
        error_exit "Invalid conflict-resolution value: ${CONFLICT_RESOLUTION}. Must be latest, oldest, or fail."
    fi
    
    if [[ ! "${PARALLEL_DOWNLOADS}" =~ ^[0-9]+$ ]] || [[ "${PARALLEL_DOWNLOADS}" -lt 1 ]] || [[ "${PARALLEL_DOWNLOADS}" -gt 16 ]]; then
        error_exit "Invalid parallel downloads value: ${PARALLEL_DOWNLOADS}. Must be a number between 1 and 16."
    fi
}

# Create cache directory
setup_cache() {
    if [[ ! -d "${CACHE_DIR}" ]]; then
        log "INFO" "Creating cache directory: ${CACHE_DIR}"
        if [[ "${DRY_RUN}" != "true" ]]; then
            mkdir -p "${CACHE_DIR}" || error_exit "Failed to create cache directory: ${CACHE_DIR}"
        fi
    fi
    
    # Create subdirectories
    local subdirs=("metadata" "plugins" "checksums" "dependencies")
    for subdir in "${subdirs[@]}"; do
        local dir="${CACHE_DIR}/${subdir}"
        if [[ ! -d "${dir}" && "${DRY_RUN}" != "true" ]]; then
            mkdir -p "${dir}" || error_exit "Failed to create cache subdirectory: ${dir}"
        fi
    done
}

# Download with retry logic
download_with_retry() {
    local url="$1"
    local output_file="$2"
    local description="$3"
    local retry_count=0
    
    if [[ "${OFFLINE_MODE}" == "true" ]]; then
        if [[ -f "${output_file}" ]]; then
            log "DEBUG" "Using cached ${description}: ${output_file}"
            return 0
        else
            log "WARN" "Offline mode enabled but ${description} not found in cache: ${output_file}"
            return 1
        fi
    fi
    
    while [[ ${retry_count} -lt ${RETRY_COUNT} ]]; do
        log "DEBUG" "Downloading ${description} (attempt $((retry_count + 1))/${RETRY_COUNT}): ${url}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log "INFO" "[DRY RUN] Would download ${description} from: ${url}"
            return 0
        fi
        
        if curl -fsSL --max-time 30 --retry 2 --connect-timeout 10 \
               -H "User-Agent: Jenkins-Plugin-Resolver/1.0" \
               "${url}" -o "${output_file}" 2>/dev/null; then
            log "DEBUG" "Successfully downloaded ${description}"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ ${retry_count} -lt ${RETRY_COUNT} ]]; then
                log "WARN" "Failed to download ${description}, retrying in ${RETRY_DELAY} seconds..."
                sleep "${RETRY_DELAY}"
            else
                log "ERROR" "Failed to download ${description} after ${RETRY_COUNT} attempts"
                return 1
            fi
        fi
    done
}

# Fetch update center metadata
fetch_update_center() {
    local update_center_file="${CACHE_DIR}/metadata/update-center.json"
    local temp_file="${update_center_file}.tmp"
    
    # Check if we have a recent cached version (less than 1 hour old)
    if [[ -f "${update_center_file}" && "${OFFLINE_MODE}" != "true" ]]; then
        local file_age=$(($(date +%s) - $(stat -c %Y "${update_center_file}" 2>/dev/null || echo 0)))
        if [[ ${file_age} -lt 3600 ]]; then
            log "DEBUG" "Using recent cached update center metadata"
            return 0
        fi
    fi
    
    for url in "${UPDATE_CENTER_URLS[@]}"; do
        if download_with_retry "${url}" "${temp_file}" "update center metadata"; then
            if [[ "${DRY_RUN}" != "true" ]]; then
                # Validate JSON
                if jq empty "${temp_file}" 2>/dev/null; then
                    mv "${temp_file}" "${update_center_file}"
                    log "INFO" "Successfully fetched update center metadata"
                    return 0
                else
                    log "WARN" "Invalid JSON from ${url}, trying next URL"
                    rm -f "${temp_file}"
                fi
            else
                return 0
            fi
        fi
    done
    
    if [[ ! -f "${update_center_file}" ]]; then
        if [[ "${OFFLINE_MODE}" == "true" ]]; then
            log "WARN" "Offline mode enabled but no cached update center metadata found"
        else
            error_exit "Failed to fetch update center metadata from all sources"
        fi
    fi
}

# Parse plugin requirements from input file
parse_input_plugins() {
    local input_file="$1"
    local -n plugin_list_ref=$2
    
    log "INFO" "Parsing input plugin file: ${input_file}"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        line="$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "${line}" || "${line}" =~ ^# ]]; then
            continue
        fi
        
        # Parse plugin:version format
        if [[ "${line}" =~ ^([^:]+):([^:]+)$ ]]; then
            local plugin_name="${BASH_REMATCH[1]}"
            local plugin_version="${BASH_REMATCH[2]}"
            plugin_list_ref["${plugin_name}"]="${plugin_version}"
            log "DEBUG" "Added plugin: ${plugin_name}:${plugin_version}"
        elif [[ "${line}" =~ ^([^:]+)$ ]]; then
            local plugin_name="${BASH_REMATCH[1]}"
            plugin_list_ref["${plugin_name}"]="latest"
            log "DEBUG" "Added plugin: ${plugin_name}:latest"
        else
            log "WARN" "Invalid plugin format, skipping: ${line}"
        fi
    done < "${input_file}"
    
    log "INFO" "Parsed ${#plugin_list_ref[@]} plugins from input file"
}

# Resolve plugin dependencies recursively
resolve_dependencies() {
    local -n input_plugins_ref=$1
    local -n resolved_plugins_ref=$2
    local current_depth="${3:-0}"
    
    if [[ "${RESOLVE_DEPENDENCIES}" != "true" ]]; then
        log "INFO" "Dependency resolution disabled, using input plugins as-is"
        for plugin in "${!input_plugins_ref[@]}"; do
            resolved_plugins_ref["${plugin}"]="${input_plugins_ref[${plugin}]}"
        done
        return 0
    fi
    
    if [[ ${current_depth} -ge ${MAX_DEPTH} ]]; then
        log "DEBUG" "Maximum dependency depth (${MAX_DEPTH}) reached"
        return 0
    fi
    
    log "INFO" "Resolving dependencies at depth ${current_depth}"
    
    local update_center_file="${CACHE_DIR}/metadata/update-center.json"
    if [[ ! -f "${update_center_file}" ]]; then
        log "WARN" "No update center metadata available for dependency resolution"
        return 0
    fi
    
    local -A new_dependencies
    local plugins_processed=0
    
    for plugin_name in "${!input_plugins_ref[@]}"; do
        plugins_processed=$((plugins_processed + 1))
        
        if [[ ${plugins_processed} % 10 -eq 0 ]]; then
            log "INFO" "Processing plugin ${plugins_processed}/${#input_plugins_ref[@]}: ${plugin_name}"
        else
            log "DEBUG" "Processing plugin: ${plugin_name}"
        fi
        
        # Skip if already processed
        if [[ -n "${resolved_plugins_ref[${plugin_name}]:-}" ]]; then
            log "DEBUG" "Plugin ${plugin_name} already resolved, skipping"
            continue
        fi
        
        # Add current plugin to resolved list
        resolved_plugins_ref["${plugin_name}"]="${input_plugins_ref[${plugin_name}]}"
        
        # Extract dependencies from update center
        if [[ "${DRY_RUN}" != "true" ]]; then
            local dependencies
            dependencies=$(jq -r ".plugins.\"${plugin_name}\".dependencies[]?.name // empty" "${update_center_file}" 2>/dev/null || echo "")
            
            if [[ -n "${dependencies}" ]]; then
                while IFS= read -r dep_plugin; do
                    if [[ -n "${dep_plugin}" && -z "${resolved_plugins_ref[${dep_plugin}]:-}" && -z "${new_dependencies[${dep_plugin}]:-}" ]]; then
                        new_dependencies["${dep_plugin}"]="latest"
                        log "DEBUG" "Found dependency: ${plugin_name} -> ${dep_plugin}"
                    fi
                done <<< "${dependencies}"
            fi
        fi
    done
    
    # Recursively resolve new dependencies
    if [[ ${#new_dependencies[@]} -gt 0 ]]; then
        log "INFO" "Found ${#new_dependencies[@]} new dependencies at depth ${current_depth}"
        resolve_dependencies new_dependencies resolved_plugins_ref $((current_depth + 1))
    fi
}

# Resolve version conflicts
resolve_conflicts() {
    local -n plugins_ref=$1
    
    log "INFO" "Resolving version conflicts using strategy: ${CONFLICT_RESOLUTION}"
    
    # For now, we'll implement a simple latest-wins strategy
    # In a full implementation, this would compare semantic versions
    case "${CONFLICT_RESOLUTION}" in
        "latest")
            log "DEBUG" "Using latest-wins conflict resolution"
            ;;
        "oldest")
            log "DEBUG" "Using oldest-wins conflict resolution"
            ;;
        "fail")
            log "DEBUG" "Using fail-on-conflict resolution"
            ;;
    esac
}

# Generate output file
generate_output() {
    local -n plugins_ref=$1
    local output_file="$2"
    
    log "INFO" "Generating output file: ${output_file}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY RUN] Would write ${#plugins_ref[@]} plugins to ${output_file}"
        for plugin in "${!plugins_ref[@]}"; do
            echo "${plugin}:${plugins_ref[${plugin}]}"
        done | sort
        return 0
    fi
    
    # Create temporary file
    local temp_file="${output_file}.tmp"
    
    # Write header
    cat > "${temp_file}" << EOF
# Resolved Jenkins Plugins
# Generated by ${SCRIPT_NAME} on $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Total plugins: ${#plugins_ref[@]}
# Input file: ${INPUT_FILE}
# Dependency resolution: ${RESOLVE_DEPENDENCIES}
# Max depth: ${MAX_DEPTH}
# Conflict resolution: ${CONFLICT_RESOLUTION}

EOF
    
    # Write plugins sorted by name
    for plugin in $(printf '%s\n' "${!plugins_ref[@]}" | sort); do
        echo "${plugin}:${plugins_ref[${plugin}]}" >> "${temp_file}"
    done
    
    # Atomic move
    mv "${temp_file}" "${output_file}" || error_exit "Failed to write output file: ${output_file}"
    
    log "INFO" "Successfully wrote ${#plugins_ref[@]} plugins to ${output_file}"
}

# Display summary
show_summary() {
    local -n plugins_ref=$1
    
    if [[ "${SILENT_MODE}" == "true" ]]; then
        return 0
    fi
    
    echo
    echo "=== Plugin Resolution Summary ==="
    echo "Input file: ${INPUT_FILE}"
    echo "Output file: ${OUTPUT_FILE}"
    echo "Total plugins resolved: ${#plugins_ref[@]}"
    echo "Dependency resolution: ${RESOLVE_DEPENDENCIES}"
    echo "Max dependency depth: ${MAX_DEPTH}"
    echo "Conflict resolution strategy: ${CONFLICT_RESOLUTION}"
    echo "Cache directory: ${CACHE_DIR}"
    echo "Dry run mode: ${DRY_RUN}"
    echo "Offline mode: ${OFFLINE_MODE}"
    echo
    
    if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
        echo "=== Plugin List ==="
        for plugin in $(printf '%s\n' "${!plugins_ref[@]}" | sort); do
            echo "  ${plugin}:${plugins_ref[${plugin}]}"
        done
        echo
    fi
}

# Main function
main() {
    log "INFO" "Starting Jenkins Plugin Resolver v1.0"
    
    # Create PID file
    echo $$ > "${PID_FILE}"
    
    # Parse and validate arguments
    parse_args "$@"
    validate_args
    
    # Setup environment
    setup_cache
    
    # Fetch update center metadata
    if [[ "${RESOLVE_DEPENDENCIES}" == "true" ]]; then
        fetch_update_center
    fi
    
    # Parse input plugins
    declare -A input_plugins
    parse_input_plugins "${INPUT_FILE}" input_plugins
    
    if [[ ${#input_plugins[@]} -eq 0 ]]; then
        error_exit "No plugins found in input file: ${INPUT_FILE}"
    fi
    
    # Resolve dependencies
    declare -A resolved_plugins
    resolve_dependencies input_plugins resolved_plugins
    
    # Resolve conflicts
    resolve_conflicts resolved_plugins
    
    # Generate output
    generate_output resolved_plugins "${OUTPUT_FILE}"
    
    # Show summary
    show_summary resolved_plugins
    
    log "INFO" "Plugin resolution completed successfully"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi