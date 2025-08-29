# Jenkins High Availability Infrastructure

![Jenkins HA](https://img.shields.io/badge/Jenkins-HA%20Ready-green) ![Ansible](https://img.shields.io/badge/Ansible-2.14+-blue) ![Docker](https://img.shields.io/badge/Docker-24.x-blue) ![Production Ready](https://img.shields.io/badge/Production-Ready-brightgreen)

A production-grade, containerized Jenkins infrastructure with **Blue-Green Deployment** and **Multi-Team Support** managed through Ansible automation. This repository provides complete infrastructure-as-code for deploying and managing a scalable Jenkins environment with automated pipeline creation, comprehensive monitoring, and enterprise security.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Features](#features)
- [Team Configuration](#team-configuration)
- [Pipeline Automation](#pipeline-automation)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Deployment](#deployment)
- [Operations](#operations)
- [Documentation](#documentation)
- [Support](#support)

## Overview

This infrastructure provides:

- **Blue-Green Deployment**: Zero-downtime deployments with automated environment switching
- **Multi-Team Support**: Isolated Jenkins masters with automated pipeline creation
- **Containerized Architecture**: Docker/Podman containers with native Ansible orchestration
- **Automated Pipeline Creation**: DSL-driven job creation with team-specific configurations
- **Dynamic Agent Scaling**: Container-based agents (Maven, Python, Node.js, DIND) provisioned on-demand
- **HAProxy Load Balancing**: Advanced traffic routing with health checks and team-based routing
- **Monitoring Stack**: Prometheus/Grafana with 26-panel dashboards and DORA metrics
- **Enterprise Security**: Container vulnerability scanning, compliance validation, and audit logging
- **Automated Operations**: Health checks, backups, and infrastructure maintenance
- **Pre-commit Code Quality**: Comprehensive Groovy/Jenkinsfile validation with security scanning

### Key Components

- **Blue-Green Jenkins Masters**: Multiple team environments with zero-downtime switching
- **HAProxy Load Balancer**: Team-aware traffic routing with health checks and API management
- **Automated Pipeline Generation**: DSL-based creation of team-specific jobs and infrastructure pipelines
- **Dynamic Agent Templates**: On-demand containerized agents with security constraints
- **Monitoring**: Enhanced Grafana dashboards with SLI tracking and DORA metrics
- **Storage**: NFS/GlusterFS shared storage with encryption and access controls
- **Security**: Trivy vulnerability scanning, container security monitoring, and compliance validation
- **Code Quality Framework**: Pre-commit hooks with Groovy/Jenkins validation, security scanning, and CI/CD integration

## Quick Start

### For Operators (Deploy to Production)
```bash
# 1. Clone repository
git clone <repository-url>
cd jenkins-ha

# 2. Install dependencies
pip install -r requirements.txt
ansible-galaxy collection install -r ansible/requirements.yml

# 3. Configure inventory
cp ansible/inventories/staging/hosts.yml ansible/inventories/production/hosts.yml
# Edit with your production hosts

# 4. Deploy infrastructure
make deploy-production
```

### For Developers (Local Development)
```bash
# 1. Setup complete development environment with pre-commit hooks
make dev-setup                   # Install pre-commit hooks and setup environment
source ./activate-dev-env.sh     # Activate development environment

# 2. Install dependencies and deploy
pip install -r requirements.txt
make deploy-local

# 3. Access services
# Jenkins: http://localhost:8080 (DevOps team)
# Jenkins: http://localhost:8081 (Developer team)  
# Grafana: http://localhost:9300
# Prometheus: http://localhost:9090

# 4. Comprehensive testing and validation
make test-full                   # Run all tests including pre-commit
make test-security-comprehensive # Run comprehensive security testing
make test-groovy                 # Full Groovy validation (requires Groovy SDK)
make test-groovy-basic           # Basic Groovy validation (no SDK required)
make test-jenkinsfiles           # Validate all Jenkinsfiles structure
make test-dsl                    # Enhanced DSL validation with security
make test-jenkins-security       # Security pattern scanning

# 5. Pre-commit hook management
make pre-commit-install          # Install pre-commit hooks
make pre-commit-run             # Run pre-commit on all files
make pre-commit-update          # Update hooks to latest versions
pre-commit run --all-files      # Manual pre-commit run

# 6. Security testing (enterprise-grade)
make test-secrets               # TruffleHog secret detection
make test-infrastructure-security # Checkov IaC security scanning
make test-dependency-vulnerabilities # OWASP dependency vulnerability scanning
make test-sast                  # Semgrep static application security testing

# 7. Development workflow
make dev-test                   # Run fast development tests
./scripts/security-scan-comprehensive.sh --tools trufflehog,semgrep
./scripts/dsl-syntax-validator.sh --dsl-path jenkins-dsl/ --security-check
```

### For Administrators (Day-2 Operations)
```bash
# Monitor infrastructure
make monitor

# Run backups and disaster recovery
make backup
./scripts/disaster-recovery.sh production --validate

# Comprehensive security operations
make test-security-comprehensive    # Run all security scans
./scripts/security-scan-comprehensive.sh --all
./scripts/security-tool-installer.sh --essential
ansible-playbook ansible/site.yml --tags security --check

# Advanced operational procedures
./scripts/ha-setup.sh production full
./scripts/migrate-to-smart-sharing.sh --dry-run
./scripts/validate-data-flow.sh
ansible-playbook ansible/site.yml --tags validation -e validation_mode=strict

# Unified data management operations
./scripts/unified-devops-manager.sh --sync-and-backup     # DevOps: sync and backup
./scripts/unified-developer-manager.sh --sync-only        # Developer: sync only
./scripts/unified-qa-manager.sh --backup-then-sync        # QA: backup then sync
```

## Architecture

### Multi-Team Blue-Green Architecture
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          HAProxy Load Balancer                             │
│                      Statistics: 8404 | API: 8405                          │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
┌───────▼─────────┐    ┌─────────▼──────────┐    ┌─────────▼─────────┐
│   DevOps Team   │    │  Developer Team    │    │     QA Team       │
│   Port: 8080    │    │   Port: 8081       │    │   Port: 8082      │
└─────────────────┘    └────────────────────┘    └───────────────────┘
│                      │                        │
│ ┌─────────────────┐  │ ┌─────────────────┐    │ ┌─────────────────┐
│ │ Blue Environment│  │ │ Blue Environment│    │ │ Blue Environment│
│ │ jenkins-devops- │  │ │ jenkins-dev-    │    │ │ jenkins-qa-     │
│ │ blue (Active)   │  │ │ blue (Active)   │    │ │ blue (Active)   │
│ └─────────────────┘  │ └─────────────────┘    │ └─────────────────┘
│                      │                        │
│ ┌─────────────────┐  │ ┌─────────────────┐    │ ┌─────────────────┐
│ │Green Environment│  │ │Green Environment│    │ │Green Environment│
│ │ jenkins-devops- │  │ │ jenkins-dev-    │    │ │ jenkins-qa-     │
│ │ green (Standby) │  │ │ green (Standby) │    │ │ green (Standby) │
│ └─────────────────┘  │ └─────────────────┘    │ └─────────────────┘
└──────────────────────┴────────────────────────┴───────────────────┘
                                  │
                         ┌────────▼─────────┐
                         │  Shared Storage  │
                         │   (NFS/GlusterFS)│
                         │ - Jenkins Homes  │
                         │ - Build Artifacts│
                         │ - Team Configs   │
                         └──────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        Dynamic Agent Pool                                   │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐  │
│  │ DIND Agent    │ │ Maven Agent   │ │ Python Agent  │ │ Node.js Agent │  │
│  │ (Docker-in-   │ │ (Java Builds) │ │ (Python Apps) │ │ (Frontend)    │  │
│  │  Docker)      │ │               │ │               │ │               │  │
│  └───────────────┘ └───────────────┘ └───────────────┘ └───────────────┘  │
│                     Auto-scaling: 0-10 agents per team                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Container Architecture
- **Runtime Support**: Docker 24.x and Podman 4.x with native Ansible orchestration
- **Resource-Optimized Blue-Green**: Only active environment runs (50% resource reduction) with dynamic switching
- **Smart Data Sharing**: Selective data sharing between blue-green environments with plugin isolation for safe upgrades
- **Image Management**: Custom-built images with Trivy vulnerability scanning and security hardening
- **Orchestration**: Direct container management with comprehensive validation framework
- **Dynamic SSL Management**: Team-based wildcard SSL certificates auto-generated from jenkins_teams configuration
- **Networking**: Custom bridge networks with DNS resolution, team isolation, and corrected subdomain format ({team}jenkins.domain.com)
- **Storage**: Smart shared storage (NFS/GlusterFS) with selective data sharing and volume preservation
- **Multi-Team Isolation**: Separate container environments with security constraints and resource limits
- **Container Security**: Runtime monitoring, vulnerability scanning, and compliance validation

## Features

### Production-Ready Infrastructure
- ✅ **Blue-Green Deployment**: Zero-downtime deployments with automated switching and rollback triggers
- ✅ **Multi-Team Support**: Isolated Jenkins environments with automated pipeline creation
- ✅ **Container Orchestration**: Docker/Podman with native Ansible management and security constraints
- ✅ **HAProxy Load Balancing**: Team-aware traffic routing with health checks and SLI monitoring
- ✅ **Shared Storage**: NFS/GlusterFS with encryption and access controls
- ✅ **SSL/TLS**: Certificate management and encryption
- ✅ **Automated Pipeline Creation**: DSL-driven job creation with team-specific configurations

### Security & Compliance
- ✅ **System Hardening**: CIS benchmark compliance and security controls
- ✅ **Comprehensive Security Framework**: 7-tool enterprise security scanning (TruffleHog, Checkov, Semgrep, Bandit, Safety, Trivy, OWASP Dependency-Check)
- ✅ **Container Security**: Trivy vulnerability scanning, security constraints, runtime monitoring, and compliance validation
- ✅ **Secret Detection**: TruffleHog advanced secret detection across entire codebase
- ✅ **Infrastructure Security**: Checkov IaC security scanning for Ansible/Docker configurations
- ✅ **Static Application Security Testing**: Enhanced Semgrep SAST with custom security rules
- ✅ **Dependency Vulnerability Scanning**: OWASP Dependency-Check and Safety for comprehensive dependency analysis
- ✅ **Intrusion Detection**: Fail2ban, AIDE file integrity, RKHunter
- ✅ **Access Control**: RBAC, team-based isolation, credential management
- ✅ **Audit Logging**: Comprehensive logging and compliance reporting
- ✅ **Automated Security Scanning**: Cross-platform security tool installation and management
- ✅ **Pre-commit Security Framework**: Multi-layer validation with 4 security hooks and 25+ risk patterns
- ✅ **Security Reporting**: Multi-format security reports (JSON, SARIF, HTML, text)

### Monitoring & Observability  
- ✅ **Enhanced Metrics Collection**: Prometheus with custom Jenkins metrics and SLI tracking
- ✅ **Advanced Visualization**: 26-panel Grafana dashboards with DORA metrics and blue-green status
- ✅ **Automated Alerting**: AlertManager with notification routing and rollback triggers
- ✅ **Log Management**: Centralized logging and analysis
- ✅ **Health Monitoring**: Multi-layer health checks with automated rollback capabilities

### Backup & Recovery
- ✅ **Enterprise Backup**: Automated daily incremental, weekly full backups with RTO/RPO compliance
- ✅ **Unified Data Management**: 5-mode operation system (sync-only, backup-only, sync-and-backup, backup-then-sync, sync-then-backup)
- ✅ **Multiple Targets**: Local, cloud, and remote storage options with flexible targeting
- ✅ **Automated Disaster Recovery**: Complete DR procedures with 15-minute RTO, 5-minute RPO targets
- ✅ **Point-in-Time Recovery**: Restore to specific timestamps with integrity verification
- ✅ **Backup Verification**: Automated backup testing, validation, and comprehensive retention management
- ✅ **Parallel Operations**: Concurrent sync and backup operations for maximum efficiency
- ✅ **Smart Scheduling**: Independent scheduling for different operation types with team-specific overrides

### DevOps Integration
- ✅ **Automated Pipeline Creation**: Team-specific infrastructure and application pipelines
- ✅ **Dynamic Agent Templates**: DIND, Maven, Python, Node.js container agents with security constraints
- ✅ **Job DSL Automation**: Organized job definitions with team-specific configurations
- ✅ **Infrastructure as Code**: Complete Ansible automation with blue-green deployment
- ✅ **Environment Management**: Production, staging, and devcontainer support
- ✅ **Multi-Team Workflows**: Isolated CI/CD environments with automated job provisioning

### Development & Code Quality
- ✅ **Comprehensive Pre-commit Framework**: 12+ hooks with automated setup and management
- ✅ **Enterprise Development Environment**: Complete automated setup with virtual environment and tool configuration
- ✅ **Multi-level Testing**: Fast, full, and security testing modes with comprehensive validation
- ✅ **Groovy Validation**: Full syntax checking for all 22 Groovy files with compiler integration
- ✅ **Jenkinsfile Validation**: Structure validation for all 7 Jenkinsfiles with best practices enforcement
- ✅ **Enhanced DSL Validation**: Security-aware DSL syntax validation with complexity analysis
- ✅ **Security Pattern Detection**: 25+ security pattern detection for Jenkins/Groovy code
- ✅ **GitHub Actions Integration**: Comprehensive CI pipeline with PR validation, security scanning, and automated releases
- ✅ **Development Workflow Automation**: 15+ Makefile targets for streamlined development operations
- ✅ **Cross-platform Compatibility**: Ubuntu, RHEL, and macOS support for all development tools
- ✅ **Multiple Output Formats**: Text, JSON, and SARIF reporting for human and machine consumption
- ✅ **Automated Code Quality**: Pre-commit hook management with update and cleaning capabilities

## Team Configuration

Teams are configured in `ansible/group_vars/all/jenkins_teams.yml` with automatic pipeline creation:

### DevOps Team
```yaml
- team_name: devops
  active_environment: blue
  ports:
    web: 8080
    agent: 50000
  seed_jobs:
    - name: "infrastructure-health-check"
      type: "pipeline"
      display_name: "Infrastructure Health Check"
      triggers:
        - type: "cron"
          schedule: "H/15 * * * *"
    - name: "backup-pipeline"
      type: "pipeline"
      display_name: "Jenkins Backup"
      triggers:
        - type: "cron"
          schedule: "H 3 * * *"
    - name: "image-builder"
      type: "pipeline"
      display_name: "Jenkins Image Builder"
      triggers:
        - type: "cron"
          schedule: "H 2 * * 0"
```

### Developer Team
```yaml
- team_name: developer
  active_environment: blue
  ports:
    web: 8081
    agent: 50001
  seed_jobs:
    - name: "maven-app-pipeline"
      type: "pipeline"
      display_name: "Maven Application Pipeline"
      agent_label: "maven"
      deploy_enabled: true
    - name: "python-app-pipeline"
      type: "pipeline"
      display_name: "Python Application Pipeline"
      agent_label: "python"
    - name: "nodejs-app-pipeline"
      type: "pipeline"
      display_name: "Node.js Application Pipeline"
      agent_label: "nodejs"
```

## Pipeline Automation

### Automated Job Creation
Each team automatically receives:

**Infrastructure Jobs** (DevOps Team):
- Health monitoring (every 15 minutes)
- Automated backups (daily at 3 AM)
- Image building (weekly on Sunday)
- Blue-green environment switching

**Application Pipelines** (Developer Team):
- Maven application builds with testing and Docker image creation
- Python application builds with version selection and linting
- Node.js application builds with version selection and npm options

**Monitoring Jobs** (All Teams):
- Team-specific health checks
- Agent connectivity monitoring
- Storage usage validation

### DSL Seed Job Integration
- **Embedded DSL Scripts**: Team configurations automatically generate pipeline jobs
- **Daily Job Updates**: Seed jobs run at 6 AM to create/update team pipelines
- **Sandbox Security**: All DSL execution runs in sandbox mode with pre-approved signatures
- **External Pipeline Support**: References external Jenkinsfiles in `pipelines/` directory

## Comprehensive Security Scanning

### Enterprise Security Framework

The infrastructure includes a comprehensive 7-tool security scanning framework providing complete coverage across all attack vectors:

```bash
# Complete security scanning suite
make test-security-comprehensive     # Run all security scans
./scripts/security-scan-comprehensive.sh --all
./scripts/security-tool-installer.sh --all
```

### Security Tools Integrated

#### Core Security Scanners
- **TruffleHog**: Advanced secret detection across entire codebase with verified secrets only
- **Checkov**: Infrastructure as Code security scanning for Ansible, Docker, and YAML templates
- **Semgrep**: Static Application Security Testing (SAST) with custom security rules
- **Bandit**: Python security linting with comprehensive vulnerability detection
- **Safety**: Python dependency vulnerability checking against known security databases
- **Trivy**: Container and filesystem vulnerability scanning with severity filtering
- **OWASP Dependency-Check**: Comprehensive dependency vulnerability scanning with CVSS scoring

#### Security Integration Features
```bash
# Individual security tool execution
make test-secrets                    # TruffleHog secret detection
make test-infrastructure-security    # Checkov IaC security
make test-dependency-vulnerabilities # OWASP dependency scanning
make test-sast                      # Semgrep SAST scanning

# Advanced security operations
./scripts/security-scan-comprehensive.sh --tools trufflehog,checkov --output-format json
./scripts/security-tool-installer.sh --essential  # Install core security tools
```

### Security Reporting
- **Multi-format Output**: JSON, SARIF, HTML, and text reporting
- **Severity Filtering**: Configurable severity thresholds and filtering
- **Compliance Integration**: Automated security compliance validation
- **CI/CD Integration**: GitHub Actions security scanning pipeline

## Pre-commit Development Framework

### Comprehensive Code Quality Enforcement

The infrastructure includes an enterprise-grade pre-commit framework with 12+ hooks providing comprehensive code quality enforcement:

```bash
# Setup and manage pre-commit framework
make dev-setup                      # Complete development environment setup
make pre-commit-install             # Install pre-commit hooks
make pre-commit-run                 # Run all hooks on entire codebase
make pre-commit-update              # Update hooks to latest versions
```

### Pre-commit Hook Categories

#### Security Validation Hooks
- **TruffleHog Secret Detection**: Prevent credential leaks with verified secrets scanning
- **Security Pattern Scanning**: 25+ Jenkins/Groovy security risk patterns
- **Checkov IaC Security**: Infrastructure as Code security validation
- **Semgrep SAST**: Static application security testing integration

#### Code Quality Hooks  
- **Groovy Syntax Validation**: Full compiler integration with fallback validation
- **Jenkinsfile Structure Validation**: Best practices enforcement for pipeline definitions
- **DSL Security Validation**: Enhanced Job DSL validation with security analysis
- **YAML/JSON Linting**: Configuration file validation and formatting

#### Development Workflow
```bash
# Multi-level testing support
make test-full                      # Comprehensive test suite
make dev-test                       # Fast development tests
make test-groovy                    # Full Groovy validation (requires SDK)
make test-groovy-basic              # Basic validation (no SDK required)

# Enhanced validation tools
./scripts/dsl-syntax-validator.sh --dsl-path jenkins-dsl/ --security-check
./scripts/pre-commit-setup.sh      # Automated setup with environment detection
```

## Smart Data Sharing Architecture

### Zero-Downtime Blue-Green with Data Consistency

The infrastructure implements smart data sharing to ensure true zero-downtime deployments while maintaining data consistency:

### The Challenge
Traditional blue-green deployments suffer from data inconsistency when switching environments, as each environment maintains isolated data storage.

### The Solution
```bash
# Smart data sharing operations
./scripts/migrate-to-smart-sharing.sh --dry-run      # Preview migration
./scripts/migrate-to-smart-sharing.sh --team devops  # Migrate specific team
./scripts/rollback-smart-sharing.sh --team devops    # Rollback if needed
```

### Data Sharing Strategy
- **Shared Data**: Jobs, builds, workspace, user configurations, system settings
- **Isolated Data**: Plugins, plugin configurations, JVM settings, environment-specific configs
- **Safe Upgrades**: Plugin isolation allows safe Jenkins upgrades without affecting active environment

### Benefits
- **True Zero-Downtime**: No data loss or inconsistency during environment switches
- **Safe Plugin Management**: Isolated plugin upgrades with rollback capability  
- **Resource Optimization**: 50% resource reduction with active-only deployment
- **Data Persistence**: Complete build history and job configurations preserved across switches

## Unified Data Management System

### Enterprise Backup & Sync Operations

The infrastructure includes a comprehensive unified data management system that provides flexible backup and sync operations with enterprise-grade reliability:

### Operation Modes

#### Core Operation Types
```bash
# Sync operations only (traditional behavior)
./scripts/unified-devops-manager.sh --sync-only

# Backup operations only
./scripts/unified-devops-manager.sh --backup-only --retention 14

# Combined operations (parallel execution)
./scripts/unified-devops-manager.sh --sync-and-backup

# Sequential operations (backup first, then sync)
./scripts/unified-devops-manager.sh --backup-then-sync

# Sequential operations (sync first, then backup)
./scripts/unified-devops-manager.sh --sync-then-backup
```

#### Flexible Targeting
```bash
# Sync to shared storage (default)
./scripts/unified-devops-manager.sh --sync-only

# Blue-green environment sync
./scripts/unified-devops-manager.sh --target green --sync-only

# Backup with custom retention and method
./scripts/unified-devops-manager.sh --backup-only --retention 30 --backup-method tar

# Preview operations without execution
./scripts/unified-devops-manager.sh --sync-and-backup --dry-run --verbose
```

### Advanced Features

#### Enterprise Capabilities
- **Parallel Operations**: Concurrent sync and backup for maximum efficiency
- **Verification System**: Built-in integrity verification for both sync and backup
- **Comprehensive Logging**: Detailed operation tracking with configurable log levels
- **Error Handling**: Graceful failure handling with automatic retry logic
- **Progress Tracking**: Real-time status reporting and operation monitoring
- **Retention Management**: Automated cleanup of old backups based on configurable policies

#### Storage Backend Support
- **Local Storage**: Traditional local filesystem backups
- **NFS Storage**: Network-attached storage for centralized backups
- **Future Support**: S3-compatible cloud storage (roadmap item)

#### Security & Compliance
- **Encrypted Backups**: Optional backup encryption with configurable keys
- **Access Controls**: Proper file permissions and ownership management  
- **Audit Logging**: Comprehensive audit trails for compliance requirements
- **Integrity Verification**: Automatic backup integrity validation

### Configuration Management

#### Team-Specific Configuration
```yaml
# Default operation mode for all teams
default_operation_mode: "sync-and-backup"

# Team-specific overrides
team_operation_modes:
  devops: "sync-and-backup"      # DevOps team: full backup and sync
  developer: "sync-only"         # Developer team: sync only
  qa: "backup-then-sync"         # QA team: backup before sync
```

#### Scheduling Configuration
```yaml
# Unified operations schedule
unified_cron_schedule: "*/5 * * * *"    # Every 5 minutes

# Dedicated backup schedule
backup_cron_schedule: "0 2 * * *"       # Daily at 2 AM

# Retention policies
backup_daily_retention: 7               # 7 days
backup_weekly_retention: 4              # 4 weeks
backup_monthly_retention: 12            # 12 months
```

### Operational Benefits

#### Maximum Flexibility
- **Operation Mode Selection**: Choose between sync-only, backup-only, or combined operations
- **Target Flexibility**: Sync to shared storage or specific blue-green environments
- **Method Selection**: Multiple backup methods (tar, borg) and sync methods (rsync, cp)
- **Scheduling Options**: Independent scheduling for different operation types

#### Enterprise Reliability
- **Backup Verification**: Automatic integrity checking for all backups
- **Retry Logic**: Configurable retry mechanisms for failed operations
- **Monitoring Integration**: Built-in metrics and alerting capabilities
- **Resource Management**: Configurable timeouts and resource limits

#### Operational Efficiency
- **Parallel Execution**: Simultaneous sync and backup operations when using combined modes
- **Incremental Sync**: Efficient data synchronization using rsync technology
- **Automated Cleanup**: Intelligent backup retention and cleanup policies
- **Performance Tuning**: Configurable bandwidth limits and resource constraints

### Migration & Compatibility

#### Backward Compatibility
- **Legacy Script Support**: Existing sync scripts remain fully functional
- **Gradual Migration**: Teams can adopt unified system at their own pace
- **Configuration Preservation**: Existing configurations automatically supported
- **Zero Disruption**: New system deploys alongside existing infrastructure

#### Migration Path
```bash
# Enable unified system (default: enabled)
unified_data_management_enabled: true

# Disable legacy scripts (optional)
legacy_script_support: false

# Migration mode for gradual transition
migration_mode: true
```

## Prerequisites

### System Requirements

#### Control Node (Ansible Controller)
- **OS**: Ubuntu 22.04+ or RHEL 9+
- **Python**: 3.9+
- **Ansible**: 2.14+
- **Container Runtime**: Docker 24.x or Podman 4.x
- **Disk Space**: 20GB+ for playbooks and logs
- **Network**: SSH access to target infrastructure

#### Target Infrastructure

**Jenkins Masters (HA Cluster)**
- **CPU**: 4-8 cores per master
- **RAM**: 16GB+ per master (8GB Jenkins + 8GB system)
- **Disk**: 100GB+ OS + 50GB+ container storage + shared storage access
- **Count**: Minimum 1 for blue-green (supports 2-4 masters)

**Dynamic Agent Resources (Container-based)**
- **DIND Agent**: 2GB RAM, privileged Docker access
- **Maven Agent**: 4GB RAM, 3GB heap, persistent .m2 cache
- **Python Agent**: 2GB RAM, pip cache persistence
- **Node.js Agent**: 3GB RAM, npm cache persistence
- **Scaling**: Auto-scaling based on demand (0-10 concurrent agents per team)

**Monitoring Stack**
- **CPU**: 4 cores
- **RAM**: 8GB
- **Storage**: 200GB+ for metrics and logs
- **Ports**: Prometheus (9090), Grafana (9300), cAdvisor (9200)

**Supporting Services**
- **HAProxy Load Balancer**: 2 CPU, 4GB RAM (can be virtual/shared)
- **Shared Storage**: NFS 4.1+ server or GlusterFS 10.x cluster

### Network Requirements
- **Connectivity**: All nodes must have network connectivity
- **DNS**: Hostname resolution or IP-based inventory
- **Firewall**: Required ports open (22/tcp, 80/tcp, 443/tcp, 8080-8082/tcp, 9090/tcp, 9300/tcp)
- **Bandwidth**: 1Gbps+ recommended for image transfers
- **Time Sync**: NTP synchronization across all nodes

## Installation

### 1. Environment Setup

```bash
# Clone repository
git clone <repository-url>
cd jenkins-ha

# Create Python virtual environment
python3 -m venv ansible-env
source ansible-env/bin/activate

# Install Python dependencies
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r ansible/requirements.yml
```

### 2. Inventory Configuration

```bash
# Copy and customize inventory
cp ansible/inventories/staging/hosts.yml ansible/inventories/production/hosts.yml

# Edit inventory with your infrastructure
vim ansible/inventories/production/hosts.yml
```

Required inventory groups:
```yaml
jenkins_masters:
  hosts:
    jenkins-01:
      ansible_host: 192.168.86.30
    jenkins-02:
      ansible_host: 192.168.86.30

load_balancers:
  hosts:
    haproxy-01:
      ansible_host: 192.168.86.30

monitoring:
  hosts:
    monitoring-01:
      ansible_host: 192.168.86.30
```

### 3. Vault Setup

```bash
# Generate vault password
./scripts/vault-setup.sh production

# Create encrypted variables
ansible-vault create ansible/inventories/production/group_vars/all/vault.yml
```

## Deployment

### Production Deployment

```bash
# Full infrastructure deployment
make deploy-production

# Alternative: Direct ansible command
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production
```

### Local Development

```bash
make deploy-local
```

### Component-Specific Deployment

```bash
# Deploy only Jenkins infrastructure
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins

# Deploy monitoring stack
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags monitoring

# Deploy security hardening
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags security
```

### Deployment Verification

```bash
# Test infrastructure health
ansible all -i ansible/inventories/production/hosts.yml -m ping

# Check team services
curl -I http://your-jenkins-vip:8080/login  # DevOps team
curl -I http://your-jenkins-vip:8081/login  # Developer team

# Verify monitoring
curl http://your-monitoring-host:9090/-/healthy  # Prometheus
curl http://your-monitoring-host:9300/api/health  # Grafana

# Check load balancer stats
curl http://your-load-balancer:8404/stats
```

## Operations

### Daily Operations

```bash
# Monitor infrastructure health
make monitor

# Check service status and comprehensive system health
make status
./scripts/validate-data-flow.sh                    # Validate Jenkins agent connectivity
./scripts/validate-jenkins-connectivity.sh         # Test Jenkins master health

# Security operations
make test-security-comprehensive                   # Run all security scans
./scripts/security-scan-comprehensive.sh --all     # Comprehensive security scanning
make test-secrets                                  # Daily secret detection scan

# System maintenance
./scripts/backup.sh status                         # Check backup status
./scripts/monitor.sh logs                          # View system logs

# Unified data management operations
./scripts/unified-devops-manager.sh --sync-and-backup --verbose    # Full DevOps sync and backup
./scripts/unified-developer-manager.sh --sync-only                 # Developer sync operations
./scripts/unified-qa-manager.sh --backup-then-sync                 # QA backup then sync
```

### Team Pipeline Management

```bash
# View team configurations
cat ansible/group_vars/all/jenkins_teams.yml

# Trigger seed job updates (manual)
# Access Jenkins UI -> Team folder -> dsl-seed-job -> Build Now

# Blue-green environment switch
./scripts/blue-green-switch.sh <team-name> switch
```

### Maintenance Operations

```bash
# Backup and disaster recovery
make backup
./scripts/disaster-recovery.sh production --validate  # Validate DR procedures
./scripts/backup.sh emergency                        # Emergency backup

# Security maintenance
make test-security-comprehensive                     # Full security audit
./scripts/security-tool-installer.sh --all          # Update security tools
ansible-playbook ansible/site.yml --tags security   # Security compliance scan

# Infrastructure updates
ansible-playbook ansible/site.yml -e jenkins_version=2.427.1
./scripts/ha-setup.sh production full                # HA infrastructure updates
ansible-playbook ansible/site.yml --tags validation -e validation_mode=strict

# Smart data sharing operations
./scripts/migrate-to-smart-sharing.sh --dry-run      # Preview smart sharing migration
./scripts/migrate-to-smart-sharing.sh --force        # Migrate all teams
./scripts/validate-dsl-signatures.sh                 # Validate DSL signatures

# Unified data management maintenance
./scripts/unified-devops-manager.sh --backup-only --retention 30    # Extended backup retention
./scripts/unified-developer-manager.sh --sync-and-backup --verify   # Sync with verification
./scripts/unified-qa-manager.sh --backup-then-sync --dry-run        # Preview QA operations

# Team configuration updates
# Edit ansible/group_vars/all/jenkins_teams.yml
# Redeploy: ansible-playbook ansible/site.yml --tags jenkins,config
```

### Emergency Operations

```bash
# Disaster recovery
./scripts/disaster-recovery.sh production --validate     # Validate DR procedures
./scripts/disaster-recovery.sh production --execute      # Execute disaster recovery

# Emergency procedures
./scripts/backup.sh emergency                            # Emergency backup
./scripts/fix-blue-green-deployment.sh                   # Fix blue-green deployment issues
./scripts/validate-blue-green-port-fixes.sh              # Validate port configurations

# Blue-green emergency operations
./scripts/blue-green-switch.sh <team-name> rollback      # Emergency rollback
./scripts/rollback-smart-sharing.sh --team <team-name>   # Rollback smart sharing

# Security incident response
./scripts/security-scan-comprehensive.sh --emergency-report
make test-security-comprehensive                         # Emergency security scan
ansible-playbook ansible/site.yml --tags security --check
```

## Advanced Operations & Command Reference

### Complete Makefile Command Reference

#### Core Infrastructure Commands
```bash
make deploy-production              # Deploy to production environment
make deploy-local                   # Deploy to local development
make build-images                   # Build and push Docker images
make backup                         # Run backup procedures
make monitor                        # Setup monitoring stack
make status                         # Check service status
```

#### Comprehensive Testing Suite
```bash
# Master test commands
make test                          # Run all basic tests
make test-full                     # Comprehensive test suite including pre-commit
make dev-test                      # Fast development tests

# Syntax and structure validation
make test-syntax                   # Test Ansible syntax
make test-inventory               # Test inventory configurations
make test-lint                    # Run Ansible linting
make test-templates               # Validate Jinja2 templates
make test-connectivity            # Test connectivity to local environment
```

#### Groovy and Jenkins Validation
```bash
make test-groovy                   # Full Groovy validation (requires Groovy SDK)
make test-groovy-basic            # Basic Groovy validation (no SDK required)
make test-jenkinsfiles            # Validate all Jenkinsfiles
make test-dsl                     # Enhanced DSL validation with security
make test-jenkins-security        # Jenkins security pattern scanning
```

#### Enterprise Security Testing
```bash
make test-security                 # Basic security validation
make test-security-comprehensive  # Run all security scans
make test-secrets                 # TruffleHog secret detection
make test-infrastructure-security # Checkov IaC security scanning
make test-dependency-vulnerabilities # OWASP dependency vulnerability scanning
make test-sast                    # Semgrep static application security testing
make security-report              # Generate comprehensive security report
```

#### Pre-commit Framework Management
```bash
make pre-commit-install           # Install pre-commit hooks
make pre-commit-run              # Run pre-commit on all files
make pre-commit-update           # Update hooks to latest versions
make pre-commit-clean            # Clean pre-commit cache
```

#### Development Environment
```bash
make dev-setup                    # Complete development environment setup
make dev-activate                 # Show how to activate development environment
make dev-test                     # Run development tests (fast subset)
```

### Comprehensive Script Library

#### Security Operations (25+ Scripts)
```bash
# Comprehensive security scanning
./scripts/security-scan-comprehensive.sh --all
./scripts/security-scan-comprehensive.sh --tools trufflehog,checkov --output-format json
./scripts/security-tool-installer.sh --all          # Install all security tools
./scripts/security-tool-installer.sh --essential    # Install essential tools only

# Enhanced DSL validation
./scripts/dsl-syntax-validator.sh --dsl-path jenkins-dsl/ --security-check --complexity-check
./scripts/validate-dsl-signatures.sh                # Validate DSL signatures
```

#### Infrastructure Management
```bash
# High availability setup
./scripts/ha-setup.sh production full               # Complete HA setup
./scripts/disaster-recovery.sh production --validate # Validate DR procedures
./scripts/disaster-recovery.sh production --execute  # Execute disaster recovery

# Smart data sharing
./scripts/migrate-to-smart-sharing.sh --dry-run     # Preview migration
./scripts/migrate-to-smart-sharing.sh --team devops # Migrate specific team
./scripts/rollback-smart-sharing.sh --team devops   # Rollback smart sharing
```

#### Unified Data Management (Advanced Backup & Sync)
```bash
# Basic operations
./scripts/unified-{team}-manager.sh --sync-only             # Traditional sync operations
./scripts/unified-{team}-manager.sh --backup-only           # Backup operations only
./scripts/unified-{team}-manager.sh --sync-and-backup       # Parallel sync and backup

# Sequential operations  
./scripts/unified-{team}-manager.sh --backup-then-sync      # Backup first, then sync
./scripts/unified-{team}-manager.sh --sync-then-backup      # Sync first, then backup

# Advanced targeting and options
./scripts/unified-{team}-manager.sh --target green --sync-only        # Blue-green sync
./scripts/unified-{team}-manager.sh --backup-only --retention 30      # Custom retention
./scripts/unified-{team}-manager.sh --sync-and-backup --dry-run       # Preview operations
./scripts/unified-{team}-manager.sh --backup-then-sync --verbose      # Detailed logging

# Team-specific examples
./scripts/unified-devops-manager.sh --sync-and-backup       # DevOps team unified operations
./scripts/unified-developer-manager.sh --sync-only          # Developer team sync only
./scripts/unified-qa-manager.sh --backup-then-sync          # QA team backup then sync
```

#### Validation and Troubleshooting
```bash
# System validation
./scripts/validate-data-flow.sh                     # Validate Jenkins connectivity
./scripts/validate-jenkins-connectivity.sh          # Test Jenkins master health
./scripts/validate-blue-green-port-fixes.sh         # Validate port configurations
./scripts/validate-jenkins-casc.sh                  # Validate Jenkins Configuration as Code

# Troubleshooting
./scripts/fix-blue-green-deployment.sh              # Fix blue-green deployment issues
./scripts/deploy-haproxy-ssl.sh                     # HAProxy SSL deployment
./scripts/container-operations-validator.sh         # Validate container operations
```

#### Development and Build Tools
```bash
# Development environment
./scripts/pre-commit-setup.sh                       # Setup pre-commit environment
./scripts/generate-pipeline-templates.sh            # Generate pipeline templates
./scripts/plugin-downloader.sh                      # Download Jenkins plugins

# Infrastructure tools
./scripts/build-images.sh                           # Build Docker images
./scripts/generate-secure-credentials.sh            # Generate secure credentials
./scripts/vault-setup.sh                           # Setup Ansible Vault
```

## Documentation

### Core Documentation
- **[CLAUDE.md](CLAUDE.md)**: Complete deployment commands and configuration guidance with enhanced security framework
- **[Architecture](docs/ARCHITECTURE.md)**: System design and component overview
- **[Security Guide](docs/SECURITY.md)**: Comprehensive security hardening, 7-tool scanning framework, compliance, and incident response
- **[Blue-Green Deployment](docs/BLUE-GREEN-DEPLOYMENT.md)**: Zero-downtime deployment strategy with resource optimization
- **[Smart Data Sharing](docs/SMART-DATA-SHARING.md)**: Advanced data consistency for blue-green deployments
- **[Backup & Recovery](docs/BACKUP-RECOVERY.md)**: Backup strategies and disaster recovery procedures
- **[Monitoring](docs/MONITORING.md)**: Enhanced observability with 26-panel dashboards and SLI tracking
- **[High Availability](docs/HIGH-AVAILABILITY.md)**: HA configuration and management with dynamic SSL

### Advanced Documentation
- **[Operations Guide](docs/OPERATIONS.md)**: Day-to-day operational procedures and troubleshooting
- **[Job DSL Management](docs/JOB-DSL-MANAGEMENT.md)**: DSL automation and sandbox security
- **[DSL Sandbox Guide](docs/DSL-SANDBOX-GUIDE.md)**: Secure DSL execution and approval workflows
- **[Multi-Team HAProxy Guide](docs/MULTI-TEAM-HAPROXY-GUIDE.md)**: Advanced load balancer configuration
- **[Containerized HAProxy Guide](docs/CONTAINERIZED-HAPROXY-GUIDE.md)**: Container-based load balancing
- **[Role Separation](docs/ROLE-SEPARATION.md)**: Ansible role architecture and separation of concerns
- **[View Management](docs/VIEW-MANAGEMENT.md)**: Jenkins view and dashboard management
- **[Deployment Guide](docs/DEPLOYMENT.md)**: Comprehensive deployment procedures and validation

### Pipeline Documentation
- **[Pipeline Directory](pipelines/)**: External Jenkinsfile definitions for infrastructure jobs
- **[DSL Scripts](jenkins-dsl/)**: Job DSL definitions and examples
- **[Team Configuration](ansible/group_vars/all/jenkins_teams.yml)**: Team-specific pipeline configurations

## Support

### Getting Help

1. **Documentation**: Check the relevant documentation in the `docs/` directory
2. **Configuration**: Review `CLAUDE.md` for deployment commands and troubleshooting
3. **Issues**: Create an issue with detailed description and logs
4. **Community**: Join our community discussions

### Reporting Issues

When reporting issues, please include:
- Environment details (staging/production)
- Team configuration and affected services
- Error messages and logs
- Steps to reproduce
- Expected vs actual behavior

### Service URLs

After deployment, access services at:

```bash
# Team Services
DevOps Jenkins:    http://<jenkins-host>:8080
Developer Jenkins: http://<jenkins-host>:8081

# Monitoring
Grafana:          http://<monitoring-host>:9300
Prometheus:       http://<monitoring-host>:9090
HAProxy Stats:    http://<load-balancer>:8404/stats

# Local Development
DevOps Jenkins:    http://localhost:8080
Developer Jenkins: http://localhost:8081
Grafana:          http://localhost:9300
Prometheus:       http://localhost:9090
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add/update documentation
5. Submit a pull request

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Jenkins HA Infrastructure** - Production-ready, secure, and highly available Jenkins infrastructure with automated pipeline creation, comprehensive monitoring, and enterprise security.