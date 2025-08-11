# Jenkins High Availability Infrastructure

![Jenkins HA](https://img.shields.io/badge/Jenkins-HA%20Ready-green) ![Ansible](https://img.shields.io/badge/Ansible-2.14+-blue) ![Docker](https://img.shields.io/badge/Docker-24.x-blue) ![Production Ready](https://img.shields.io/badge/Production-Ready-brightgreen)

A production-grade, containerized Jenkins infrastructure with **Blue-Green Deployment** and **Multi-Team Support** managed through Ansible automation. This repository provides complete infrastructure-as-code for deploying and managing a scalable Jenkins environment with blue-green deployment strategy, comprehensive security, monitoring, and disaster recovery capabilities.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Deployment](#deployment)
- [Operations](#operations)
- [Documentation](#documentation)
- [Support](#support)

## Overview

This infrastructure provides:

- **Blue-Green Deployment**: Zero-downtime deployments with automated environment switching
- **Multi-Team Support**: Isolated Jenkins masters for multiple teams (devops, developer, qa)
- **Containerized Architecture**: Docker/Podman containers with native Ansible orchestration
- **Dynamic Agent Scaling**: Container-based agents provisioned on-demand via Docker Cloud Plugin
- **HAProxy Load Balancing**: Advanced traffic routing with health checks and failover
- **Security Hardening**: Comprehensive security controls and compliance measures
- **Monitoring Stack**: Prometheus/Grafana with custom dashboards and alerting
- **Automated Backups**: Multi-tier backup strategy with disaster recovery procedures
- **Private Registry**: Harbor integration for secure image management
- **Job DSL Integration**: Automated job creation and management through code

### Key Components

- **Blue-Green Jenkins Masters**: Multiple team environments with zero-downtime switching
- **HAProxy Load Balancer**: Traffic routing with health checks and API management
- **Dynamic Agent Templates**: On-demand containerized agents (DIND, Maven, Python, Node.js)
- **Job DSL Automation**: Code-driven job creation and management
- **Registry**: Harbor private Docker registry with vulnerability scanning
- **Monitoring**: Prometheus metrics collection and Grafana visualization
- **Storage**: NFS/GlusterFS shared storage for persistence
- **Security**: Fail2ban, AIDE, RKHunter, and comprehensive hardening

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

# 4. Set up vault passwords
./scripts/vault-setup.sh production

# 5. Deploy infrastructure
make deploy-production
```

### For Developers (Local Development)
```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Deploy local environment
make deploy-local

# 3. Access Jenkins
open http://localhost:8080
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

### Blue-Green Multi-Team Architecture
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
│   Port: 8080    │    │   Port: 8090       │    │   Port: 8100      │
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
- **Image Management**: Custom-built images with security hardening
- **Orchestration**: Direct container management (no Docker Compose dependency)
- **Networking**: Custom bridge networks with DNS resolution
- **Storage**: Named volumes and bind mounts for persistence
- **Multi-Team Isolation**: Separate container environments per team

For detailed architecture information, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Features

### Production-Ready Infrastructure
- ✅ **Blue-Green Deployment**: Zero-downtime deployments with automated switching
- ✅ **Multi-Team Support**: Isolated Jenkins environments for different teams
- ✅ **Container Orchestration**: Docker/Podman with native Ansible management
- ✅ **HAProxy Load Balancing**: Advanced traffic routing with health checks and API
- ✅ **Shared Storage**: NFS/GlusterFS for persistent Jenkins data
- ✅ **SSL/TLS**: Certificate management and encryption
- ✅ **Job DSL Automation**: Code-driven job creation and pipeline management

### Security & Compliance
- ✅ **System Hardening**: CIS benchmark compliance and security controls
- ✅ **Intrusion Detection**: Fail2ban, AIDE file integrity, RKHunter
- ✅ **Access Control**: RBAC, LDAP integration, credential management
- ✅ **Vulnerability Scanning**: Container image scanning with Trivy
- ✅ **Audit Logging**: Comprehensive logging and compliance reporting

### Monitoring & Observability  
- ✅ **Metrics Collection**: Prometheus with custom Jenkins metrics
- ✅ **Visualization**: Grafana dashboards for infrastructure and applications
- ✅ **Alerting**: AlertManager with notification routing
- ✅ **Log Management**: Centralized logging and analysis
- ✅ **Health Checks**: Automated health monitoring and reporting

### Backup & Recovery
- ✅ **Automated Backups**: Daily incremental, weekly full backups
- ✅ **Multiple Targets**: Local, cloud, and remote storage options
- ✅ **Disaster Recovery**: Complete DR procedures and testing
- ✅ **Point-in-Time Recovery**: Restore to specific timestamps
- ✅ **Backup Verification**: Automated backup testing and validation

### DevOps Integration
- ✅ **Infrastructure Pipelines**: Complete infrastructure management pipelines
- ✅ **Dynamic Agent Templates**: DIND, Maven, Python, Node.js container agents
- ✅ **Job DSL Scripts**: Organized job definitions in `jenkins-dsl/` directory
- ✅ **Harbor Registry**: Private Docker registry with RBAC and vulnerability scanning
- ✅ **Infrastructure as Code**: Complete Ansible automation with blue-green deployment
- ✅ **Environment Management**: Production, staging, and devcontainer support
- ✅ **Multi-Team Workflows**: Isolated CI/CD environments per development team

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
- **Count**: Minimum 2 for HA (supports 2-4 masters)

**Dynamic Agent Resources (Container-based)**
- **DIND Agent**: 2GB RAM, privileged Docker access
- **Maven Agent**: 4GB RAM, 3GB heap, persistent .m2 cache
- **Python Agent**: 2GB RAM, pip cache persistence
- **Node.js Agent**: 3GB RAM, npm cache persistence
- **Scaling**: Auto-scaling based on demand (0-10 concurrent agents)

**Shared Storage**
- **Type**: NFS 4.1+ server or GlusterFS 10.x cluster
- **Capacity**: 1TB+ (scalable with growth)
- **Performance**: 2000+ IOPS, 100MB/s+ throughput
- **Redundancy**: RAID 10 or distributed replication

**Supporting Services**
- **Harbor Registry**: 4 CPU, 8GB RAM, 200GB+ storage
- **Monitoring Stack**: 4 CPU, 8GB RAM, 200GB+ storage
- **Load Balancer**: 2 CPU, 4GB RAM (can be virtual/shared)

### Network Requirements
- **Connectivity**: All nodes must have network connectivity
- **DNS**: Hostname resolution or IP-based inventory
- **Firewall**: Required ports open (see [docs/SECURITY.md](docs/SECURITY.md))
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

### 3. Vault Setup

```bash
# Generate vault password
./scripts/vault-setup.sh production

# Create encrypted variables
ansible-vault create ansible/inventories/production/group_vars/all/vault.yml
```

### 4. SSL Certificates (Optional)

```bash
# For production with custom certificates
mkdir -p environments/certificates/production
cp your-certificates/* environments/certificates/production/

# For Let's Encrypt (automatic)
# Certificates will be generated during deployment
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

### Staging Deployment

```bash
make deploy-staging
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
  --tags jenkins-infrastructure

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

# Check Jenkins accessibility
curl -I http://your-jenkins-vip:8080/login

# Verify load balancer stats
curl http://your-load-balancer:8404/stats

# Check container status
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker ps | grep jenkins"
```

## Operations

### Daily Operations

```bash
# Monitor infrastructure health
make monitor

# Check security status
ansible-playbook ansible/site.yml --tags security --check

# View system logs
./scripts/monitor.sh logs

# Check backup status
./scripts/backup.sh status
```

### Maintenance Operations

```bash
# Run backups
make backup

# Update Jenkins version
ansible-playbook ansible/site.yml -e jenkins_version=2.427.1

# Security hardening check
ansible-playbook ansible/site.yml --tags security

# Certificate renewal
ansible-playbook ansible/site.yml --tags ssl-certificates
```

### Emergency Operations

```bash
# Disaster recovery
./scripts/disaster-recovery.sh

# Emergency backup
./scripts/backup.sh emergency

# Security incident response
./scripts/incident-response.sh critical "description"
```

## Documentation

### Core Documentation
- **[Architecture](docs/ARCHITECTURE.md)**: System design and component overview
- **[Blue-Green Deployment](docs/BLUE-GREEN-DEPLOYMENT.md)**: Zero-downtime deployment strategy
- **[Job DSL Management](docs/JOB-DSL-MANAGEMENT.md)**: Automated job creation and pipeline management
- **[Playbook Organization](docs/PLAYBOOK-ORGANIZATION.md)**: Ansible playbook structure and usage
- **[Deployment](docs/DEPLOYMENT.md)**: Complete deployment procedures
- **[Security](docs/SECURITY.md)**: Security hardening and compliance
- **[Backup & Recovery](docs/BACKUP-RECOVERY.md)**: Backup strategies and disaster recovery
- **[Monitoring](docs/MONITORING.md)**: Observability and alerting setup
- **[Troubleshooting](docs/TROUBLESHOOTING.md)**: Common issues and solutions

### Operations Runbooks
- **[Production Deployment](docs/runbooks/PRODUCTION-DEPLOYMENT.md)**: Step-by-step production deployment
- **[Disaster Recovery](docs/runbooks/DISASTER-RECOVERY.md)**: Complete DR procedures
- **[Security Operations](docs/runbooks/SECURITY-OPERATIONS.md)**: Security incident response
- **[Monitoring Operations](docs/runbooks/MONITORING-OPERATIONS.md)**: Alert handling and escalation

### Configuration Management
- **[Inventory Management](docs/config/INVENTORY-MANAGEMENT.md)**: Host and environment management
- **[Variable Management](docs/config/VARIABLE-MANAGEMENT.md)**: Variable hierarchy and vault usage
- **[SSL Certificate Management](docs/config/SSL-MANAGEMENT.md)**: Certificate lifecycle management
- **[Secrets Management](docs/config/SECRETS-MANAGEMENT.md)**: Vault operations and password rotation

### Reference Guides
- **[Network Architecture](docs/reference/NETWORK-ARCHITECTURE.md)**: Network topology and security zones
- **[Incident Response](docs/reference/INCIDENT-RESPONSE.md)**: Security incident procedures
- **[Compliance Documentation](docs/reference/COMPLIANCE.md)**: Security compliance and auditing

## Support

### Getting Help

1. **Documentation**: Check the relevant documentation in the `docs/` directory
2. **Troubleshooting**: Review [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
3. **Issues**: Create an issue with detailed description and logs
4. **Community**: Join our community discussions

### Reporting Issues

When reporting issues, please include:
- Environment details (staging/production)
- Error messages and logs
- Steps to reproduce
- Expected vs actual behavior

### Emergency Contacts

- **Infrastructure Team**: infra@company.com
- **Security Team**: security@company.com  
- **24/7 Support**: +1-555-0123

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add/update documentation
5. Submit a pull request

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Jenkins HA Infrastructure** - Production-ready, secure, and highly available Jenkins infrastructure with comprehensive automation and monitoring.
