# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-grade Jenkins infrastructure with **Blue-Green Deployment**, **Multi-Team Support**, and **Enterprise Security** using Ansible for configuration management. The system deploys Jenkins masters in blue-green configuration with secure container management, HAProxy load balancing, comprehensive monitoring stack (Prometheus/Grafana), automated backup and disaster recovery systems, and Job DSL automation with enhanced security controls.

### Recent Security & Operational Enhancements
- **Container Security**: Trivy vulnerability scanning, security constraints, runtime monitoring
- **Automated Rollback**: SLI-based rollback triggers with configurable thresholds
- **Enhanced Monitoring**: 26-panel Grafana dashboards with DORA metrics and SLI tracking
- **Disaster Recovery**: Enterprise-grade automated DR with RTO/RPO compliance
- **Pre-deployment Validation**: Comprehensive system validation framework
- **Security Compliance**: Real-time security monitoring and compliance reporting
- **Architecture Simplification**: Single configuration per team with runtime blue-green differentiation (DevOps expert validated)
- **Build Optimization**: Unified Docker images for blue-green environments reducing build complexity by 55%
- **✅ Resource-Optimized Blue-Green**: Only active environment runs (50% resource reduction) with dynamic switching - **COMPLETE**: Both HAProxy and Jenkins master deployments optimized
- **✅ Dynamic SSL Generation**: Team-based wildcard SSL certificates auto-generated from `jenkins_teams` configuration
- **✅ Improved Domain Architecture**: Corrected subdomain format `{team}jenkins.domain.com` for better team isolation
- **✅ SSL Architecture Refactor**: SSL generation moved to high-availability-v2 role for better separation of concerns
- **⚡ Jenkins Container Optimization**: Active-only container deployment in jenkins-master-v2 role with intelligent environment switching
- **✅ Smart Data Sharing**: Selective data sharing between blue-green environments with plugin isolation for safe upgrades
- **🔒 HAProxy SSL Container Fix**: Resolved persistent SSL certificate mounting issues with container-safe approach, comprehensive troubleshooting system, and automated recovery
- **🪝 Comprehensive Pre-commit Hooks**: Advanced Groovy/Jenkinsfile validation with security scanning, syntax checking, and best practices enforcement
- **🔍 Enhanced Code Quality**: Multi-layer validation for 22 Groovy files and 7 Jenkinsfiles with automated CI/CD integration

## Key Commands

### Core Deployment Commands
```bash
# Deploy to production environment
make deploy-production

# Deploy to local development environment  
make deploy-local

# Build and push Docker images
make build-images

# Run backup procedures
make backup

# Setup monitoring stack
make monitor
```

### Direct Ansible Commands
```bash
# Full infrastructure deployment
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

# Deploy specific components with tags
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags jenkins,deploy
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags monitoring
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags backup
```

### Testing and Validation
```bash
# Test inventory configuration
python tests/inventory_test.py ansible/inventories/production/hosts.yml

# Test playbook syntax
ansible-playbook tests/playbook-syntax.yml --syntax-check

# Validate Ansible playbook syntax
ansible-playbook ansible/site.yml --syntax-check

# Run comprehensive pre-deployment validation
ansible-playbook ansible/site.yml --tags validation -e validation_mode=strict

# Security compliance scan
/usr/local/bin/jenkins-security-scan.sh --all

# SSL certificate validation (NEW)
ansible-playbook ansible/site.yml --tags ssl --check

# Test SSL certificate generation for teams (NEW)
ansible-playbook ansible/site.yml --tags ssl,wildcard --limit local

# HAProxy SSL deployment with troubleshooting (NEW)
./scripts/deploy-haproxy-ssl.sh

# HAProxy SSL troubleshooting and recovery (NEW)
ansible-playbook ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml --extra-vars "troubleshoot_mode=fix"
```

