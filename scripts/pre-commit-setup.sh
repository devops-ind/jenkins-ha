#!/bin/bash
# Pre-commit Hooks Setup Script for Jenkins HA Infrastructure
# Installs and configures pre-commit hooks for local development

set -euo pipefail

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$PROJECT_ROOT/.venv"
FORCE_REINSTALL=false
SKIP_VENV=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Pre-commit Hooks Setup Script for Jenkins HA Infrastructure

OPTIONS:
    --force              Force reinstallation of all components
    --skip-venv          Skip virtual environment creation
    --help               Show this help message

DESCRIPTION:
    This script sets up pre-commit hooks for local development, including:
    - Python virtual environment with testing dependencies
    - Pre-commit hook installation and configuration
    - Ansible and security tooling setup
    - Initial validation run

EXAMPLES:
    $0                   # Standard setup
    $0 --force           # Force reinstall everything
    $0 --skip-venv       # Use system Python (not recommended)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        --skip-venv)
            SKIP_VENV=true
            shift
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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if we're in the project root
    if [[ ! -f "$PROJECT_ROOT/.pre-commit-config.yaml" ]]; then
        error "Not in Jenkins HA project root directory"
        error "Expected to find .pre-commit-config.yaml in: $PROJECT_ROOT"
        exit 1
    fi
    
    # Check for Python 3
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is required but not installed"
        exit 1
    fi
    
    # Check for git
    if ! command -v git &> /dev/null; then
        error "Git is required but not installed"
        exit 1
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir &> /dev/null; then
        error "Not in a git repository"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Setup Python virtual environment
setup_virtual_environment() {
    if [[ "$SKIP_VENV" == "true" ]]; then
        warn "Skipping virtual environment setup"
        return
    fi
    
    log "Setting up Python virtual environment..."
    
    # Remove existing venv if force reinstall
    if [[ "$FORCE_REINSTALL" == "true" && -d "$VENV_DIR" ]]; then
        warn "Removing existing virtual environment"
        rm -rf "$VENV_DIR"
    fi
    
    # Create virtual environment
    if [[ ! -d "$VENV_DIR" ]]; then
        log "Creating virtual environment at $VENV_DIR"
        python3 -m venv "$VENV_DIR"
    else
        log "Virtual environment already exists"
    fi
    
    # Activate virtual environment
    source "$VENV_DIR/bin/activate"
    
    # Upgrade pip
    log "Upgrading pip..."
    pip install --upgrade pip
    
    success "Virtual environment ready"
}

# Install Python dependencies
install_dependencies() {
    log "Installing Python dependencies..."
    
    # Activate venv if not skipped
    if [[ "$SKIP_VENV" == "false" && -d "$VENV_DIR" ]]; then
        source "$VENV_DIR/bin/activate"
    fi
    
    # Install base requirements
    if [[ -f "$PROJECT_ROOT/requirements.txt" ]]; then
        log "Installing base requirements..."
        pip install -r "$PROJECT_ROOT/requirements.txt"
    fi
    
    # Install test requirements
    if [[ -f "$PROJECT_ROOT/tests/blue-green/requirements.txt" ]]; then
        log "Installing test requirements..."
        pip install -r "$PROJECT_ROOT/tests/blue-green/requirements.txt"
    fi
    
    # Install pre-commit
    log "Installing pre-commit..."
    pip install pre-commit
    
    # Install additional linting tools
    log "Installing additional development tools..."
    pip install \
        black \
        isort \
        flake8 \
        mypy \
        bandit \
        safety \
        ansible-lint \
        yamllint
    
    success "Dependencies installed"
}

# Install Ansible collections
install_ansible_collections() {
    log "Installing Ansible collections..."
    
    if [[ -f "$PROJECT_ROOT/collections/requirements.yml" ]]; then
        ansible-galaxy collection install -r "$PROJECT_ROOT/collections/requirements.yml"
        success "Ansible collections installed"
    else
        warn "Ansible collections requirements file not found"
    fi
}

