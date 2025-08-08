# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-grade Jenkins High Availability infrastructure repository using Ansible for configuration management. The system deploys Jenkins masters in HA configuration with Docker containers, Harbor registry integration, monitoring stack (Prometheus/Grafana), and automated backup systems.

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
- **Jenkins Masters**: Deployed in HA configuration with automatic failover
- **Jenkins Agents**: Dynamic and static agents with various tool stacks (maven, python, nodejs, docker)
- **Harbor Registry**: Private Docker registry for image management
- **Monitoring Stack**: Prometheus metrics collection and Grafana dashboards
- **Backup System**: Automated backup and disaster recovery procedures
- **Shared Storage**: NFS/GlusterFS for persistent data across HA nodes

### Deployment Flow (ansible/site.yml)
1. **Bootstrap Infrastructure**: Common setup, Docker, shared storage, security hardening
2. **Harbor Registry Integration**: Setup private Docker registry connection
3. **Jenkins Image Building**: Custom Jenkins images with predefined agent configurations
4. **Jenkins Infrastructure Deployment**: Masters deployed serially for HA, then agents in parallel
5. **High Availability Configuration**: Load balancer setup and cluster configuration
6. **Monitoring and Backup Setup**: Prometheus/Grafana stack and backup procedures
7. **Post-Deployment Verification**: Health checks and deployment summary

### Key Ansible Roles
- `jenkins-infrastructure`: Core Jenkins master/agent deployment with systemd services
- `high-availability`: HA clustering and load balancer configuration
- `harbor`: Private registry integration and authentication
- `monitoring`: Prometheus/Grafana stack with Jenkins-specific dashboards
- `backup`: Automated backup procedures and disaster recovery
- `security`: Security hardening and access controls

### Environment Configuration
- **Production**: `environments/production.env` and `ansible/inventories/production/`
- **Staging**: `environments/staging.env` and `ansible/inventories/staging/`
- **Vault Variables**: Encrypted in `ansible/inventories/*/group_vars/all/vault.yml`

### Pipeline Definitions
Jenkins pipelines are pre-configured in `pipelines/` directory:
- `Jenkinsfile.infrastructure-update`: Infrastructure updates and maintenance
- `Jenkinsfile.backup`: Automated backup procedures
- `Jenkinsfile.disaster-recovery`: Disaster recovery procedures
- `Jenkinsfile.monitoring`: Monitoring setup and configuration
- `Jenkinsfile.security-scan`: Security scanning procedures
- `Jenkinsfile.image-builder`: Custom image building pipeline

### Inventory Structure
Required inventory groups for proper deployment:
- `jenkins_masters`: HA-enabled Jenkins master nodes
- `jenkins_agents`: Worker nodes for build execution
- `monitoring`: Prometheus/Grafana monitoring stack
- `harbor`: Private Docker registry nodes

### Script Utilities
- `scripts/deploy.sh`: Environment-aware deployment wrapper
- `scripts/backup.sh`: Manual backup execution
- `scripts/disaster-recovery.sh`: Disaster recovery procedures
- `scripts/ha-setup.sh`: High availability cluster setup
- `scripts/monitor.sh`: Monitoring stack management

## Important Notes

### HA Deployment Considerations
- Jenkins masters deploy serially (one at a time) to ensure proper cluster formation
- Agents deploy with 50% parallelization by default (configurable via `agent_serial_execution`)
- Primary master (first in inventory) handles image building and initial cluster setup
- VIP configuration required for load balancer access

### Security and Secrets Management
- All sensitive data stored in Ansible Vault files
- Harbor registry credentials managed through vault variables  
- Jenkins admin credentials encrypted and rotated through Ansible
- SSL/TLS certificates managed in `environments/certificates/`

### Monitoring and Alerting
- Prometheus rules defined in `monitoring/prometheus/rules/jenkins.yml`
- Grafana dashboards in `monitoring/grafana/dashboards/`
- Jenkins health checks integrated with monitoring stack
- Automated alerting for HA failover events

### Backup and Recovery
- Automated backup schedules configurable per environment
- Disaster recovery procedures documented and automated
- Jenkins home directory and configuration backed up to shared storage
- Database backup for monitoring and registry data