### Pre-commit Hooks and Code Quality (NEW)
```bash
# Setup development environment with pre-commit hooks
make dev-setup
./scripts/pre-commit-setup.sh

# Activate development environment
source ./activate-dev-env.sh

# Run all validation tests
make test-full

# Groovy and Jenkins validation
make test-groovy              # Full Groovy syntax validation (requires Groovy SDK)
make test-groovy-basic        # Basic Groovy validation (no Groovy SDK required)
make test-jenkinsfiles        # Validate all Jenkinsfiles structure
make test-dsl                 # Enhanced DSL validation with security
make test-jenkins-security    # Security pattern scanning

# Pre-commit hook management
make pre-commit-install       # Install pre-commit hooks
make pre-commit-run          # Run pre-commit on all files
make pre-commit-update       # Update hooks to latest versions
make pre-commit-clean        # Clean pre-commit cache

# Enhanced DSL syntax validator
./scripts/dsl-syntax-validator.sh --dsl-path jenkins-dsl/ --security-check --complexity-check
./scripts/dsl-syntax-validator.sh --dsl-path pipelines/ --security-check --output-format json

# Manual validation runs (useful for debugging)
pre-commit run groovy-syntax --all-files
pre-commit run jenkinsfile-validation --all-files  
pre-commit run jenkins-security-scan --all-files
```

### Smart Data Sharing Commands (Blue-Green Enhancement)
```bash
# Preview smart sharing migration (dry run)
scripts/migrate-to-smart-sharing.sh --dry-run

# Migrate specific team to smart sharing
scripts/migrate-to-smart-sharing.sh --team devops

# Migrate all teams to smart sharing 
scripts/migrate-to-smart-sharing.sh --force

# Rollback migration if issues occur
scripts/rollback-smart-sharing.sh --team devops

# Validate shared storage after migration
ansible-playbook ansible/site.yml --tags shared-storage,validation
```

### Unified Data Management Commands (Enterprise Backup & Sync)
```bash
# Basic operations
scripts/unified-devops-manager.sh --sync-only             # Traditional sync operations
scripts/unified-devops-manager.sh --backup-only           # Backup operations only  
scripts/unified-devops-manager.sh --sync-and-backup       # Parallel sync and backup

# Sequential operations
scripts/unified-devops-manager.sh --backup-then-sync      # Backup first, then sync
scripts/unified-devops-manager.sh --sync-then-backup      # Sync first, then backup

# Advanced targeting
scripts/unified-devops-manager.sh --target green --sync-only        # Blue-green sync
scripts/unified-devops-manager.sh --backup-only --retention 30      # Custom retention  
scripts/unified-devops-manager.sh --sync-and-backup --dry-run       # Preview operations
scripts/unified-devops-manager.sh --backup-then-sync --verbose      # Detailed logging

# Team-specific operations
scripts/unified-developer-manager.sh --sync-only          # Developer team sync only
scripts/unified-qa-manager.sh --backup-then-sync          # QA team backup then sync
```

### Environment Setup
```bash
# Install Python dependencies
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r collections/requirements.yml

# Generate secure credentials
scripts/generate-credentials.sh production

# Setup vault passwords (interactive)
ansible-vault create ansible/inventories/production/group_vars/all/vault.yml

# Automated HA setup (production)
scripts/ha-setup.sh production full

# Disaster recovery validation
scripts/disaster-recovery.sh production --validate
```

## Architecture Overview

