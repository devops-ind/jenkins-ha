# ARCHITECTURE

## Overview

This document describes the architecture of the Jenkins High Availability infrastructure, including component interactions, data flow, and deployment patterns. The infrastructure is built with Ansible automation, containerized deployments (Docker/Podman), and comprehensive security hardening.

## Table of Contents

- [System Architecture](#system-architecture)
- [Component Overview](#component-overview)
- [Container Architecture](#container-architecture)
- [Network Architecture](#network-architecture)
- [Data Flow](#data-flow)
- [High Availability Design](#high-availability-design)
- [Security Architecture](#security-architecture)
- [Ansible Role Architecture](#ansible-role-architecture)
- [Scalability Considerations](#scalability-considerations)

## System Architecture

The Jenkins HA infrastructure follows a distributed, containerized architecture managed by Ansible with the following layers:

```
┌─────────────────────────────────────────────────────────────┐
│                 Load Balancer Layer                        │
│            (HAProxy + Keepalived + VIP)                    │
│          Stats UI: port 8404 | Health Checks               │
└─────────────────┬───────────────────────────┬───────────────┘
                  │                           │
┌─────────────────▼───────────────┐ ┌─────────▼───────────────┐
│      Jenkins Master 1           │ │      Jenkins Master 2   │
│    (Active - Port 8080)          │ │    (Standby - Port 8081)│
│  ┌─────────────────────────────┐ │ │ ┌─────────────────────────┐
│  │  jenkins-master-1 Container │ │ │ │  jenkins-master-2 Container
│  │  - Custom Jenkins Image     │ │ │ │  - Custom Jenkins Image │
│  │  - Systemd Service          │ │ │ │  - Systemd Service      │
│  │  - Health Monitoring        │ │ │ │  - Health Monitoring    │
│  │  - JCasC Configuration      │ │ │ │  - JCasC Configuration  │
│  └─────────────────────────────┘ │ │ └─────────────────────────┘
└─────────────────┬───────────────┘ └─────────┬───────────────┘
                  │                           │
           ┌──────▼─────────────────────────────▼────────┐
           │           Container Network                 │
           │         (jenkins-network)                   │
           │      Subnet: 172.20.0.0/16                 │
           └─────────────────┬───────────────────────────┘
                             │
                    ┌────────▼─────────┐
                    │  Shared Storage  │
                    │   (NFS/GlusterFS)│
                    │ ┌──────────────┐ │
                    │ │Jenkins Home  │ │
                    │ │Configurations│ │
                    │ │Build Artifacts│ │
                    │ │Logs & Reports│ │
                    │ │Backups       │ │
                    │ └──────────────┘ │
                    └──────────────────┘
```

### Agent Layer (Containerized)
```
┌────────────────────────────────────────────────────────────┐
│                    Agent Container Pool                    │
│                  (Docker/Podman Runtime)                   │
├────────────────┬───────────────┬───────────────┬────────────┤
│  DIND Agent    │  Maven Agent  │ Python Agent  │ Node Agent │
│ ┌────────────┐ │ ┌───────────┐ │ ┌───────────┐ │ ┌─────────┐ │
│ │Docker-in-  │ │ │OpenJDK 11 │ │ │Python 3.11│ │ │Node 18  │ │
│ │Docker      │ │ │Maven 3.9.6│ │ │pytest     │ │ │npm/yarn │ │
│ │Privileged  │ │ │Docker CLI │ │ │Docker CLI │ │ │Docker CLI│ │
│ │Port: 50000 │ │ │Port: 50001│ │ │Port: 50002│ │ │Port:50003│ │
│ └────────────┘ │ └───────────┘ │ └───────────┘ │ └─────────┘ │
└────────────────┴───────────────┴───────────────┴────────────┘
```

### Supporting Infrastructure
```
┌─────────────────────────────────────────────────────────────┐
│                  Supporting Services                       │
├─────────────────┬─────────────────┬─────────────────────────┤
│ Harbor Registry │ Monitoring      │ Security & Backup       │
│ ┌─────────────┐ │ ┌─────────────┐ │ ┌─────────────────────┐ │
│ │ Image Store │ │ │ Prometheus  │ │ │ Fail2ban            │ │
│ │ Vuln Scan   │ │ │ Grafana     │ │ │ AIDE File Integrity │ │
│ │ Auth LDAP   │ │ │ AlertMgr    │ │ │ RKHunter            │ │
│ │ Replication │ │ │ Node Export │ │ │ Automated Backups   │ │
│ └─────────────┘ │ └─────────────┘ │ └─────────────────────┘ │
└─────────────────┴─────────────────┴─────────────────────────┘
```

## Container Architecture

### Container Runtime Support
The infrastructure supports both Docker and Podman as container runtimes, with automatic detection and configuration through Ansible variables.

### Custom Jenkins Images
All Jenkins components use custom-built images optimized for HA deployment:

#### Master Image (`jenkins-master:latest`)
- **Base**: `jenkins/jenkins:2.426.1`
- **Features**: 
  - Pre-installed plugins for HA and container workflows
  - Configuration as Code (JCasC) support
  - Docker CLI integration
  - Health check endpoints
  - Security hardening
- **Configuration**: Shared via mounted volumes and environment variables

#### Agent Images
- **DIND Agent** (`jenkins-agent-dind:latest`): Docker-in-Docker with privileged access
- **Maven Agent** (`jenkins-agent-maven:latest`): OpenJDK 11 + Maven 3.9.6
- **Python Agent** (`jenkins-agent-python:latest`): Python 3.11 + testing frameworks
- **Node.js Agent** (`jenkins-agent-nodejs:latest`): Node.js 18 + npm/yarn/build tools

### Container Networking
- **Network**: Custom bridge network (`jenkins-network`)
- **Subnet**: 172.20.0.0/16 with gateway 172.20.0.1
- **DNS**: Automatic service discovery between containers
- **Security**: Isolated network namespace with firewall rules

### Volume Management
- **Named Volumes**: Persistent storage for Jenkins home and caches
- **Bind Mounts**: Shared storage and Docker socket access
- **Permissions**: Automated UID/GID mapping for security

## Component Overview

### Core Components

#### 1. Jenkins Masters (Active-Passive HA)
- **Container Names**: `jenkins-master-1`, `jenkins-master-2`
- **Systemd Integration**: Managed via systemd services for automatic restart
- **Health Monitoring**: Automated health checks with curl-based endpoints
- **Configuration**: JCasC-based configuration management
- **Shared State**: All masters share Jenkins home via NFS/GlusterFS
- **Port Allocation**: Sequential port assignment (8080, 8081, etc.)

#### 2. Load Balancer (HAProxy + Keepalived)
- **HAProxy Features**:
  - Round-robin load balancing with health checks
  - Statistics dashboard on port 8404
  - SSL termination support
  - Session persistence for UI consistency
- **Keepalived Features**:
  - Virtual IP (VIP) management
  - VRRP protocol for failover
  - Script-based health monitoring
  - Automatic failover in <30 seconds

#### 3. Shared Storage
- **NFS Support**: 
  - Automatic NFS server/client configuration
  - Export management with proper permissions
  - Mount options optimized for Jenkins workloads
- **GlusterFS Support**:
  - Distributed storage across multiple nodes
  - Replication for high availability
  - Client-side caching for performance
- **Directory Structure**: Organized subdirectories for different data types

#### 4. Container Registry (Harbor)
- **Integration**: Seamless authentication with Jenkins
- **Image Management**: Automated builds and vulnerability scanning
- **Maven Integration**: Harbor as Maven repository proxy
- **Security**: Role-based access control and image signing

#### 5. Jenkins Agents (Containerized)
- **Deployment**: Containerized agents with systemd service management
- **Scalability**: Dynamic scaling based on workload
- **Isolation**: Separate containers with resource limits
- **Connectivity**: Automatic agent registration with masters
- **Workspace**: Shared workspace via mounted volumes

### Supporting Infrastructure

#### 1. Monitoring Stack
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and notification
- **Node Exporter**: System metrics collection

#### 2. Backup System
- **Scheduled Backups**: Daily incremental, weekly full backups
- **Multiple Targets**: Local storage, cloud storage, remote sites
- **Retention Policies**: Configurable retention periods
- **Restore Testing**: Automated backup verification

## Network Architecture

### Network Segmentation
```
┌─────────────────────────────────────────────────────────────┐
│                     DMZ Network                            │
│                  (Public Access)                           │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │              Load Balancer                              │ │
│ │             (VIP: 10.0.1.10)                           │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────┐
│                 Internal Network                           │
│                (Private Subnet)                            │
│ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ │
│ │ Jenkins Masters │ │ Jenkins Agents  │ │ Shared Storage  │ │
│ │ 10.0.2.10-20   │ │ 10.0.3.10-50   │ │ 10.0.4.10-20   │ │
│ └─────────────────┘ └─────────────────┘ └─────────────────┘ │
│ ┌─────────────────┐ ┌─────────────────┐                   │
│ │ Harbor Registry │ │ Monitoring      │                   │
│ │ 10.0.5.10      │ │ 10.0.6.10-20   │                   │
│ └─────────────────┘ └─────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

### Port Configuration
- **Load Balancer**: 80/443 (HTTP/HTTPS)
- **Jenkins Masters**: 8080 (HTTP), 50000 (Agent connection)
- **Harbor Registry**: 80/443 (HTTP/HTTPS)
- **Prometheus**: 9090 (HTTP)
- **Grafana**: 3000 (HTTP)
- **NFS**: 2049 (NFS protocol)

## Data Flow

### Build Execution Flow
```
1. User submits build → Load Balancer → Active Jenkins Master
2. Jenkins Master schedules build → Available Agent
3. Agent pulls source code → SCM Repository
4. Agent builds artifact → Shared Storage
5. Agent publishes results → Jenkins Master
6. Jenkins Master updates UI → User notification
```

### Configuration Synchronization
```
1. Configuration change → Active Jenkins Master
2. Change written to → Shared Storage (Jenkins Home)
3. Standby Masters detect change → File system monitoring
4. Standby Masters reload → Configuration sync
```

## High Availability Design

### Failure Scenarios and Recovery

#### 1. Primary Master Failure
- **Detection**: Load balancer health checks (30-second intervals)
- **Action**: Traffic redirected to secondary master
- **Recovery Time**: < 2 minutes
- **Data Loss**: None (shared storage)

#### 2. Shared Storage Failure
- **Detection**: File system monitoring
- **Action**: Automatic failover to backup storage
- **Recovery Time**: < 5 minutes
- **Data Loss**: Minimal (last checkpoint)

#### 3. Network Partition
- **Detection**: Split-brain prevention mechanisms
- **Action**: Primary master maintains quorum
- **Recovery Time**: Automatic upon network restoration
- **Data Loss**: None

### Recovery Objectives
- **RTO (Recovery Time Objective)**: 5 minutes
- **RPO (Recovery Point Objective)**: 15 minutes
- **Availability Target**: 99.9% (8.76 hours downtime/year)

## Security Architecture

### Authentication and Authorization
- **User Authentication**: LDAP/Active Directory integration
- **Role-Based Access**: Jenkins matrix-based security
- **API Security**: Token-based authentication
- **Agent Communication**: Certificate-based mutual TLS

### Network Security
- **Firewall Rules**: Restrictive ingress/egress policies
- **VPN Access**: Required for administrative access
- **Certificate Management**: Automated certificate rotation
- **Audit Logging**: Comprehensive activity logging

### Container Security
- **Image Scanning**: Trivy vulnerability scanning
- **Runtime Security**: SELinux/AppArmor policies
- **Resource Limits**: CPU/Memory constraints
- **Secret Management**: Encrypted secret storage

## Scalability Considerations

### Horizontal Scaling
- **Agent Scaling**: Dynamic agent provisioning based on queue depth
- **Master Scaling**: Additional standby masters for larger deployments
- **Storage Scaling**: Distributed storage with auto-expansion
- **Network Scaling**: Load balancer clustering

### Performance Optimization
- **Build Parallelization**: Multiple concurrent builds per agent
- **Artifact Caching**: Local and distributed caching strategies
- **Database Optimization**: Connection pooling and indexing
- **Monitoring**: Performance metrics and alerting

### Capacity Planning
- **Current Capacity**: 100 concurrent builds, 500 projects
- **Growth Projection**: 50% annual increase
- **Resource Allocation**: CPU, memory, and storage sizing
- **Bottleneck Analysis**: Regular performance reviews

## Ansible Role Architecture

The infrastructure is deployed and managed through a comprehensive set of Ansible roles:

### Core Infrastructure Roles

#### 1. **common** - Base System Configuration
- **Purpose**: System-wide configuration and essential packages
- **Features**:
  - Package management and system updates
  - User and group management
  - SSH configuration and hardening
  - Firewall and network configuration
  - NTP synchronization and locale settings

#### 2. **docker** - Container Runtime Setup
- **Purpose**: Docker/Podman installation and configuration
- **Features**:
  - Multi-distro support (RHEL, Debian families)
  - Container runtime detection and setup
  - Docker daemon configuration
  - Registry authentication setup
  - Container network management

#### 3. **shared-storage** - Distributed Storage
- **Purpose**: NFS/GlusterFS setup for shared persistence
- **Features**:
  - NFS server/client configuration
  - GlusterFS cluster setup
  - Mount point management
  - Permission and security configuration
  - Storage health monitoring

#### 4. **harbor** - Container Registry
- **Purpose**: Private Docker registry with security features
- **Features**:
  - Harbor installation and configuration
  - LDAP/OIDC authentication integration
  - Image vulnerability scanning setup
  - Replication configuration
  - Backup and maintenance procedures

### Jenkins-Specific Roles

#### 5. **jenkins-images** - Custom Image Building
- **Purpose**: Build and manage custom Jenkins images
- **Features**:
  - Multi-stage Dockerfile generation
  - Plugin pre-installation and configuration
  - Security hardening in images
  - Registry push automation
  - Image manifest generation
- **Artifacts**:
  - jenkins-master:latest
  - jenkins-agent-dind:latest
  - jenkins-agent-maven:latest
  - jenkins-agent-python:latest
  - jenkins-agent-nodejs:latest

#### 6. **jenkins-master** - Core Deployment
- **Purpose**: Deploy and manage Jenkins masters and agents
- **Features**:
  - Container orchestration without Docker Compose
  - Systemd service integration
  - Network and volume management
  - Health monitoring and logging
  - Configuration as Code (JCasC) setup
- **Components**:
  - Master container deployment
  - Agent container management
  - Service discovery configuration
  - Resource limit enforcement

### High Availability & Operations Roles

#### 7. **high-availability** - HA Configuration
- **Purpose**: Load balancing and failover management
- **Features**:
  - HAProxy installation and configuration
  - Keepalived VIP management
  - Health check scripting
  - Failover automation
  - SSL/TLS termination
- **Monitoring**:
  - Real-time health monitoring
  - Automatic failover triggers
  - Statistics dashboard

#### 8. **security** - Security Hardening
- **Purpose**: Comprehensive security implementation
- **Features**:
  - System hardening (kernel parameters, file permissions)
  - Fail2ban intrusion prevention
  - SSH security configuration
  - File integrity monitoring (AIDE)
  - Rootkit detection (RKHunter)
  - Jenkins security policies
- **Compliance**: CIS benchmarks and security best practices

#### 9. **monitoring** - Observability Stack
- **Purpose**: Monitoring and alerting infrastructure
- **Features**:
  - Prometheus metrics collection
  - Grafana dashboard deployment
  - AlertManager notification routing
  - Custom Jenkins metrics
  - Log aggregation setup

#### 10. **backup** - Data Protection
- **Purpose**: Automated backup and recovery procedures
- **Features**:
  - Scheduled backup automation
  - Multiple storage backends
  - Incremental and full backup strategies
  - Restoration procedures
  - Backup verification and testing

### Role Dependencies and Execution Order

```
Deployment Flow:
1. common → docker → shared-storage
2. harbor (parallel with step 3)
3. security → jenkins-images
4. jenkins-master → high-availability
5. monitoring → backup
```

### Role Configuration Management

- **Variables**: Hierarchical variable precedence (group_vars, host_vars, role defaults)
- **Templates**: Jinja2 templates for dynamic configuration generation
- **Handlers**: Service restart and reload automation
- **Tags**: Granular control over role execution
- **Idempotency**: All roles designed for safe re-execution

## Technology Stack

- **Orchestration**: Ansible 2.14+
- **Containerization**: Docker 24.x / Podman 4.x
- **Load Balancing**: HAProxy 2.8+ + Keepalived
- **Storage**: NFS 4.1 / GlusterFS 10.x
- **Monitoring**: Prometheus + Grafana + AlertManager
- **Registry**: Harbor 2.8+ with Trivy scanning
- **Security**: Fail2ban, AIDE, RKHunter, SSL/TLS
- **Backup**: Custom scripts with multiple backend support
- **CI/CD**: Jenkins 2.426.1 LTS with containerized agents
