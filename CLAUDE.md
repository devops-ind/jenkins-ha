# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-grade Jenkins infrastructure with **Blue-Green Deployment**, **Multi-Team Support**, and **Enterprise Security** using Ansible for configuration management. The system deploys Jenkins masters in blue-green configuration with secure container management, HAProxy load balancing, Harbor registry integration, comprehensive monitoring stack (Prometheus/Grafana), automated backup and disaster recovery systems, and Job DSL automation with enhanced security controls.

### Recent Security & Operational Enhancements
- **Container Security**: Trivy vulnerability scanning, security constraints, runtime monitoring
- **Automated Rollback**: SLI-based rollback triggers with configurable thresholds
- **Enhanced Monitoring**: 26-panel Grafana dashboards with DORA metrics and SLI tracking
- **Disaster Recovery**: Enterprise-grade automated DR with RTO/RPO compliance
- **Pre-deployment Validation**: Comprehensive system validation framework
- **Security Compliance**: Real-time security monitoring and compliance reporting

## Key Commands

### Core Deployment Commands
```bash
# Deploy to production environment
make deploy-production

# Deploy to staging environment  
make deploy-staging

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
- **Blue-Green Jenkins Masters**: Multiple team environments with zero-downtime deployments and automated rollback
- **HAProxy Load Balancer**: Advanced traffic routing with health checks, SLI monitoring, and API management
- **Secure Dynamic Jenkins Agents**: Container-based agents (maven, python, nodejs, dind) with security constraints and vulnerability scanning
- **Job DSL Automation**: Code-driven job creation with security sandboxing and approval workflows
- **Harbor Registry Integration**: Private Docker registry with automated image scanning and compliance validation
- **Comprehensive Monitoring Stack**: Prometheus metrics, enhanced Grafana dashboards with 26 panels, DORA metrics, and SLI tracking
- **Enterprise Backup & DR**: Automated backup with RTO/RPO compliance and automated disaster recovery procedures
- **Secure Shared Storage**: NFS/GlusterFS with encryption and access controls for persistent data across teams
- **Security Infrastructure**: Container security monitoring, vulnerability scanning, compliance validation, and audit logging

### Deployment Flow (ansible/site.yml)
1. **Pre-deployment Validation**: Comprehensive system validation framework with connectivity, security, and resource checks
2. **Bootstrap Infrastructure**: Common setup, Docker, shared storage, security hardening with container security constraints
3. **Harbor Registry Integration**: Setup private Docker registry connection with security scanning integration
4. **Secure Jenkins Image Building**: Custom Jenkins images with vulnerability scanning and security validation
5. **Blue-Green Jenkins Deployment**: Deploy blue/green environments with enhanced pre-switch validation and automated rollback triggers
6. **HAProxy Load Balancer Setup**: Configure traffic routing, health checks, and SLI monitoring integration
7. **Job DSL Seed Job Creation**: Secure automated job creation with approval workflows (removed vulnerable dynamic-ansible-executor.groovy)
8. **Enhanced Monitoring and Backup Setup**: Comprehensive Grafana dashboards, SLI tracking, and enterprise backup procedures
9. **Security Scanning & Compliance**: Container vulnerability scanning, security constraint validation, and compliance reporting
10. **Post-Deployment Verification**: Multi-layer health checks, security validation, and comprehensive deployment summary

### Key Ansible Roles
- `jenkins-master`: Unified Jenkins deployment supporting both single and multi-team configurations with blue-green deployment, secure container management, vulnerability scanning, and security constraints
- `harbor`: Private registry integration with automated security scanning and authentication
- `monitoring`: Enhanced Prometheus/Grafana stack with 26-panel dashboards, DORA metrics, SLI tracking, and automated alerting
- `backup`: Enterprise-grade automated backup procedures with RTO/RPO compliance and disaster recovery automation
- `security`: Comprehensive security hardening, container security constraints, vulnerability scanning, compliance validation, and audit logging
- `common`: System bootstrap with pre-deployment validation framework
- `high-availability`: Advanced HA configuration with automated rollback triggers


### Environment Configuration
- **Production**: `environments/production.env` and `ansible/inventories/production/`
- **Staging**: `environments/staging.env` and `ansible/inventories/staging/`
- **DevContainer**: Local development with `deployment_mode: devcontainer`
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
- `harbor`: Private Docker registry nodes
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
- Jenkins masters deploy in blue/green pairs for each team
- Only active environment (blue or green) exposes external ports
- HAProxy handles traffic routing between blue/green environments
- Environment switching provides zero-downtime deployments
- Each team can independently switch their blue/green environments
- Dynamic agents provision on-demand (no static agent management)

### Security and Secrets Management
- **Enhanced Vault Security**: All sensitive data stored in encrypted Ansible Vault files with automated credential generation
- **Container Security**: Trivy vulnerability scanning, security constraints (non-root, non-privileged, read-only filesystem)
- **Runtime Security Monitoring**: Real-time container security monitoring with automated alerting
- **Harbor Registry Security**: Registry credentials managed through vault variables with automated scanning integration
- **Jenkins Security**: Admin credentials encrypted and rotated through Ansible with secure Job DSL execution
- **SSL/TLS Management**: Certificates managed in `environments/certificates/` with automated renewal
- **Compliance Validation**: Automated security compliance reporting and validation
- **Audit Logging**: Comprehensive security audit logging with centralized collection
- **Access Controls**: Enhanced RBAC with team-based isolation and security policies

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