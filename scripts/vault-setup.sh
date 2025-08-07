#!/bin/bash

# Vault Setup Script for Jenkins HA Infrastructure
# This script helps setup and manage Ansible Vault for secure credential storage

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VAULT_PASSWORDS_DIR="$PROJECT_ROOT/environments/vault-passwords"
INVENTORIES_DIR="$PROJECT_ROOT/ansible/inventories"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
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

# Help function
show_help() {
    cat << EOF
Vault Setup Script for Jenkins HA Infrastructure

Usage: $0 [COMMAND] [ENVIRONMENT]

Commands:
    create      Create new vault file for environment
    edit        Edit existing vault file
    encrypt     Encrypt existing plain text vault file
    decrypt     Decrypt vault file (temporary, for editing)
    rekey       Change vault password
    view        View encrypted vault content
    validate    Validate vault file can be decrypted
    setup       Initial setup of vault infrastructure
    rotate      Rotate all passwords in vault file

Environments:
    production  Production environment
    staging     Staging environment
    local       Local development environment

Examples:
    $0 setup production                    # Initial vault setup for production
    $0 create production                   # Create new vault file for production
    $0 edit production                     # Edit production vault file
    $0 validate production                 # Validate production vault file
    $0 rekey production                    # Change production vault password
    $0 rotate production                   # Rotate all passwords in vault

Security Features:
    - Strong password generation using cryptographic random sources
    - Automatic file permission setting (600 for vault files)
    - Backup and rollback for password changes
    - Validation of required security variables
    - Git ignore patterns to prevent accidental commits

EOF
}

# Check if environment is valid
validate_environment() {
    local env="$1"
    case "$env" in
        production|staging|local)
            return 0
            ;;
        *)
            log_error "Invalid environment: $env"
            log_error "Valid environments: production, staging, local"
            return 1
            ;;
    esac
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v ansible-vault &> /dev/null; then
        missing_deps+=("ansible-vault")
    fi
    
    if ! command -v openssl &> /dev/null; then
        log_warning "OpenSSL not found - using fallback password generation"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install Ansible to continue"
        return 1
    fi
    
    return 0
}

# Setup vault directory structure
setup_vault_structure() {
    log_info "Setting up vault directory structure..."
    
    # Create vault passwords directory
    mkdir -p "$VAULT_PASSWORDS_DIR"
    chmod 700 "$VAULT_PASSWORDS_DIR"
    
    # Create .gitignore for vault passwords if it doesn't exist
    if [[ ! -f "$VAULT_PASSWORDS_DIR/.gitignore" ]]; then
        cat > "$VAULT_PASSWORDS_DIR/.gitignore" << 'EOF'
# Vault password files - NEVER commit these
*
!.gitignore
!README.md
EOF
        log_success "Created .gitignore for vault passwords"
    fi
    
    # Update main .gitignore if needed
    local main_gitignore="$PROJECT_ROOT/.gitignore"
    if [[ -f "$main_gitignore" ]] && ! grep -q "environments/vault-passwords/" "$main_gitignore"; then
        echo "" >> "$main_gitignore"
        echo "# Vault password files - NEVER commit these" >> "$main_gitignore"
        echo "environments/vault-passwords/*" >> "$main_gitignore"
        echo "!environments/vault-passwords/.gitignore" >> "$main_gitignore"
        echo "!environments/vault-passwords/README.md" >> "$main_gitignore"
        log_success "Updated main .gitignore with vault password exclusions"
    fi
    
    log_success "Vault directory structure setup complete"
}

# Generate strong password
generate_vault_password() {
    # Generate a strong password using openssl or fallback methods
    if command -v openssl &> /dev/null; then
        # Generate 32 character password with special characters
        openssl rand -base64 48 | tr -d "=+/\n" | cut -c1-32
    elif [[ -r /dev/urandom ]]; then
        # Fallback to urandom
        tr -dc 'A-Za-z0-9!@#$%^&*()_+-=[]{}|;:,.<>?' < /dev/urandom | head -c32
    else
        # Fallback to date-based generation (less secure)
        echo "V@ult$(date +%s)$(hostname | tr -d ' ')$(shuf -i 1000-9999 -n1)!"
    fi
}