### Core Infrastructure Components
- **🔄 Resource-Optimized Blue-Green Jenkins Masters**: Multiple team environments with zero-downtime deployments and automated rollback. **OPTIMIZED**: Only active environment runs (50% resource reduction), single configuration per team with runtime environment differentiation
- **🌐 Dynamic HAProxy Load Balancer**: Advanced traffic routing with health checks, SLI monitoring, and API management. **ENHANCED**: Supports dynamic team discovery, corrected subdomain format (`{team}jenkins.domain.com`), and blue-green switching
- **🔒 Dynamic SSL Certificate Management**: Wildcard SSL certificates auto-generated based on `jenkins_teams` configuration. **NEW**: Team-aware certificate generation with automatic subdomain inclusion
- **🔧 Secure Dynamic Jenkins Agents**: Container-based agents (maven, python, nodejs, dind) with security constraints and vulnerability scanning
- **📋 Job DSL Automation**: Code-driven job creation with security sandboxing and approval workflows. **IMPROVED**: Production-safe DSL with no auto-execution startup failures
- **📊 Comprehensive Monitoring Stack**: Prometheus metrics, enhanced Grafana dashboards with 26 panels, DORA metrics, and SLI tracking
- **💾 Enterprise Backup & DR**: Automated backup with RTO/RPO compliance and automated disaster recovery procedures
- **📁 Smart Shared Storage**: NFS/GlusterFS with selective data sharing - jobs/builds/workspace shared between blue-green, plugins isolated for safe upgrades
- **🛡️ Security Infrastructure**: Container security monitoring, vulnerability scanning, compliance validation, and audit logging
- **🪝 Pre-commit Validation Framework**: Comprehensive code quality enforcement with Groovy/Jenkinsfile validation, security scanning, and automated CI/CD integration

### Deployment Flow (ansible/site.yml)
1. **Pre-deployment Validation**: Comprehensive system validation framework with connectivity, security, and resource checks
2. **Bootstrap Infrastructure**: Common setup, Docker, shared storage, security hardening with container security constraints
4. **Secure Jenkins Image Building**: Custom Jenkins images with vulnerability scanning and security validation
5. **Blue-Green Jenkins Deployment**: Deploy blue/green environments with enhanced pre-switch validation and automated rollback triggers
6. **HAProxy Load Balancer Setup**: Configure traffic routing, health checks, and SLI monitoring integration
7. **Job DSL Seed Job Creation**: Secure automated job creation with approval workflows (removed vulnerable dynamic-ansible-executor.groovy)
8. **Enhanced Monitoring and Backup Setup**: Comprehensive Grafana dashboards, SLI tracking, and enterprise backup procedures
9. **Security Scanning & Compliance**: Container vulnerability scanning, security constraint validation, and compliance reporting
10. **Post-Deployment Verification**: Multi-layer health checks, security validation, and comprehensive deployment summary

### Key Ansible Roles
- `jenkins-master-v2`: **OPTIMIZED** Unified Jenkins deployment with single configuration per team, **resource-optimized blue-green deployment** (active-only containers), production-safe DSL architecture, 55% code reduction (4 files vs 13 files), and **INTEGRATED BACKUP** via unified-data-manager.sh with 5-mode operations
- `high-availability-v2`: **ENHANCED** Advanced HA configuration with perfect jenkins-master-v2 compatibility, dynamic team discovery, resource-optimized blue-green deployment, and **NEW** dynamic SSL certificate generation based on `jenkins_teams`
- `monitoring`: Enhanced Prometheus/Grafana stack with 26-panel dashboards, DORA metrics, SLI tracking, and automated alerting
- `security`: **REFACTORED** System hardening and compliance validation (SSL generation moved to high-availability-v2 for better separation of concerns)
- `common`: System bootstrap with pre-deployment validation framework


### Environment Configuration
- **Production**: `environments/production.env` and `ansible/inventories/production/`
- **Local**: `environments/local.env` and `ansible/inventories/local/` with `deployment_mode: local`
- **Vault Variables**: Encrypted in `ansible/inventories/*/group_vars/all/vault.yml`

### Pipeline Definitions
Jenkins pipelines are pre-configured in `pipelines/` directory with enhanced security and safety:
- `Jenkinsfile.infrastructure-update`: Infrastructure updates with **automated rollback triggers**, SLI monitoring, and approval gates
- `Jenkinsfile.backup`: Automated backup procedures with validation and reporting
- `Jenkinsfile.disaster-recovery`: Comprehensive disaster recovery with RTO/RPO compliance testing
- `Jenkinsfile.monitoring`: Enhanced monitoring setup with SLI configuration and alerting
- `Jenkinsfile.security-scan`: **Trivy vulnerability scanning** with compliance reporting
- `Jenkinsfile.image-builder`: Secure image building with vulnerability scanning and security validation
- `Jenkinsfile.health-check`: Multi-layer health monitoring with blue-green validation and security checks

### Job DSL Scripts
Job definitions are organized in `jenkins-dsl/` directory with enhanced security:
- `jenkins-dsl/folders.groovy`: Folder structure creation
- `jenkins-dsl/views.groovy`: View and dashboard definitions
- `jenkins-dsl/infrastructure/secure-ansible-executor.groovy`: **Secure Ansible execution** with sandboxing and approval workflows (replaces removed dynamic-ansible-executor.groovy)
- `jenkins-dsl/infrastructure/*.groovy`: Infrastructure pipeline jobs with security validation
- `jenkins-dsl/applications/*.groovy`: Sample application jobs with security best practices

**Security Note**: The vulnerable `dynamic-ansible-executor.groovy` has been removed and replaced with secure execution patterns.

### Inventory Structure
Required inventory groups for proper deployment:
- `jenkins_masters`: Blue-green Jenkins master nodes (supports multiple teams)
- `monitoring`: Prometheus/Grafana monitoring stack
- `load_balancers`: HAProxy load balancer nodes
- `shared_storage`: NFS/GlusterFS storage nodes

**Note**: No static agents - all agents are dynamic containers provisioned on-demand

### Script Utilities
- `scripts/deploy.sh`: Environment-aware deployment wrapper with validation
- `scripts/backup.sh`: Manual backup execution with integrity validation
- `scripts/disaster-recovery.sh`: **Enterprise-grade automated disaster recovery** with RTO/RPO compliance (508 lines)
- `scripts/ha-setup.sh`: **Comprehensive HA infrastructure setup automation** with multiple deployment modes (559 lines)
- `scripts/blue-green-switch.sh`: Blue-green environment switching with enhanced pre-switch validation
- `scripts/blue-green-healthcheck.sh`: Multi-layer health validation for environments
- `scripts/monitor.sh`: Monitoring stack management with SLI configuration
- `scripts/generate-credentials.sh`: **Secure credential generation** and rotation
- `/usr/local/bin/jenkins-security-scan.sh`: **Trivy vulnerability scanning** automation
- `/usr/local/bin/jenkins-security-monitor.sh`: **Real-time security monitoring** with compliance validation

## Important Notes

### Blue-Green Deployment Considerations  
- **🚀 COMPLETE RESOURCE-OPTIMIZED ARCHITECTURE**: Only active environment runs (50% resource reduction) - **IMPLEMENTED** in both HAProxy and Jenkins master deployments
- **🔄 Active-Only Deployment**: 
  - **HAProxy**: Routes traffic only to active environment backends
  - **Jenkins Masters**: Deploy only active environment containers, inactive containers stopped
  - **Instant Switching**: Ready for zero-downtime environment switching via configuration update
- **⚡ End-to-End Dynamic Environment Switching**: 
  - **HAProxy**: Routes traffic based on `team.active_environment` setting
  - **Jenkins**: Deploys containers based on `team.active_environment` setting
  - **Unified Management**: Single inventory variable controls entire stack
- **🎯 Team-Independent Switching**: Each team can independently switch their blue/green environments without affecting other teams
- **☁️ Dynamic Agent Provisioning**: All agents are dynamic containers provisioned on-demand (no static agent management)
- **🏗️ Consistent Artifacts**: Same Docker images for both environments, differences only at infrastructure and routing level
- **📊 Enhanced Monitoring**: Blue-green status integrated into monitoring dashboards with automated rollback triggers
- **💾 Volume Preservation**: Both blue and green volumes maintained for instant environment switching

