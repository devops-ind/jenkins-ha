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
	@$(SCRIPTS_DIR)/deploy-local.sh

.PHONY: local-verbose
local-verbose: ## Deploy locally with verbose output
	@echo "$(BLUE)🚀 Deploying Jenkins HA locally (verbose)...$(RESET)"
	@$(SCRIPTS_DIR)/deploy-local.sh --verbose

.PHONY: local-dry-run
local-dry-run: ## Perform a dry run of local deployment
	@echo "$(BLUE)🔍 Dry run of local deployment...$(RESET)"
	@$(SCRIPTS_DIR)/deploy-local.sh --dry-run

.PHONY: local-jenkins
local-jenkins: ## Deploy only Jenkins infrastructure locally
	@echo "$(BLUE)🏗️ Deploying Jenkins infrastructure locally...$(RESET)"
	@$(SCRIPTS_DIR)/deploy-local.sh --tags common,docker,jenkins,infrastructure

.PHONY: local-monitoring
local-monitoring: ## Deploy only monitoring stack locally
	@echo "$(BLUE)📊 Deploying monitoring stack locally...$(RESET)"
	@$(SCRIPTS_DIR)/deploy-local.sh --tags monitoring,prometheus,grafana


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
	@$(SCRIPTS_DIR)/deploy-local.sh --tags images

##@ Testing and Validation

.PHONY: test
test: test-syntax test-inventory ## Run all tests

.PHONY: test-syntax
test-syntax: ## Test Ansible syntax
	@echo "$(BLUE)🔍 Testing Ansible syntax...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-playbook site.yml --syntax-check
	@cd $(ANSIBLE_DIR) && ansible-playbook deploy-local.yml --syntax-check

.PHONY: test-inventory
test-inventory: ## Test inventory configurations
	@echo "$(BLUE)🔍 Testing inventory configurations...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible-inventory -i $(LOCAL_INVENTORY) --list > /dev/null
	@cd $(ANSIBLE_DIR) && ansible-inventory -i $(PRODUCTION_INVENTORY) --list > /dev/null
	@echo "$(GREEN)✅ All inventories are valid$(RESET)"

.PHONY: test-connectivity
test-connectivity: ## Test connectivity to local environment
	@echo "$(BLUE)🔍 Testing connectivity to local environment...$(RESET)"
	@cd $(ANSIBLE_DIR) && ansible -i $(LOCAL_INVENTORY) localhost -m ping

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
	@curl -s -o /dev/null -w "Grafana:    %{http_code}\n" http://localhost:3000/api/health || echo "Grafana:    Not running"
	@curl -s -o /dev/null -w "Prometheus: %{http_code}\n" http://localhost:9090/-/healthy || echo "Prometheus: Not running"  

.PHONY: urls
urls: ## Show service URLs
	@echo "$(BLUE)🌐 Service URLs:$(RESET)"
	@echo "$(GREEN)Jenkins:    http://localhost:8080$(RESET)"
	@echo "$(GREEN)Grafana:    http://localhost:3000$(RESET)"
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