# Generate application-specific strong password
generate_app_password() {
    local app_name="$1"
    local timestamp=$(date +%Y)
    
    if command -v openssl &> /dev/null; then
        # Generate password with app context
        local base_pass=$(openssl rand -base64 24 | tr -d "=+/\n")
        echo "${app_name}@${base_pass}@${timestamp}!"
    else
        echo "${app_name}@Str0ng$(date +%s)@${timestamp}!"
    fi
}

# Setup vault for environment
setup_environment_vault() {
    local env="$1"
    local vault_password_file="$VAULT_PASSWORDS_DIR/$env"
    local vault_file="$INVENTORIES_DIR/$env/group_vars/all/vault.yml"
    
    log_info "Setting up vault for environment: $env"
    
    # Create directories if they don't exist
    mkdir -p "$(dirname "$vault_file")"
    
    # Create vault password if it doesn't exist
    if [[ ! -f "$vault_password_file" ]]; then
        log_info "Creating vault password file for $env..."
        generate_vault_password > "$vault_password_file"
        chmod 600 "$vault_password_file"
        log_success "Created vault password file: $vault_password_file"
        log_warning "Please backup this password securely and separately from the repository!"
        log_warning "Password file location: $vault_password_file"
    else
        log_info "Vault password file already exists: $vault_password_file"
    fi
    
    # Encrypt vault file if it exists and is not encrypted
    if [[ -f "$vault_file" ]]; then
        if ! ansible-vault view "$vault_file" --vault-password-file="$vault_password_file" &>/dev/null; then
            log_info "Encrypting existing vault file..."
            ansible-vault encrypt "$vault_file" --vault-password-file="$vault_password_file"
            log_success "Encrypted vault file: $vault_file"
        else
            log_info "Vault file is already encrypted: $vault_file"
        fi
    else
        log_warning "Vault file does not exist: $vault_file"
        log_info "You can create it with: $0 create $env"
    fi
}

# Create new vault file
create_vault() {
    local env="$1"
    local vault_password_file="$VAULT_PASSWORDS_DIR/$env"
    local vault_file="$INVENTORIES_DIR/$env/group_vars/all/vault.yml"
    
    if [[ ! -f "$vault_password_file" ]]; then
        log_error "Vault password file not found: $vault_password_file"
        log_error "Run: $0 setup $env first"
        return 1
    fi
    
    if [[ -f "$vault_file" ]]; then
        log_warning "Vault file already exists: $vault_file"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            return 0
        fi
    fi
    
    log_info "Creating new vault file for $env..."
    ansible-vault create "$vault_file" --vault-password-file="$vault_password_file"
    log_success "Created vault file: $vault_file"
}

# Edit vault file
edit_vault() {
    local env="$1"
    local vault_password_file="$VAULT_PASSWORDS_DIR/$env"
    local vault_file="$INVENTORIES_DIR/$env/group_vars/all/vault.yml"
    
    if [[ ! -f "$vault_password_file" ]]; then
        log_error "Vault password file not found: $vault_password_file"
        return 1
    fi
    
    if [[ ! -f "$vault_file" ]]; then
        log_error "Vault file not found: $vault_file"
        return 1
    fi
    
    log_info "Editing vault file for $env..."
    ansible-vault edit "$vault_file" --vault-password-file="$vault_password_file"
}

# Encrypt vault file
encrypt_vault() {
    local env="$1"
    local vault_password_file="$VAULT_PASSWORDS_DIR/$env"
    local vault_file="$INVENTORIES_DIR/$env/group_vars/all/vault.yml"
    
    if [[ ! -f "$vault_password_file" ]]; then
        log_error "Vault password file not found: $vault_password_file"
        return 1
    fi
    
    if [[ ! -f "$vault_file" ]]; then
        log_error "Vault file not found: $vault_file"
        return 1
    fi
    
    log_info "Encrypting vault file for $env..."
    ansible-vault encrypt "$vault_file" --vault-password-file="$vault_password_file"
    log_success "Encrypted vault file: $vault_file"
}