### Security and Secrets Management
- **🔐 Enhanced Vault Security**: All sensitive data stored in encrypted Ansible Vault files with automated credential generation
- **🛡️ Container Security**: Trivy vulnerability scanning, security constraints (non-root, non-privileged, read-only filesystem)
- **👁️ Runtime Security Monitoring**: Real-time container security monitoring with automated alerting
- **🔑 Jenkins Security**: Admin credentials encrypted and rotated through Ansible with secure Job DSL execution
- **📜 Dynamic SSL/TLS Management**: **NEW** Wildcard SSL certificates auto-generated based on `jenkins_teams` configuration, managed in `high-availability-v2` role for better architecture
- **✅ Compliance Validation**: Automated security compliance reporting and validation
- **📝 Audit Logging**: Comprehensive security audit logging with centralized collection
- **🚪 Access Controls**: Enhanced RBAC with team-based isolation and security policies
- **🌐 Team-Aware SSL**: SSL certificates automatically include all team subdomains in format `{team}jenkins.{domain}`
- **🪝 Pre-commit Security Validation**: **NEW** Multi-layer security scanning for Groovy/Jenkins code with 25+ security patterns including:
  - **Critical Risk Detection**: System.exit(), Runtime.getRuntime(), ProcessBuilder usage
  - **Code Injection Prevention**: GroovyShell, evaluate(), ScriptEngine pattern detection
  - **Credential Exposure Prevention**: Hardcoded password, token, API key detection
  - **Shell Injection Protection**: Variable expansion in shell command validation
  - **File System Security**: Path traversal, dangerous rm -rf operation detection
  - **Jenkins-Specific Security**: Instance manipulation, master node execution prevention
  - **Privilege Escalation Prevention**: sudo usage, permission modification detection

### Monitoring and Alerting
- **Enhanced Prometheus Rules**: Advanced SLI/SLO monitoring rules in `monitoring/prometheus/rules/jenkins.yml`
- **Comprehensive Grafana Dashboards**: 26-panel dashboard with DORA metrics, SLI tracking, deployment success rates, and blue-green status
- **Multi-layer Health Checks**: Jenkins health checks integrated with monitoring stack and automated rollback triggers
- **Blue-green Environment Monitoring**: Enhanced health monitoring with pre-switch validation and rollback automation
- **HAProxy Advanced Monitoring**: Statistics, health checks, and SLI integration for load balancer monitoring
- **Per-team Security Metrics**: Team-specific dashboards with security compliance and vulnerability tracking
- **Container Security Monitoring**: Real-time security monitoring with resource usage, compliance, and vulnerability alerts
- **Automated Rollback Integration**: SLI threshold monitoring with automatic rollback triggers on performance degradation

### Backup and Recovery
- **Enterprise Backup System**: Automated backup schedules with integrity validation and configurable retention policies
- **Automated Disaster Recovery**: Comprehensive DR procedures with RTO/RPO compliance (15-minute RTO, 5-minute RPO targets)
- **Team Configuration Backup**: Jenkins team configurations and secure Job DSL scripts backed up to encrypted shared storage
- **Blue-green Environment DR**: Enhanced backup and restore procedures with validation and rollback capabilities
- **Database Backup**: Monitoring and registry data backup with point-in-time recovery
- **Version Controlled Recovery**: Job DSL scripts and infrastructure code version controlled with automated recovery workflows
- **DR Site Management**: Automated failover to secondary sites with DNS management and service orchestration
- **Compliance Reporting**: RTO/RPO compliance tracking with automated reporting and alerting

### Development and Code Quality
- **Comprehensive Pre-commit Framework**: **NEW** Advanced code quality enforcement with automated validation pipeline including:
  - **Groovy Validation**: Syntax checking for all 22 Groovy files with Groovy compiler integration and fallback validation
  - **Jenkinsfile Validation**: Structure validation for all 7 Jenkinsfiles with pipeline best practices enforcement
  - **Security Scanning**: Multi-pattern security analysis with 25+ risk detection patterns
  - **Best Practices Enforcement**: Automated checking for naming conventions, documentation, and code organization
  - **GitHub Actions Integration**: Automated PR validation, comprehensive CI/CD testing, and release tagging workflows
  - **Development Environment**: Automated setup with virtual environment, tool installation, and hook configuration
  - **Multiple Output Formats**: Text and JSON reporting for human and machine consumption
  - **Complexity Analysis**: Code complexity monitoring with configurable thresholds and reporting
- always update documentation for the work in repository.
- use code-searcher for all the code scanning
- never use Unicode emoji symbols or images in the code, like these ❌
- always use bash-executor for running any bash commands