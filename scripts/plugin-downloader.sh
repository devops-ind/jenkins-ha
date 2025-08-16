#!/bin/bash
# Plugin Downloader for Jenkins HA Infrastructure
# Downloads and validates Jenkins plugins for upgrade operations

set -euo pipefail

# Configuration
JENKINS_UPDATE_CENTER="https://updates.jenkins.io"
PLUGIN_TIMEOUT=300
MAX_RETRIES=3
RETRY_DELAY=5

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

# Display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --plugins PLUGINS           Comma-separated list of plugin names
    --strategy STRATEGY         Download strategy: latest, specific, compatible
    --output DIR                Output directory for downloaded plugins
    --team TEAM                 Team name for context
    --jenkins-version VERSION   Jenkins version for compatibility check
    --include-dependencies      Download plugin dependencies
    --verify-checksums          Verify plugin checksums
    --timeout SECONDS          Download timeout (default: 300)
    --help                      Show this help

STRATEGIES:
    latest                      Download latest available versions
    specific                    Download specific versions (requires version list)
    compatible                  Download versions compatible with Jenkins version

EXAMPLES:
    # Download latest versions of plugins
    $0 --plugins "workflow-aggregator,docker-workflow" --strategy latest --output /tmp/plugins
    
    # Download compatible versions for specific Jenkins version
    $0 --plugins "workflow-aggregator,docker-workflow" --strategy compatible \
       --jenkins-version 2.500.1 --output /tmp/plugins --include-dependencies

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --plugins)
                PLUGINS="$2"
                shift 2
                ;;
            --strategy)
                STRATEGY="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --team)
                TEAM_NAME="$2"
                shift 2
                ;;
            --jenkins-version)
                JENKINS_VERSION="$2"
                shift 2
                ;;
            --include-dependencies)
                INCLUDE_DEPENDENCIES=true
                shift
                ;;
            --verify-checksums)
                VERIFY_CHECKSUMS=true
                shift
                ;;
            --timeout)
                PLUGIN_TIMEOUT="$2"
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
    if [[ -z "${PLUGINS:-}" ]]; then
        error "Plugins list is required"
        usage
        exit 1
    fi
    
    if [[ -z "${OUTPUT_DIR:-}" ]]; then
        error "Output directory is required"
        usage
        exit 1
    fi
    
    STRATEGY="${STRATEGY:-latest}"
}

# Download update center metadata
download_update_center() {
    log "Downloading Jenkins update center metadata..."
    
    local update_center_url="${JENKINS_UPDATE_CENTER}/current/update-center.json"
    local metadata_file="${OUTPUT_DIR}/update-center.json"
    
    if ! curl -f -s --max-time "$PLUGIN_TIMEOUT" "$update_center_url" -o "$metadata_file"; then
        error "Failed to download update center metadata"
        return 1
    fi
    
    # Remove JSONP wrapper
    sed -i 's/^updateCenter.post(//; s/);$//' "$metadata_file" 2>/dev/null || true
    
    success "Update center metadata downloaded"
    echo "$metadata_file"
}

# Get plugin information from update center
get_plugin_info() {
    local plugin_name="$1"
    local metadata_file="$2"
    
    jq -r ".plugins[\"$plugin_name\"] // empty" "$metadata_file"
}

# Get compatible plugin version
get_compatible_version() {
    local plugin_name="$1"
    local jenkins_version="$2"
    local metadata_file="$3"
    
    local plugin_info=$(get_plugin_info "$plugin_name" "$metadata_file")
    
    if [[ -z "$plugin_info" ]]; then
        echo ""
        return 1
    fi
    
    # Check if current version is compatible
    local required_core=$(echo "$plugin_info" | jq -r '.requiredCore // "1.0"')
    
    if version_compare "$jenkins_version" ">="  "$required_core"; then
        echo "$plugin_info" | jq -r '.version'
        return 0
    fi
    
    # If not compatible, would need to search historical versions
    # For now, return empty (plugin not compatible)
    echo ""
    return 1
}

# Compare versions
version_compare() {
    local version1="$1"
    local operator="$2"
    local version2="$3"
    
    python3 -c "
import sys
from packaging import version

v1 = version.parse('$version1')
v2 = version.parse('$version2')

operators = {
    '==': lambda a, b: a == b,
    '!=': lambda a, b: a != b,
    '<': lambda a, b: a < b,
    '<=': lambda a, b: a <= b,
    '>': lambda a, b: a > b,
    '>=': lambda a, b: a >= b
}

if '$operator' in operators:
    result = operators['$operator'](v1, v2)
    sys.exit(0 if result else 1)
else:
    sys.exit(1)
"
}

