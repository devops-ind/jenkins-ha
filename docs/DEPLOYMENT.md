# Jenkins HA Deployment Guide

## Overview

This document provides comprehensive deployment guidance for the Jenkins High Availability infrastructure with enhanced security, automated rollback capabilities, and enterprise-grade operational procedures.

**Enhanced Features:**
- **Automated HA Setup**: Enterprise-grade setup script with 559 lines of functionality
- **Security Integration**: Trivy vulnerability scanning and container security constraints
- **Automated Rollback**: SLI-based rollback triggers and approval gates
- **Pre-deployment Validation**: Comprehensive system validation framework
- **Blue-Green Deployment**: Enhanced blue-green operations with validation

## Table of Contents

- [Quick Start](#quick-start)
- [Pre-deployment Preparation](#pre-deployment-preparation)
- [Deployment Methods](#deployment-methods)
- [Enhanced Infrastructure Pipeline](#enhanced-infrastructure-pipeline)
- [Blue-Green Deployment](#blue-green-deployment)
- [Security Deployment](#security-deployment)
- [Post-deployment Validation](#post-deployment-validation)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Automated HA Setup (Recommended)

```bash
# 1. Clone repository and setup credentials
git clone https://github.com/company/jenkins-ha.git
cd jenkins-ha
scripts/generate-credentials.sh production

# 2. Configure inventory with your infrastructure details
cp ansible/inventories/production/hosts.yml.example ansible/inventories/production/hosts.yml
# Edit hosts.yml with your infrastructure details

# 3. Deploy full HA infrastructure with validation
scripts/ha-setup.sh production full

# 4. Validate deployment
scripts/ha-setup.sh production validate-only
```

### Traditional Make-based Deployment

```bash
# Setup and deploy
make vault-create && make credentials
make deploy-production
make health-check
```

## Prerequisites

### System Requirements

#### Control Node (Ansible Host)
- **OS**: Ubuntu 22.04+ or RHEL 9+
- **Python**: 3.9+
- **Ansible**: 2.14+
- **Container Runtime**: Docker 24.x or Podman 4.x
- **Disk Space**: 20GB+ for playbooks, images, and logs
- **Network**: SSH access to all target nodes

#### Target Nodes

**Jenkins Masters (minimum 2 for HA)**
- **CPU**: 4-8 cores (for container orchestration)
- **RAM**: 16GB+ (8GB for Jenkins + 8GB for system/containers)
- **Disk**: 100GB+ (OS) + 50GB+ (container storage) + Shared storage access
- **OS**: Ubuntu 22.04+ or RHEL 9+
- **Container Runtime**: Docker 24.x or Podman 4.x
- **Network**: 1Gbps+ with low latency to shared storage

**Jenkins Agents (Containerized)**
- **CPU**: 4-16 cores (based on parallel build requirements)
- **RAM**: 8-32GB (containers + build requirements)
- **Disk**: 100GB+ (OS) + 200GB+ (container volumes + build workspace)
- **OS**: Ubuntu 22.04+ or RHEL 9+
- **Container Runtime**: Docker 24.x or Podman 4.x

**Shared Storage**
- **Type**: NFS 4.1+ server or GlusterFS 10.x cluster
- **Capacity**: 1TB+ (scalable with growth)
- **Performance**: 2000+ IOPS, 100MB/s+ throughput
- **Redundancy**: RAID 10 or distributed replication
- **Network**: Dedicated storage network recommended

**Harbor Registry Node**
- **CPU**: 4 cores
- **RAM**: 8GB
- **Disk**: 200GB+ (for image storage)
- **OS**: Ubuntu 22.04+ or RHEL 9+
- **Network**: High bandwidth for image push/pull

**Monitoring Nodes**
- **CPU**: 4 cores
- **RAM**: 8GB
- **Disk**: 200GB+ (for metrics storage and retention)
- **OS**: Ubuntu 22.04+ or RHEL 9+

### Software Dependencies

#### Required Packages
```bash
# Install Python and Ansible
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv

# Create virtual environment
python3 -m venv ansible-env
source ansible-env/bin/activate

# Install Ansible and dependencies
pip install -r requirements.txt

# Install additional tools
sudo apt-get install -y \
    openssh-client \
    rsync \
    git \
    curl \
    jq \
    docker.io \
    docker-compose \
    sshpass
```

#### Ansible Collections
```bash
# Install required collections
ansible-galaxy collection install -r ansible/requirements.yml

# Key collections used:
# - community.docker (Docker management)
# - containers.podman (Podman support)
# - ansible.posix (POSIX utilities)
# - community.general (General utilities)
```

#### Container Runtime Setup
```bash
# Docker setup (if using Docker)
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER

# Podman setup (if using Podman)
sudo apt-get install -y podman
sudo systemctl enable podman
sudo systemctl start podman
```

#### Network Configuration
- **SSH Key Authentication**: Passwordless SSH access to all nodes
- **Container Networks**: Docker/Podman bridge networks for isolation
- **Firewall Rules**: Required ports open between components (see SECURITY.md)
- **DNS Resolution**: All hostnames resolvable or use IP addresses
- **Time Synchronization**: NTP configured on all nodes (chrony recommended)

### Credentials and Certificates

#### Required Secrets
- **Ansible Vault Password**: For encrypted variables
- **SSH Private Keys**: For node access
- **Jenkins Admin Password**: For initial setup
- **Harbor Registry Credentials**: For image management
- **SSL Certificates**: For HTTPS (optional)

#### Vault Setup
```bash
# Create vault password file
echo "your-secure-vault-password" > environments/vault-passwords/.vault_pass_production
chmod 600 environments/vault-passwords/.vault_pass_production

# Create encrypted variables
ansible-vault create ansible/inventories/production/group_vars/all/vault.yml
```

## Environment Preparation

### 1. Inventory Configuration

#### Production Inventory
```yaml
# ansible/inventories/production/hosts.yml
all:
  children:
    jenkins_masters:
      hosts:
        jenkins-master-01:
          ansible_host: 10.0.2.10
          jenkins_master_priority: 1
        jenkins-master-02:
          ansible_host: 10.0.2.11
          jenkins_master_priority: 2
    jenkins_agents:
      hosts:
        jenkins-agent-01:
          ansible_host: 10.0.3.10
          agent_labels: ["docker", "dind", "privileged"]
        jenkins-agent-02:
          ansible_host: 10.0.3.11
          agent_labels: ["maven", "java", "dynamic"]
        jenkins-agent-03:
          ansible_host: 10.0.3.12
          agent_labels: ["python", "nodejs", "dynamic"]
    monitoring:
      hosts:
        monitoring-01:
          ansible_host: 10.0.6.10
    harbor:
      hosts:
        harbor-01:
          ansible_host: 10.0.5.10
    shared_storage:
      hosts:
        storage-01:
          ansible_host: 10.0.4.10
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/jenkins-infra.pem
    jenkins_vip: 10.0.1.10
    shared_storage_path: /mnt/jenkins-shared
```

### 2. Environment Variables

#### Production Environment
```bash
# environments/production.env
ENVIRONMENT=production
JENKINS_VERSION=2.426.1
JENKINS_MASTER_HOST=jenkins-master-01
HARBOR_REGISTRY=harbor.company.com
BACKUP_ENABLED=true
MONITORING_ENABLED=true
HA_ENABLED=true
SHARED_STORAGE_TYPE=nfs
PROMETHEUS_HOST=monitoring-01
BACKUP_RETENTION_DAYS=30
```

### 3. Vault Variables

#### Encrypted Secrets
```yaml
# ansible/inventories/production/group_vars/all/vault.yml
vault_jenkins_admin_password: "SecureAdminPassword123!"
vault_harbor_admin_password: "HarborAdminPass456!"
vault_harbor_db_password: "DatabasePassword789!"
vault_harbor_redis_password: "RedisPassword012!"
vault_monitoring_admin_password: "MonitoringPass345!"
vault_backup_encryption_key: "BackupEncryptionKey678!"
```

## Initial Deployment

### 1. Pre-Deployment Validation

#### System Checks
```bash
# Verify Ansible installation
ansible --version

# Test connectivity
ansible all -i ansible/inventories/production/hosts.yml -m ping

# Validate inventory
python3 tests/inventory-test.py ansible/inventories/production/hosts.yml

# Check playbook syntax
ansible-playbook ansible/site.yml --syntax-check
```

#### Environment Validation
```bash
# Check disk space on all nodes
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "df -h / | tail -1"

# Verify time synchronization
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "timedatectl status"

# Check network connectivity between nodes
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "ping -c 3 {{ hostvars[groups['shared_storage'][0]]['ansible_host'] }}"
```

### 2. Bootstrap Deployment

#### Phase 1: Base Infrastructure
```bash
# Deploy base system configuration
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags common \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Deploy container runtime (Docker/Podman)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags docker \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Deploy shared storage
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags shared-storage \
  --vault-password-file=environments/vault-passwords/.vault_pass_production
```

#### Phase 2: Security and Registry
```bash
# Deploy security hardening
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags security \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Deploy Harbor registry
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags harbor \
  --vault-password-file=environments/vault-passwords/.vault_pass_production
```

#### Phase 3: Jenkins Images
```bash
# Build and push Jenkins images
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins-images \
  --vault-password-file=environments/vault-passwords/.vault_pass_production \
  --limit jenkins_masters[0]  # Build only on primary master
```

### 3. Full Infrastructure Deployment

#### Complete Deployment (Recommended)
```bash
# Deploy entire infrastructure with proper ordering
make deploy-production

# Alternative: Direct ansible command with all phases
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production
```

#### Staged Deployment (Advanced)
```bash
# Phase 4: Jenkins Infrastructure
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Phase 5: High Availability Setup
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags high-availability \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Phase 6: Monitoring and Backup
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags monitoring,backup \
  --vault-password-file=environments/vault-passwords/.vault_pass_production
```

#### Deployment with Custom Variables
```bash
# Deploy with container runtime selection
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production \
  -e jenkins_container_runtime=podman \
  -e jenkins_version=2.426.1 \
  -e jenkins_master_count=3 \
  -e shared_storage_type=glusterfs
```

#### Container-Specific Deployment Options
```bash
# Deploy with Docker runtime
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production \
  -e jenkins_container_runtime=docker

# Deploy with Podman runtime (rootless containers)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production \
  -e jenkins_container_runtime=podman
```

## Configuration Management

### 1. Jenkins Configuration

#### Initial Setup
```bash
# Access Jenkins web interface
open http://10.0.1.10:8080  # Using VIP address

# Retrieve initial admin password
ansible jenkins_masters[0] -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
```

#### Plugin Management
```bash
# Install additional plugins
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/roles/jenkins-master/tasks/bootstrap-jobs.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production
```

### 2. Agent Configuration

#### Dynamic Agent Setup
```bash
# Configure Kubernetes/Docker agents
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags agents \
  --vault-password-file=environments/vault-passwords/.vault_pass_production
```

### 3. High Availability Setup

#### HA Configuration
```bash
# Setup HA cluster
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/ha-setup.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production
```

## Verification Procedures

### 1. System Health Checks

#### Infrastructure Verification
```bash
# Check container runtime services
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl status docker podman" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Check Jenkins container status
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker ps | grep jenkins-master || podman ps | grep jenkins-master"

# Check Jenkins systemd services
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl status jenkins-master-*"

# Verify shared storage mounts
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "mount | grep jenkins && df -h /shared/jenkins"

# Check container networks
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker network ls | grep jenkins || podman network ls | grep jenkins"

# Check load balancer and VIP status
curl -I http://10.0.1.10:8080/login
curl -s http://10.0.1.10:8404/stats  # HAProxy stats
```

#### Application Testing
```bash
# Test Jenkins API
curl -u admin:password http://10.0.1.10:8080/api/json

# Test Harbor registry
curl -k https://harbor.company.com/api/v2.0/systeminfo

# Test monitoring endpoints
curl http://10.0.6.10:9090/api/v1/query?query=up
curl http://10.0.6.10:3000/api/health
```

### 2. Functionality Testing

#### Build Testing
```bash
# Create test job via API
curl -X POST "http://10.0.1.10:8080/createItem?name=test-job" \
  -u admin:password \
  --data-binary @test-job-config.xml \
  -H "Content-Type: text/xml"

# Trigger test build
curl -X POST "http://10.0.1.10:8080/job/test-job/build" \
  -u admin:password
```

#### HA Testing
```bash
# Test failover
sudo systemctl stop jenkins  # On primary master
# Verify traffic redirects to secondary
curl -I http://10.0.1.10:8080/login
```

## Common Deployment Scenarios

### 1. New Environment Setup

```bash
# Complete setup from scratch
./scripts/deploy.sh production
```

### 2. Adding New Agents

```bash
# Update inventory with new agent
# Run agents deployment
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags agents \
  --limit jenkins_agents
```

### 3. Scaling Masters

```bash
# Add new master to inventory
# Run HA setup
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/ha-setup.yml
```

### 4. Update Deployment

```bash
# Update with new Jenkins version
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  -e jenkins_version=2.427.1
```

## Rollback Procedures

### 1. Configuration Rollback

```bash
# Restore from backup
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/backup-restore.yml \
  -e restore_timestamp=20240115_140000
```

### 2. Version Rollback

```bash
# Deploy previous version
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  -e jenkins_version=2.425.1 \
  -e force_reinstall=true
```

### 3. Emergency Procedures

```bash
# Stop all services
ansible all -i ansible/inventories/production/hosts.yml \
  -m service -a "name=jenkins state=stopped" \
  --become

# Start in maintenance mode
ansible jenkins_masters[0] -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker run -d --name jenkins-maintenance \
    -p 8080:8080 jenkins/jenkins:lts-alpine"
```

## Troubleshooting

### Common Issues

#### 1. Deployment Failures

**Symptom**: Ansible playbook fails
```bash
# Check connectivity
ansible all -i ansible/inventories/production/hosts.yml -m ping

# Verify SSH access
ssh -i ~/.ssh/jenkins-infra.pem ubuntu@jenkins-master-01

# Check vault password
ansible-vault view ansible/inventories/production/group_vars/all/vault.yml
```

#### 2. Jenkins Master Container Issues

**Symptom**: Jenkins not accessible
```bash
# Check container status (Docker)
sudo docker ps -a | grep jenkins-master
sudo docker inspect jenkins-master-1

# Check container status (Podman)
sudo podman ps -a | grep jenkins-master
sudo podman inspect jenkins-master-1

# Check container logs
sudo docker logs jenkins-master-1
# OR
sudo podman logs jenkins-master-1

# Check systemd service status
sudo systemctl status jenkins-master-1.service

# Check disk space and volumes
df -h /opt/jenkins
sudo docker volume ls | grep jenkins
# OR
sudo podman volume ls | grep jenkins

# Check container health
sudo docker inspect jenkins-master-1 | jq '.[0].State.Health'
# OR
sudo podman healthcheck run jenkins-master-1
```

#### 2a. Container Network Issues

**Symptom**: Containers cannot communicate
```bash
# Check container network
sudo docker network inspect jenkins-network
# OR
sudo podman network inspect jenkins-network

# Test container connectivity
sudo docker exec jenkins-master-1 ping jenkins-master-2
sudo docker exec jenkins-master-1 nslookup jenkins-agent-dind

# Check port bindings
sudo docker port jenkins-master-1
sudo netstat -tlnp | grep :8080
```

#### 3. Shared Storage Issues

**Symptom**: NFS mount failures
```bash
# Check NFS service
sudo systemctl status nfs-server

# Test mount manually
sudo mount -t nfs storage-01:/export/jenkins /mnt/test

# Check exports
sudo exportfs -v
```

#### 4. Network Connectivity

**Symptom**: Agents cannot connect
```bash
# Check firewall rules
sudo ufw status

# Test port connectivity
telnet jenkins-master-01 50000

# Check DNS resolution
nslookup jenkins-master-01
```

#### 5. Performance Issues

**Symptom**: Slow build execution
```bash
# Check system resources
top
iostat 1

# Check Jenkins queue
curl -u admin:password http://10.0.1.10:8080/queue/api/json

# Monitor shared storage performance
iostat -x 1
```

### Log Locations

#### System and Deployment Logs
- **Ansible Logs**: `ansible/logs/deploy_*.log`
- **System Logs**: `/var/log/syslog` (Ubuntu) or `/var/log/messages` (RHEL)
- **Systemd Logs**: `journalctl -u jenkins-master-1.service`

#### Container Logs
- **Jenkins Container Logs**: 
  - Docker: `docker logs jenkins-master-1`
  - Podman: `podman logs jenkins-master-1`
  - File: `/opt/jenkins/logs/jenkins.log`
- **Agent Container Logs**: 
  - Docker: `docker logs jenkins-agent-dind`
  - Podman: `podman logs jenkins-agent-python`

#### Application Logs
- **Jenkins Application**: `/shared/jenkins/logs/`
- **HAProxy Logs**: `/var/log/haproxy.log`
- **Harbor Logs**: `/var/log/harbor/` (if deployed)
- **Monitoring Logs**: 
  - Prometheus: `/var/log/prometheus/`
  - Grafana: `/var/log/grafana/`

#### Security and Audit Logs
- **Fail2ban**: `/var/log/fail2ban.log`
- **AIDE**: `/var/log/aide/aide.log`
- **Security Audit**: `/var/log/security-audit.log`

### Support Contacts

- **Infrastructure Team**: infra@company.com
- **Security Team**: security@company.com
- **24/7 Support**: +1-555-0123

### External References

- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Ansible Documentation](https://docs.ansible.com/)
- [Docker Documentation](https://docs.docker.com/)
- [Harbor Documentation](https://goharbor.io/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
