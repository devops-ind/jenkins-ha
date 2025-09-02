#!/bin/bash
# Enterprise Jenkins Plugin Cache Manager
# Manages offline plugin cache for resilient builds

set -euo pipefail

# Script configuration
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="2.0.0"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Default configuration
CACHE_DIR="/var/cache/jenkins-plugins"
OFFLINE_DIR="${CACHE_DIR}/offline"
METADATA_DIR="${CACHE_DIR}/metadata"
CHECKSUMS_DIR="${CACHE_DIR}/checksums"
LOCK_FILE="${CACHE_DIR}/.cache-manager.lock"
MAX_CACHE_AGE_DAYS="30"
MAX_CACHE_SIZE_GB="10"
PARALLEL_DOWNLOADS="6"
RETRY_COUNT="5"
RETRY_DELAY="15"
OPERATION=""
PLUGIN_LIST=""
CLEAN_CACHE="false"
FORCE_DOWNLOAD="false"
VERIFY_CHECKSUMS="true"
QUIET_MODE="false"
DRY_RUN="false"

# Colors for output
if [[ -t 1 ]] && [[ "${QUIET_MODE}" != "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    NC=''
fi

# Jenkins update center configuration
UPDATE_CENTER_URLS=(
    "https://updates.jenkins.io/current/update-center.json"
    "https://mirrors.jenkins.io/updates/current/update-center.json"
    "https://ftp-chi.osuosl.org/pub/jenkins/updates/current/update-center.json"
    "https://mirror.xmission.com/jenkins/updates/current/update-center.json"
)

PLUGIN_DOWNLOAD_URLS=(
    "https://updates.jenkins.io/download/plugins"
    "https://mirrors.jenkins.io/plugins"
    "https://ftp-chi.osuosl.org/pub/jenkins/plugins"
    "https://mirror.xmission.com/jenkins/plugins"
)

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "${QUIET_MODE}" == "true" && "${level}" != "ERROR" ]]; then
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
        "SUCCESS")
            echo -e "${PURPLE}[${timestamp}] [SUCCESS] ${message}${NC}"
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
    if [[ -f "${LOCK_FILE}" ]]; then
        rm -f "${LOCK_FILE}"
    fi
}

# Signal handlers
trap cleanup EXIT
trap 'error_exit "Script interrupted by user" 130' INT TERM

# Usage function
usage() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Jenkins Plugin Cache Manager

USAGE:
    ${SCRIPT_NAME} [OPERATION] [OPTIONS]

OPERATIONS:
    populate    Populate cache with plugins from list
    verify      Verify cache integrity and checksums
    clean       Clean old cache entries
    stats       Display cache statistics
    sync        Sync cache with update center
    export      Export cache for offline use
    import      Import offline cache

OPTIONS:
    --cache-dir DIR           Cache directory (default: ${CACHE_DIR})
    --plugin-list FILE        Plugin list file
    --max-age DAYS           Maximum cache age in days (default: ${MAX_CACHE_AGE_DAYS})
    --max-size GB            Maximum cache size in GB (default: ${MAX_CACHE_SIZE_GB})
    --parallel NUM           Parallel downloads (default: ${PARALLEL_DOWNLOADS})
    --retry-count NUM        Network retry count (default: ${RETRY_COUNT})
    --retry-delay SEC        Retry delay in seconds (default: ${RETRY_DELAY})
    --force                  Force download even if cached
    --no-verify              Skip checksum verification
    --clean                  Clean cache before operation
    --quiet                  Quiet mode - minimal output
    --dry-run               Show what would be done
    --help                  Show this help message

EXAMPLES:
    # Populate cache with plugins
    ${SCRIPT_NAME} populate --plugin-list plugins.txt
    
    # Verify cache integrity
    ${SCRIPT_NAME} verify --cache-dir /var/cache/plugins
    
    # Clean old cache entries
    ${SCRIPT_NAME} clean --max-age 7 --max-size 5
    
    # Export cache for offline use
    ${SCRIPT_NAME} export --cache-dir /var/cache/plugins
    
    # Display cache statistics
    ${SCRIPT_NAME} stats

CACHE STRUCTURE:
    ${CACHE_DIR}/
    ├── plugins/           # Downloaded plugin files
    ├── metadata/          # Plugin metadata and update center data
    ├── checksums/         # Checksum verification files
    └── offline/          # Offline export packages

