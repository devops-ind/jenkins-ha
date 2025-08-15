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

### Key Components

- **Blue-Green Jenkins Masters**: Multiple team environments with zero-downtime switching
- **HAProxy Load Balancer**: Team-aware traffic routing with health checks and API management
- **Automated Pipeline Generation**: DSL-based creation of team-specific jobs and infrastructure pipelines
- **Dynamic Agent Templates**: On-demand containerized agents with security constraints
- **Monitoring**: Enhanced Grafana dashboards with SLI tracking and DORA metrics
- **Storage**: NFS/GlusterFS shared storage with encryption and access controls
- **Security**: Trivy vulnerability scanning, container security monitoring, and compliance validation

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
# 1. Install dependencies
pip install -r requirements.txt

# 2. Deploy local environment
make deploy-local

# 3. Access services
# Jenkins: http://localhost:8080 (DevOps team)
# Jenkins: http://localhost:8081 (Developer team)
# Grafana: http://localhost:9300
# Prometheus: http://localhost:9090
```

### For Administrators (Day-2 Operations)
```bash
# Monitor infrastructure
make monitor

# Run backups
make backup

# Check security status
ansible-playbook ansible/site.yml --tags security --check
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
- **Blue-Green Deployment**: Automated environment switching with health checks
- **Image Management**: Custom-built images with security hardening and vulnerability scanning
- **Orchestration**: Direct container management with site.yml playbook
- **Networking**: Custom bridge networks with DNS resolution and team isolation
- **Storage**: Named volumes and bind mounts for persistence across blue-green switches
- **Multi-Team Isolation**: Separate container environments with resource constraints

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
- ✅ **Container Security**: Trivy vulnerability scanning, security constraints, and runtime monitoring
- ✅ **Intrusion Detection**: Fail2ban, AIDE file integrity, RKHunter
- ✅ **Access Control**: RBAC, team-based isolation, credential management
- ✅ **Audit Logging**: Comprehensive logging and compliance reporting
- ✅ **Vulnerability Management**: Automated security scanning and compliance validation

### Monitoring & Observability  
- ✅ **Enhanced Metrics Collection**: Prometheus with custom Jenkins metrics and SLI tracking
- ✅ **Advanced Visualization**: 26-panel Grafana dashboards with DORA metrics and blue-green status
- ✅ **Automated Alerting**: AlertManager with notification routing and rollback triggers
- ✅ **Log Management**: Centralized logging and analysis
- ✅ **Health Monitoring**: Multi-layer health checks with automated rollback capabilities

### Backup & Recovery
- ✅ **Enterprise Backup**: Automated daily incremental, weekly full backups with RTO/RPO compliance
- ✅ **Multiple Targets**: Local, cloud, and remote storage options
- ✅ **Automated Disaster Recovery**: Complete DR procedures with 15-minute RTO, 5-minute RPO targets
- ✅ **Point-in-Time Recovery**: Restore to specific timestamps
- ✅ **Backup Verification**: Automated backup testing and validation

### DevOps Integration
- ✅ **Automated Pipeline Creation**: Team-specific infrastructure and application pipelines
- ✅ **Dynamic Agent Templates**: DIND, Maven, Python, Node.js container agents with security constraints
- ✅ **Job DSL Automation**: Organized job definitions with team-specific configurations
- ✅ **Infrastructure as Code**: Complete Ansible automation with blue-green deployment
- ✅ **Environment Management**: Production, staging, and devcontainer support
- ✅ **Multi-Team Workflows**: Isolated CI/CD environments with automated job provisioning

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
      ansible_host: 192.168.1.10
    jenkins-02:
      ansible_host: 192.168.1.11

load_balancers:
  hosts:
    haproxy-01:
      ansible_host: 192.168.1.20

monitoring:
  hosts:
    monitoring-01:
      ansible_host: 192.168.1.30
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

# Check service status
make status

# View system logs
./scripts/monitor.sh logs

# Check backup status
./scripts/backup.sh status
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
# Run backups
make backup

# Update Jenkins version
ansible-playbook ansible/site.yml -e jenkins_version=2.427.1

# Security compliance scan
ansible-playbook ansible/site.yml --tags security

# Update team configurations
# Edit ansible/group_vars/all/jenkins_teams.yml
# Redeploy: ansible-playbook ansible/site.yml --tags jenkins,config
```

### Emergency Operations

```bash
# Disaster recovery
./scripts/disaster-recovery.sh production --validate

# Emergency backup
./scripts/backup.sh emergency

# Blue-green rollback
./scripts/blue-green-switch.sh <team-name> rollback
```

## Documentation

### Core Documentation
- **[CLAUDE.md](CLAUDE.md)**: Complete deployment commands and configuration guidance
- **[Architecture](docs/ARCHITECTURE.md)**: System design and component overview
- **[Security Guide](docs/SECURITY.md)**: Security hardening, compliance, and incident response
- **[Blue-Green Deployment](docs/BLUE-GREEN-DEPLOYMENT.md)**: Zero-downtime deployment strategy
- **[Backup & Recovery](docs/BACKUP-RECOVERY.md)**: Backup strategies and disaster recovery
- **[Monitoring](docs/MONITORING.md)**: Observability and alerting setup
- **[High Availability](docs/HIGH-AVAILABILITY.md)**: HA configuration and management

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