# Decrypt vault file
decrypt_vault() {
    local env="$1"
    local vault_password_file="$VAULT_PASSWORDS_DIR/$env"
    local vault_file="$INVENTORIES_DIR/$env/group_vars/all/vault.yml"
    
    if [[ ! -f "$vault_password_file" ]]; then
        log_error "Vault password file not found: $vault_password_file"
        return 1
    fi
    
    if [[ ! -f "$vault_file" ]]; then
        log_error "Vault file not found: $vault_file"
        return 1
    fi
    
    log_warning "Decrypting vault file - remember to encrypt it again!"
    ansible-vault decrypt "$vault_file" --vault-password-file="$vault_password_file"
    log_success "Decrypted vault file: $vault_file"
    log_warning "File is now in plain text. Encrypt it with: $0 encrypt $env"
}

# View vault file
view_vault() {
    local env="$1"
    local vault_password_file="$VAULT_PASSWORDS_DIR/$env"
    local vault_file="$INVENTORIES_DIR/$env/group_vars/all/vault.yml"
    
    if [[ ! -f "$vault_password_file" ]]; then
        log_error "Vault password file not found: $vault_password_file"
        return 1
    fi
    
    if [[ ! -f "$vault_file" ]]; then
        log_error "Vault file not found: $vault_file"
        return 1
    fi
    
    log_info "Viewing vault file for $env..."
    ansible-vault view "$vault_file" --vault-password-file="$vault_password_file"
}

# Rekey vault file
rekey_vault() {
    local env="$1"
    local vault_password_file="$VAULT_PASSWORDS_DIR/$env"
    local vault_file="$INVENTORIES_DIR/$env/group_vars/all/vault.yml"
    
    if [[ ! -f "$vault_password_file" ]]; then
        log_error "Vault password file not found: $vault_password_file"
        return 1
    fi
    
    if [[ ! -f "$vault_file" ]]; then
        log_error "Vault file not found: $vault_file"
        return 1
    fi
    
    log_info "Changing vault password for $env..."
    
    # Backup current password
    cp "$vault_password_file" "$vault_password_file.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Generate new password
    generate_vault_password > "$vault_password_file.new"
    chmod 600 "$vault_password_file.new"
    
    # Rekey the vault file
    if ansible-vault rekey "$vault_file" --vault-password-file="$vault_password_file" --new-vault-password-file="$vault_password_file.new"; then
        mv "$vault_password_file.new" "$vault_password_file"
        log_success "Successfully changed vault password for $env"
        log_warning "Please backup the new password securely!"
        log_info "Old password backed up to: $vault_password_file.backup.*"
    else
        log_error "Failed to rekey vault file"
        rm -f "$vault_password_file.new"
        return 1
    fi
}

# Rotate passwords in vault
rotate_passwords() {
    local env="$1"
    local vault_password_file="$VAULT_PASSWORDS_DIR/$env"
    local vault_file="$INVENTORIES_DIR/$env/group_vars/all/vault.yml"
    
    if [[ ! -f "$vault_password_file" ]]; then
        log_error "Vault password file not found: $vault_password_file"
        return 1
    fi
    
    if [[ ! -f "$vault_file" ]]; then
        log_error "Vault file not found: $vault_file"
        return 1
    fi
    
    log_info "Rotating passwords in vault for $env..."
    log_warning "This will generate new passwords for all applications"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        return 0
    fi
    
    # Create backup
    local backup_file="$vault_file.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$vault_file" "$backup_file"
    log_info "Created backup: $backup_file"
    
    # Decrypt for editing
    ansible-vault decrypt "$vault_file" --vault-password-file="$vault_password_file"
    
    # Generate new passwords
    local new_jenkins_pass=$(generate_app_password "J3nk1ns")
    local new_harbor_pass=$(generate_app_password "H@rb0r")
    local new_grafana_pass=$(generate_app_password "Gr@f@n@")
    local new_prometheus_pass=$(generate_app_password "Pr0m3th3us")
    
    # Update passwords in file
    sed -i.tmp "s/vault_jenkins_admin_password:.*/vault_jenkins_admin_password: \"$new_jenkins_pass\"/" "$vault_file"
    sed -i.tmp "s/vault_harbor_admin_password:.*/vault_harbor_admin_password: \"$new_harbor_pass\"/" "$vault_file"
    sed -i.tmp "s/vault_grafana_admin_password:.*/vault_grafana_admin_password: \"$new_grafana_pass\"/" "$vault_file"
    sed -i.tmp "s/vault_prometheus_basic_auth_password:.*/vault_prometheus_basic_auth_password: \"$new_prometheus_pass\"/" "$vault_file"
    
    # Clean up temp file
    rm -f "$vault_file.tmp"
    
    # Re-encrypt
    ansible-vault encrypt "$vault_file" --vault-password-file="$vault_password_file"
    
    log_success "Password rotation completed for $env"
    log_warning "Please update any external systems with the new passwords"
    log_info "Backup available at: $backup_file"
}