EOF
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    OPERATION="$1"
    shift
    
    case "${OPERATION}" in
        populate|verify|clean|stats|sync|export|import)
            ;; # Valid operations
        --help|-h)
            usage
            exit 0
            ;;
        *)
            error_exit "Invalid operation: ${OPERATION}. Use --help for usage information."
            ;;
    esac
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cache-dir)
                CACHE_DIR="$2"
                OFFLINE_DIR="${CACHE_DIR}/offline"
                METADATA_DIR="${CACHE_DIR}/metadata"
                CHECKSUMS_DIR="${CACHE_DIR}/checksums"
                LOCK_FILE="${CACHE_DIR}/.cache-manager.lock"
                shift 2
                ;;
            --plugin-list)
                PLUGIN_LIST="$2"
                shift 2
                ;;
            --max-age)
                MAX_CACHE_AGE_DAYS="$2"
                shift 2
                ;;
            --max-size)
                MAX_CACHE_SIZE_GB="$2"
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
            --force)
                FORCE_DOWNLOAD="true"
                shift
                ;;
            --no-verify)
                VERIFY_CHECKSUMS="false"
                shift
                ;;
            --clean)
                CLEAN_CACHE="true"
                shift
                ;;
            --quiet)
                QUIET_MODE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
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
    if [[ ! "${MAX_CACHE_AGE_DAYS}" =~ ^[0-9]+$ ]] || [[ "${MAX_CACHE_AGE_DAYS}" -lt 1 ]] || [[ "${MAX_CACHE_AGE_DAYS}" -gt 365 ]]; then
        error_exit "Invalid max-age value: ${MAX_CACHE_AGE_DAYS}. Must be a number between 1 and 365."
    fi
    
    if [[ ! "${MAX_CACHE_SIZE_GB}" =~ ^[0-9]+$ ]] || [[ "${MAX_CACHE_SIZE_GB}" -lt 1 ]] || [[ "${MAX_CACHE_SIZE_GB}" -gt 1000 ]]; then
        error_exit "Invalid max-size value: ${MAX_CACHE_SIZE_GB}. Must be a number between 1 and 1000."
    fi
    
    if [[ ! "${PARALLEL_DOWNLOADS}" =~ ^[0-9]+$ ]] || [[ "${PARALLEL_DOWNLOADS}" -lt 1 ]] || [[ "${PARALLEL_DOWNLOADS}" -gt 16 ]]; then
        error_exit "Invalid parallel downloads value: ${PARALLEL_DOWNLOADS}. Must be a number between 1 and 16."
    fi
    
    if [[ "${OPERATION}" == "populate" && -z "${PLUGIN_LIST}" ]]; then
        error_exit "Plugin list file is required for populate operation. Use --plugin-list FILE"
    fi
    
    if [[ "${OPERATION}" == "populate" && ! -f "${PLUGIN_LIST}" ]]; then
        error_exit "Plugin list file does not exist: ${PLUGIN_LIST}"
    fi
}

# Acquire lock
acquire_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")
        if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
            error_exit "Another instance is already running (PID: ${lock_pid})"
        else
            log "WARN" "Removing stale lock file"
            rm -f "${LOCK_FILE}"
        fi
    fi
    
    echo $$ > "${LOCK_FILE}"
}

# Initialize cache directories
init_cache() {
    log "DEBUG" "Initializing cache directories"
    
    local dirs=("${CACHE_DIR}" "${CACHE_DIR}/plugins" "${METADATA_DIR}" "${CHECKSUMS_DIR}" "${OFFLINE_DIR}")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            if [[ "${DRY_RUN}" != "true" ]]; then
                mkdir -p "${dir}" || error_exit "Failed to create directory: ${dir}"
                chmod 755 "${dir}"
            else
                log "INFO" "[DRY RUN] Would create directory: ${dir}"
            fi
        fi
    done
}

# Download with retry logic and failover
download_with_retry() {
    local urls=("$@")
    local output_file="${urls[-1]}"
    unset 'urls[-1]'  # Remove output file from URLs array
    local description="${urls[-1]}"
    unset 'urls[-1]'  # Remove description from URLs array
    
    local retry_count=0
    local current_retry_delay="${RETRY_DELAY}"
    
    while [[ ${retry_count} -lt ${RETRY_COUNT} ]]; do
        for url in "${urls[@]}"; do
            log "DEBUG" "Downloading ${description} (attempt $((retry_count + 1))/${RETRY_COUNT}): ${url}"
            
            if [[ "${DRY_RUN}" == "true" ]]; then
                log "INFO" "[DRY RUN] Would download ${description} from: ${url}"
                return 0
            fi
            
            # Use curl with comprehensive options for resilience
            if timeout 60 curl -fsSL \
                   --max-time 30 \
                   --connect-timeout 10 \
                   --retry 2 \
                   --retry-delay 5 \
                   --retry-max-time 120 \
                   --fail-early \
                   --location \
                   --compressed \
                   -H "User-Agent: Jenkins-Plugin-Cache-Manager/${SCRIPT_VERSION}" \
                   -H "Accept: application/octet-stream,*/*" \
                   "${url}" -o "${output_file}" 2>/dev/null; then
                log "DEBUG" "Successfully downloaded ${description} from ${url}"
                return 0
            else
                log "WARN" "Failed to download ${description} from ${url}"
            fi
        done
        
        retry_count=$((retry_count + 1))
        if [[ ${retry_count} -lt ${RETRY_COUNT} ]]; then
            log "WARN" "All URLs failed for ${description}, retrying in ${current_retry_delay} seconds..."
            sleep "${current_retry_delay}"
            current_retry_delay=$((current_retry_delay * 2))  # Exponential backoff
        fi
    done
    
    log "ERROR" "Failed to download ${description} after ${RETRY_COUNT} attempts from all URLs"
    return 1
}

# Verify file checksum
verify_checksum() {
    local file="$1"
    local expected_checksum="$2"
    local checksum_file="$3"
    
    if [[ "${VERIFY_CHECKSUMS}" != "true" ]]; then
        return 0
    fi
    
    if [[ ! -f "${file}" ]]; then
        log "ERROR" "File does not exist for checksum verification: ${file}"
        return 1
    fi
    
    local actual_checksum
    actual_checksum=$(sha256sum "${file}" | cut -d' ' -f1)
    
    if [[ "${actual_checksum}" == "${expected_checksum}" ]]; then
        log "DEBUG" "Checksum verification passed for: $(basename "${file}")"
        echo "${actual_checksum}" > "${checksum_file}"
        return 0
    else
        log "ERROR" "Checksum verification failed for: $(basename "${file}")"
        log "ERROR" "Expected: ${expected_checksum}"
        log "ERROR" "Actual: ${actual_checksum}"
        return 1
    fi
}

# Fetch update center metadata
fetch_update_center() {
    local update_center_file="${METADATA_DIR}/update-center.json"
    local temp_file="${update_center_file}.tmp"
    
    # Check if we have recent metadata (less than 4 hours old)
    if [[ -f "${update_center_file}" && "${FORCE_DOWNLOAD}" != "true" ]]; then
        local file_age
        if [[ "$(uname)" == "Darwin" ]]; then
            file_age=$(($(date +%s) - $(stat -f %m "${update_center_file}" 2>/dev/null || echo 0)))
        else
            file_age=$(($(date +%s) - $(stat -c %Y "${update_center_file}" 2>/dev/null || echo 0)))
        fi
        
        if [[ ${file_age} -lt 14400 ]]; then  # 4 hours
            log "DEBUG" "Using recent cached update center metadata"
            return 0
        fi
    fi
    
    log "INFO" "Fetching update center metadata"
    
    local urls=("${UPDATE_CENTER_URLS[@]}" "update center metadata" "${temp_file}")
    if download_with_retry "${urls[@]}"; then
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Validate JSON
            if command -v jq >/dev/null 2>&1; then
                if jq empty "${temp_file}" 2>/dev/null; then
                    mv "${temp_file}" "${update_center_file}"
                    log "SUCCESS" "Successfully fetched update center metadata"
                    return 0
                else
                    log "ERROR" "Invalid JSON in update center metadata"
                    rm -f "${temp_file}"
                    return 1
                fi
            else
                # If jq is not available, assume it's valid
                mv "${temp_file}" "${update_center_file}"
                log "SUCCESS" "Successfully fetched update center metadata (no JSON validation)"
                return 0
            fi
        else
            return 0
        fi
    else
        return 1
    fi
}

# Parse plugin list
parse_plugin_list() {
    local plugin_file="$1"
    local -n plugins_ref=$2
    
    log "INFO" "Parsing plugin list: ${plugin_file}"
    
    local line_count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_count=$((line_count + 1))
        
        # Skip comments and empty lines
        line="$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "${line}" || "${line}" =~ ^# ]]; then
            continue
        fi
        
        # Parse plugin:version format
        if [[ "${line}" =~ ^([^:]+):([^:]+)$ ]]; then
            local plugin_name="${BASH_REMATCH[1]}"
            local plugin_version="${BASH_REMATCH[2]}"
            plugins_ref["${plugin_name}"]="${plugin_version}"
            log "DEBUG" "Added plugin: ${plugin_name}:${plugin_version}"
        elif [[ "${line}" =~ ^([^:]+)$ ]]; then
            local plugin_name="${BASH_REMATCH[1]}"
            plugins_ref["${plugin_name}"]="latest"
            log "DEBUG" "Added plugin: ${plugin_name}:latest"
        else
            log "WARN" "Invalid plugin format at line ${line_count}, skipping: ${line}"
        fi
    done < "${plugin_file}"
    
    log "INFO" "Parsed ${#plugins_ref[@]} plugins from ${plugin_file}"
}

# Download plugin with metadata
download_plugin() {
    local plugin_name="$1"
    local plugin_version="$2"
    local plugin_dir="${CACHE_DIR}/plugins"
    local plugin_file="${plugin_dir}/${plugin_name}.hpi"
    local checksum_file="${CHECKSUMS_DIR}/${plugin_name}.sha256"
    
    # Skip if already exists and not forcing
    if [[ -f "${plugin_file}" && "${FORCE_DOWNLOAD}" != "true" ]]; then
        log "DEBUG" "Plugin already cached: ${plugin_name}"
        return 0
    fi
    
    log "INFO" "Downloading plugin: ${plugin_name}:${plugin_version}"
    
    # Construct download URLs
    local download_urls=()
    for base_url in "${PLUGIN_DOWNLOAD_URLS[@]}"; do
        if [[ "${plugin_version}" == "latest" ]]; then
            download_urls+=("${base_url}/${plugin_name}/latest/${plugin_name}.hpi")
        else
            download_urls+=("${base_url}/${plugin_name}/${plugin_version}/${plugin_name}.hpi")
        fi
    done
    
    # Add description and output file
    local urls=("${download_urls[@]}" "plugin ${plugin_name}:${plugin_version}" "${plugin_file}")
    
    if download_with_retry "${urls[@]}"; then
        # Verify file size
        if [[ -f "${plugin_file}" && "${DRY_RUN}" != "true" ]]; then
            local file_size
            file_size=$(stat -c%s "${plugin_file}" 2>/dev/null || stat -f%z "${plugin_file}" 2>/dev/null || echo 0)
            if [[ ${file_size} -lt 1000 ]]; then  # Less than 1KB is suspicious
                log "ERROR" "Downloaded plugin file is too small: ${plugin_name} (${file_size} bytes)"
                rm -f "${plugin_file}"
                return 1
            fi
            
            # Create checksum for future verification
            if [[ "${VERIFY_CHECKSUMS}" == "true" ]]; then
                sha256sum "${plugin_file}" | cut -d' ' -f1 > "${checksum_file}"
            fi
            
            log "SUCCESS" "Successfully downloaded plugin: ${plugin_name} (${file_size} bytes)"
        fi
        return 0
    else
        return 1
    fi
}

