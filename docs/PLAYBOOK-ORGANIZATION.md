# Ansible Playbook Organization

This document explains the organization and usage of Ansible playbooks in the Jenkins HA infrastructure project.

## Table of Contents

- [Structure Overview](#structure-overview)
- [Root-Level Playbooks](#root-level-playbooks)
- [Specialized Playbooks](#specialized-playbooks)
- [Usage Examples](#usage-examples)
- [Best Practices](#best-practices)

## Structure Overview

The Ansible playbooks are organized into two main categories based on their purpose and usage patterns:

```
ansible/
├── site.yml                     # 🎯 Main deployment orchestration
├── deploy-local.yml             # 🏠 DevContainer deployment
├── deploy-backup.yml            # 💾 Backup system only
├── deploy-monitoring.yml        # 📊 Monitoring stack only
├── deploy-images.yml            # 🐳 Image building only
└── playbooks/                   # 📁 Specialized operations
    ├── bootstrap.yml            # 🔧 Initial server setup
    ├── blue-green-operations.yml # 🔄 Environment switching
    └── disaster-recovery.yml    # 🚨 Emergency recovery
```

## Root-Level Playbooks

These are **entry-point playbooks** designed for **specific deployment scenarios** and **daily operations**.

### Main Deployment (`site.yml`)

**Purpose**: Complete Jenkins infrastructure deployment with blue-green architecture

**Features**:
- Full infrastructure orchestration
- Dynamic host selection based on deployment mode
- Multi-team Jenkins deployment
- Comprehensive health checks and verification

**Usage**:
```bash
# Full production deployment
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

# Staging deployment
ansible-playbook -i ansible/inventories/staging/hosts.yml ansible/site.yml

# DevContainer deployment (automatic host selection)
DEPLOYMENT_ENV=devcontainer ansible-playbook ansible/site.yml
```

### Local Development (`deploy-local.yml`)

**Purpose**: DevContainer and local development deployment

**Features**:
- Optimized for local development environments
- Reduced resource requirements
- Developer-friendly output and debugging
- Quick setup and teardown

**Usage**:
```bash
# Local deployment
ansible-playbook ansible/deploy-local.yml

# With custom parameters
ansible-playbook ansible/deploy-local.yml \
  -e jenkins_master_memory=4g \
  -e monitoring_enabled=true
```

### Component-Specific Deployments

#### Backup System (`deploy-backup.yml`)
```bash
# Deploy only backup system
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/deploy-backup.yml
```

#### Monitoring Stack (`deploy-monitoring.yml`)
```bash
# Deploy only monitoring (Prometheus/Grafana)
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/deploy-monitoring.yml
```

#### Image Building (`deploy-images.yml`)
```bash
# Build and push Jenkins images
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/deploy-images.yml \
  -e force_rebuild=true
```

## Specialized Playbooks

These playbooks handle **specialized administrative tasks** and **operational procedures**.

### Server Bootstrap (`playbooks/bootstrap.yml`)

**Purpose**: Initial server preparation and user setup

**Features**:
- Creates Jenkins user and directories
- Sets system limits and permissions
- Prepares servers for Jenkins installation
- System-level configuration

**Usage**:
```bash
# Bootstrap new servers
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/bootstrap.yml

# Bootstrap with custom serial execution
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/bootstrap.yml \
  -e bootstrap_serial=2
```

**When to Use**:
- Setting up new servers
- After OS installation
- Before running main deployment
- When adding new nodes to cluster

### Blue-Green Operations (`playbooks/blue-green-operations.yml`)

**Purpose**: Environment switching and blue-green deployment management

**Features**:
- Environment status checking
- Zero-downtime environment switching
- Health validation and verification
- Team-specific operations
- Batch operations across multiple teams

**Usage**:

#### Check Environment Status
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=status
```

#### Switch Environment (Single Team)
```bash
# Switch DevOps team to green environment
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=switch \
  -e environment=green \
  -e team_filter=devops
```

#### Switch All Teams
```bash
# Switch all teams to green environment
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/blue-green-operations.yml \
  -e batch_blue_green_operation=switch-all \
  -e batch_target_environment=green
```

#### Health Check
```bash
# Health check for specific team
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=health-check \
  -e team_filter=qa

# Health check for all teams
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/blue-green-operations.yml \
  -e batch_blue_green_operation=health-check-all
```

#### Rollback
```bash
# Rollback DevOps team to previous environment
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=rollback \
  -e team_filter=devops
```

### Disaster Recovery (`playbooks/disaster-recovery.yml`)

**Purpose**: Comprehensive disaster recovery and emergency operations

**Features**:
- Infrastructure assessment
- Backup restoration
- Service failover
- Recovery testing
- Comprehensive reporting

**Usage**:

#### Assess Infrastructure
```bash
# Check current infrastructure state
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=assess
```

#### Restore from Backup (Dry Run)
```bash
# Preview restoration process
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=restore \
  -e backup_timestamp=latest \
  -e dr_dry_run=true
```

#### Full Restore
```bash
# Actual restoration (DESTRUCTIVE)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=restore \
  -e backup_timestamp=2024-01-15-14-30 \
  -e dr_scope=full \
  -e dr_dry_run=false
```

#### Service Failover
```bash
# Emergency failover to green environment
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=failover \
  -e failover_environment=green
```

#### Test Recovery Procedures
```bash
# Test disaster recovery procedures
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=test-recovery
```

## Usage Examples

### Daily Operations

#### Deploy Infrastructure Updates
```bash
# Update to new Jenkins version
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  -e jenkins_version=2.427.1 \
  --tags jenkins
```

#### Switch Environments for Deployment
```bash
# 1. Deploy to green environment
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  -e deployment_target=green

# 2. Switch traffic to green
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=switch \
  -e environment=green \
  -e team_filter=all
```

#### Emergency Response
```bash
# 1. Assess damage
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=assess

# 2. Quick failover if needed
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=failover
```

### Development Workflow

#### Local Development
```bash
# Start local development environment
ansible-playbook ansible/deploy-local.yml

# Test configuration changes
ansible-playbook ansible/deploy-local.yml --tags jenkins

# Clean rebuild
ansible-playbook ansible/deploy-local.yml -e force_rebuild=true
```

#### Testing and Validation
```bash
# Test disaster recovery procedures
ansible-playbook ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=test-recovery \
  -e dr_dry_run=true

# Validate blue-green switching
ansible-playbook ansible/playbooks/blue-green-operations.yml \
  -e batch_blue_green_operation=health-check-all
```

## Best Practices

### Playbook Selection Guidelines

1. **Use `site.yml` for**:
   - Full infrastructure deployments
   - Production rollouts
   - Complete environment setup

2. **Use `deploy-*.yml` for**:
   - Component-specific updates
   - Development environments
   - Targeted deployments

3. **Use `playbooks/*.yml` for**:
   - Administrative tasks
   - Emergency operations
   - Specialized procedures

### Execution Best Practices

#### Pre-Execution Checks
```bash
# Always check syntax first
ansible-playbook --syntax-check playbook.yml

# Dry run for destructive operations
ansible-playbook playbook.yml --check

# Test connectivity
ansible all -i inventory/hosts.yml -m ping
```

#### Production Execution
```bash
# Use explicit inventory
ansible-playbook -i ansible/inventories/production/hosts.yml playbook.yml

# Use vault password files
ansible-playbook playbook.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Log execution
ansible-playbook playbook.yml | tee logs/deployment-$(date +%Y%m%d-%H%M%S).log
```

#### Error Handling
```bash
# Continue on recoverable errors
ansible-playbook playbook.yml --force-handlers

# Stop on first error
ansible-playbook playbook.yml --abort-on-error

# Debug mode for troubleshooting
ansible-playbook playbook.yml -vvv
```

### Variable Management

#### Environment-Specific Variables
```bash
# Production
ansible-playbook playbook.yml -e deployment_environment=production

# Staging
ansible-playbook playbook.yml -e deployment_environment=staging

# Development
ansible-playbook playbook.yml -e deployment_environment=development
```

#### Common Variable Patterns
```bash
# Force operations
-e force_rebuild=true
-e skip_health_checks=true
-e dr_dry_run=false

# Target filtering
-e team_filter=devops
-e target_hosts=jenkins_masters
-e deployment_target=green

# Operation modes
-e blue_green_operation=switch
-e dr_operation=restore
-e recovery_scope=jenkins-only
```

### Safety Measures

#### Production Safety
- Always use `--check` mode first
- Set `dry_run=true` for destructive operations
- Use explicit inventory files
- Verify target hosts before execution
- Backup before major changes

#### Emergency Procedures
- Keep disaster recovery playbook tested
- Maintain updated inventory files
- Document emergency contacts
- Practice failover procedures regularly
- Monitor execution logs

---

For additional information, see:
- [Blue-Green Deployment Guide](docs/BLUE-GREEN-DEPLOYMENT.md)
- [Disaster Recovery Procedures](docs/BACKUP-RECOVERY.md)
- [Inventory Management](docs/config/INVENTORY-MANAGEMENT.md)
- [Variable Management](docs/config/VARIABLE-MANAGEMENT.md)