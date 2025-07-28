#!/bin/bash
set -euo pipefail

# Local DevContainer Deployment Script
# This script deploys Jenkins HA infrastructure locally in devcontainers

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"

# Default values
INVENTORY="local"
PLAYBOOK="deploy-local.yml"
TAGS=""
VERBOSE=""
DRY_RUN=""
SKIP_TAGS=""

# Help function
show_help() {
    cat << EOF
🚀 Jenkins HA Local DevContainer Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output (-vv for more verbose)
    -d, --dry-run          Perform a dry run (--check mode)
    -t, --tags TAGS        Run only tasks with specified tags
    -s, --skip-tags TAGS   Skip tasks with specified tags
    -i, --inventory INV    Use specific inventory (default: local)
    -p, --playbook BOOK    Use specific playbook (default: deploy-local.yml)

EXAMPLES:
    # Full local deployment
    $0

    # Deploy only Jenkins infrastructure
    $0 --tags jenkins,infrastructure

    # Deploy with verbose output
    $0 --verbose

    # Dry run to see what would be deployed
    $0 --dry-run

    # Deploy only monitoring stack
    $0 --tags monitoring,prometheus,grafana

    # Skip backup configuration
    $0 --skip-tags backup

COMMON TAG COMBINATIONS:
    # Core infrastructure only
    --tags common,docker,jenkins,infrastructure

    # Full stack with monitoring
    --tags common,docker,jenkins,infrastructure,monitoring

    # Images and registry
    --tags images,harbor,registry

    # Everything except backup
    --skip-tags backup

SERVICE URLS (after deployment):
    • Jenkins:    http://localhost:8080
    • Grafana:    http://localhost:3000
    • Prometheus: http://localhost:9090  
    • Harbor:     http://localhost:8082

DEFAULT CREDENTIALS:
    • Jenkins:    admin / admin123
    • Grafana:    admin / admin
    • Harbor:     admin / Harbor12345

EOF
}

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

log_header() {
    echo -e "${PURPLE}[DEPLOY]${NC} $1"
}

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if we're in a devcontainer or have Docker available
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not available. Please ensure Docker is installed and running."
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "Ansible is not installed. Please install Ansible."
        exit 1
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "$ANSIBLE_DIR/site.yml" ]]; then
        log_error "Cannot find ansible directory or site.yml. Please run from project root."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                if [[ "$VERBOSE" == "-v" ]]; then
                    VERBOSE="-vv"
                else
                    VERBOSE="-v"
                fi
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="--check"
                shift
                ;;
            -t|--tags)
                TAGS="--tags $2"
                shift 2
                ;;
            -s|--skip-tags)
                SKIP_TAGS="--skip-tags $2"
                shift 2
                ;;
            -i|--inventory)
                INVENTORY="$2"
                shift 2
                ;;
            -p|--playbook)
                PLAYBOOK="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main deployment function
deploy() {
    log_header "Starting Jenkins HA Local Deployment"
    
    # Change to ansible directory
    cd "$ANSIBLE_DIR"
    
    # Build ansible-playbook command
    local cmd="ansible-playbook"
    cmd="$cmd -i inventories/${INVENTORY}/hosts.yml"
    cmd="$cmd $PLAYBOOK"
    
    if [[ -n "$VERBOSE" ]]; then
        cmd="$cmd $VERBOSE"
    fi
    
    if [[ -n "$DRY_RUN" ]]; then
        cmd="$cmd $DRY_RUN"
        log_info "Running in dry-run mode (no changes will be made)"
    fi
    
    if [[ -n "$TAGS" ]]; then
        cmd="$cmd $TAGS"
        log_info "Running with tags: ${TAGS#--tags }"
    fi
    
    if [[ -n "$SKIP_TAGS" ]]; then
        cmd="$cmd $SKIP_TAGS"
        log_info "Skipping tags: ${SKIP_TAGS#--skip-tags }"
    fi
    
    # Display command that will be executed
    log_info "Executing: $cmd"
    echo
    
    # Execute the deployment
    if eval "$cmd"; then
        log_success "Deployment completed successfully!"
        
        if [[ -z "$DRY_RUN" ]]; then
            echo
            log_header "🎉 Local Jenkins HA Environment Ready!"
            echo -e "${CYAN}Access URLs:${NC}"
            echo -e "  • Jenkins:    ${GREEN}http://localhost:8080${NC}"
            echo -e "  • Grafana:    ${GREEN}http://localhost:3000${NC}"
            echo -e "  • Prometheus: ${GREEN}http://localhost:9090${NC}"
            echo -e "  • Harbor:     ${GREEN}http://localhost:8082${NC}"
            echo
            echo -e "${CYAN}Default Credentials:${NC}"
            echo -e "  • Jenkins:    ${YELLOW}admin${NC} / ${YELLOW}admin123${NC}"
            echo -e "  • Grafana:    ${YELLOW}admin${NC} / ${YELLOW}admin${NC}"
            echo -e "  • Harbor:     ${YELLOW}admin${NC} / ${YELLOW}Harbor12345${NC}"
            echo
            echo -e "${CYAN}Useful Commands:${NC}"
            echo -e "  • Check containers: ${GREEN}docker ps${NC}"
            echo -e "  • View logs:        ${GREEN}docker logs <container-name>${NC}"
            echo -e "  • Stop all:         ${GREEN}docker stop \$(docker ps -q)${NC}"
            echo -e "  • Cleanup:          ${GREEN}docker system prune -f${NC}"
        fi
    else
        log_error "Deployment failed!"
        exit 1
    fi
}

# Cleanup function
cleanup() {
    log_info "Performing cleanup if needed..."
    # Add any cleanup logic here
}

# Trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    # Show banner
    echo -e "${PURPLE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                 Jenkins HA Local Deployment                  ║"
    echo "║              DevContainer Development Environment             ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    parse_args "$@"
    check_prerequisites
    deploy
}

# Run main function with all arguments
main "$@"