# Populate cache operation
operation_populate() {
    log "INFO" "Starting cache population operation"
    
    if [[ "${CLEAN_CACHE}" == "true" ]]; then
        operation_clean
    fi
    
    # Fetch update center metadata
    fetch_update_center
    
    # Parse plugin list
    declare -A plugins_to_cache
    parse_plugin_list "${PLUGIN_LIST}" plugins_to_cache
    
    if [[ ${#plugins_to_cache[@]} -eq 0 ]]; then
        error_exit "No plugins found in list: ${PLUGIN_LIST}"
    fi
    
    # Download plugins in parallel
    local success_count=0
    local failure_count=0
    local total_plugins=${#plugins_to_cache[@]}
    
    log "INFO" "Downloading ${total_plugins} plugins with ${PARALLEL_DOWNLOADS} parallel connections"
    
    # Create array of plugin download jobs
    local plugin_jobs=()
    for plugin_name in "${!plugins_to_cache[@]}"; do
        plugin_jobs+=("${plugin_name}:${plugins_to_cache[${plugin_name}]}")
    done
    
    # Process plugins in batches
    local batch_size="${PARALLEL_DOWNLOADS}"
    local batch_start=0
    
    while [[ ${batch_start} -lt ${total_plugins} ]]; do
        local batch_jobs=()
        local batch_end=$((batch_start + batch_size))
        
        if [[ ${batch_end} -gt ${total_plugins} ]]; then
            batch_end=${total_plugins}
        fi
        
        # Start batch downloads
        for ((i=batch_start; i<batch_end; i++)); do
            local job="${plugin_jobs[${i}]}"
            local plugin_name="${job%:*}"
            local plugin_version="${job#*:}"
            
            (
                if download_plugin "${plugin_name}" "${plugin_version}"; then
                    echo "SUCCESS:${plugin_name}"
                else
                    echo "FAILURE:${plugin_name}"
                fi
            ) &
            
            batch_jobs+=("$!")
        done
        
        # Wait for batch to complete
        for job_pid in "${batch_jobs[@]}"; do
            if wait "${job_pid}"; then
                success_count=$((success_count + 1))
            else
                failure_count=$((failure_count + 1))
            fi
        done
        
        log "INFO" "Batch progress: $((batch_end))/${total_plugins} plugins processed"
        batch_start=${batch_end}
    done
    
    log "SUCCESS" "Cache population completed: ${success_count} successful, ${failure_count} failed"
    
    if [[ ${failure_count} -gt 0 ]]; then
        log "WARN" "Some plugins failed to download. Check logs for details."
        return 1
    fi
    
    return 0
}

# Verify cache operation
operation_verify() {
    log "INFO" "Starting cache verification operation"
    
    local plugins_dir="${CACHE_DIR}/plugins"
    if [[ ! -d "${plugins_dir}" ]]; then
        log "WARN" "No plugins directory found: ${plugins_dir}"
        return 0
    fi
    
    local total_plugins=0
    local verified_plugins=0
    local failed_plugins=0
    
    # Count total plugins
    total_plugins=$(find "${plugins_dir}" -name "*.hpi" | wc -l)
    
    if [[ ${total_plugins} -eq 0 ]]; then
        log "WARN" "No plugins found in cache"
        return 0
    fi
    
    log "INFO" "Verifying ${total_plugins} cached plugins"
    
    # Verify each plugin
    while IFS= read -r -d '' plugin_file; do
        local plugin_name
        plugin_name="$(basename "${plugin_file}" .hpi)"
        local checksum_file="${CHECKSUMS_DIR}/${plugin_name}.sha256"
        
        # Check file integrity
        if [[ ! -f "${plugin_file}" ]]; then
            log "ERROR" "Plugin file missing: ${plugin_name}"
            failed_plugins=$((failed_plugins + 1))
            continue
        fi
        
        # Check file size
        local file_size
        if [[ "$(uname)" == "Darwin" ]]; then
            file_size=$(stat -f%z "${plugin_file}" 2>/dev/null || echo 0)
        else
            file_size=$(stat -c%s "${plugin_file}" 2>/dev/null || echo 0)
        fi
        
        if [[ ${file_size} -lt 1000 ]]; then
            log "ERROR" "Plugin file too small: ${plugin_name} (${file_size} bytes)"
            failed_plugins=$((failed_plugins + 1))
            continue
        fi
        
        # Verify checksum if available
        if [[ -f "${checksum_file}" && "${VERIFY_CHECKSUMS}" == "true" ]]; then
            local expected_checksum
            expected_checksum="$(cat "${checksum_file}" 2>/dev/null || echo "")"
            if [[ -n "${expected_checksum}" ]]; then
                if verify_checksum "${plugin_file}" "${expected_checksum}" "${checksum_file}"; then
                    log "DEBUG" "Plugin verified: ${plugin_name}"
                    verified_plugins=$((verified_plugins + 1))
                else
                    log "ERROR" "Plugin checksum failed: ${plugin_name}"
                    failed_plugins=$((failed_plugins + 1))
                fi
            else
                log "DEBUG" "Plugin verified (no checksum): ${plugin_name}"
                verified_plugins=$((verified_plugins + 1))
            fi
        else
            log "DEBUG" "Plugin verified (basic): ${plugin_name}"
            verified_plugins=$((verified_plugins + 1))
        fi
    done < <(find "${plugins_dir}" -name "*.hpi" -print0)
    
    log "SUCCESS" "Cache verification completed: ${verified_plugins} verified, ${failed_plugins} failed"
    
    if [[ ${failed_plugins} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# Clean cache operation
operation_clean() {
    log "INFO" "Starting cache cleanup operation"
    
    local plugins_dir="${CACHE_DIR}/plugins"
    local metadata_dir="${METADATA_DIR}"
    local checksums_dir="${CHECKSUMS_DIR}"
    
    # Calculate current cache size
    local current_size_bytes=0
    if [[ -d "${CACHE_DIR}" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            current_size_bytes=$(du -sk "${CACHE_DIR}" 2>/dev/null | cut -f1 || echo 0)
            current_size_bytes=$((current_size_bytes * 1024))  # Convert to bytes
        else
            current_size_bytes=$(du -sb "${CACHE_DIR}" 2>/dev/null | cut -f1 || echo 0)
        fi
    fi
    
    local current_size_mb=$((current_size_bytes / 1024 / 1024))
    local max_size_bytes=$((MAX_CACHE_SIZE_GB * 1024 * 1024 * 1024))
    
    log "INFO" "Current cache size: ${current_size_mb} MB (limit: ${MAX_CACHE_SIZE_GB} GB)"
    
    # Clean by age first
    local files_removed=0
    local bytes_freed=0
    
    if [[ -d "${plugins_dir}" ]]; then
        log "INFO" "Cleaning files older than ${MAX_CACHE_AGE_DAYS} days"
        
        while IFS= read -r -d '' old_file; do
            if [[ "${DRY_RUN}" == "true" ]]; then
                log "INFO" "[DRY RUN] Would remove old file: $(basename "${old_file}")"
            else
                local file_size
                if [[ "$(uname)" == "Darwin" ]]; then
                    file_size=$(stat -f%z "${old_file}" 2>/dev/null || echo 0)
                else
                    file_size=$(stat -c%s "${old_file}" 2>/dev/null || echo 0)
                fi
                
                rm -f "${old_file}"
                files_removed=$((files_removed + 1))
                bytes_freed=$((bytes_freed + file_size))
                log "DEBUG" "Removed old file: $(basename "${old_file}")"
            fi
        done < <(find "${plugins_dir}" -name "*.hpi" -mtime +"${MAX_CACHE_AGE_DAYS}" -print0 2>/dev/null || true)
    fi
    
    # Clean by size if still over limit
    current_size_bytes=$((current_size_bytes - bytes_freed))
    if [[ ${current_size_bytes} -gt ${max_size_bytes} && "${DRY_RUN}" != "true" ]]; then
        log "INFO" "Cache still over size limit, removing oldest files"
        
        # Remove oldest files until under limit
        while IFS= read -r -d '' old_file; do
            if [[ ${current_size_bytes} -le ${max_size_bytes} ]]; then
                break
            fi
            
            local file_size
            if [[ "$(uname)" == "Darwin" ]]; then
                file_size=$(stat -f%z "${old_file}" 2>/dev/null || echo 0)
            else
                file_size=$(stat -c%s "${old_file}" 2>/dev/null || echo 0)
            fi
            
            rm -f "${old_file}"
            files_removed=$((files_removed + 1))
            bytes_freed=$((bytes_freed + file_size))
            current_size_bytes=$((current_size_bytes - file_size))
            log "DEBUG" "Removed for size: $(basename "${old_file}")"
        done < <(find "${plugins_dir}" -name "*.hpi" -printf '%T@ %p\0' 2>/dev/null | sort -z -n | cut -d' ' -f2- -z || true)
    fi
    
    # Clean orphaned checksums
    if [[ -d "${checksums_dir}" ]]; then
        while IFS= read -r -d '' checksum_file; do
            local plugin_name
            plugin_name="$(basename "${checksum_file}" .sha256)"
            local plugin_file="${plugins_dir}/${plugin_name}.hpi"
            
            if [[ ! -f "${plugin_file}" ]]; then
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log "INFO" "[DRY RUN] Would remove orphaned checksum: $(basename "${checksum_file}")"
                else
                    rm -f "${checksum_file}"
                    log "DEBUG" "Removed orphaned checksum: $(basename "${checksum_file}")"
                fi
            fi
        done < <(find "${checksums_dir}" -name "*.sha256" -print0 2>/dev/null || true)
    fi
    
    # Clean old metadata
    if [[ -d "${metadata_dir}" ]]; then
        while IFS= read -r -d '' metadata_file; do
            if [[ "${DRY_RUN}" == "true" ]]; then
                log "INFO" "[DRY RUN] Would remove old metadata: $(basename "${metadata_file}")"
            else
                rm -f "${metadata_file}"
                log "DEBUG" "Removed old metadata: $(basename "${metadata_file}")"
            fi
        done < <(find "${metadata_dir}" -name "*.json" -mtime +1 -print0 2>/dev/null || true)
    fi
    
    local mb_freed=$((bytes_freed / 1024 / 1024))
    log "SUCCESS" "Cache cleanup completed: removed ${files_removed} files, freed ${mb_freed} MB"
    
    return 0
}

# Display cache statistics
operation_stats() {
    log "INFO" "Gathering cache statistics"
    
    if [[ ! -d "${CACHE_DIR}" ]]; then
        echo "Cache directory does not exist: ${CACHE_DIR}"
        return 0
    fi
    
    local plugins_dir="${CACHE_DIR}/plugins"
    local metadata_dir="${METADATA_DIR}"
    local checksums_dir="${CHECKSUMS_DIR}"
    local offline_dir="${OFFLINE_DIR}"
    
    # Count files and calculate sizes
    local plugin_count=0
    local plugin_size_bytes=0
    local metadata_count=0
    local metadata_size_bytes=0
    local checksum_count=0
    local total_size_bytes=0
    
    if [[ -d "${plugins_dir}" ]]; then
        plugin_count=$(find "${plugins_dir}" -name "*.hpi" 2>/dev/null | wc -l)
        if [[ "$(uname)" == "Darwin" ]]; then
            plugin_size_bytes=$(find "${plugins_dir}" -name "*.hpi" -exec stat -f%z {} + 2>/dev/null | awk '{sum += $1} END {print sum+0}')
        else
            plugin_size_bytes=$(find "${plugins_dir}" -name "*.hpi" -exec stat -c%s {} + 2>/dev/null | awk '{sum += $1} END {print sum+0}')
        fi
    fi
    
    if [[ -d "${metadata_dir}" ]]; then
        metadata_count=$(find "${metadata_dir}" -name "*.json" 2>/dev/null | wc -l)
        if [[ "$(uname)" == "Darwin" ]]; then
            metadata_size_bytes=$(find "${metadata_dir}" -name "*.json" -exec stat -f%z {} + 2>/dev/null | awk '{sum += $1} END {print sum+0}')
        else
            metadata_size_bytes=$(find "${metadata_dir}" -name "*.json" -exec stat -c%s {} + 2>/dev/null | awk '{sum += $1} END {print sum+0}')
        fi
    fi
    
    if [[ -d "${checksums_dir}" ]]; then
        checksum_count=$(find "${checksums_dir}" -name "*.sha256" 2>/dev/null | wc -l)
    fi
    
    # Calculate total cache size
    if [[ "$(uname)" == "Darwin" ]]; then
        total_size_bytes=$(du -sk "${CACHE_DIR}" 2>/dev/null | cut -f1 || echo 0)
        total_size_bytes=$((total_size_bytes * 1024))  # Convert to bytes
    else
        total_size_bytes=$(du -sb "${CACHE_DIR}" 2>/dev/null | cut -f1 || echo 0)
    fi
    
    # Convert to human-readable sizes
    local plugin_size_mb=$((plugin_size_bytes / 1024 / 1024))
    local metadata_size_kb=$((metadata_size_bytes / 1024))
    local total_size_mb=$((total_size_bytes / 1024 / 1024))
    
    # Find oldest and newest files
    local oldest_plugin="N/A"
    local newest_plugin="N/A"
    local oldest_date="N/A"
    local newest_date="N/A"
    
    if [[ -d "${plugins_dir}" && ${plugin_count} -gt 0 ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            oldest_plugin=$(find "${plugins_dir}" -name "*.hpi" -exec stat -f "%m %N" {} + 2>/dev/null | sort -n | head -1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "N/A")
            newest_plugin=$(find "${plugins_dir}" -name "*.hpi" -exec stat -f "%m %N" {} + 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "N/A")
            oldest_date=$(find "${plugins_dir}" -name "*.hpi" -exec stat -f "%Sm" -t "%Y-%m-%d %H:%M" {} + 2>/dev/null | sort | head -1 || echo "N/A")
            newest_date=$(find "${plugins_dir}" -name "*.hpi" -exec stat -f "%Sm" -t "%Y-%m-%d %H:%M" {} + 2>/dev/null | sort -r | head -1 || echo "N/A")
        else
            oldest_plugin=$(find "${plugins_dir}" -name "*.hpi" -printf '%T@ %f\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2 || echo "N/A")
            newest_plugin=$(find "${plugins_dir}" -name "*.hpi" -printf '%T@ %f\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2 || echo "N/A")
            oldest_date=$(find "${plugins_dir}" -name "*.hpi" -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort | head -1 || echo "N/A")
            newest_date=$(find "${plugins_dir}" -name "*.hpi" -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort -r | head -1 || echo "N/A")
        fi
    fi
    
    # Display statistics
    cat << EOF

${PURPLE}================================================================================
                        JENKINS PLUGIN CACHE STATISTICS
================================================================================${NC}

${GREEN}📁 Cache Location:${NC} ${CACHE_DIR}
${GREEN}🏷️ Cache Version:${NC} ${SCRIPT_VERSION}
${GREEN}📅 Generated:${NC} $(date '+%Y-%m-%d %H:%M:%S %Z')

${GREEN}📊 Storage Summary:${NC}
   Total Cache Size: ${total_size_mb} MB
   Plugin Storage:   ${plugin_size_mb} MB (${plugin_count} files)
   Metadata Storage: ${metadata_size_kb} KB (${metadata_count} files)
   Checksum Files:   ${checksum_count} files
   Size Limit:       ${MAX_CACHE_SIZE_GB} GB
   Age Limit:        ${MAX_CACHE_AGE_DAYS} days

${GREEN}📦 Plugin Cache Details:${NC}
   Total Plugins:    ${plugin_count}
   Oldest Plugin:    ${oldest_plugin}
   Oldest Date:      ${oldest_date}
   Newest Plugin:    ${newest_plugin}
   Newest Date:      ${newest_date}

${GREEN}🔧 Configuration:${NC}
   Parallel Downloads: ${PARALLEL_DOWNLOADS}
   Retry Count:        ${RETRY_COUNT}
   Retry Delay:        ${RETRY_DELAY}s
   Checksum Verification: ${VERIFY_CHECKSUMS}
   Max Cache Age:      ${MAX_CACHE_AGE_DAYS} days
   Max Cache Size:     ${MAX_CACHE_SIZE_GB} GB

${GREEN}📂 Directory Structure:${NC}
   Plugins:    ${plugins_dir}
   Metadata:   ${metadata_dir}
   Checksums:  ${checksums_dir}
   Offline:    ${offline_dir}

EOF

    # Health status
    local health_status="HEALTHY"
    local health_color="${GREEN}"
    local health_issues=()
    
    # Check for issues
    if [[ ${total_size_bytes} -gt $((MAX_CACHE_SIZE_GB * 1024 * 1024 * 1024)) ]]; then
        health_status="WARNING"
        health_color="${YELLOW}"
        health_issues+=("Cache size exceeds limit")
    fi
    
    if [[ ${plugin_count} -eq 0 ]]; then
        health_status="WARNING"
        health_color="${YELLOW}"
        health_issues+=("No plugins in cache")
    fi
    
    if [[ ${checksum_count} -lt $((plugin_count / 2)) ]]; then
        health_status="WARNING"
        health_color="${YELLOW}"
        health_issues+=("Missing checksums for some plugins")
    fi
    
    echo -e "${health_color}🏥 Cache Health:${NC} ${health_status}"
    
    if [[ ${#health_issues[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Issues Detected:${NC}"
        for issue in "${health_issues[@]}"; do
            echo "   • ${issue}"
        done
    fi
    
    echo -e "\n${PURPLE}================================================================================${NC}\n"
    
    return 0
}

# Export cache for offline use
operation_export() {
    log "INFO" "Starting cache export operation"
    
    local export_file="${OFFLINE_DIR}/jenkins-plugins-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    if [[ ! -d "${CACHE_DIR}/plugins" ]]; then
        error_exit "No plugins directory found for export: ${CACHE_DIR}/plugins"
    fi
    
    local plugin_count
    plugin_count=$(find "${CACHE_DIR}/plugins" -name "*.hpi" 2>/dev/null | wc -l)
    
    if [[ ${plugin_count} -eq 0 ]]; then
        error_exit "No plugins found for export"
    fi
    
    log "INFO" "Exporting ${plugin_count} plugins to: ${export_file}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY RUN] Would export ${plugin_count} plugins to: ${export_file}"
        return 0
    fi
    
    # Create export archive
    if tar -czf "${export_file}" -C "${CACHE_DIR}" plugins metadata checksums 2>/dev/null; then
        local export_size
        if [[ "$(uname)" == "Darwin" ]]; then
            export_size=$(stat -f%z "${export_file}" 2>/dev/null || echo 0)
        else
            export_size=$(stat -c%s "${export_file}" 2>/dev/null || echo 0)
        fi
        
        local export_size_mb=$((export_size / 1024 / 1024))
        
        # Generate export metadata
        cat > "${export_file}.info" << EOF
{
    "export_date": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
    "plugin_count": ${plugin_count},
    "export_size_bytes": ${export_size},
    "export_size_mb": ${export_size_mb},
    "cache_manager_version": "${SCRIPT_VERSION}",
    "export_file": "$(basename "${export_file}")"
}
EOF
        
        log "SUCCESS" "Cache exported successfully: ${export_file} (${export_size_mb} MB)"
        echo "Export file: ${export_file}"
        echo "Export info: ${export_file}.info"
        return 0
    else
        error_exit "Failed to create export archive"
    fi
}

# Import offline cache
operation_import() {
    log "INFO" "Starting cache import operation"
    
    if [[ -z "${PLUGIN_LIST}" ]]; then
        error_exit "Import file is required. Use --plugin-list FILE"
    fi
    
    if [[ ! -f "${PLUGIN_LIST}" ]]; then
        error_exit "Import file does not exist: ${PLUGIN_LIST}"
    fi
    
    log "INFO" "Importing cache from: ${PLUGIN_LIST}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY RUN] Would import cache from: ${PLUGIN_LIST}"
        return 0
    fi
    
    # Create backup of existing cache
    if [[ -d "${CACHE_DIR}/plugins" ]]; then
        local backup_dir="${CACHE_DIR}/backup-$(date +%Y%m%d-%H%M%S)"
        log "INFO" "Creating backup of existing cache: ${backup_dir}"
        cp -r "${CACHE_DIR}/plugins" "${backup_dir}-plugins" 2>/dev/null || true
        cp -r "${CACHE_DIR}/metadata" "${backup_dir}-metadata" 2>/dev/null || true
        cp -r "${CACHE_DIR}/checksums" "${backup_dir}-checksums" 2>/dev/null || true
    fi
    
    # Extract import file
    if tar -xzf "${PLUGIN_LIST}" -C "${CACHE_DIR}" 2>/dev/null; then
        local imported_count
        imported_count=$(find "${CACHE_DIR}/plugins" -name "*.hpi" 2>/dev/null | wc -l || echo 0)
        
        log "SUCCESS" "Cache imported successfully: ${imported_count} plugins"
        return 0
    else
        error_exit "Failed to import cache from: ${PLUGIN_LIST}"
    fi
}

# Sync cache with update center
operation_sync() {
    log "INFO" "Starting cache sync operation"
    
    # First update metadata
    fetch_update_center
    
    # Then verify existing plugins
    operation_verify
    
    log "SUCCESS" "Cache sync completed"
    return 0
}

# Main function
main() {
    log "INFO" "Starting Jenkins Plugin Cache Manager v${SCRIPT_VERSION}"
    
    # Parse and validate arguments
    parse_args "$@"
    validate_args
    
    # Acquire lock
    acquire_lock
    
    # Initialize cache
    init_cache
    
    # Execute operation
    case "${OPERATION}" in
        "populate")
            operation_populate
            ;;
        "verify")
            operation_verify
            ;;
        "clean")
            operation_clean
            ;;
        "stats")
            operation_stats
            ;;
        "sync")
            operation_sync
            ;;
        "export")
            operation_export
            ;;
        "import")
            operation_import
            ;;
        *)
            error_exit "Unknown operation: ${OPERATION}"
            ;;
    esac
    
    local exit_code=$?
    
    if [[ ${exit_code} -eq 0 ]]; then
        log "SUCCESS" "Operation '${OPERATION}' completed successfully"
    else
        log "ERROR" "Operation '${OPERATION}' failed with exit code ${exit_code}"
    fi
    
    return ${exit_code}
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi