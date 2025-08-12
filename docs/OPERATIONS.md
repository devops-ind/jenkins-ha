# Jenkins HA Operations Guide

## Overview

This document provides comprehensive operational guidance for managing the Jenkins High Availability infrastructure, including deployment operations, troubleshooting, maintenance procedures, and quick reference commands.

## Table of Contents

- [Quick Reference Commands](#quick-reference-commands)
- [Deployment Operations](#deployment-operations)
- [Blue-Green Operations](#blue-green-operations)
- [Disaster Recovery](#disaster-recovery)
- [Monitoring Operations](#monitoring-operations)
- [Troubleshooting Guide](#troubleshooting-guide)
- [Maintenance Procedures](#maintenance-procedures)

## Quick Reference Commands

### 🎯 Main Deployments

#### Full Infrastructure
```bash
# Production deployment
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

# Staging deployment  
ansible-playbook -i ansible/inventories/staging/hosts.yml ansible/site.yml

# Local development
ansible-playbook ansible/deploy-local.yml
```

#### Component Deployments
```bash
# Backup system only
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/deploy-backup.yml

# Monitoring stack only
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/deploy-monitoring.yml

# Image building only
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/deploy-images.yml
```

### 🛡️ Safety Checks

```bash
# Syntax check
ansible-playbook --syntax-check ansible/site.yml

# Dry run
ansible-playbook ansible/site.yml --check

# Test connectivity
ansible all -i ansible/inventories/production/hosts.yml -m ping

# Verbose output
ansible-playbook ansible/site.yml -vvv
```

## Deployment Operations

### Enhanced HA Setup Script

Use the comprehensive setup script for automated deployments:

```bash
# Full production setup
scripts/ha-setup.sh production full

# Staging masters only
scripts/ha-setup.sh staging masters-only

# Validation only (dry run)
scripts/ha-setup.sh production validate-only

# Local monitoring setup
scripts/ha-setup.sh local monitoring-only
```

**Setup Modes:**
- `full` - Complete infrastructure deployment
- `masters-only` - Jenkins masters and agents only
- `monitoring-only` - Monitoring stack only  
- `validate-only` - Dry run validation

### Manual Deployment Steps

1. **Pre-deployment Validation**
   ```bash
   ansible-playbook ansible/site.yml --tags validation
   ```

2. **Infrastructure Bootstrap**
   ```bash
   ansible-playbook ansible/site.yml --tags bootstrap
   ```

3. **Jenkins Deployment**
   ```bash
   ansible-playbook ansible/site.yml --tags jenkins
   ```

4. **Post-deployment Verification**
   ```bash
   ansible-playbook ansible/site.yml --tags verify
   ```

## Blue-Green Operations

### 🔄 Environment Management

#### Environment Status
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=status
```

#### Environment Switching
```bash
# Switch single team to green
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=switch -e environment=green -e team_filter=devops

# Switch all teams to green
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e batch_blue_green_operation=switch-all -e batch_target_environment=green

# Rollback team to previous environment
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=rollback -e team_filter=devops
```

#### Health Checks
```bash
# Health check single team
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=health-check -e team_filter=qa

# Health check all teams  
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e batch_blue_green_operation=health-check-all
```

### Manual Blue-Green Scripts

Per-team scripts are available on Jenkins masters:

```bash
# Team-specific switching
/var/jenkins/scripts/blue-green-switch-devops.sh
/var/jenkins/scripts/blue-green-switch-qa.sh

# Team-specific health checks
/var/jenkins/scripts/blue-green-healthcheck-devops.sh
/var/jenkins/scripts/blue-green-healthcheck-qa.sh
```

## Disaster Recovery

### 🚨 Emergency Procedures

#### Infrastructure Assessment
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=assess
```

#### Backup Restoration
```bash
# Dry run restore (preview)
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=restore -e backup_timestamp=latest -e dr_dry_run=true

# Actual restore (DESTRUCTIVE)
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=restore -e backup_timestamp=2024-01-15-14-30 -e dr_dry_run=false
```

#### Emergency Failover
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=failover -e failover_environment=green
```

### Automated DR Script

```bash
# Full disaster recovery validation
scripts/disaster-recovery.sh production --validate

# Emergency failover with monitoring
scripts/disaster-recovery.sh production --failover --monitor
```

## Monitoring Operations

### Access Monitoring Interfaces

- **Prometheus**: `http://monitoring-host:9090`
- **Grafana**: `http://monitoring-host:3000`
  - Username: `admin`
  - Password: Check vault (`vault_grafana_admin_password`)

### Monitoring Playbooks

```bash
# Deploy monitoring stack only
ansible-playbook ansible/deploy-monitoring.yml

# Monitor deployment with SLI tracking
scripts/monitor.sh production --sli-tracking
```

### Key Metrics to Monitor

1. **Jenkins Health**: Response time, build success rates
2. **Container Resources**: CPU, memory, storage usage
3. **Blue-Green Status**: Environment health, switch success rates
4. **Security Metrics**: Failed authentication attempts, vulnerability scans

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Jenkins Master Not Responding

**Symptoms:**
- HTTP 500/503 errors
- Timeouts on Jenkins URLs
- Build queue not processing

**Diagnosis:**
```bash
# Check container status
docker ps | grep jenkins
podman ps | grep jenkins

# Check logs
docker logs jenkins-master-{team}-{environment}
```

**Solutions:**
```bash
# Restart Jenkins container
ansible-playbook ansible/site.yml --tags jenkins -e force_restart=true

# Switch to healthy blue-green environment
scripts/blue-green-switch.sh {team} {healthy_environment}
```

#### 2. Dynamic Agents Not Connecting

**Symptoms:**
- Builds stuck in queue
- "Agent is offline" messages
- Container spawn failures

**Diagnosis:**
```bash
# Check Docker daemon
docker info

# Check agent templates in Jenkins
curl -u admin:password http://jenkins:8080/computer/api/json
```

**Solutions:**
```bash
# Restart Docker/Podman service
sudo systemctl restart docker
# or
sudo systemctl restart podman

# Recreate agent templates
ansible-playbook ansible/site.yml --tags jenkins -e recreate_agents=true
```

#### 3. Load Balancer Issues

**Symptoms:**
- Inconsistent responses
- SSL certificate errors
- Health check failures

**Diagnosis:**
```bash
# Check HAProxy status
sudo systemctl status haproxy

# Check backend health
curl -s http://load-balancer:8404/stats
```

**Solutions:**
```bash
# Reconfigure HAProxy
ansible-playbook ansible/site.yml --tags ha

# Force SSL certificate renewal
ansible-playbook ansible/site.yml --tags security -e force_cert_renewal=true
```

#### 4. Storage/Backup Issues

**Symptoms:**
- Disk space warnings
- Backup failures
- Performance degradation

**Diagnosis:**
```bash
# Check disk usage
df -h /var/jenkins
df -h /shared/jenkins

# Check backup status
ansible-playbook ansible/deploy-backup.yml --tags verify
```

**Solutions:**
```bash
# Clean up old artifacts
scripts/cleanup.sh production --remove-old-builds

# Force backup rotation
ansible-playbook ansible/deploy-backup.yml -e force_rotation=true
```

### Emergency Procedures

#### Complete System Recovery

1. **Assessment Phase**
   ```bash
   ansible-playbook ansible/playbooks/disaster-recovery.yml -e dr_operation=assess
   ```

2. **Service Isolation**
   ```bash
   # Stop all services
   ansible all -i ansible/inventories/production/hosts.yml -m service -a "name=jenkins-master state=stopped"
   ```

3. **Data Recovery**
   ```bash
   # Restore from latest backup
   ansible-playbook ansible/playbooks/disaster-recovery.yml \
     -e dr_operation=restore -e backup_timestamp=latest
   ```

4. **Service Restart**
   ```bash
   # Full redeployment
   ansible-playbook ansible/site.yml -e skip_validation=true
   ```

#### Rollback Procedures

```bash
# Rollback to previous deployment
ansible-playbook ansible/playbooks/blue-green-operations.yml \
  -e batch_blue_green_operation=rollback-all

# Emergency rollback with force
scripts/blue-green-switch.sh all previous --force
```

## Maintenance Procedures

### Regular Maintenance Tasks

#### Weekly Tasks
- Monitor disk usage and clean up old builds
- Review security scan results
- Validate backup integrity
- Check for system updates

#### Monthly Tasks  
- Rotate credentials and certificates
- Performance optimization review
- Capacity planning assessment
- Disaster recovery testing

### Maintenance Commands

```bash
# System updates
ansible all -i ansible/inventories/production/hosts.yml -m package -a "name=* state=latest" --become

# Security updates only
ansible all -i ansible/inventories/production/hosts.yml -m package -a "name=* state=latest security=yes" --become

# Certificate renewal
scripts/generate-credentials.sh production --rotate-certs

# Backup testing
scripts/disaster-recovery.sh production --test-backup
```

### Variable Patterns

```bash
# Team filtering
-e team_filter=devops          # Single team
-e team_filter=all             # All teams

# Environment targeting
-e environment=blue            # Blue environment
-e environment=green           # Green environment

# Operation modes
-e blue_green_operation=switch # Switch environments
-e dr_operation=restore        # Disaster recovery restore
-e batch_blue_green_operation=switch-all # Batch switch all teams

# Safety controls
-e dr_dry_run=true            # Disaster recovery dry run
-e skip_health_checks=false   # Health check control
-e validate_recovery=true     # Recovery validation
-e force_rebuild=true         # Force complete rebuild
```

## Support Resources

### Log Locations
- **Jenkins Logs**: `/var/jenkins/logs/`
- **Container Logs**: `docker logs` or `podman logs`
- **System Logs**: `/var/log/jenkins/`
- **Ansible Logs**: `ansible/logs/`

### Configuration Files
- **Main Inventory**: `ansible/inventories/production/hosts.yml`
- **Team Configuration**: `ansible/group_vars/all/jenkins_teams.yml`
- **Vault Secrets**: `ansible/inventories/*/group_vars/all/vault.yml`

### Emergency Contacts
- **Operations Team**: ops@company.com
- **Security Team**: security@company.com  
- **On-call Engineer**: +1-555-0123