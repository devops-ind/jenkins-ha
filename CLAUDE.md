# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-grade Jenkins infrastructure with **Blue-Green Deployment** and **Multi-Team Support** using Ansible for configuration management. The system deploys Jenkins masters in blue-green configuration with Docker containers, HAProxy load balancing, Harbor registry integration, monitoring stack (Prometheus/Grafana), automated backup systems, and Job DSL automation.

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
python tests/inventory-test.py ansible/inventories/production/hosts.yml

# Test playbook syntax
ansible-playbook tests/playbook-syntax.yml --syntax-check

# Validate Ansible playbook syntax
ansible-playbook ansible/site.yml --syntax-check
```

### Environment Setup
```bash
# Install Python dependencies
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r collections/requirements.yml

# Setup vault passwords (interactive)
ansible-vault create ansible/inventories/production/group_vars/all/vault.yml
```

## Architecture Overview

### Core Infrastructure Components
- **Blue-Green Jenkins Masters**: Multiple team environments with zero-downtime deployments
- **HAProxy Load Balancer**: Advanced traffic routing with health checks and API management
- **Dynamic Jenkins Agents**: Container-based agents (maven, python, nodejs, dind) with auto-scaling
- **Job DSL Automation**: Code-driven job creation and pipeline management
- **Harbor Registry**: Private Docker registry for image management
- **Monitoring Stack**: Prometheus metrics collection and Grafana dashboards
- **Backup System**: Automated backup and disaster recovery procedures
- **Shared Storage**: NFS/GlusterFS for persistent data across teams

### Deployment Flow (ansible/site.yml)
1. **Bootstrap Infrastructure**: Common setup, Docker, shared storage, security hardening
2. **Harbor Registry Integration**: Setup private Docker registry connection
3. **Jenkins Image Building**: Custom Jenkins images with predefined agent configurations
4. **Blue-Green Jenkins Deployment**: Deploy blue/green environments for each team
5. **HAProxy Load Balancer Setup**: Configure traffic routing and health checks
6. **Job DSL Seed Job Creation**: Automated job creation from jenkins-dsl/ scripts
7. **Monitoring and Backup Setup**: Prometheus/Grafana stack and backup procedures
8. **Post-Deployment Verification**: Health checks and deployment summary

### Key Ansible Roles
- `jenkins-infrastructure`: Blue-green Jenkins deployment with multi-team container management
- `harbor`: Private registry integration and authentication
- `monitoring`: Prometheus/Grafana stack with Jenkins-specific dashboards
- `backup`: Automated backup procedures and disaster recovery
- `security`: Security hardening and access controls

### Environment Configuration
- **Production**: `environments/production.env` and `ansible/inventories/production/`
- **Staging**: `environments/staging.env` and `ansible/inventories/staging/`
- **DevContainer**: Local development with `deployment_mode: devcontainer`
- **Vault Variables**: Encrypted in `ansible/inventories/*/group_vars/all/vault.yml`

### Pipeline Definitions
Jenkins pipelines are pre-configured in `pipelines/` directory:
- `Jenkinsfile.infrastructure-update`: Infrastructure updates and maintenance
- `Jenkinsfile.backup`: Automated backup procedures
- `Jenkinsfile.disaster-recovery`: Disaster recovery procedures
- `Jenkinsfile.monitoring`: Monitoring setup and configuration
- `Jenkinsfile.security-scan`: Security scanning procedures
- `Jenkinsfile.image-builder`: Custom image building pipeline
- `Jenkinsfile.health-check`: Comprehensive health monitoring

### Job DSL Scripts
Job definitions are organized in `jenkins-dsl/` directory:
- `jenkins-dsl/folders.groovy`: Folder structure creation
- `jenkins-dsl/views.groovy`: View and dashboard definitions
- `jenkins-dsl/infrastructure/*.groovy`: Infrastructure pipeline jobs
- `jenkins-dsl/applications/*.groovy`: Sample application jobs

### Inventory Structure
Required inventory groups for proper deployment:
- `jenkins_masters`: Blue-green Jenkins master nodes (supports multiple teams)
- `monitoring`: Prometheus/Grafana monitoring stack
- `harbor`: Private Docker registry nodes
- `load_balancers`: HAProxy load balancer nodes
- `shared_storage`: NFS/GlusterFS storage nodes

**Note**: No static agents - all agents are dynamic containers provisioned on-demand

### Script Utilities
- `scripts/deploy.sh`: Environment-aware deployment wrapper
- `scripts/backup.sh`: Manual backup execution
- `scripts/disaster-recovery.sh`: Disaster recovery procedures
- `scripts/blue-green-switch.sh`: Blue-green environment switching
- `scripts/blue-green-healthcheck.sh`: Health validation for environments
- `scripts/monitor.sh`: Monitoring stack management
- `scripts/vault-setup.sh`: Ansible vault password management

## Important Notes

### Blue-Green Deployment Considerations
- Jenkins masters deploy in blue/green pairs for each team
- Only active environment (blue or green) exposes external ports
- HAProxy handles traffic routing between blue/green environments
- Environment switching provides zero-downtime deployments
- Each team can independently switch their blue/green environments
- Dynamic agents provision on-demand (no static agent management)

### Security and Secrets Management
- All sensitive data stored in Ansible Vault files
- Harbor registry credentials managed through vault variables  
- Jenkins admin credentials encrypted and rotated through Ansible
- SSL/TLS certificates managed in `environments/certificates/`

### Monitoring and Alerting
- Prometheus rules defined in `monitoring/prometheus/rules/jenkins.yml`
- Grafana dashboards in `monitoring/grafana/dashboards/`
- Jenkins health checks integrated with monitoring stack
- Blue-green environment health monitoring and alerting
- HAProxy statistics and health check monitoring
- Per-team metrics and dashboards

### Backup and Recovery
- Automated backup schedules configurable per environment
- Disaster recovery procedures documented and automated
- Jenkins team configurations and Job DSL scripts backed up to shared storage
- Blue-green environment backup and restore procedures
- Database backup for monitoring and registry data
- Job DSL scripts version controlled for recovery