# Download plugin with retry logic
download_plugin_with_retry() {
    local plugin_name="$1"
    local plugin_version="$2"
    local output_file="$3"
    local attempt=1
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        log "Downloading $plugin_name:$plugin_version (attempt $attempt/$MAX_RETRIES)..."
        
        local download_url="${JENKINS_UPDATE_CENTER}/download/plugins/${plugin_name}/${plugin_version}/${plugin_name}.hpi"
        
        if curl -f -L --max-time "$PLUGIN_TIMEOUT" "$download_url" -o "$output_file"; then
            success "Downloaded $plugin_name:$plugin_version"
            return 0
        fi
        
        if [[ $attempt -lt $MAX_RETRIES ]]; then
            warn "Download failed, retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
        
        ((attempt++))
    done
    
    error "Failed to download $plugin_name:$plugin_version after $MAX_RETRIES attempts"
    return 1
}

# Verify plugin checksum
verify_plugin_checksum() {
    local plugin_file="$1"
    local expected_checksum="$2"
    
    if [[ "${VERIFY_CHECKSUMS:-false}" != "true" ]]; then
        return 0
    fi
    
    if [[ -z "$expected_checksum" ]]; then
        warn "No checksum available for verification"
        return 0
    fi
    
    local actual_checksum=$(sha256sum "$plugin_file" | cut -d' ' -f1)
    
    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        success "Checksum verification passed"
        return 0
    else
        error "Checksum verification failed"
        error "Expected: $expected_checksum"
        error "Actual: $actual_checksum"
        return 1
    fi
}

# Download plugin dependencies
download_dependencies() {
    local plugin_name="$1"
    local metadata_file="$2"
    local downloaded_plugins="$3"  # Array name
    
    if [[ "${INCLUDE_DEPENDENCIES:-false}" != "true" ]]; then
        return 0
    fi
    
    log "Resolving dependencies for $plugin_name..."
    
    local plugin_info=$(get_plugin_info "$plugin_name" "$metadata_file")
    local dependencies=$(echo "$plugin_info" | jq -r '.dependencies[]?.name // empty')
    
    if [[ -z "$dependencies" ]]; then
        log "No dependencies found for $plugin_name"
        return 0
    fi
    
    while IFS= read -r dep_name; do
        if [[ -n "$dep_name" ]]; then
            # Check if already downloaded
            local -n downloaded_ref="$downloaded_plugins"
            if [[ " ${downloaded_ref[*]} " =~ " ${dep_name} " ]]; then
                log "Dependency $dep_name already downloaded"
                continue
            fi
            
            log "Processing dependency: $dep_name"
            
            # Determine version based on strategy
            local dep_version
            case "$STRATEGY" in
                "latest")
                    dep_version=$(echo "$plugin_info" | jq -r ".dependencies[] | select(.name==\"$dep_name\") | .version // empty")
                    if [[ -z "$dep_version" ]]; then
                        dep_version=$(get_plugin_info "$dep_name" "$metadata_file" | jq -r '.version')
                    fi
                    ;;
                "compatible")
                    dep_version=$(get_compatible_version "$dep_name" "${JENKINS_VERSION}" "$metadata_file")
                    ;;
                *)
                    dep_version=$(get_plugin_info "$dep_name" "$metadata_file" | jq -r '.version')
                    ;;
            esac
            
            if [[ -n "$dep_version" ]]; then
                local dep_file="${OUTPUT_DIR}/${dep_name}.hpi"
                if download_plugin_with_retry "$dep_name" "$dep_version" "$dep_file"; then
                    downloaded_ref+=("$dep_name")
                    
                    # Recursively download dependencies of dependencies
                    download_dependencies "$dep_name" "$metadata_file" "$downloaded_plugins"
                fi
            else
                warn "Could not determine version for dependency: $dep_name"
            fi
        fi
    done <<< "$dependencies"
}

# Generate plugin manifest
generate_plugin_manifest() {
    local manifest_file="${OUTPUT_DIR}/plugin-manifest.json"
    
    log "Generating plugin manifest..."
    
    local plugins_info="[]"
    
    for plugin_file in "${OUTPUT_DIR}"/*.hpi; do
        if [[ -f "$plugin_file" ]]; then
            local plugin_name=$(basename "$plugin_file" .hpi)
            local plugin_size=$(stat -f%z "$plugin_file" 2>/dev/null || stat -c%s "$plugin_file" 2>/dev/null || echo "0")
            local plugin_checksum=$(sha256sum "$plugin_file" | cut -d' ' -f1)
            local download_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            
            plugins_info=$(echo "$plugins_info" | jq --arg name "$plugin_name" \
                --arg size "$plugin_size" \
                --arg checksum "$plugin_checksum" \
                --arg downloaded "$download_time" \
                '. += [{"name": $name, "size": ($size | tonumber), "checksum": $checksum, "downloaded_at": $downloaded}]')
        fi
    done
    
    local manifest=$(cat <<EOF
{
    "download_summary": {
        "strategy": "$STRATEGY",
        "jenkins_version": "${JENKINS_VERSION:-unknown}",
        "team": "${TEAM_NAME:-unknown}",
        "download_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "total_plugins": $(echo "$plugins_info" | jq 'length'),
        "include_dependencies": ${INCLUDE_DEPENDENCIES:-false},
        "verify_checksums": ${VERIFY_CHECKSUMS:-false}
    },
    "plugins": $plugins_info
}
EOF
)
    
    echo "$manifest" > "$manifest_file"
    success "Plugin manifest generated: $manifest_file"
}

# Main download function
main() {
    parse_args "$@"
    
    log "Starting plugin download process"
    log "Strategy: $STRATEGY, Output: $OUTPUT_DIR"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Download update center metadata
    local metadata_file
    metadata_file=$(download_update_center) || exit 1
    
    # Parse plugins list
    IFS=',' read -ra PLUGIN_LIST <<< "$PLUGINS"
    local downloaded_plugins=()
    local failed_plugins=()
    
    # Download each plugin
    for plugin_name in "${PLUGIN_LIST[@]}"; do
        log "Processing plugin: $plugin_name"
        
        # Determine version based on strategy
        local plugin_version
        case "$STRATEGY" in
            "latest")
                plugin_version=$(get_plugin_info "$plugin_name" "$metadata_file" | jq -r '.version // empty')
                ;;
            "compatible")
                if [[ -z "${JENKINS_VERSION:-}" ]]; then
                    error "Jenkins version required for compatible strategy"
                    exit 1
                fi
                plugin_version=$(get_compatible_version "$plugin_name" "$JENKINS_VERSION" "$metadata_file")
                ;;
            "specific")
                # Would need version mapping for specific strategy
                plugin_version=$(get_plugin_info "$plugin_name" "$metadata_file" | jq -r '.version // empty')
                ;;
            *)
                error "Unknown strategy: $STRATEGY"
                exit 1
                ;;
        esac
        
        if [[ -z "$plugin_version" ]]; then
            error "Could not determine version for plugin: $plugin_name"
            failed_plugins+=("$plugin_name")
            continue
        fi
        
        log "Selected version $plugin_version for $plugin_name"
        
        # Download plugin
        local plugin_file="${OUTPUT_DIR}/${plugin_name}.hpi"
        if download_plugin_with_retry "$plugin_name" "$plugin_version" "$plugin_file"; then
            # Verify checksum if available
            local expected_checksum=$(get_plugin_info "$plugin_name" "$metadata_file" | jq -r '.sha256 // empty')
            if verify_plugin_checksum "$plugin_file" "$expected_checksum"; then
                downloaded_plugins+=("$plugin_name")
                
                # Download dependencies
                download_dependencies "$plugin_name" "$metadata_file" downloaded_plugins
            else
                error "Checksum verification failed for $plugin_name"
                rm -f "$plugin_file"
                failed_plugins+=("$plugin_name")
            fi
        else
            failed_plugins+=("$plugin_name")
        fi
    done
    
    # Generate manifest
    generate_plugin_manifest
    
    # Report results
    log "Download completed"
    success "Successfully downloaded ${#downloaded_plugins[@]} plugins: ${downloaded_plugins[*]}"
    
    if [[ ${#failed_plugins[@]} -gt 0 ]]; then
        error "Failed to download ${#failed_plugins[@]} plugins: ${failed_plugins[*]}"
        exit 1
    fi
    
    success "All plugins downloaded successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi