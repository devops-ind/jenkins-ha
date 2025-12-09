#!/bin/bash
# Security Tool Installer for Jenkins HA Infrastructure
# Installs and configures security scanning tools

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

# Detect OS and package manager
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            OS="ubuntu"
            PKG_MANAGER="apt-get"
        elif command -v yum &> /dev/null; then
            OS="rhel"
            PKG_MANAGER="yum"
        elif command -v pacman &> /dev/null; then
            OS="arch"
            PKG_MANAGER="pacman"
        else
            OS="linux"
            PKG_MANAGER="unknown"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        PKG_MANAGER="brew"
    else
        OS="unknown"
        PKG_MANAGER="unknown"
    fi
}

# Install TruffleHog
install_trufflehog() {
    log "Installing TruffleHog..."
    
    if command -v trufflehog &> /dev/null; then
        success "TruffleHog already installed"
        return 0
    fi
    
    case "$OS" in
        "ubuntu"|"rhel"|"linux")
            curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin
            ;;
        "macos")
            if command -v brew &> /dev/null; then
                brew install trufflesecurity/trufflehog/trufflehog
            else
                curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin
            fi
            ;;
        *)
            curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin
            ;;
    esac
    
    if command -v trufflehog &> /dev/null; then
        success "TruffleHog installed successfully"
    else
        error "Failed to install TruffleHog"
        return 1
    fi
}

# Install Trivy
install_trivy() {
    log "Installing Trivy..."
    
    if command -v trivy &> /dev/null; then
        success "Trivy already installed"
        return 0
    fi
    
    case "$OS" in
        "ubuntu")
            sudo apt-get update
            sudo apt-get install -y wget apt-transport-https gnupg lsb-release
            wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
            echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
            sudo apt-get update
            sudo apt-get install -y trivy
            ;;
        "rhel")
            sudo yum install -y wget
            wget https://github.com/aquasecurity/trivy/releases/latest/download/trivy_Linux-64bit.rpm
            sudo rpm -ivh trivy_Linux-64bit.rpm
            ;;
        "macos")
            if command -v brew &> /dev/null; then
                brew install trivy
            else
                curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
            fi
            ;;
        *)
            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
            ;;
    esac
    
    if command -v trivy &> /dev/null; then
        success "Trivy installed successfully"
    else
        error "Failed to install Trivy"
        return 1
    fi
}

# Install OWASP Dependency-Check
install_dependency_check() {
    log "Installing OWASP Dependency-Check..."
    
    if command -v dependency-check.sh &> /dev/null; then
        success "OWASP Dependency-Check already installed"
        return 0
    fi
    
    # Check Java availability
    if ! command -v java &> /dev/null; then
        warn "Java is required for OWASP Dependency-Check"
        case "$OS" in
            "ubuntu")
                log "Installing OpenJDK..."
                sudo apt-get update
                sudo apt-get install -y openjdk-11-jdk
                ;;
            "rhel")
                log "Installing OpenJDK..."
                sudo yum install -y java-11-openjdk-devel
                ;;
            "macos")
                if command -v brew &> /dev/null; then
                    log "Installing OpenJDK..."
                    brew install openjdk@11
                else
                    warn "Please install Java manually and re-run this script"
                    return 1
                fi
                ;;
            *)
                warn "Please install Java manually and re-run this script"
                return 1
                ;;
        esac
    fi
    
    # Download and install Dependency-Check
    local version="8.4.3"  # Update this to latest version
    local install_dir="/opt/dependency-check"
    
    log "Downloading OWASP Dependency-Check v${version}..."
    sudo mkdir -p "$install_dir"
    cd /tmp
    wget "https://github.com/jeremylong/DependencyCheck/releases/download/v${version}/dependency-check-${version}-release.zip"
    unzip "dependency-check-${version}-release.zip"
    sudo mv dependency-check/* "$install_dir/"
    sudo chmod +x "$install_dir/bin/dependency-check.sh"
    
    # Create symlink
    sudo ln -sf "$install_dir/bin/dependency-check.sh" /usr/local/bin/dependency-check.sh
    
    # Cleanup
    rm -rf dependency-check*
    
    if command -v dependency-check.sh &> /dev/null; then
        success "OWASP Dependency-Check installed successfully"
    else
        error "Failed to install OWASP Dependency-Check"
        return 1
    fi
}

# Install Snyk CLI (optional)
install_snyk() {
    log "Installing Snyk CLI..."
    
    if command -v snyk &> /dev/null; then
        success "Snyk CLI already installed"
        return 0
    fi
    
    if ! command -v npm &> /dev/null; then
        warn "npm is required for Snyk CLI installation"
        case "$OS" in
            "ubuntu")
                log "Installing Node.js and npm..."
                curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
                sudo apt-get install -y nodejs
                ;;
            "rhel")
                log "Installing Node.js and npm..."
                curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
                sudo yum install -y nodejs
                ;;
            "macos")
                if command -v brew &> /dev/null; then
                    log "Installing Node.js..."
                    brew install node
                else
                    warn "Please install Node.js manually for Snyk CLI"
                    return 1
                fi
                ;;
            *)
                warn "Please install Node.js manually for Snyk CLI"
                return 1
                ;;
        esac
    fi
    
    npm install -g snyk
    
    if command -v snyk &> /dev/null; then
        success "Snyk CLI installed successfully"
        warn "Run 'snyk auth' to authenticate before first use"
    else
        error "Failed to install Snyk CLI"
        return 1
    fi
}

# Install Python security tools
install_python_tools() {
    log "Installing Python security tools..."
    
    local tools=("semgrep" "checkov" "bandit" "safety" "detect-secrets")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            success "$tool already installed"
        else
            log "Installing $tool..."
            pip install "$tool" || warn "Failed to install $tool"
        fi
    done
}

# Install system tools
install_system_tools() {
    log "Installing system security tools..."
    
    case "$OS" in
        "ubuntu")
            sudo apt-get update
            sudo apt-get install -y \
                shellcheck \
                jq \
                curl \
                wget \
                unzip \
                git
            ;;
        "rhel")
            sudo yum install -y \
                ShellCheck \
                jq \
                curl \
                wget \
                unzip \
                git
            ;;
        "macos")
            if command -v brew &> /dev/null; then
                brew install \
                    shellcheck \
                    jq
            fi
            ;;
    esac
}

# Verify installations
verify_installations() {
    log "Verifying tool installations..."
    
    local tools=(
        "trufflehog:TruffleHog"
        "trivy:Trivy"
        "dependency-check.sh:OWASP Dependency-Check"
        "semgrep:Semgrep"
        "checkov:Checkov"
        "bandit:Bandit"
        "safety:Safety"
        "shellcheck:ShellCheck"
        "jq:jq"
    )
    
    local installed_count=0
    local total_count=${#tools[@]}
    
    echo ""
    echo "=== Installation Verification ==="
    
    for tool_info in "${tools[@]}"; do
        IFS=':' read -r tool_cmd tool_name <<< "$tool_info"
        
        if command -v "$tool_cmd" &> /dev/null; then
            local version
            case "$tool_cmd" in
                "trufflehog")
                    version=$($tool_cmd --version 2>&1 | head -n1 || echo "unknown")
                    ;;
                "trivy")
                    version=$($tool_cmd --version 2>&1 | grep Version || echo "unknown")
                    ;;
                "dependency-check.sh")
                    version=$($tool_cmd --version 2>&1 | head -n1 || echo "unknown")
                    ;;
                *)
                    version=$($tool_cmd --version 2>&1 | head -n1 || echo "unknown")
                    ;;
            esac
            echo "✅ $tool_name: $version"
            installed_count=$((installed_count + 1))
        else
            echo "❌ $tool_name: Not installed"
        fi
    done
    
    echo ""
    echo "Installed: $installed_count/$total_count tools"
    
    if [[ $installed_count -eq $total_count ]]; then
        success "All security tools installed successfully!"
    else
        warn "Some tools failed to install - check logs above"
    fi
}

# Generate configuration files
generate_configs() {
    log "Generating security tool configurations..."
    
    # Create .trivyignore file
    cat > .trivyignore << 'EOF'
# Trivy ignore patterns
CVE-2019-*
LOW
UNKNOWN
EOF
    
    # Create .semgrepignore file
    cat > .semgrepignore << 'EOF'
# Semgrep ignore patterns
.git/
node_modules/
.venv/
__pycache__/
*.pyc
EOF
    
    success "Configuration files generated"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Security Tool Installer for Jenkins HA Infrastructure

OPTIONS:
    --all              Install all security tools (default)
    --essential        Install only essential tools (TruffleHog, Trivy, Python tools)
    --python-only      Install only Python-based tools
    --help             Show this help message

TOOLS INSTALLED:
    - TruffleHog       Secret detection
    - Trivy            Container vulnerability scanning
    - OWASP Dependency-Check  Dependency vulnerability scanning
    - Semgrep          Static application security testing
    - Checkov          Infrastructure as code security
    - Bandit           Python security linting
    - Safety           Python dependency vulnerability checking
    - ShellCheck       Shell script security validation
    - Snyk CLI         Advanced vulnerability scanning (optional)

EXAMPLES:
    $0                 # Install all tools
    $0 --essential     # Install essential tools only
    $0 --python-only   # Install Python tools only

EOF
}

# Main function
main() {
    local install_mode="all"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                install_mode="all"
                shift
                ;;
            --essential)
                install_mode="essential"
                shift
                ;;
            --python-only)
                install_mode="python"
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
    
    log "Starting security tool installation..."
    detect_os
    log "Detected OS: $OS (Package manager: $PKG_MANAGER)"
    
    # Install tools based on mode
    case "$install_mode" in
        "all")
            install_system_tools
            install_python_tools
            install_trufflehog
            install_trivy
            install_dependency_check
            install_snyk
            ;;
        "essential")
            install_system_tools
            install_python_tools
            install_trufflehog
            install_trivy
            ;;
        "python")
            install_python_tools
            ;;
    esac
    
    generate_configs
    verify_installations
    
    success "Security tool installation completed!"
    echo ""
    echo "Next steps:"
    echo "1. Run 'snyk auth' to authenticate Snyk CLI (if installed)"
    echo "2. Test tools with: make test-security-comprehensive"
    echo "3. Run pre-commit: pre-commit run --all-files"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi