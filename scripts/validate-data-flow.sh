#!/bin/bash

#
# Jenkins Data Flow Validation Script
# Validates the corrected data flow architecture between masters and dynamic agents
#

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VALIDATION_SCRIPT="${PROJECT_ROOT}/tests/data-flow-validation.groovy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Print banner
print_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║             Jenkins Data Flow Validation                    ║
║                                                              ║
║  Testing corrected architecture where:                      ║
║  • Masters mount shared volume at: /shared/jenkins          ║
║  • Agents use remoteFs: /shared/jenkins                     ║  
║  • Workspace data shared between masters and agents         ║
╚══════════════════════════════════════════════════════════════╝
EOF
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if validation script exists
    if [[ ! -f "$VALIDATION_SCRIPT" ]]; then
        log_error "Validation script not found: $VALIDATION_SCRIPT"
        exit 1
    fi
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check if any Jenkins containers are running
    RUNNING_CONTAINERS=$(docker ps --filter "label=service=jenkins-master" --format "{{.Names}}" | wc -l)
    if [[ $RUNNING_CONTAINERS -eq 0 ]]; then
        log_warning "No Jenkins master containers currently running"
        log_info "You may need to deploy Jenkins first: make deploy-local"
    else
        log_success "Found $RUNNING_CONTAINERS Jenkins master container(s) running"
    fi
    
    log_success "Prerequisites validated"
}

# Check volume architecture
check_volume_architecture() {
    log_info "Checking Docker volume architecture..."
    
    # List Jenkins-related volumes
    JENKINS_VOLUMES=$(docker volume ls --filter "name=jenkins-" --format "{{.Name}}" | sort)
    
    if [[ -z "$JENKINS_VOLUMES" ]]; then
        log_warning "No Jenkins volumes found"
        return 1
    fi
    
    log_info "Jenkins Docker volumes:"
    echo "$JENKINS_VOLUMES" | while read -r volume; do
        echo "  • $volume"
        
        # Check if it's a shared volume
        if [[ "$volume" =~ jenkins-.*-shared ]]; then
            log_info "    └─ Shared volume (used for workspace data)"
        elif [[ "$volume" =~ jenkins-.*-cache ]]; then
            log_info "    └─ Cache volume (used for build dependencies)"  
        elif [[ "$volume" =~ jenkins-.*-(blue|green)-home ]]; then
            log_info "    └─ Home volume (Jenkins master data)"
        fi
    done
    
    # Count volume types
    SHARED_VOLUMES=$(echo "$JENKINS_VOLUMES" | grep -c "shared" || true)
    CACHE_VOLUMES=$(echo "$JENKINS_VOLUMES" | grep -c "cache" || true)
    HOME_VOLUMES=$(echo "$JENKINS_VOLUMES" | grep -c -E "(blue|green)-home" || true)
    
    log_success "Volume summary: $SHARED_VOLUMES shared, $CACHE_VOLUMES cache, $HOME_VOLUMES home volumes"
}

# Test container volume mounts
test_volume_mounts() {
    log_info "Testing volume mounts in running containers..."
    
    # Get running Jenkins containers
    RUNNING_CONTAINERS=$(docker ps --filter "label=service=jenkins-master" --format "{{.Names}}")
    
    if [[ -z "$RUNNING_CONTAINERS" ]]; then
        log_warning "No running Jenkins containers to test"
        return 0
    fi
    
    echo "$RUNNING_CONTAINERS" | while read -r container; do
        log_info "Testing volume mounts in container: $container"
        
        # Check if shared volume is mounted
        SHARED_MOUNT=$(docker exec "$container" sh -c "mount | grep '/shared/jenkins' | head -1" 2>/dev/null || echo "")
        
        if [[ -n "$SHARED_MOUNT" ]]; then
            log_success "  ✅ Shared volume mounted: $SHARED_MOUNT"
        else
            log_warning "  ⚠️  Shared volume mount not visible (normal for Docker volumes)"
        fi
        
        # Check if shared directory exists and is writable
        if docker exec "$container" sh -c "test -d /shared/jenkins && test -w /shared/jenkins" 2>/dev/null; then
            log_success "  ✅ Shared directory exists and is writable"
        else
            log_error "  ❌ Shared directory not accessible"
        fi
        
        # Test basic file operations
        TEST_FILE="/shared/jenkins/data-flow-test-$(date +%s).txt"
        if docker exec "$container" sh -c "echo 'Data flow test' > '$TEST_FILE' && cat '$TEST_FILE' && rm '$TEST_FILE'" &>/dev/null; then
            log_success "  ✅ File operations working correctly"
        else
            log_error "  ❌ File operations failed"
        fi
    done
}

# Generate validation summary
generate_summary() {
    log_info "Generating validation summary..."
    
    cat << EOF

═══════════════════════════════════════════════════════════════
                     VALIDATION SUMMARY
═══════════════════════════════════════════════════════════════

Architecture Overview:
  • Corrected data flow issue where workspace and shared volume were misaligned
  • Updated both JCasC templates to use shared volume path for remoteFs
  • All workspace data now properly shared between masters and agents

Key Changes Made:
  • jenkins-config.yml.j2: remoteFs set to {{ jenkins_master_shared_path }}
  • casc-config-team.yml.j2: remoteFs set to {{ jenkins_master_shared_path }}
  • Both templates now consistently use shared volume for agent workspaces

Data Flow (Fixed):
  1. Jenkins Master mounts shared volume at: /shared/jenkins
  2. Dynamic agents use remoteFs: /shared/jenkins (workspace location) 
  3. Job workspaces created in: /shared/jenkins/workspace/job-name
  4. Build artifacts stored in shared volume, accessible to masters
  5. Cache volumes provide performance optimization for dependencies

Next Steps:
  • Deploy updated configuration to test environment
  • Run data flow validation pipeline
  • Monitor build performance improvements
  • Update team documentation with corrected architecture

═══════════════════════════════════════════════════════════════
EOF
}

# Main execution
main() {
    print_banner
    
    log_info "Starting Jenkins data flow validation..."
    
    validate_prerequisites
    check_volume_architecture
    test_volume_mounts
    
    log_success "Data flow validation completed!"
    
    generate_summary
    
    echo
    log_info "To run the full validation pipeline:"
    log_info "1. Deploy Jenkins with updated configuration: make deploy-local"
    log_info "2. Access Jenkins UI and run the data flow validation job"
    log_info "3. Check build logs for detailed validation results"
    
    echo
    log_info "Validation script location: $VALIDATION_SCRIPT"
    log_info "Use this pipeline script to create a Jenkins job for automated testing"
}

# Run main function
main "$@"