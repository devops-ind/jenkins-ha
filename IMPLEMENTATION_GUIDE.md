# Jenkins HA Infrastructure - Complete Implementation & Troubleshooting Guide

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Running site.yml - Complete Guide](#running-siteyml---complete-guide)
6. [Running Individual Roles](#running-individual-roles)
7. [Running Playbooks](#running-playbooks)
8. [Building and Managing Images](#building-and-managing-images)
9. [Configuration Guide](#configuration-guide)
10. [Common Operations](#common-operations)
11. [Troubleshooting](#troubleshooting)
12. [Advanced Topics](#advanced-topics)

---

## Project Overview

A production-grade Jenkins infrastructure with **Blue-Green Deployment**, **Multi-Team Support**, and **Enterprise Security** using Ansible for configuration management.

### Key Features

✅ **Blue-Green Jenkins Masters**: Zero-downtime deployments with automated rollback
✅ **HAProxy Load Balancer**: Advanced traffic routing with health checks
✅ **Dynamic Container Agents**: Secure, on-demand agent provisioning
✅ **Comprehensive Monitoring**: Prometheus + Grafana with 26-panel dashboards
✅ **Enterprise Backup & DR**: Automated backup with RTO/RPO compliance
✅ **Job DSL Automation**: Code-driven job creation with security sandboxing
✅ **Container Security**: Trivy scanning, runtime monitoring, compliance validation

### Technology Stack

- **Configuration Management**: Ansible 2.9+
- **Containerization**: Docker / Podman
- **Load Balancing**: HAProxy
- **Monitoring**: Prometheus, Grafana, Loki, Promtail
- **Storage**: NFS / GlusterFS
- **CI/CD**: Jenkins with Job DSL
- **Security**: Trivy, SELinux, AppArmor

---

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Load Balancer (HAProxy)                  │
│              Multi-Team Routing + Health Checks                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
┌───────▼──────┐  ┌──────▼──────┐  ┌─────▼───────┐
│ Team Alpha   │  │ Team Beta   │  │ Team Gamma  │
│  Blue/Green  │  │ Blue/Green  │  │ Blue/Green  │
│   Jenkins    │  │  Jenkins    │  │  Jenkins    │
└──────┬───────┘  └──────┬──────┘  └──────┬──────┘
       │                 │                 │
       └─────────────────┼─────────────────┘
                         │
        ┌────────────────┴────────────────┐
        │                                  │
┌───────▼──────────┐         ┌────────────▼─────────┐
│ Monitoring Stack │         │   Shared Storage     │
│ - Prometheus     │         │   - NFS/GlusterFS    │
│ - Grafana        │         │   - Job DSL Scripts  │
│ - Loki           │         │   - Backup Storage   │
└──────────────────┘         └──────────────────────┘
```

### Deployment Flow

1. **Pre-deployment Validation** - System requirements, connectivity, security checks
2. **Bootstrap Infrastructure** - Common setup, Docker, storage, security hardening
3. **Build Jenkins Images** - Custom images with vulnerability scanning
4. **Deploy Jenkins Masters** - Blue-green deployment with health validation
5. **Configure Load Balancer** - HAProxy with multi-team routing
6. **Setup Monitoring** - Prometheus targets, Grafana dashboards
7. **Configure Backup** - Automated backup with DR procedures
8. **Post-deployment Verification** - Multi-layer health checks

---

## Prerequisites

### System Requirements

**Minimum (Development)**:
- CPU: 2 cores
- RAM: 4 GB
- Disk: 20 GB free
- OS: Ubuntu 20.04+, CentOS 7+, RHEL 7+

**Recommended (Production)**:
- CPU: 4+ cores per Jenkins master
- RAM: 8+ GB per Jenkins master
- Disk: 50+ GB SSD
- OS: Ubuntu 22.04 LTS, RHEL 8+

### Software Dependencies

```bash
# Ansible
sudo apt-get update
sudo apt-get install -y ansible python3-pip

# Python packages
pip3 install -r requirements.txt

# Ansible collections
ansible-galaxy collection install -r ansible/requirements.yml

# Docker (if running locally)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

### Network Requirements

- **Outbound Internet**: Docker Hub, GitHub, Maven Central, NPM Registry
- **Ports**:
  - Jenkins Masters: 8080, 8180, 8090, 8190 (blue/green pairs)
  - HAProxy: 80, 443, 8404 (stats)
  - Monitoring: 9090 (Prometheus), 3000 (Grafana), 3100 (Loki)
  - Storage: 2049 (NFS), 24007 (GlusterFS)

---

## Quick Start

### 1. Clone and Setup

```bash
# Clone repository
git clone https://github.com/your-org/jenkins-ha.git
cd jenkins-ha

# Install dependencies
pip3 install -r requirements.txt
ansible-galaxy collection install -r ansible/requirements.yml

# Verify installation
ansible --version
```

### 2. Configure Inventory

**Local Development** (`ansible/inventories/local/hosts.yml`):
```yaml
all:
  children:
    jenkins_masters:
      hosts:
        localhost:
          ansible_connection: local
          deployment_mode: local

    monitoring:
      hosts:
        localhost:
          ansible_connection: local
```

**Production** (`ansible/inventories/production/hosts.yml`):
```yaml
all:
  children:
    jenkins_masters:
      hosts:
        jenkins01:
          ansible_host: 192.168.1.10
          host_fqdn: jenkins01.example.com
        jenkins02:
          ansible_host: 192.168.1.11
          host_fqdn: jenkins02.example.com

    monitoring:
      hosts:
        monitoring01:
          ansible_host: 192.168.1.50
          host_fqdn: monitoring01.example.com

    load_balancers:
      hosts:
        haproxy01:
          ansible_host: 192.168.1.20
          host_fqdn: haproxy01.example.com

    shared_storage:
      hosts:
        storage01:
          ansible_host: 192.168.1.30
          host_fqdn: storage01.example.com
```

### 3. Configure Teams

**File**: `ansible/inventories/production/group_vars/all/jenkins_teams.yml`

```yaml
jenkins_teams:
  - team_name: team-alpha
    active_environment: blue
    blue_green_enabled: true
    ports:
      web: 8080
      agent: 50000
    plugins:
      - git
      - workflow-aggregator
      - docker-workflow

  - team_name: team-beta
    active_environment: blue
    blue_green_enabled: true
    ports:
      web: 8090
      agent: 50010
    plugins:
      - git
      - pipeline-stage-view
      - kubernetes
```

### 4. Setup Secrets

```bash
# Generate credentials
./scripts/generate-secure-credentials.sh production

# Create Ansible Vault
ansible-vault create ansible/inventories/production/group_vars/all/vault.yml
```

**Vault Content**:
```yaml
---
# Jenkins Admin Credentials
vault_jenkins_admin_user: admin
vault_jenkins_admin_password: "CHANGE_ME_SECURE_PASSWORD"

# Docker Registry
vault_docker_registry_username: "registry-user"
vault_docker_registry_password: "CHANGE_ME_REGISTRY_PASSWORD"

# Monitoring
vault_grafana_admin_password: "CHANGE_ME_GRAFANA_PASSWORD"
```

### 5. Deploy (Local)

```bash
# Full deployment
make local

# Or with Ansible directly
cd ansible
ansible-playbook -i inventories/local/hosts.yml site.yml
```

### 6. Deploy (Production)

```bash
# Full deployment with validation
cd ansible
ansible-playbook -i inventories/production/hosts.yml site.yml

# With verbose output
ansible-playbook -i inventories/production/hosts.yml site.yml -vv

# Dry run (check mode)
ansible-playbook -i inventories/production/hosts.yml site.yml --check
```

---

## Running site.yml - Complete Guide

`site.yml` is the main orchestration playbook that deploys the entire infrastructure.

### Basic Usage

```bash
cd ansible

# Full deployment
ansible-playbook -i inventories/production/hosts.yml site.yml

# Verbose mode
ansible-playbook -i inventories/production/hosts.yml site.yml -v
ansible-playbook -i inventories/production/hosts.yml site.yml -vv
ansible-playbook -i inventories/production/hosts.yml site.yml -vvv

# Dry run (no changes)
ansible-playbook -i inventories/production/hosts.yml site.yml --check

# Show differences (with check mode)
ansible-playbook -i inventories/production/hosts.yml site.yml --check --diff
```

### Using Tags to Run Specific Components

Tags allow you to run specific parts of the deployment.

#### 1. Bootstrap Only

```bash
# Run all bootstrap tasks (common, docker, storage, security)
ansible-playbook -i inventories/production/hosts.yml site.yml --tags bootstrap

# Run specific bootstrap components
ansible-playbook -i inventories/production/hosts.yml site.yml --tags common
ansible-playbook -i inventories/production/hosts.yml site.yml --tags docker
ansible-playbook -i inventories/production/hosts.yml site.yml --tags storage
ansible-playbook -i inventories/production/hosts.yml site.yml --tags security
```

**Example Output**:
```
PLAY [Bootstrap Infrastructure] ****************************************

TASK [common : Update apt cache] ***************************************
ok: [jenkins01]

TASK [docker : Install Docker CE] **************************************
changed: [jenkins01]

PLAY RECAP *************************************************************
jenkins01: ok=25 changed=8 unreachable=0 failed=0 skipped=3
```

#### 2. Build Jenkins Images

```bash
# Build all Jenkins images
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true

# Build with vulnerability scanning
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images,build \
  -e build_jenkins_images=true \
  -e trivy_scan_enabled=true
```

**Example Output**:
```
PLAY [Build and Manage Jenkins Images] *********************************

TASK [jenkins-images : Build Jenkins master image] *********************
changed: [jenkins01]

TASK [jenkins-images : Scan image for vulnerabilities with Trivy] ******
ok: [jenkins01]

TASK [jenkins-images : Display vulnerability scan results] *************
ok: [jenkins01] => {
    "msg": "✅ Scan complete: 0 CRITICAL, 2 HIGH, 5 MEDIUM vulnerabilities"
}
```

#### 3. Deploy Jenkins Infrastructure

```bash
# Deploy all Jenkins masters
ansible-playbook -i inventories/production/hosts.yml site.yml --tags jenkins

# Deploy + verify
ansible-playbook -i inventories/production/hosts.yml site.yml --tags jenkins,verify

# Deploy specific team only
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags jenkins \
  -e "jenkins_teams=[{'team_name': 'team-alpha', 'ports': {'web': 8080}}]"
```

**Example Output**:
```
PLAY [Deploy Jenkins Infrastructure] ***********************************

TASK [jenkins-master : Deploy team-alpha blue environment] *************
changed: [jenkins01]

TASK [jenkins-master : Deploy team-alpha green environment] ************
changed: [jenkins01]

TASK [jenkins-master : Wait for Jenkins to be ready] *******************
ok: [jenkins01]

PLAY RECAP *************************************************************
jenkins01: ok=42 changed=15 unreachable=0 failed=0
```

#### 4. Setup Load Balancer

```bash
# Deploy HAProxy
ansible-playbook -i inventories/production/hosts.yml site.yml --tags ha

# With specific tags
ansible-playbook -i inventories/production/hosts.yml site.yml --tags haproxy
ansible-playbook -i inventories/production/hosts.yml site.yml --tags loadbalancer
ansible-playbook -i inventories/production/hosts.yml site.yml --tags cluster
```

**Example Output**:
```
PLAY [Configure High Availability] *************************************

TASK [high-availability : Deploy HAProxy configuration] ****************
changed: [haproxy01]

TASK [high-availability : Start HAProxy container] *********************
changed: [haproxy01]

TASK [high-availability : Verify HAProxy health] ***********************
ok: [haproxy01] => {
    "msg": "✅ HAProxy is healthy: All backends UP"
}
```

#### 5. Setup Monitoring Stack

```bash
# Full monitoring deployment
ansible-playbook -i inventories/production/hosts.yml site.yml --tags monitoring

# Prometheus only
ansible-playbook -i inventories/production/hosts.yml site.yml --tags prometheus

# Grafana only
ansible-playbook -i inventories/production/hosts.yml site.yml --tags grafana

# Update Prometheus targets only (zero-downtime)
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags phase1-file-sd,targets
```

**Example Output**:
```
PLAY [Setup Monitoring Stack] ******************************************

TASK [monitoring : Deploy Prometheus] **********************************
changed: [monitoring01]

TASK [monitoring : Generate Jenkins targets] ***************************
changed: [monitoring01] => (team-alpha)
changed: [monitoring01] => (team-beta)

TASK [monitoring : Deploy Grafana] *************************************
changed: [monitoring01]

TASK [monitoring : Import dashboards] **********************************
changed: [monitoring01] => (jenkins-comprehensive.json)

PLAY RECAP *************************************************************
monitoring01: ok=68 changed=22 unreachable=0 failed=0
```

#### 6. Configure Backup System

```bash
# Setup backup system
ansible-playbook -i inventories/production/hosts.yml site.yml --tags backup

# With storage configuration
ansible-playbook -i inventories/production/hosts.yml site.yml --tags backup,storage
```

**Example Output**:
```
PLAY [Configure Backup System] *****************************************

TASK [backup : Create backup directories] *****************************
changed: [storage01]

TASK [backup : Deploy backup scripts] **********************************
changed: [storage01]

TASK [backup : Configure backup schedules] *****************************
changed: [storage01]

TASK [backup : Enable backup timers] ***********************************
changed: [storage01]
```

#### 7. Run Validation Only

```bash
# Pre-deployment validation
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags validation

# Post-deployment verification
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags verify

# Complete verification suite
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags verify,api,monitoring,summary
```

### Using Multiple Tags

```bash
# Deploy Jenkins and monitoring together
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags jenkins,monitoring

# Full infrastructure except backup
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --skip-tags backup

# Bootstrap + Jenkins only
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags bootstrap,jenkins
```

### Using Extra Variables

```bash
# Override deployment mode
ansible-playbook -i inventories/production/hosts.yml site.yml \
  -e deployment_mode=production

# Skip validation
ansible-playbook -i inventories/production/hosts.yml site.yml \
  -e validation_mode=skip

# Enable debug mode
ansible-playbook -i inventories/production/hosts.yml site.yml \
  -e ansible_debug=true

# Set custom team configuration
ansible-playbook -i inventories/production/hosts.yml site.yml \
  -e "jenkins_teams=[{'team_name': 'custom', 'active_environment': 'blue', 'ports': {'web': 9000}}]"

# Enable feature flags
ansible-playbook -i inventories/production/hosts.yml site.yml \
  -e monitoring_enabled=true \
  -e backup_enabled=true \
  -e trivy_scan_enabled=true
```

### Limiting Execution to Specific Hosts

```bash
# Run on single host
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --limit jenkins01

# Run on multiple hosts
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --limit jenkins01,jenkins02

# Run on host group
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --limit jenkins_masters

# Exclude hosts
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --limit 'all:!jenkins02'
```

### Step-by-Step Execution

```bash
# Interactive step mode
ansible-playbook -i inventories/production/hosts.yml site.yml --step

# Start at specific task
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --start-at-task="Deploy Jenkins Infrastructure"
```

### Parallel and Serial Execution

```bash
# Run on 2 hosts at a time
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --forks 2

# Override serial execution
ansible-playbook -i inventories/production/hosts.yml site.yml \
  -e serial_execution=1
```

---

## Running Individual Roles

Each role can be run independently for targeted updates or troubleshooting.

### 1. Common Role (System Bootstrap)

**Purpose**: System preparation, package installation, user setup

```bash
# Run common role
ansible-playbook -i inventories/production/hosts.yml site.yml --tags common

# What it does:
# - Updates system packages
# - Creates required users and groups
# - Configures system settings (ulimits, sysctl)
# - Installs base packages (curl, git, jq, etc.)
# - Configures NTP
# - Sets up log rotation
```

**Example with specific tasks**:
```bash
# Update packages only
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m apt -a "update_cache=yes" -b

# Create monitoring user
ansible all -i inventories/production/hosts.yml \
  -m user -a "name=prometheus state=present" -b
```

### 2. Docker Role

**Purpose**: Container runtime setup

```bash
# Install Docker
ansible-playbook -i inventories/production/hosts.yml site.yml --tags docker

# Verify Docker installation
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker info" -b

# What it does:
# - Installs Docker CE / Podman
# - Configures Docker daemon
# - Sets up Docker registry authentication
# - Configures storage driver
# - Creates Docker networks
# - Enables and starts Docker service
```

**Manual Docker operations**:
```bash
# Check Docker status
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m systemd -a "name=docker state=started enabled=yes" -b

# Pull base images
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker pull jenkins/jenkins:lts" -b
```

### 3. Shared Storage Role

**Purpose**: NFS/GlusterFS setup for persistent data

```bash
# Setup shared storage
ansible-playbook -i inventories/production/hosts.yml site.yml --tags storage

# Verify mounts
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "df -h | grep /mnt/shared-jenkins" -b

# What it does:
# - Installs NFS/GlusterFS packages
# - Creates storage directories
# - Configures exports/volumes
# - Mounts storage on Jenkins masters
# - Sets permissions
# - Configures backup storage
```

**Manual storage operations**:
```bash
# Check NFS exports
ansible shared_storage -i inventories/production/hosts.yml \
  -m shell -a "showmount -e localhost" -b

# Test write access
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "touch /mnt/shared-jenkins/test && rm /mnt/shared-jenkins/test" -b
```

### 4. Security Role

**Purpose**: Security hardening and SSL/TLS setup

```bash
# Apply security configurations
ansible-playbook -i inventories/production/hosts.yml site.yml --tags security

# What it does:
# - Configures firewall rules
# - Sets up SSL/TLS certificates
# - Hardens SSH configuration
# - Configures SELinux/AppArmor
# - Sets up security scanning
# - Configures audit logging
```

**Manual security checks**:
```bash
# Check firewall status
ansible all -i inventories/production/hosts.yml \
  -m shell -a "ufw status" -b

# Verify SSL certificates
ansible haproxy -i inventories/production/hosts.yml \
  -m shell -a "openssl x509 -in /etc/ssl/certs/jenkins.crt -text -noout" -b
```

### 5. Jenkins-Images Role

**Purpose**: Build custom Jenkins Docker images

```bash
# Build Jenkins images
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true

# Build with security scanning
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e trivy_scan_enabled=true

# What it does:
# - Creates Dockerfiles from templates
# - Installs Jenkins plugins
# - Configures JCasC (Jenkins Configuration as Code)
# - Builds Docker images
# - Scans for vulnerabilities with Trivy
# - Pushes to registry (optional)
# - Tags images appropriately
```

**Manual image operations**:
```bash
# List built images
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker images | grep jenkins" -b

# Tag image
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker tag jenkins-master:latest jenkins-master:v2.0.0" -b

# Push to registry
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker push registry.example.com/jenkins-master:latest" -b
```

### 6. Jenkins-Master Role

**Purpose**: Deploy Jenkins instances with blue-green support

```bash
# Deploy all Jenkins masters
ansible-playbook -i inventories/production/hosts.yml site.yml --tags jenkins

# Deploy specific team
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags jenkins \
  --extra-vars "team_filter=team-alpha"

# What it does:
# - Creates Jenkins home directories
# - Deploys blue and green containers
# - Configures JCasC files
# - Sets up Job DSL seed jobs
# - Configures plugins
# - Sets up agents
# - Configures security
# - Exposes ports (active environment only)
```

**Manual Jenkins operations**:
```bash
# Check running Jenkins containers
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker ps | grep jenkins" -b

# Restart Jenkins (active environment)
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker restart jenkins-team-alpha-blue" -b

# View Jenkins logs
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker logs --tail 100 jenkins-team-alpha-blue" -b
```

### 7. High-Availability Role

**Purpose**: HAProxy load balancer configuration

```bash
# Deploy HAProxy
ansible-playbook -i inventories/production/hosts.yml site.yml --tags ha

# Update HAProxy configuration only
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags haproxy,config

# What it does:
# - Installs HAProxy
# - Configures multi-team routing
# - Sets up health checks
# - Configures SSL/TLS termination
# - Sets up statistics page
# - Configures logging
# - Enables high availability with Keepalived (optional)
```

**Manual HAProxy operations**:
```bash
# Check HAProxy status
ansible load_balancers -i inventories/production/hosts.yml \
  -m shell -a "docker exec haproxy haproxy -v" -b

# View HAProxy stats
ansible load_balancers -i inventories/production/hosts.yml \
  -m uri -a "url=http://localhost:8404/stats"

# Reload HAProxy config
ansible load_balancers -i inventories/production/hosts.yml \
  -m shell -a "docker exec haproxy haproxy -c -f /etc/haproxy/haproxy.cfg && docker restart haproxy" -b
```

### 8. Monitoring Role

**Purpose**: Prometheus, Grafana, Loki deployment

```bash
# Full monitoring stack
ansible-playbook -i inventories/production/hosts.yml site.yml --tags monitoring

# Prometheus only
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags monitoring,prometheus

# Update Prometheus targets (zero-downtime)
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags phase1-file-sd,targets

# Grafana only
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags monitoring,grafana

# What it does:
# - Deploys Prometheus server
# - Generates file-based service discovery targets
# - Deploys exporters (node-exporter, cAdvisor)
# - Deploys Grafana with dashboards
# - Configures Loki for log aggregation
# - Deploys Promtail log collectors
# - Sets up alerting rules
# - Configures Alertmanager (optional)
```

**Manual monitoring operations**:
```bash
# Check Prometheus targets
ansible monitoring -i inventories/production/hosts.yml \
  -m uri -a "url=http://localhost:9090/api/v1/targets return_content=yes"

# Reload Prometheus configuration
ansible monitoring -i inventories/production/hosts.yml \
  -m shell -a "docker exec prometheus kill -HUP 1" -b

# View Prometheus logs
ansible monitoring -i inventories/production/hosts.yml \
  -m shell -a "docker logs prometheus --tail 50" -b

# Check Grafana
ansible monitoring -i inventories/production/hosts.yml \
  -m uri -a "url=http://localhost:3000/api/health return_content=yes"
```

### 9. Backup Role

**Purpose**: Automated backup configuration

```bash
# Configure backup system
ansible-playbook -i inventories/production/hosts.yml site.yml --tags backup

# What it does:
# - Creates backup directories
# - Deploys backup scripts
# - Configures systemd timers
# - Sets up backup retention policies
# - Configures backup verification
# - Sets up disaster recovery procedures
```

**Manual backup operations**:
```bash
# Run backup manually
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "/usr/local/bin/jenkins-backup.sh" -b

# Check backup status
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "systemctl status jenkins-backup.timer" -b

# List backups
ansible shared_storage -i inventories/production/hosts.yml \
  -m shell -a "ls -lht /mnt/backups/jenkins/" -b
```

---

## Running Playbooks

Standalone playbooks for specific operations.

### 1. Blue-Green Switch Playbook

**File**: `ansible/playbooks/blue-green-switch.yml`

**Purpose**: Switch active environment for a team

```bash
# Switch team-alpha from blue to green
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/blue-green-switch.yml \
  -e team_name=team-alpha \
  -e target_environment=green

# Switch with validation
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/blue-green-switch.yml \
  -e team_name=team-alpha \
  -e target_environment=green \
  -e perform_validation=true

# Dry run
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/blue-green-switch.yml \
  -e team_name=team-alpha \
  -e target_environment=green \
  --check
```

**Parameters**:
- `team_name` (required): Team to switch
- `target_environment` (required): blue or green
- `perform_validation` (optional): Pre-switch health check
- `skip_backup` (optional): Skip backup before switch

**Example Output**:
```
PLAY [Blue-Green Environment Switch] ***********************************

TASK [Validate passive environment health] *****************************
ok: [jenkins01] => {
    "msg": "✅ Green environment is healthy"
}

TASK [Update HAProxy backend] ******************************************
changed: [haproxy01]

TASK [Update team configuration] ***************************************
changed: [jenkins01]

TASK [Verify switch completed] *****************************************
ok: [jenkins01] => {
    "msg": "✅ Successfully switched team-alpha to green"
}

PLAY RECAP *************************************************************
jenkins01: ok=12 changed=3 unreachable=0 failed=0
haproxy01: ok=4 changed=1 unreachable=0 failed=0
```

### 2. Disaster Recovery Playbook

**File**: `ansible/playbooks/disaster-recovery.yml`

**Purpose**: Execute disaster recovery procedures

```bash
# Full DR execution
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/disaster-recovery.yml

# Validate DR readiness
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/disaster-recovery.yml \
  --tags validate

# Restore specific team
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/disaster-recovery.yml \
  -e team_name=team-alpha \
  -e restore_date=20251117

# Test DR procedures (no actual changes)
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/disaster-recovery.yml \
  --tags test \
  --check
```

**Tags**:
- `validate`: Check DR readiness
- `backup`: Create pre-DR backup
- `restore`: Restore from backup
- `test`: Test DR procedures
- `verify`: Verify recovery

### 3. Bootstrap Playbook

**File**: `ansible/playbooks/bootstrap.yml`

**Purpose**: Initial infrastructure setup

```bash
# Full bootstrap
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/bootstrap.yml

# Bootstrap specific components
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/bootstrap.yml \
  --tags users,packages

# Bootstrap with custom configuration
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/bootstrap.yml \
  -e bootstrap_skip_docker=false \
  -e bootstrap_skip_storage=false
```

### 4. Jenkins Validation Playbook

**File**: `ansible/playbooks/jenkins-validation.yml`

**Purpose**: Comprehensive Jenkins health checks

```bash
# Validate all Jenkins instances
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/jenkins-validation.yml

# Validate specific team
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/jenkins-validation.yml \
  -e team_name=team-alpha

# Generate validation report
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/jenkins-validation.yml \
  -e generate_report=true \
  -e report_path=/tmp/jenkins-validation.html
```

**Checks performed**:
- ✅ Container health
- ✅ Port accessibility
- ✅ API responsiveness
- ✅ Plugin status
- ✅ Agent connectivity
- ✅ Job DSL execution
- ✅ Backup status
- ✅ Security configuration

### 5. Jenkins Version Upgrade Playbook

**File**: `ansible/playbooks/jenkins-version-upgrade.yml`

**Purpose**: Upgrade Jenkins version with zero-downtime

```bash
# Upgrade to specific version
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/jenkins-version-upgrade.yml \
  -e jenkins_version=2.440.1

# Upgrade with backup
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/jenkins-version-upgrade.yml \
  -e jenkins_version=2.440.1 \
  -e perform_backup=true

# Upgrade specific team only
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/jenkins-version-upgrade.yml \
  -e jenkins_version=2.440.1 \
  -e team_name=team-alpha
```

**Process**:
1. Backup current Jenkins
2. Deploy new version to passive environment
3. Run validation tests
4. Switch to new version
5. Verify upgrade success
6. Rollback if issues detected

---

## Building and Managing Images

### Using update-images.yml

**Note**: Check if `update-images.yml` exists, otherwise use `site.yml` with `--tags images`.

**Build all images**:
```bash
# Using site.yml
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true

# Build with custom base image
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e jenkins_base_image=jenkins/jenkins:2.440.1-lts
```

### Build Specific Images

```bash
# Build master image only
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e image_type=master

# Build agent images
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e image_type=agents

# Build custom team image
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e team_name=team-alpha \
  -e custom_plugins_file=/path/to/team-alpha-plugins.txt
```

### Image Security Scanning

```bash
# Build with Trivy scanning
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e trivy_scan_enabled=true

# Fail build on critical vulnerabilities
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e trivy_scan_enabled=true \
  -e trivy_fail_on_critical=true

# Scan existing images
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "trivy image jenkins-master:latest" -b
```

### Push Images to Registry

```bash
# Build and push
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e jenkins_images_push=true \
  -e docker_registry=registry.example.com

# Tag and push manually
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker tag jenkins-master:latest registry.example.com/jenkins-master:v2.0.0" -b

ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker push registry.example.com/jenkins-master:v2.0.0" -b
```

### Image Versioning

```bash
# Build with version tag
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e jenkins_image_version=v2.0.0

# Build with Git commit SHA
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e jenkins_image_version=$(git rev-parse --short HEAD)

# Build with timestamp
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e jenkins_image_version=$(date +%Y%m%d-%H%M%S)
```

---

## Configuration Guide

### Environment Variables

**File**: `environments/production.env`

```bash
# Deployment Configuration
DEPLOYMENT_ENV=production
ANSIBLE_INVENTORY=ansible/inventories/production/hosts.yml

# Jenkins Configuration
JENKINS_VERSION=2.440.1
JENKINS_ADMIN_USER=admin

# Monitoring Configuration
PROMETHEUS_VERSION=v2.45.0
GRAFANA_VERSION=10.0.3

# Storage Configuration
SHARED_STORAGE_TYPE=nfs  # nfs or glusterfs
NFS_SERVER=storage01.example.com
NFS_PATH=/exports/jenkins

# Security Configuration
SSL_ENABLED=true
TRIVY_SCAN_ENABLED=true

# Backup Configuration
BACKUP_ENABLED=true
BACKUP_RETENTION_DAYS=30
```

**Load environment**:
```bash
source environments/production.env
ansible-playbook -i $ANSIBLE_INVENTORY site.yml
```

### Multi-Team Configuration

**File**: `ansible/inventories/production/group_vars/all/jenkins_teams.yml`

```yaml
jenkins_teams:
  # Development Team
  - team_name: dev-team
    active_environment: blue
    blue_green_enabled: true
    ports:
      web: 8080
      agent: 50000
    resources:
      memory: 4g
      cpu: 2
    plugins:
      - git
      - workflow-aggregator
      - docker-workflow
      - kubernetes
    job_dsl_scripts:
      - job-dsl/dev-team/folders.groovy
      - job-dsl/dev-team/pipelines.groovy

  # QA Team
  - team_name: qa-team
    active_environment: blue
    blue_green_enabled: true
    ports:
      web: 8090
      agent: 50010
    resources:
      memory: 2g
      cpu: 1
    plugins:
      - git
      - junit
      - jacoco
    job_dsl_scripts:
      - job-dsl/qa-team/test-jobs.groovy

  # Production Team
  - team_name: prod-team
    active_environment: green
    blue_green_enabled: true
    ports:
      web: 8100
      agent: 50020
    resources:
      memory: 8g
      cpu: 4
    plugins:
      - git
      - workflow-aggregator
      - kubernetes
      - prometheus
    job_dsl_scripts:
      - job-dsl/prod-team/deployment-pipelines.groovy
    backup_enabled: true
    backup_retention_days: 90
```

### Monitoring Configuration

**File**: `ansible/inventories/production/group_vars/all/monitoring.yml`

```yaml
# Monitoring Settings
monitoring_enabled: true
monitoring_deployment_type: separate  # separate or colocated
monitoring_use_fqdn: false

# Prometheus Configuration
prometheus_scrape_interval: 30s
prometheus_evaluation_interval: 30s
prometheus_retention_days: 15
prometheus_targets_backup_versions: 10

# Grafana Configuration
grafana_admin_user: admin
grafana_admin_password: "{{ vault_grafana_admin_password }}"
grafana_port: 3000
grafana_dashboards:
  - jenkins-comprehensive.json
  - infrastructure-health.json
  - security-metrics.json

# Alerting Configuration
alertmanager_enabled: true
alertmanager_port: 9093
alert_receivers:
  - name: ops-team
    email_configs:
      - to: ops@example.com
  - name: pagerduty
    pagerduty_configs:
      - service_key: "{{ vault_pagerduty_key }}"

# Loki Configuration
loki_enabled: true
loki_retention_days: 30
loki_port: 3100

# Service Discovery
cadvisor_enabled: true
node_exporter_enabled: true
promtail_enabled: true
```

### Storage Configuration

**NFS Configuration**:
```yaml
# File: ansible/inventories/production/group_vars/all/storage.yml
shared_storage_type: nfs
nfs_server: storage01.example.com
nfs_export_path: /exports/jenkins
nfs_mount_point: /mnt/shared-jenkins
nfs_mount_options: rw,sync,hard,intr

nfs_exports:
  - path: /exports/jenkins
    clients:
      - host: 192.168.1.0/24
        options: rw,sync,no_subtree_check,no_root_squash
```

**GlusterFS Configuration**:
```yaml
shared_storage_type: glusterfs
glusterfs_volume_name: jenkins-shared
glusterfs_brick_path: /data/glusterfs/jenkins
glusterfs_mount_point: /mnt/shared-jenkins

glusterfs_nodes:
  - storage01.example.com
  - storage02.example.com
  - storage03.example.com

glusterfs_volume_options:
  performance.cache-size: 1GB
  network.ping-timeout: 10
```

### HA Configuration

**File**: `ansible/inventories/production/group_vars/all/ha.yml`

```yaml
# High Availability Settings
jenkins_ha_enabled: true
haproxy_enabled: true

# HAProxy Configuration
haproxy_stats_port: 8404
haproxy_stats_user: admin
haproxy_stats_password: "{{ vault_haproxy_stats_password }}"

# SSL/TLS Configuration
haproxy_ssl_enabled: true
haproxy_ssl_cert_path: /etc/ssl/certs/jenkins.pem
haproxy_ssl_redirect: true

# Load Balancing
haproxy_balance_algorithm: roundrobin  # roundrobin, leastconn, source
haproxy_health_check_interval: 5s
haproxy_health_check_timeout: 3s

# Keepalived (optional VRRP)
keepalived_enabled: false
keepalived_virtual_ip: 192.168.1.100
keepalived_priority: 100  # Master priority
```

---

## Common Operations

### 1. Add New Team

```bash
# 1. Update jenkins_teams.yml
vi ansible/inventories/production/group_vars/all/jenkins_teams.yml

# Add:
# - team_name: new-team
#   active_environment: blue
#   ports:
#     web: 8200
#     agent: 50030

# 2. Deploy new team
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags jenkins \
  -e "team_filter=new-team"

# 3. Update monitoring
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags monitoring,targets

# 4. Update HAProxy
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags ha
```

### 2. Blue-Green Switch

```bash
# 1. Validate passive environment
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/jenkins-validation.yml \
  -e team_name=team-alpha \
  -e validate_environment=green

# 2. Perform switch
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/blue-green-switch.yml \
  -e team_name=team-alpha \
  -e target_environment=green \
  -e perform_validation=true

# 3. Verify switch
curl http://haproxy01:8080/api/json
```

### 3. Update Jenkins Plugins

```bash
# 1. Update plugins list
vi ansible/inventories/production/group_vars/all/jenkins_teams.yml

# 2. Rebuild image
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags images \
  -e build_jenkins_images=true \
  -e team_name=team-alpha

# 3. Deploy to passive environment
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags jenkins \
  -e team_name=team-alpha \
  -e deploy_environment=green

# 4. Switch environments
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/blue-green-switch.yml \
  -e team_name=team-alpha \
  -e target_environment=green
```

### 4. Scale Jenkins Masters

```bash
# 1. Add new host to inventory
vi ansible/inventories/production/hosts.yml

# Add:
# jenkins_masters:
#   hosts:
#     jenkins03:
#       ansible_host: 192.168.1.12

# 2. Bootstrap new host
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags bootstrap \
  --limit jenkins03

# 3. Deploy Jenkins
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags jenkins \
  --limit jenkins03

# 4. Update HAProxy
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags ha

# 5. Update monitoring
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags monitoring,targets
```

### 5. Backup and Restore

**Manual Backup**:
```bash
# Backup specific team
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "/usr/local/bin/jenkins-backup.sh team-alpha" -b

# Backup all teams
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags backup \
  -e backup_action=execute
```

**Restore**:
```bash
# List available backups
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "ls -lht /mnt/backups/jenkins/team-alpha/" -b

# Restore from backup
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/disaster-recovery.yml \
  -e team_name=team-alpha \
  -e restore_date=20251117 \
  -e restore_time=143000
```

### 6. Update Monitoring Targets

```bash
# Zero-downtime target update
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags phase1-file-sd,targets

# Verify targets
curl -s http://monitoring01:9090/api/v1/targets | jq '.data.activeTargets | length'

# Reload Prometheus
ansible monitoring -i inventories/production/hosts.yml \
  -m shell -a "docker exec prometheus kill -HUP 1" -b
```

### 7. Certificate Renewal

```bash
# Update SSL certificates
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags security,ssl

# Reload HAProxy with new certs
ansible load_balancers -i inventories/production/hosts.yml \
  -m shell -a "docker restart haproxy" -b

# Verify certificate
ansible load_balancers -i inventories/production/hosts.yml \
  -m shell -a "openssl s_client -connect localhost:443 -servername jenkins.example.com < /dev/null 2>/dev/null | openssl x509 -noout -dates" -b
```

### 8. View Logs

```bash
# Jenkins logs
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker logs --tail 100 jenkins-team-alpha-blue" -b

# HAProxy logs
ansible load_balancers -i inventories/production/hosts.yml \
  -m shell -a "docker logs --tail 100 haproxy" -b

# Prometheus logs
ansible monitoring -i inventories/production/hosts.yml \
  -m shell -a "docker logs --tail 50 prometheus" -b

# System logs
ansible all -i inventories/production/hosts.yml \
  -m shell -a "journalctl -u docker.service --since '1 hour ago' --no-pager" -b
```

---

## Troubleshooting

### 1. Ansible Connection Issues

**Problem**: Cannot connect to hosts

```bash
# Test connectivity
ansible all -i inventories/production/hosts.yml -m ping

# Test with verbose output
ansible all -i inventories/production/hosts.yml -m ping -vvv

# Check SSH access
ssh -i ~/.ssh/id_rsa user@jenkins01

# Verify inventory
ansible-inventory -i inventories/production/hosts.yml --list
```

**Solutions**:
```bash
# Fix SSH key permissions
chmod 600 ~/.ssh/id_rsa

# Add SSH key to agent
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa

# Use password authentication
ansible-playbook -i inventories/production/hosts.yml site.yml --ask-pass

# Use sudo password
ansible-playbook -i inventories/production/hosts.yml site.yml --ask-become-pass
```

### 2. Docker Issues

**Problem**: Docker service not running

```bash
# Check Docker status
ansible all -i inventories/production/hosts.yml \
  -m systemd -a "name=docker" -b

# Start Docker
ansible all -i inventories/production/hosts.yml \
  -m systemd -a "name=docker state=started enabled=yes" -b

# Check Docker info
ansible all -i inventories/production/hosts.yml \
  -m shell -a "docker info" -b
```

**Problem**: Container not starting

```bash
# Check container logs
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker logs jenkins-team-alpha-blue" -b

# Inspect container
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker inspect jenkins-team-alpha-blue" -b

# Remove and recreate
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags jenkins \
  -e force_recreate=true
```

### 3. Jenkins Not Accessible

**Problem**: Cannot reach Jenkins web interface

```bash
# Check if container is running
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker ps | grep jenkins-team-alpha-blue" -b

# Check port binding
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker port jenkins-team-alpha-blue" -b

# Test local access
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "curl -I http://localhost:8080" -b

# Check firewall
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "ufw status | grep 8080" -b
```

**Solutions**:
```bash
# Restart container
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker restart jenkins-team-alpha-blue" -b

# Open firewall port
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m ufw -a "rule=allow port=8080 proto=tcp" -b

# Check Jenkins logs
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker logs jenkins-team-alpha-blue | tail -50" -b
```

### 4. Monitoring Targets Not Discovered

**Problem**: Prometheus shows 0 active targets

**Diagnosis**:
```bash
# Check target files exist
ansible monitoring -i inventories/production/hosts.yml \
  -m shell -a "ls -lh /opt/monitoring/prometheus/targets.d/" -b

# Validate JSON syntax
ansible monitoring -i inventories/production/hosts.yml \
  -m shell -a "python3 -m json.tool /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json" -b

# Check Prometheus logs
ansible monitoring -i inventories/production/hosts.yml \
  -m shell -a "docker logs prometheus 2>&1 | grep -i 'file_sd\|error'" -b
```

**Solutions**:
```bash
# Regenerate targets
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags phase1-file-sd,targets

# Reload Prometheus
ansible monitoring -i inventories/production/hosts.yml \
  -m shell -a "docker exec prometheus kill -HUP 1" -b

# Restart Prometheus
ansible monitoring -i inventories/production/hosts.yml \
  -m shell -a "docker restart prometheus" -b

# See detailed troubleshooting:
cat docs/PROMETHEUS_TARGETS_DISCOVERY_GUIDE.md
```

### 5. Storage Mount Issues

**Problem**: Shared storage not mounted

```bash
# Check mount status
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "df -h | grep shared-jenkins" -b

# Check NFS exports
ansible shared_storage -i inventories/production/hosts.yml \
  -m shell -a "showmount -e localhost" -b

# Test NFS connectivity
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "showmount -e storage01" -b
```

**Solutions**:
```bash
# Remount NFS
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "mount -t nfs storage01:/exports/jenkins /mnt/shared-jenkins" -b

# Restart NFS service
ansible shared_storage -i inventories/production/hosts.yml \
  -m systemd -a "name=nfs-kernel-server state=restarted" -b

# Redeploy storage configuration
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags storage
```

### 6. Blue-Green Switch Fails

**Problem**: Environment switch does not complete

```bash
# Check passive environment health
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m uri -a "url=http://localhost:8180/api/json return_content=yes" \
  register: health_check

# Check HAProxy backend status
ansible load_balancers -i inventories/production/hosts.yml \
  -m shell -a "curl http://localhost:8404/stats" -b

# Verify container is running
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "docker ps | grep green" -b
```

**Solutions**:
```bash
# Validate passive environment first
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/jenkins-validation.yml \
  -e team_name=team-alpha \
  -e validate_environment=green

# Manual switch with validation
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/blue-green-switch.yml \
  -e team_name=team-alpha \
  -e target_environment=green \
  -e perform_validation=true \
  -v

# Rollback if needed
ansible-playbook -i inventories/production/hosts.yml \
  playbooks/blue-green-switch.yml \
  -e team_name=team-alpha \
  -e target_environment=blue
```

### 7. Vault Decryption Errors

**Problem**: Cannot decrypt vault files

```bash
# Test vault password
ansible-vault view ansible/inventories/production/group_vars/all/vault.yml

# Re-encrypt vault
ansible-vault rekey ansible/inventories/production/group_vars/all/vault.yml

# Edit vault
ansible-vault edit ansible/inventories/production/group_vars/all/vault.yml
```

**Use vault password file**:
```bash
# Create password file
echo "your-vault-password" > ~/.vault_pass
chmod 600 ~/.vault_pass

# Use in playbook
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --vault-password-file ~/.vault_pass
```

### 8. High Resource Usage

**Problem**: High CPU or memory usage

```bash
# Check container resource usage
ansible all -i inventories/production/hosts.yml \
  -m shell -a "docker stats --no-stream" -b

# Check system resources
ansible all -i inventories/production/hosts.yml \
  -m shell -a "free -h && df -h" -b

# Check for zombie containers
ansible all -i inventories/production/hosts.yml \
  -m shell -a "docker ps -a | grep -i exited" -b
```

**Solutions**:
```bash
# Adjust container resources
# Edit: ansible/inventories/production/group_vars/all/jenkins_teams.yml
# resources:
#   memory: 2g
#   cpu: 1

# Redeploy with new limits
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags jenkins

# Clean up stopped containers
ansible all -i inventories/production/hosts.yml \
  -m shell -a "docker container prune -f" -b

# Clean up images
ansible all -i inventories/production/hosts.yml \
  -m shell -a "docker image prune -a -f" -b
```

---

## Advanced Topics

### 1. Custom Job DSL Integration

**Location**: `jenkins-dsl/`

**Deploy custom DSL**:
```bash
# Update DSL scripts
vi jenkins-dsl/team-alpha/custom-jobs.groovy

# Sync to shared storage
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags jenkins,job-dsl

# Trigger seed job manually
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m uri -a "
    url=http://localhost:8080/job/seed-job/build
    method=POST
    user={{ jenkins_admin_user }}
    password={{ jenkins_admin_password }}
    force_basic_auth=yes
    status_code=201
  "
```

### 2. Multi-Region Deployment

**Setup**:
```yaml
# File: ansible/inventories/multi-region/hosts.yml
all:
  children:
    us_east:
      children:
        jenkins_masters:
          hosts:
            jenkins-us-east-01:
              ansible_host: 10.1.1.10
              region: us-east
        monitoring:
          hosts:
            monitoring-us-east-01:
              ansible_host: 10.1.1.50

    eu_west:
      children:
        jenkins_masters:
          hosts:
            jenkins-eu-west-01:
              ansible_host: 10.2.1.10
              region: eu-west
        monitoring:
          hosts:
            monitoring-eu-west-01:
              ansible_host: 10.2.1.50
```

**Deploy to specific region**:
```bash
ansible-playbook -i inventories/multi-region/hosts.yml site.yml \
  --limit us_east

ansible-playbook -i inventories/multi-region/hosts.yml site.yml \
  --limit eu_west
```

### 3. Custom Agent Templates

**Create custom agent image**:
```bash
# File: docker/agents/custom-agent/Dockerfile
FROM jenkins/inbound-agent:latest

USER root

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    terraform \
    awscli

USER jenkins

# Build
docker build -t custom-jenkins-agent:latest docker/agents/custom-agent/

# Use in pipeline
# Jenkinsfile:
# agent {
#   docker {
#     image 'custom-jenkins-agent:latest'
#   }
# }
```

### 4. Performance Tuning

**Jenkins JVM Options**:
```yaml
# File: ansible/inventories/production/group_vars/all/jenkins_teams.yml
jenkins_teams:
  - team_name: team-alpha
    java_opts: >-
      -Xmx4g
      -Xms2g
      -XX:+UseG1GC
      -XX:MaxGCPauseMillis=200
      -Djava.awt.headless=true
      -Dhudson.model.DirectoryBrowserSupport.CSP="default-src 'self'; script-src 'self' 'unsafe-inline'"
```

**Monitoring Performance Metrics**:
```bash
# Check JVM metrics
curl -s http://jenkins01:8080/prometheus | grep jvm

# Check build queue
curl -s http://jenkins01:8080/prometheus | grep jenkins_builds_queue_size

# Check executor usage
curl -s http://jenkins01:8080/prometheus | grep jenkins_executor
```

### 5. Disaster Recovery Testing

**Automated DR Test**:
```bash
# Schedule regular DR tests
# File: /etc/cron.weekly/jenkins-dr-test

#!/bin/bash
set -e

# Run DR validation
ansible-playbook \
  -i /path/to/ansible/inventories/production/hosts.yml \
  /path/to/ansible/playbooks/disaster-recovery.yml \
  --tags validate \
  >> /var/log/jenkins-dr-test.log 2>&1

# Send notification
if [ $? -eq 0 ]; then
  echo "DR Test PASSED" | mail -s "Jenkins DR Test Success" ops@example.com
else
  echo "DR Test FAILED" | mail -s "Jenkins DR Test FAILURE" ops@example.com
fi
```

### 6. Security Hardening

**Enable additional security features**:
```bash
# Run security scan
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags security

# Enable Trivy scanning
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "/usr/local/bin/jenkins-security-scan.sh --all" -b

# Review security findings
ansible jenkins_masters -i inventories/production/hosts.yml \
  -m shell -a "cat /var/log/jenkins-security-scan.log" -b

# Apply security patches
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags security,patches
```

### 7. Automated Testing Pipeline

**CI/CD for Infrastructure**:
```yaml
# File: .github/workflows/ansible-test.yml
name: Ansible Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          ansible-galaxy collection install -r ansible/requirements.yml

      - name: Syntax check
        run: |
          ansible-playbook ansible/site.yml --syntax-check

      - name: Lint check
        run: |
          ansible-lint ansible/site.yml

      - name: Dry run
        run: |
          ansible-playbook -i ansible/inventories/local/hosts.yml \
            ansible/site.yml --check
```

---

## Additional Resources

### Useful Scripts

**Location**: `scripts/`

- `deploy.sh` - Deployment wrapper
- `backup.sh` - Manual backup execution
- `disaster-recovery.sh` - DR automation
- `ha-setup.sh` - HA infrastructure setup
- `monitor.sh` - Monitoring stack management
- `generate-secure-credentials.sh` - Credential generation

### Documentation

- `CLAUDE.md` - Project overview and key commands
- `docs/PROMETHEUS_TARGETS_DISCOVERY_GUIDE.md` - Monitoring troubleshooting
- `docs/gluster-fs.md` - GlusterFS setup
- `docs/keepalived.md` - Keepalived HA configuration
- `examples/` - Implementation examples and guides

### Makefile Targets

```bash
# List all available targets
make help

# Common targets
make local                 # Deploy locally
make deploy-production     # Deploy to production
make build-images          # Build Docker images
make test                  # Run tests
make backup                # Run backup
make monitor               # Setup monitoring
```

### Getting Help

```bash
# Ansible documentation
ansible-doc <module_name>

# Role documentation
ansible-doc -t role jenkins-master

# Check playbook tasks
ansible-playbook site.yml --list-tasks

# Check available tags
ansible-playbook site.yml --list-tags

# Check available hosts
ansible-playbook site.yml --list-hosts
```

---

## Support and Contributing

### Reporting Issues

Create detailed issue reports with:
- Full error messages
- Ansible playbook output (`-vvv`)
- System information (`ansible all -m setup`)
- Steps to reproduce

### Contributing

1. Fork repository
2. Create feature branch
3. Test changes locally
4. Run syntax checks
5. Submit pull request

---

## License

This project is part of the Jenkins HA Infrastructure.

---

**Last Updated**: 2025-11-17
**Version**: 2.0
**Branch**: claude/fix-prometheus-targets-discovery-0136aJd4rAiv6ecZ35gbz7ZU