# Setup pre-commit hooks
setup_precommit_hooks() {
    log "Setting up pre-commit hooks..."
    
    # Change to project directory
    cd "$PROJECT_ROOT"
    
    # Install pre-commit hooks
    if [[ "$FORCE_REINSTALL" == "true" ]]; then
        log "Uninstalling existing pre-commit hooks..."
        pre-commit uninstall || true
    fi
    
    log "Installing pre-commit hooks..."
    pre-commit install
    
    # Install commit-msg hook for conventional commits
    pre-commit install --hook-type commit-msg || warn "Commit-msg hook installation failed"
    
    success "Pre-commit hooks installed"
}

# Run initial validation
run_initial_validation() {
    log "Running initial validation on all files..."
    
    cd "$PROJECT_ROOT"
    
    # Run pre-commit on all files
    log "Running pre-commit checks..."
    if pre-commit run --all-files; then
        success "All pre-commit checks passed"
    else
        warn "Some pre-commit checks failed - this is normal for first run"
        warn "The hooks will run automatically on future commits"
    fi
}

# Generate activation script
generate_activation_script() {
    if [[ "$SKIP_VENV" == "true" ]]; then
        return
    fi
    
    log "Generating environment activation script..."
    
    cat > "$PROJECT_ROOT/activate-dev-env.sh" << 'EOF'
#!/bin/bash
# Development Environment Activation Script
# Source this file to activate the development environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

if [[ -d "$VENV_DIR" ]]; then
    source "$VENV_DIR/bin/activate"
    echo "✅ Development environment activated"
    echo "📝 Pre-commit hooks are installed and ready"
    echo "🔧 Run 'make test' to run full test suite"
    echo "🚀 Run 'make local' to deploy locally"
else
    echo "❌ Virtual environment not found at $VENV_DIR"
    echo "💡 Run './scripts/pre-commit-setup.sh' to set up the environment"
fi
EOF
    
    chmod +x "$PROJECT_ROOT/activate-dev-env.sh"
    success "Activation script created: ./activate-dev-env.sh"
}

# Display completion information
display_completion_info() {
    success "Pre-commit setup completed successfully!"
    
    echo
    echo -e "${BLUE}🎉 Setup Complete!${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    
    if [[ "$SKIP_VENV" == "false" ]]; then
        echo -e "  1. ${GREEN}Activate development environment:${NC}"
        echo -e "     ${BLUE}source ./activate-dev-env.sh${NC}"
        echo
    fi
    
    echo -e "  2. ${GREEN}Make changes to your code${NC}"
    echo -e "     Pre-commit hooks will run automatically on commit"
    echo
    echo -e "  3. ${GREEN}Run tests manually:${NC}"
    echo -e "     ${BLUE}make test${NC}                 # Run all tests"
    echo -e "     ${BLUE}pre-commit run --all-files${NC} # Run pre-commit on all files"
    echo
    echo -e "  4. ${GREEN}Deploy locally:${NC}"
    echo -e "     ${BLUE}make local${NC}                # Deploy Jenkins HA locally"
    echo
    echo -e "${YELLOW}Installed hooks:${NC}"
    echo -e "  • Python code formatting (black, isort)"
    echo -e "  • Python linting (flake8, mypy)"
    echo -e "  • Security scanning (bandit)"
    echo -e "  • Ansible validation (ansible-lint)"
    echo -e "  • YAML/JSON validation"
    echo -e "  • Shell script validation (shellcheck)"
    echo -e "  • Custom security patterns"
    echo -e "  • Jinja2 template validation"
    echo -e "  • Docker security checks"
    echo
    echo -e "${GREEN}Happy coding! 🚀${NC}"
}

# Main execution
main() {
    log "Starting pre-commit setup for Jenkins HA Infrastructure"
    
    check_prerequisites
    setup_virtual_environment
    install_dependencies
    install_ansible_collections
    setup_precommit_hooks
    run_initial_validation
    generate_activation_script
    display_completion_info
}

# Run main function
main "$@"