# Validate vault file
validate_vault() {
    local env="$1"
    local vault_password_file="$VAULT_PASSWORDS_DIR/$env"
    local vault_file="$INVENTORIES_DIR/$env/group_vars/all/vault.yml"
    
    if [[ ! -f "$vault_password_file" ]]; then
        log_error "Vault password file not found: $vault_password_file"
        return 1
    fi
    
    if [[ ! -f "$vault_file" ]]; then
        log_error "Vault file not found: $vault_file"
        return 1
    fi
    
    log_info "Validating vault file for $env..."
    
    if ansible-vault view "$vault_file" --vault-password-file="$vault_password_file" >/dev/null 2>&1; then
        log_success "Vault file is valid and can be decrypted"
        
        # Additional validation - check for required variables
        local content=$(ansible-vault view "$vault_file" --vault-password-file="$vault_password_file")
        local required_vars=(
            "vault_jenkins_admin_password"
            "vault_harbor_admin_password"
            "vault_grafana_admin_password"
            "vault_prometheus_basic_auth_password"
            "vault_ssl_key_password"
            "vault_backup_encryption_key"
        )
        
        local missing_vars=()
        for var in "${required_vars[@]}"; do
            if echo "$content" | grep -q "^$var:"; then
                log_success "Required variable found: $var"
            else
                log_warning "Required variable missing: $var"
                missing_vars+=("$var")
            fi
        done
        
        # Check password strength
        if echo "$content" | grep -q "changeme"; then
            log_error "Default passwords detected - please change them!"
            return 1
        fi
        
        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            log_warning "Missing ${#missing_vars[@]} required variables"
            return 1
        else
            log_success "All required variables present"
        fi
    else
        log_error "Vault file validation failed - cannot decrypt"
        return 1
    fi
}

# Main function
main() {
    local command="${1:-}"
    local environment="${2:-}"
    
    # Check dependencies first
    check_dependencies || exit 1
    
    if [[ -z "$command" ]]; then
        show_help
        exit 1
    fi
    
    case "$command" in
        help|--help|-h)
            show_help
            exit 0
            ;;
        setup)
            if [[ -z "$environment" ]]; then
                log_error "Environment required for setup command"
                show_help
                exit 1
            fi
            validate_environment "$environment" || exit 1
            setup_vault_structure
            setup_environment_vault "$environment"
            ;;
        create)
            if [[ -z "$environment" ]]; then
                log_error "Environment required for create command"
                exit 1
            fi
            validate_environment "$environment" || exit 1
            create_vault "$environment"
            ;;
        edit)
            if [[ -z "$environment" ]]; then
                log_error "Environment required for edit command"
                exit 1
            fi
            validate_environment "$environment" || exit 1
            edit_vault "$environment"
            ;;
        encrypt)
            if [[ -z "$environment" ]]; then
                log_error "Environment required for encrypt command"
                exit 1
            fi
            validate_environment "$environment" || exit 1
            encrypt_vault "$environment"
            ;;
        decrypt)
            if [[ -z "$environment" ]]; then
                log_error "Environment required for decrypt command"
                exit 1
            fi
            validate_environment "$environment" || exit 1
            decrypt_vault "$environment"
            ;;
        view)
            if [[ -z "$environment" ]]; then
                log_error "Environment required for view command"
                exit 1
            fi
            validate_environment "$environment" || exit 1
            view_vault "$environment"
            ;;
        rekey)
            if [[ -z "$environment" ]]; then
                log_error "Environment required for rekey command"
                exit 1
            fi
            validate_environment "$environment" || exit 1
            rekey_vault "$environment"
            ;;
        rotate)
            if [[ -z "$environment" ]]; then
                log_error "Environment required for rotate command"
                exit 1
            fi
            validate_environment "$environment" || exit 1
            rotate_passwords "$environment"
            ;;
        validate)
            if [[ -z "$environment" ]]; then
                log_error "Environment required for validate command"
                exit 1
            fi
            validate_environment "$environment" || exit 1
            validate_vault "$environment"
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
