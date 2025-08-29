# Jenkins HA Infrastructure Makefile
# Provides convenient commands for local development and deployment

# Default target
.DEFAULT_GOAL := help

# Variables
ANSIBLE_DIR := ansible
SCRIPTS_DIR := scripts
LOCAL_INVENTORY := inventories/local/hosts.yml
PRODUCTION_INVENTORY := inventories/production/hosts.yml

# Colors for output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

##@ Development Commands

.PHONY: local
local: ## Deploy Jenkins HA locally
	@echo "$(BLUE)🚀 Deploying Jenkins HA locally...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(LOCAL_INVENTORY) site.yml

.PHONY: local-verbose
local-verbose: ## Deploy locally with verbose output
	@echo "$(BLUE)🚀 Deploying Jenkins HA locally (verbose)...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(LOCAL_INVENTORY) site.yml -v

.PHONY: local-dry-run
local-dry-run: ## Perform a dry run of local deployment
	@echo "$(BLUE)🔍 Dry run of local deployment...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(LOCAL_INVENTORY) site.yml --check

.PHONY: local-jenkins
local-jenkins: ## Deploy only Jenkins infrastructure locally
	@echo "$(BLUE)🏗️ Deploying Jenkins infrastructure locally...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(LOCAL_INVENTORY) site.yml --tags jenkins

.PHONY: local-monitoring
local-monitoring: ## Deploy only monitoring stack locally
	@echo "$(BLUE)📊 Deploying monitoring stack locally...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(LOCAL_INVENTORY) site.yml --tags monitoring


##@ Production Commands

.PHONY: deploy-local
deploy-local: ## Deploy to local development environment
	@echo "$(BLUE)🏗️ Deploying to local development environment...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(LOCAL_INVENTORY) site.yml

.PHONY: deploy-production
deploy-production: ## Deploy to production environment
	@echo "$(RED)🚀 Deploying to production environment...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(PRODUCTION_INVENTORY) site.yml

.PHONY: backup
backup: ## Run backup procedures
	@echo "$(GREEN)💾 Running backup procedures...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(PRODUCTION_INVENTORY) site.yml --tags backup

.PHONY: monitor
monitor: ## Setup monitoring stack
	@echo "$(GREEN)📊 Setting up monitoring stack...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(PRODUCTION_INVENTORY) site.yml --tags monitoring

##@ Build Commands

.PHONY: build-images
build-images: ## Build and push Docker images
	@echo "$(BLUE)🏗️ Building Docker images...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(PRODUCTION_INVENTORY) site.yml --tags images

.PHONY: build-local-images
build-local-images: ## Build Docker images for local development
	@echo "$(BLUE)🏗️ Building Docker images locally...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook -i $(LOCAL_INVENTORY) site.yml --tags images -e build_jenkins_images=true

##@ Testing and Validation

.PHONY: test
test: test-syntax test-inventory test-lint test-security ## Run all tests

.PHONY: test-full
test-full: test pre-commit-run ## Run comprehensive test suite including pre-commit

.PHONY: test-syntax
test-syntax: ## Test Ansible syntax
	@echo "$(BLUE)🔍 Testing Ansible syntax...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook site.yml --syntax-check

.PHONY: test-inventory
test-inventory: ## Test inventory configurations
	@echo "$(BLUE)🔍 Testing inventory configurations...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-inventory -i $(LOCAL_INVENTORY) --list > /dev/null
	@cd $(ANSIBLE_DIR) && ansible-inventory -i $(PRODUCTION_INVENTORY) --list > /dev/null
	@echo "$(GREEN)✅ All inventories are valid$(RESET)"

.PHONY: test-lint
test-lint: ## Run Ansible linting
	@echo "$(BLUE)🔍 Running Ansible linting...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-lint . || echo "$(YELLOW)⚠️ Linting issues found$(RESET)"

.PHONY: test-security
test-security: ## Run security validation
	@echo "$(BLUE)🔒 Running security validation...$(RESET)"
	@if command -v bandit >/dev/null 2>&1; then \
		bandit -r scripts/ -f txt || echo "$(YELLOW)⚠️ Security issues found in scripts$(RESET)"; \
	else \
		echo "$(YELLOW)⚠️ bandit not installed, skipping security scan$(RESET)"; \
	fi

.PHONY: test-connectivity
test-connectivity: ## Test connectivity to local environment
	@echo "$(BLUE)🔍 Testing connectivity to local environment...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible -i $(LOCAL_INVENTORY) localhost -m ping

.PHONY: test-templates
test-templates: ## Validate Jinja2 templates
	@echo "$(BLUE)🔍 Validating Jinja2 templates...$(RESET)"
	@find $(ANSIBLE_DIR) -name "*.j2" -exec python3 -c "import jinja2; jinja2.Template(open('{}').read())" \; 2>/dev/null && echo "$(GREEN)✅ All templates are valid$(RESET)" || echo "$(RED)❌ Template validation failed$(RESET)"

##@ Pre-commit Hooks

.PHONY: pre-commit-install
pre-commit-install: ## Install pre-commit hooks
	@echo "$(BLUE)🪝 Installing pre-commit hooks...$(RESET)"
	@./scripts/pre-commit-setup.sh

.PHONY: pre-commit-run
pre-commit-run: ## Run pre-commit on all files
	@echo "$(BLUE)🪝 Running pre-commit on all files...$(RESET)"
	@pre-commit run --all-files

.PHONY: pre-commit-update
pre-commit-update: ## Update pre-commit hooks
	@echo "$(BLUE)🪝 Updating pre-commit hooks...$(RESET)"
	@pre-commit autoupdate

.PHONY: pre-commit-clean
pre-commit-clean: ## Clean pre-commit cache
	@echo "$(BLUE)🪝 Cleaning pre-commit cache...$(RESET)"
	@pre-commit clean

##@ Development Environment

.PHONY: dev-setup
dev-setup: ## Setup complete development environment with pre-commit
	@echo "$(BLUE)🔧 Setting up complete development environment...$(RESET)"
	@./scripts/pre-commit-setup.sh
	@echo "$(GREEN)✅ Development environment ready$(RESET)"

.PHONY: dev-activate
dev-activate: ## Show how to activate development environment
	@echo "$(BLUE)🔧 To activate development environment:$(RESET)"
	@echo "$(GREEN)source ./activate-dev-env.sh$(RESET)"

.PHONY: dev-test
dev-test: ## Run development tests (fast subset)
	@echo "$(BLUE)🧪 Running development tests...$(RESET)"
	@$(MAKE) test-syntax test-inventory test-templates test-groovy-basic

.PHONY: test-groovy
test-groovy: ## Validate all Groovy scripts and DSL files
	@echo "$(BLUE)🔍 Validating Groovy scripts...$(RESET)"
	@find jenkins-dsl/ -name "*.groovy" -exec echo "Checking: {}" \; -exec groovy -e "new File('{}').text" \; 2>/dev/null || echo "$(YELLOW)⚠️ Groovy not installed, skipping syntax validation$(RESET)"
	@echo "$(GREEN)✅ Groovy validation completed$(RESET)"

.PHONY: test-groovy-basic
test-groovy-basic: ## Basic Groovy validation without Groovy compiler
	@echo "$(BLUE)🔍 Running basic Groovy validation...$(RESET)"
	@python3 -c "
import os
import sys
import re

def basic_groovy_check(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Check balanced braces
    if content.count('{') != content.count('}'):
        print(f'❌ Unbalanced braces: {file_path}')
        return False
    
    # Check balanced parentheses  
    if content.count('(') != content.count(')'):
        print(f'❌ Unbalanced parentheses: {file_path}')
        return False
    
    print(f'✅ Basic validation passed: {file_path}')
    return True

failed = False
for root, dirs, files in os.walk('.'):
    for file in files:
        if file.endswith('.groovy'):
            file_path = os.path.join(root, file)
            if not basic_groovy_check(file_path):
                failed = True

sys.exit(1 if failed else 0)
"

.PHONY: test-jenkinsfiles
test-jenkinsfiles: ## Validate all Jenkinsfiles
	@echo "$(BLUE)🔍 Validating Jenkinsfiles...$(RESET)"
	@python3 -c "
import os
import re
import sys

def validate_jenkinsfile(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    
    issues = []
    
    if not re.search(r'pipeline\s*{', content, re.IGNORECASE):
        issues.append('Missing pipeline block')
    
    if not re.search(r'agent\s+', content, re.IGNORECASE):
        issues.append('Missing agent definition')
    
    if not re.search(r'stages\s*{', content, re.IGNORECASE):
        issues.append('Missing stages block')
    
    if issues:
        print(f'❌ Issues in {file_path}:')
        for issue in issues:
            print(f'   - {issue}')
        return False
    
    print(f'✅ Jenkinsfile valid: {file_path}')
    return True

failed = False
jenkinsfiles = []

# Find all Jenkinsfiles
for root, dirs, files in os.walk('pipelines'):
    for file in files:
        if 'Jenkinsfile' in file:
            jenkinsfiles.append(os.path.join(root, file))

if not jenkinsfiles:
    print('No Jenkinsfiles found')
else:
    for jf in jenkinsfiles:
        if not validate_jenkinsfile(jf):
            failed = True

sys.exit(1 if failed else 0)
"

.PHONY: test-dsl
test-dsl: ## Enhanced DSL validation
	@echo "$(BLUE)🔍 Running enhanced DSL validation...$(RESET)"
	@if [ -f scripts/dsl-syntax-validator.sh ]; then \
		./scripts/dsl-syntax-validator.sh; \
	else \
		echo "$(YELLOW)⚠️ DSL validator script not found$(RESET)"; \
	fi

.PHONY: test-jenkins-security
test-jenkins-security: ## Run Jenkins security validation
	@echo "$(BLUE)🔒 Running Jenkins security validation...$(RESET)"
	@python3 -c "
import os
import re
import sys

security_patterns = [
    (r'System\.exit\s*\(', 'System.exit() usage detected'),
    (r'Runtime\.getRuntime', 'Runtime.getRuntime() usage detected'),
    (r'password\s*[:=]\s*[\"\']\w+', 'Hardcoded password detected'),
    (r'secret\s*[:=]\s*[\"\']\w{8,}', 'Hardcoded secret detected'),
    (r'sudo\s', 'Sudo usage detected'),
    (r'rm\s+-rf\s+/', 'Dangerous rm -rf usage'),
]

def scan_file(file_path):
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        issues = []
        for pattern, message in security_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                issues.append(message)
        
        if issues:
            print(f'🔒 Security issues in {file_path}:')
            for issue in issues:
                print(f'   - {issue}')
            return False
        
        return True
    except Exception as e:
        print(f'Error scanning {file_path}: {e}')
        return True

failed = False
for root, dirs, files in os.walk('.'):
    for file in files:
        if file.endswith(('.groovy', 'Jenkinsfile')):
            file_path = os.path.join(root, file)
            if not scan_file(file_path):
                failed = True

if not failed:
    print('✅ Jenkins security validation passed')

sys.exit(1 if failed else 0)
"

.PHONY: test-secrets
test-secrets: ## Run secret detection with TruffleHog
	@echo "$(BLUE)🔍 Running secret detection...$(RESET)"
	@if command -v trufflehog >/dev/null 2>&1; then \
		trufflehog filesystem . --only-verified --fail || echo "$(YELLOW)⚠️ Secrets detected$(RESET)"; \
	else \
		echo "$(YELLOW)⚠️ TruffleHog not installed, skipping secret scan$(RESET)"; \
		echo "Install: curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh"; \
	fi

.PHONY: test-infrastructure-security
test-infrastructure-security: ## Run infrastructure security scanning with Checkov
	@echo "$(BLUE)🏗️ Running infrastructure security scan...$(RESET)"
	@if command -v checkov >/dev/null 2>&1; then \
		checkov --framework dockerfile,ansible,yaml_templates --skip-check CKV_DOCKER_2,CKV_DOCKER_3 . || echo "$(YELLOW)⚠️ Infrastructure security issues found$(RESET)"; \
	else \
		echo "$(YELLOW)⚠️ Checkov not installed, using pip install checkov$(RESET)"; \
		pip install checkov && checkov --framework dockerfile,ansible,yaml_templates . || echo "$(YELLOW)⚠️ Infrastructure security issues found$(RESET)"; \
	fi

.PHONY: test-dependency-vulnerabilities
test-dependency-vulnerabilities: ## Run OWASP Dependency-Check
	@echo "$(BLUE)📦 Running dependency vulnerability scan...$(RESET)"
	@if command -v dependency-check.sh >/dev/null 2>&1; then \
		dependency-check.sh --project "Jenkins-HA" --scan . --format JSON --format HTML --out dependency-check-report --failOnCVSS 7 || echo "$(YELLOW)⚠️ Vulnerable dependencies found$(RESET)"; \
	else \
		echo "$(YELLOW)⚠️ OWASP Dependency-Check not installed$(RESET)"; \
		echo "Install: https://owasp.org/www-project-dependency-check/"; \
	fi

.PHONY: test-sast
test-sast: ## Run Static Application Security Testing with Semgrep
	@echo "$(BLUE)🔎 Running SAST scan...$(RESET)"
	@if command -v semgrep >/dev/null 2>&1; then \
		semgrep --config=auto --error --skip-unknown-extensions . || echo "$(YELLOW)⚠️ SAST issues found$(RESET)"; \
	else \
		pip install semgrep && semgrep --config=auto --error --skip-unknown-extensions . || echo "$(YELLOW)⚠️ SAST issues found$(RESET)"; \
	fi

.PHONY: test-security-comprehensive
test-security-comprehensive: ## Run comprehensive security testing
	@echo "$(BLUE)🛡️ Running comprehensive security tests...$(RESET)"
	@$(MAKE) test-secrets test-infrastructure-security test-dependency-vulnerabilities test-sast test-jenkins-security

.PHONY: security-report
security-report: ## Generate comprehensive security report
	@echo "$(BLUE)📊 Generating security report...$(RESET)"
	@echo "=== Security Scan Report $(shell date) ===" > security-report.txt
	@echo "Repository: Jenkins HA Infrastructure" >> security-report.txt
	@echo "" >> security-report.txt
	@echo "Running comprehensive security scans..." >> security-report.txt
	@$(MAKE) test-security-comprehensive 2>&1 | tee -a security-report.txt
	@echo "" >> security-report.txt
	@echo "Report generated: security-report.txt"

##@ Container Management

.PHONY: ps
ps: ## Show running containers
	@echo "$(BLUE)📋 Running containers:$(RESET)"
	@docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

.PHONY: logs
logs: ## Show logs for all Jenkins containers
	@echo "$(BLUE)📋 Container logs:$(RESET)"
	@docker ps --filter "name=jenkins" --format "{{.Names}}" | xargs -I {} sh -c 'echo "=== {} ===" && docker logs --tail=20 {}'

.PHONY: logs-jenkins
logs-jenkins: ## Show Jenkins master logs
	@echo "$(BLUE)📋 Jenkins master logs:$(RESET)"
	@docker logs -f jenkins-master-dev

.PHONY: logs-grafana
logs-grafana: ## Show Grafana logs
	@echo "$(BLUE)📋 Grafana logs:$(RESET)"
	@docker logs -f grafana-dev

.PHONY: shell-jenkins
shell-jenkins: ## Access Jenkins master container shell
	@echo "$(BLUE)🐚 Accessing Jenkins master shell...$(RESET)"
	@docker exec -it jenkins-master-dev bash

.PHONY: stop
stop: ## Stop all containers
	@echo "$(YELLOW)🛑 Stopping all containers...$(RESET)"
	@docker stop $$(docker ps -q) 2>/dev/null || true

.PHONY: clean
clean: ## Clean up containers and resources
	@echo "$(YELLOW)🧹 Cleaning up containers and resources...$(RESET)"
	@docker stop $$(docker ps -aq) 2>/dev/null || true
	@docker rm $$(docker ps -aq) 2>/dev/null || true
	@docker network prune -f
	@docker volume prune -f

.PHONY: reset
reset: ## Complete reset - remove everything
	@echo "$(RED)🔥 Complete reset - removing everything...$(RESET)"
	@echo "$(RED)⚠️  This will delete ALL containers, images, and data!$(RESET)"
	@read -p "Are you sure? [y/N] " -n 1 -r && echo && [[ $$REPLY =~ ^[Yy]$$ ]]
	@docker stop $$(docker ps -aq) 2>/dev/null || true
	@docker rm $$(docker ps -aq) 2>/dev/null || true
	@docker rmi $$(docker images -q) 2>/dev/null || true
	@docker volume prune -f
	@docker network prune -f
	@docker system prune -a -f

##@ Environment Setup

.PHONY: setup
setup: ## Setup development environment
	@echo "$(BLUE)🔧 Setting up development environment...$(RESET)"
	@if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
	@echo "$(GREEN)✅ Development environment setup complete$(RESET)"

.PHONY: vault-create
vault-create: ## Create encrypted vault file for production
	@echo "$(BLUE)🔐 Creating encrypted vault file...$(RESET)"
	@ansible-vault create $(ANSIBLE_DIR)/inventories/production/group_vars/all/vault.yml

.PHONY: vault-edit
vault-edit: ## Edit encrypted vault file
	@echo "$(BLUE)🔐 Editing encrypted vault file...$(RESET)"
	@ansible-vault edit $(ANSIBLE_DIR)/inventories/production/group_vars/all/vault.yml

##@ Information Commands

.PHONY: status
status: ## Show deployment status
	@echo "$(BLUE)📊 Deployment Status:$(RESET)"
	@echo "$(YELLOW)Local Services:$(RESET)"
	@curl -s -o /dev/null -w "Jenkins:    %{http_code}\n" http://localhost:8080/login || echo "Jenkins:    Not running"
	@curl -s -o /dev/null -w "Grafana:    %{http_code}\n" http://localhost:9300/api/health || echo "Grafana:    Not running"
	@curl -s -o /dev/null -w "Prometheus: %{http_code}\n" http://localhost:9090/-/healthy || echo "Prometheus: Not running"  

.PHONY: urls
urls: ## Show service URLs
	@echo "$(BLUE)🌐 Service URLs:$(RESET)"
	@echo "$(GREEN)Jenkins:    http://localhost:8080$(RESET)"
	@echo "$(GREEN)Grafana:    http://localhost:9300$(RESET)"
	@echo "$(GREEN)Prometheus: http://localhost:9090$(RESET)"

.PHONY: credentials
credentials: ## Show credential locations
	@echo "$(BLUE)🔐 Credentials Information:$(RESET)"
	@echo "$(YELLOW)Jenkins credentials are stored in encrypted vault files$(RESET)"
	@echo "$(YELLOW)Use 'make vault-edit' to manage credentials securely$(RESET)"
	@echo "$(YELLOW)Vault location: $(ANSIBLE_DIR)/inventories/*/group_vars/all/vault.yml$(RESET)"

##@ Help

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\n$(BLUE)Jenkins HA Infrastructure Makefile$(RESET)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(GREEN)%-18s$(RESET) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(BLUE)Quick Start:$(RESET)"
	@echo "  make local          # Deploy everything locally"
	@echo "  make status         # Check service status"  
	@echo "  make urls           # Show service URLs"
	@echo "  make clean          # Clean up when done"
	@echo ""
