# BACKUP AND RECOVERY

## Overview

This document provides comprehensive backup and disaster recovery procedures for the Jenkins High Availability infrastructure. The backup system implements a multi-tier strategy with automated backups, verification procedures, and complete disaster recovery capabilities to ensure business continuity and data protection.

## Table of Contents

- [Backup Architecture](#backup-architecture)
- [Backup Strategies](#backup-strategies)
- [Automated Backup System](#automated-backup-system)
- [Manual Backup Procedures](#manual-backup-procedures)
- [Restoration Procedures](#restoration-procedures)
- [Disaster Recovery](#disaster-recovery)
- [Backup Testing and Verification](#backup-testing-and-verification)
- [Monitoring and Alerting](#monitoring-and-alerting)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Backup Architecture

### Backup Components

The backup system protects the following critical components:

```
┌─────────────────────────────────────────────────────────────┐
│                    Backup Architecture                     │
│                                                             │
│  ┌─────────────────┐   ┌─────────────────┐                 │
│  │ Jenkins Masters │   │ Jenkins Agents  │                 │
│  │ - Jenkins Home  │   │ - Agent Configs │                 │
│  │ - Configurations│   │ - Build Caches  │                 │
│  │ - Credentials   │   │ - Tool Configs  │                 │
│  │ - Job Histories │   └─────────────────┘                 │
│  │ - Plugins       │                                       │
│  │ - User Data     │   ┌─────────────────┐                 │
│  └─────────────────┘   │ Infrastructure  │                 │
│                        │ - Inventories   │                 │
│  ┌─────────────────┐   │ - Playbooks     │                 │
│  │ Shared Storage  │   │ - Certificates  │                 │
│  │ - Build Artifacts│  │ - Vault Data    │                 │
│  │ - Workspaces    │   │ - Configurations│                 │
│  │ - Logs          │   └─────────────────┘                 │
│  │ - Archives      │                                       │
│  └─────────────────┘   ┌─────────────────┐                 │
│                        │ Monitoring Data │                 │
│  ┌─────────────────┐   │ - Prometheus DB │                 │
│  │ Harbor Registry │   │ - Grafana Configs│                │
│  │ - Image Blobs   │   │ - Alert History │                 │
│  │ - Registry DB   │   │ - Dashboards    │                 │
│  │ - Configurations│   └─────────────────┘                 │
│  │ - Security Scan │                                       │
│  └─────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

### Backup Targets

#### Primary Backup Targets
- **Local Storage**: `/backup/local` - Fast recovery, short retention
- **Network Storage**: NFS/CIFS shares - Medium-term retention
- **Cloud Storage**: AWS S3/Azure Blob - Long-term retention and DR
- **Remote Sites**: Offsite replication for disaster recovery

#### Backup Classifications
- **Critical**: Jenkins home, configurations, credentials (RTO: 15 minutes)
- **Important**: Build artifacts, job histories (RTO: 2 hours)
- **Standard**: Logs, temporary files (RTO: 24 hours)

## Backup Strategies

### Backup Types and Schedule

#### Full Backups
- **Frequency**: Weekly (Sunday 2:00 AM)
- **Retention**: 4 weeks local, 3 months cloud
- **Content**: Complete system state including all data
- **Method**: Consistent snapshot + file-level backup

#### Incremental Backups
- **Frequency**: Daily (2:00 AM)
- **Retention**: 14 days local, 1 month cloud
- **Content**: Changed files since last backup
- **Method**: File-level incremental with metadata

#### Differential Backups
- **Frequency**: Every 6 hours during business hours
- **Retention**: 3 days local
- **Content**: Changes since last full backup
- **Method**: Fast file-level differential

#### Configuration Snapshots
- **Frequency**: Before any configuration change
- **Retention**: 30 snapshots rolling
- **Content**: Jenkins configuration, JCasC files, vault data
- **Method**: Git-based versioning + file backup

### Backup Schedule Matrix

```yaml
# Backup schedule configuration
backup_schedule:
  full_backup:
    cron: "0 2 * * 0"  # Sunday 2:00 AM
    retention_local: 28   # days
    retention_cloud: 90   # days
    
  incremental_backup:
    cron: "0 2 * * 1-6"  # Monday-Saturday 2:00 AM
    retention_local: 14   # days
    retention_cloud: 30   # days
    
  differential_backup:
    cron: "0 8,14,20 * * 1-5"  # Business hours every 6h
    retention_local: 3    # days
    
  config_snapshot:
    trigger: "pre_change"  # Before configuration changes
    retention: 30         # snapshots
```

### RPO and RTO Objectives

#### Recovery Point Objective (RPO)
- **Critical Data**: 15 minutes (configuration snapshots)
- **Build Data**: 6 hours (differential backups)
- **Archived Data**: 24 hours (daily incremental)

#### Recovery Time Objective (RTO)
- **Single Master Restore**: 30 minutes
- **Complete Infrastructure**: 2 hours
- **Disaster Recovery**: 4 hours

## Automated Backup System

### Backup Role Implementation

The backup system is implemented through the `backup` Ansible role with the following features:

#### Backup Components
```yaml
# Backup role configuration
backup_components:
  jenkins_masters:
    - jenkins_home: "/shared/jenkins"
    - container_configs: "/opt/jenkins"
    - systemd_configs: "/etc/systemd/system/jenkins-*"
    
  jenkins_agents:
    - agent_configs: "/opt/jenkins-agent"
    - build_caches: "/var/jenkins-cache"
    - container_configs: "/etc/systemd/system/jenkins-agent-*"
    
  shared_storage:
    - build_artifacts: "/shared/jenkins/builds"
    - workspaces: "/shared/jenkins/workspace"
    - logs: "/shared/jenkins/logs"
    
  infrastructure:
    - ansible_configs: "ansible/"
    - certificates: "environments/certificates"
    - vault_data: "ansible/inventories/*/group_vars/all/vault.yml"
    
  monitoring:
    - prometheus_data: "/var/lib/prometheus"
    - grafana_configs: "/etc/grafana"
    - alertmanager_configs: "/etc/alertmanager"
    
  harbor:
    - registry_data: "/data/registry"
    - database: "harbor_db"
    - configurations: "/harbor/common/config"
```

#### Backup Execution

##### Daily Automated Backup
```bash
#!/bin/bash
# /usr/local/bin/jenkins-backup.sh

# Source environment
source /etc/environment
source /opt/backup/config/backup.conf

# Set variables
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/local/${BACKUP_DATE}"
LOG_FILE="/var/log/backup/jenkins-backup-${BACKUP_DATE}.log"

# Create backup directory
mkdir -p "${BACKUP_DIR}" "${BACKUP_DIR}/jenkins" "${BACKUP_DIR}/infrastructure"

# Log backup start
echo "$(date): Starting Jenkins backup - ${BACKUP_DATE}" | tee -a "${LOG_FILE}"

# Backup Jenkins masters
echo "$(date): Backing up Jenkins masters..." | tee -a "${LOG_FILE}"
for master in $(docker ps --filter "name=jenkins-master" --format "{{.Names}}"); do
    echo "  Backing up ${master}..." | tee -a "${LOG_FILE}"
    
    # Create container snapshot
    docker commit "${master}" "backup/${master}:${BACKUP_DATE}"
    
    # Export container
    docker save "backup/${master}:${BACKUP_DATE}" | gzip > "${BACKUP_DIR}/jenkins/${master}-${BACKUP_DATE}.tar.gz"
    
    # Backup container logs
    docker logs "${master}" > "${BACKUP_DIR}/jenkins/${master}-logs-${BACKUP_DATE}.log" 2>&1
done

# Backup shared storage
echo "$(date): Backing up shared storage..." | tee -a "${LOG_FILE}"
if mountpoint -q /shared/jenkins; then
    tar czf "${BACKUP_DIR}/jenkins/shared-storage-${BACKUP_DATE}.tar.gz" \
        -C /shared/jenkins \
        --exclude='workspace/*/target' \
        --exclude='workspace/*/.git' \
        --exclude='logs/*.log.*' \
        .
else
    echo "  WARNING: Shared storage not mounted" | tee -a "${LOG_FILE}"
fi

# Backup infrastructure configurations
echo "$(date): Backing up infrastructure configurations..." | tee -a "${LOG_FILE}"
cd "${ANSIBLE_PROJECT_DIR}" || exit 1
tar czf "${BACKUP_DIR}/infrastructure/ansible-configs-${BACKUP_DATE}.tar.gz" \
    ansible/ \
    environments/ \
    scripts/ \
    monitoring/ \
    pipelines/ \
    Makefile \
    requirements.txt

# Backup certificates
if [ -d "environments/certificates" ]; then
    tar czf "${BACKUP_DIR}/infrastructure/certificates-${BACKUP_DATE}.tar.gz" \
        environments/certificates/
fi

# Database backups (if applicable)
if command -v pg_dump &> /dev/null; then
    echo "$(date): Backing up databases..." | tee -a "${LOG_FILE}"
    pg_dump -h localhost -U harbor harbor > "${BACKUP_DIR}/infrastructure/harbor-db-${BACKUP_DATE}.sql"
fi

# Create backup manifest
echo "$(date): Creating backup manifest..." | tee -a "${LOG_FILE}"
cat > "${BACKUP_DIR}/MANIFEST.txt" << EOF
Jenkins HA Infrastructure Backup
Backup Date: ${BACKUP_DATE}
Backup Type: $([ $(date +%w) -eq 0 ] && echo "Full" || echo "Incremental")
Environment: ${ENVIRONMENT:-production}

Contents:
$(find "${BACKUP_DIR}" -type f -exec basename {} \; | sort)

Checksums:
$(find "${BACKUP_DIR}" -type f -exec md5sum {} \;)

System Info:
Hostname: $(hostname)
Uptime: $(uptime)
Disk Usage: $(df -h /)
Jenkins Version: $(docker exec jenkins-master-1 java -jar /usr/share/jenkins/jenkins.war --version 2>/dev/null || echo "N/A")
EOF

# Compress backup directory
echo "$(date): Compressing backup..." | tee -a "${LOG_FILE}"
tar czf "/backup/local/jenkins-backup-${BACKUP_DATE}.tar.gz" -C "/backup/local" "${BACKUP_DATE}"
rm -rf "${BACKUP_DIR}"

# Upload to cloud storage
if [ "${CLOUD_BACKUP_ENABLED}" = "true" ]; then
    echo "$(date): Uploading to cloud storage..." | tee -a "${LOG_FILE}"
    if command -v aws &> /dev/null; then
        aws s3 cp "/backup/local/jenkins-backup-${BACKUP_DATE}.tar.gz" \
            "s3://${BACKUP_S3_BUCKET}/jenkins-ha/${ENVIRONMENT}/"
    elif command -v az &> /dev/null; then
        az storage blob upload \
            --file "/backup/local/jenkins-backup-${BACKUP_DATE}.tar.gz" \
            --container-name "${BACKUP_CONTAINER}" \
            --name "jenkins-ha/${ENVIRONMENT}/jenkins-backup-${BACKUP_DATE}.tar.gz"
    fi
fi

# Cleanup old backups
echo "$(date): Cleaning up old backups..." | tee -a "${LOG_FILE}"
find /backup/local -name "jenkins-backup-*.tar.gz" -mtime +${BACKUP_RETENTION_DAYS:-14} -delete

# Backup verification
echo "$(date): Verifying backup integrity..." | tee -a "${LOG_FILE}"
if tar tzf "/backup/local/jenkins-backup-${BACKUP_DATE}.tar.gz" > /dev/null; then
    echo "  Backup integrity check: PASSED" | tee -a "${LOG_FILE}"
else
    echo "  Backup integrity check: FAILED" | tee -a "${LOG_FILE}"
    exit 1
fi

# Log completion
echo "$(date): Backup completed successfully - ${BACKUP_DATE}" | tee -a "${LOG_FILE}"

# Send notification
if [ "${BACKUP_NOTIFICATIONS_ENABLED}" = "true" ]; then
    mail -s "Jenkins HA Backup Completed - ${BACKUP_DATE}" \
        "${BACKUP_NOTIFICATION_EMAIL}" < "${LOG_FILE}"
fi
```

### Ansible Backup Playbook

#### Backup Execution via Ansible
```bash
# Execute backup via Ansible
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/deploy-backup.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production \
  -e backup_type=full \
  -e backup_retention_days=30
```

#### Backup Role Tasks
```yaml
# ansible/roles/backup/tasks/main.yml
- name: Create backup directories
  file:
    path: "{{ item }}"
    state: directory
    mode: '0755'
  loop:
    - "/backup/local"
    - "/backup/scripts"
    - "/var/log/backup"

- name: Install backup dependencies
  package:
    name: "{{ backup_packages }}"
    state: present

- name: Deploy backup scripts
  template:
    src: "{{ item.src }}"
    dest: "{{ item.dest }}"
    mode: '0755'
  loop:
    - { src: "jenkins-backup.sh.j2", dest: "/usr/local/bin/jenkins-backup.sh" }
    - { src: "backup-verification.sh.j2", dest: "/usr/local/bin/backup-verification.sh" }
    - { src: "backup-cleanup.sh.j2", dest: "/usr/local/bin/backup-cleanup.sh" }

- name: Configure backup schedule
  cron:
    name: "{{ item.name }}"
    cron_file: "jenkins-backup"
    job: "{{ item.job }}"
    minute: "{{ item.minute }}"
    hour: "{{ item.hour }}"
    day: "{{ item.day }}"
    weekday: "{{ item.weekday }}"
    user: root
  loop: "{{ backup_cron_jobs }}"

- name: Configure logrotate for backup logs
  template:
    src: backup-logrotate.j2
    dest: /etc/logrotate.d/jenkins-backup
    mode: '0644'
```

## Manual Backup Procedures

### Pre-Change Backup

Before making any significant changes:

```bash
# Create pre-change backup
./scripts/backup.sh pre-change "description of change"

# Alternative: Ansible execution
ansible-playbook ansible/deploy-backup.yml \
  -e backup_type=pre_change \
  -e backup_description="jenkins version upgrade" \
  -e backup_retention_days=7
```

### Emergency Backup

For emergency situations:

```bash
# Emergency backup (fastest method)
./scripts/backup.sh emergency

# Emergency backup with specific components
ansible-playbook ansible/deploy-backup.yml \
  -e backup_type=emergency \
  -e backup_components="jenkins_masters,shared_storage" \
  -e backup_compression=false
```

### Configuration-Only Backup

For configuration-only backups:

```bash
# Backup only configurations
ansible-playbook ansible/deploy-backup.yml \
  -e backup_type=config_only \
  --tags "backup-configs"
```

### Component-Specific Backups

#### Jenkins Masters Only
```bash
docker exec jenkins-master-1 tar czf /tmp/jenkins-home-backup.tar.gz -C /var/jenkins_home .
docker cp jenkins-master-1:/tmp/jenkins-home-backup.tar.gz ./jenkins-master-1-$(date +%Y%m%d).tar.gz
```

#### Shared Storage Only
```bash
tar czf "shared-storage-$(date +%Y%m%d_%H%M%S).tar.gz" \
  -C /shared/jenkins \
  --exclude='workspace/*/target' \
  --exclude='logs/*.log.*' \
  .
```

#### Harbor Registry
```bash
# Backup Harbor data
docker-compose -f /harbor/docker-compose.yml exec -T registry \
  /bin/registry garbage-collect /etc/registry/config.yml

tar czf "harbor-data-$(date +%Y%m%d).tar.gz" \
  -C /data \
  registry/ database/
```

## Restoration Procedures

### Full System Restoration

#### 1. Disaster Recovery Restoration
```bash
#!/bin/bash
# Full infrastructure restoration from backup

BACKUP_FILE="$1"
RESTORE_ENV="${2:-production}"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file> [environment]"
    exit 1
fi

echo "Starting full system restoration..."
echo "Backup File: $BACKUP_FILE"
echo "Environment: $RESTORE_ENV"

# Stop all services
echo "Stopping all Jenkins services..."
ansible jenkins_masters -i ansible/inventories/${RESTORE_ENV}/hosts.yml \
  -m systemd -a "name=jenkins-master-* state=stopped" --become

# Extract backup
echo "Extracting backup..."
RESTORE_DIR="/tmp/restore-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESTORE_DIR"
tar xzf "$BACKUP_FILE" -C "$RESTORE_DIR"

# Restore shared storage
echo "Restoring shared storage..."
if [ -f "$RESTORE_DIR/jenkins/shared-storage-*.tar.gz" ]; then
    # Backup current data
    mv /shared/jenkins "/shared/jenkins.backup.$(date +%Y%m%d_%H%M%S)"
    mkdir -p /shared/jenkins
    
    # Restore from backup
    tar xzf "$RESTORE_DIR"/jenkins/shared-storage-*.tar.gz -C /shared/jenkins
    chown -R jenkins:jenkins /shared/jenkins
fi

# Restore container images
echo "Restoring container images..."
for image_backup in "$RESTORE_DIR"/jenkins/jenkins-master-*.tar.gz; do
    if [ -f "$image_backup" ]; then
        docker load < "$image_backup"
    fi
done

# Restore infrastructure configurations
echo "Restoring infrastructure configurations..."
if [ -f "$RESTORE_DIR/infrastructure/ansible-configs-*.tar.gz" ]; then
    tar xzf "$RESTORE_DIR"/infrastructure/ansible-configs-*.tar.gz -C /tmp/
    # Selective restore of configurations
    cp -r /tmp/ansible/inventories/* ansible/inventories/
    cp -r /tmp/environments/* environments/
fi

# Restore certificates
echo "Restoring certificates..."
if [ -f "$RESTORE_DIR/infrastructure/certificates-*.tar.gz" ]; then
    tar xzf "$RESTORE_DIR"/infrastructure/certificates-*.tar.gz -C /tmp/
    cp -r /tmp/environments/certificates/* environments/certificates/
fi

# Restart services
echo "Starting Jenkins services..."
ansible-playbook -i ansible/inventories/${RESTORE_ENV}/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  --limit jenkins_masters

# Verify restoration
echo "Verifying restoration..."
sleep 30
curl -f http://$(ansible-inventory -i ansible/inventories/${RESTORE_ENV}/hosts.yml --host jenkins-master-01 | jq -r .ansible_host):8080/login

echo "Full system restoration completed"
```

#### 2. Single Master Restoration
```bash
#!/bin/bash
# Single Jenkins master restoration

MASTER_NAME="$1"
BACKUP_FILE="$2"

# Stop target master
docker stop "$MASTER_NAME"
docker rm "$MASTER_NAME"

# Restore container
docker load < "$BACKUP_FILE"

# Restart master
systemctl start "${MASTER_NAME}.service"

# Verify
curl -f "http://localhost:$(docker port $MASTER_NAME 8080/tcp | cut -d: -f2)/login"
```

### Partial Restoration

#### Configuration-Only Restoration
```bash
# Restore only Jenkins configuration
BACKUP_DIR="/tmp/restore"
tar xzf jenkins-backup-20240115_140000.tar.gz -C "$BACKUP_DIR"

# Stop Jenkins
docker exec jenkins-master-1 java -jar /var/jenkins_home/war/WEB-INF/jenkins-cli.jar \
  -s http://localhost:8080 safe-shutdown

# Restore configuration files
docker cp "$BACKUP_DIR/jenkins/config.xml" jenkins-master-1:/var/jenkins_home/
docker cp "$BACKUP_DIR/jenkins/credentials.xml" jenkins-master-1:/var/jenkins_home/

# Restart Jenkins
docker restart jenkins-master-1
```

#### Database Restoration (Harbor)
```bash
# Restore Harbor database
docker-compose -f /harbor/docker-compose.yml stop

# Restore database
pg_restore -h localhost -U harbor -d harbor harbor-db-20240115_140000.sql

# Restart Harbor
docker-compose -f /harbor/docker-compose.yml start
```

### Point-in-Time Recovery

#### Restore to Specific Timestamp
```bash
# List available backups
ls -la /backup/local/jenkins-backup-*.tar.gz

# Restore specific backup
./scripts/restore.sh jenkins-backup-20240115_140000.tar.gz production

# Verify timestamp
docker exec jenkins-master-1 cat /var/jenkins_home/config.xml | grep lastModified
```

## Disaster Recovery

### Disaster Recovery Scenarios

#### 1. Complete Site Failure
```bash
#!/bin/bash
# Complete disaster recovery procedure

echo "=== DISASTER RECOVERY PROCEDURE ==="
echo "Scenario: Complete site failure"
echo "Target: New infrastructure deployment with data restoration"

# Step 1: Deploy new infrastructure
echo "Step 1: Deploying new infrastructure..."
ansible-playbook -i ansible/inventories/dr/hosts.yml \
  ansible/site.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_dr

# Step 2: Restore from cloud backup
echo "Step 2: Downloading latest backup from cloud..."
aws s3 cp s3://jenkins-backup/production/latest/jenkins-backup-latest.tar.gz ./

# Step 3: Full system restoration
echo "Step 3: Performing full system restoration..."
./scripts/restore.sh jenkins-backup-latest.tar.gz dr

# Step 4: Update DNS/Load balancer
echo "Step 4: Updating DNS to point to DR site..."
# Update DNS entries to point to DR infrastructure

# Step 5: Verification
echo "Step 5: Verifying DR environment..."
./scripts/disaster-recovery.sh verify

echo "Disaster recovery completed successfully"
```

#### 2. Data Center Failure
- **Detection**: Monitoring alerts indicate complete data center failure
- **Response Time**: 4 hours RTO
- **Recovery Steps**:
  1. Activate DR site infrastructure
  2. Restore latest backup from cloud storage
  3. Update DNS records to DR site
  4. Verify all services and functionality
  5. Communicate status to stakeholders

#### 3. Shared Storage Failure
- **Detection**: Storage monitoring alerts or mount failures
- **Response Time**: 2 hours RTO
- **Recovery Steps**:
  1. Restore shared storage from backup
  2. Re-mount storage on all masters
  3. Restart Jenkins services
  4. Verify data integrity

### DR Site Management

#### DR Site Configuration
```yaml
# ansible/inventories/dr/hosts.yml
all:
  children:
    jenkins_masters:
      hosts:
        jenkins-dr-master-01:
          ansible_host: 10.10.2.10
          jenkins_master_priority: 1
        jenkins-dr-master-02:
          ansible_host: 10.10.2.11
          jenkins_master_priority: 2
    jenkins_agents:
      hosts:
        jenkins-dr-agent-01:
          ansible_host: 10.10.3.10
  vars:
    ansible_user: ubuntu
    jenkins_vip: 10.10.1.10
    shared_storage_path: /mnt/jenkins-shared-dr
    environment: disaster-recovery
```

#### Regular DR Testing
```bash
#!/bin/bash
# Monthly DR testing procedure

echo "Starting DR testing procedure..."

# Deploy DR infrastructure
ansible-playbook -i ansible/inventories/dr/hosts.yml \
  ansible/site.yml \
  --tags jenkins

# Restore test backup
./scripts/restore.sh /backup/test/jenkins-backup-test.tar.gz dr

# Run verification tests
./scripts/dr-verification.sh

# Generate DR test report
./scripts/generate-dr-report.sh

# Cleanup test environment
ansible-playbook -i ansible/inventories/dr/hosts.yml \
  ansible/playbooks/cleanup.yml

echo "DR testing completed"
```

## Backup Testing and Verification

### Automated Backup Verification

#### Backup Integrity Testing
```bash
#!/bin/bash
# /usr/local/bin/backup-verification.sh

BACKUP_FILE="$1"
TEST_DIR="/tmp/backup-test-$(date +%Y%m%d_%H%M%S)"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

echo "Starting backup verification for: $BACKUP_FILE"

# Test 1: Archive integrity
echo "Test 1: Archive integrity check..."
if tar tzf "$BACKUP_FILE" > /dev/null 2>&1; then
    echo "  PASS: Archive is readable"
else
    echo "  FAIL: Archive is corrupted"
    exit 1
fi

# Test 2: Extract backup
echo "Test 2: Extraction test..."
mkdir -p "$TEST_DIR"
if tar xzf "$BACKUP_FILE" -C "$TEST_DIR"; then
    echo "  PASS: Backup extracted successfully"
else
    echo "  FAIL: Backup extraction failed"
    exit 1
fi

# Test 3: Verify manifest
echo "Test 3: Manifest verification..."
if [ -f "$TEST_DIR"/*/MANIFEST.txt ]; then
    echo "  PASS: Manifest file exists"
    cat "$TEST_DIR"/*/MANIFEST.txt | head -10
else
    echo "  FAIL: Manifest file missing"
fi

# Test 4: Check critical files
echo "Test 4: Critical files verification..."
CRITICAL_FILES=(
    "jenkins/shared-storage-*.tar.gz"
    "infrastructure/ansible-configs-*.tar.gz"
    "infrastructure/certificates-*.tar.gz"
)

for file_pattern in "${CRITICAL_FILES[@]}"; do
    if find "$TEST_DIR" -name "$file_pattern" | grep -q .; then
        echo "  PASS: Found $file_pattern"
    else
        echo "  WARN: Missing $file_pattern"
    fi
done

# Test 5: Jenkins configuration validation
echo "Test 5: Jenkins configuration validation..."
if find "$TEST_DIR" -name "shared-storage-*.tar.gz" -exec tar tzf {} \; | grep -q "config.xml"; then
    echo "  PASS: Jenkins configuration found"
else
    echo "  FAIL: Jenkins configuration missing"
fi

# Cleanup
rm -rf "$TEST_DIR"

echo "Backup verification completed"
```

#### Restore Testing
```bash
#!/bin/bash
# Monthly restore testing on isolated environment

# Create test environment
docker-compose -f test/docker-compose.test.yml up -d

# Restore backup to test environment
./scripts/restore.sh /backup/local/jenkins-backup-latest.tar.gz test

# Run functionality tests
./scripts/test-jenkins-functionality.sh

# Generate test report
./scripts/generate-restore-test-report.sh

# Cleanup test environment
docker-compose -f test/docker-compose.test.yml down
```

### Backup Quality Metrics

#### Automated Quality Checks
```python
#!/usr/bin/env python3
# /usr/local/bin/backup-quality-check.py

import os
import json
import subprocess
import datetime
from pathlib import Path

def check_backup_quality(backup_file):
    """Comprehensive backup quality assessment"""
    
    results = {
        "timestamp": datetime.datetime.now().isoformat(),
        "backup_file": backup_file,
        "tests": {}
    }
    
    # Test 1: File size check
    file_size = os.path.getsize(backup_file)
    results["tests"]["file_size"] = {
        "size_mb": round(file_size / 1024 / 1024, 2),
        "status": "pass" if file_size > 100 * 1024 * 1024 else "fail",  # Min 100MB
        "message": f"Backup size: {file_size / 1024 / 1024:.2f} MB"
    }
    
    # Test 2: Archive integrity
    try:
        subprocess.run(["tar", "tzf", backup_file], 
                      check=True, capture_output=True)
        results["tests"]["integrity"] = {
            "status": "pass",
            "message": "Archive integrity verified"
        }
    except subprocess.CalledProcessError:
        results["tests"]["integrity"] = {
            "status": "fail",
            "message": "Archive integrity check failed"
        }
    
    # Test 3: Content verification
    try:
        file_list = subprocess.run(["tar", "tzf", backup_file], 
                                  capture_output=True, text=True, check=True)
        file_count = len(file_list.stdout.strip().split('\n'))
        results["tests"]["content"] = {
            "file_count": file_count,
            "status": "pass" if file_count > 100 else "warn",
            "message": f"Archive contains {file_count} files"
        }
    except subprocess.CalledProcessError:
        results["tests"]["content"] = {
            "status": "fail",
            "message": "Content verification failed"
        }
    
    # Test 4: Age check
    file_mtime = os.path.getmtime(backup_file)
    age_hours = (datetime.datetime.now().timestamp() - file_mtime) / 3600
    results["tests"]["age"] = {
        "age_hours": round(age_hours, 2),
        "status": "pass" if age_hours < 48 else "warn",
        "message": f"Backup age: {age_hours:.2f} hours"
    }
    
    return results

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("Usage: python3 backup-quality-check.py <backup_file>")
        sys.exit(1)
    
    results = check_backup_quality(sys.argv[1])
    print(json.dumps(results, indent=2))
```

## Monitoring and Alerting

### Backup Monitoring

#### Prometheus Metrics
```yaml
# Backup metrics for Prometheus
backup_metrics:
  - name: "jenkins_backup_last_success"
    help: "Timestamp of last successful backup"
    type: "gauge"
    
  - name: "jenkins_backup_duration_seconds"
    help: "Backup execution duration"
    type: "histogram"
    
  - name: "jenkins_backup_size_bytes"
    help: "Backup file size in bytes"
    type: "gauge"
    
  - name: "jenkins_backup_files_count"
    help: "Number of files in backup"
    type: "gauge"
    
  - name: "jenkins_backup_verification_status"
    help: "Backup verification status (1=success, 0=failure)"
    type: "gauge"
```

#### Backup Status Script
```bash
#!/bin/bash
# /usr/local/bin/backup-status.sh

# Export metrics for Prometheus
cat << EOF > /var/lib/node_exporter/textfile_collector/backup.prom
# HELP jenkins_backup_last_success Timestamp of last successful backup
# TYPE jenkins_backup_last_success gauge
jenkins_backup_last_success $(stat -c %Y /backup/local/jenkins-backup-*.tar.gz | tail -1)

# HELP jenkins_backup_size_bytes Backup file size in bytes
# TYPE jenkins_backup_size_bytes gauge
jenkins_backup_size_bytes $(stat -c %s /backup/local/jenkins-backup-*.tar.gz | tail -1)

# HELP jenkins_backup_files_count Number of files in backup
# TYPE jenkins_backup_files_count gauge
jenkins_backup_files_count $(tar tzf /backup/local/jenkins-backup-*.tar.gz | wc -l | tail -1)
EOF
```

#### Alert Rules
```yaml
# Prometheus alert rules for backup monitoring
groups:
  - name: backup.rules
    rules:
      - alert: BackupMissing
        expr: time() - jenkins_backup_last_success > 86400  # 24 hours
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "Jenkins backup missing for over 24 hours"
          
      - alert: BackupSizeAnomaly
        expr: jenkins_backup_size_bytes < 100000000  # Less than 100MB
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Jenkins backup size unusually small"
          
      - alert: BackupVerificationFailed
        expr: jenkins_backup_verification_status == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Jenkins backup verification failed"
```

### Notification System

#### Backup Notifications
```bash
#!/bin/bash
# /usr/local/bin/backup-notify.sh

BACKUP_STATUS="$1"
BACKUP_FILE="$2"
LOG_FILE="$3"

case "$BACKUP_STATUS" in
    "success")
        SUBJECT="✅ Jenkins Backup Successful - $(hostname)"
        PRIORITY="normal"
        ;;
    "warning")
        SUBJECT="⚠️  Jenkins Backup Warning - $(hostname)"
        PRIORITY="high"
        ;;
    "failure")
        SUBJECT="❌ Jenkins Backup Failed - $(hostname)"
        PRIORITY="critical"
        ;;
esac

# Email notification
{
    echo "Jenkins HA Infrastructure Backup Report"
    echo "======================================="
    echo ""
    echo "Status: $BACKUP_STATUS"
    echo "Timestamp: $(date)"
    echo "Hostname: $(hostname)"
    echo "Backup File: $BACKUP_FILE"
    echo ""
    echo "Log Output:"
    echo "----------"
    tail -50 "$LOG_FILE"
} | mail -s "$SUBJECT" ops@company.com

# Slack notification (if configured)
if [ -n "$SLACK_WEBHOOK" ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"$SUBJECT\"}" \
        "$SLACK_WEBHOOK"
fi
```

## Troubleshooting

### Common Backup Issues

#### 1. Backup Script Failures

**Symptom**: Backup script exits with errors
```bash
# Check backup logs
tail -f /var/log/backup/jenkins-backup-*.log

# Check disk space
df -h /backup

# Check permissions
ls -la /backup/local

# Manual backup test
sudo -u backup /usr/local/bin/jenkins-backup.sh
```

#### 2. Container Snapshot Issues

**Symptom**: Docker commit fails
```bash
# Check container status
docker ps -a | grep jenkins-master

# Check Docker daemon logs
journalctl -u docker.service -f

# Free up Docker space
docker system prune -f

# Manual container backup
docker commit jenkins-master-1 manual-backup:$(date +%Y%m%d)
```

#### 3. Shared Storage Backup Problems

**Symptom**: Cannot backup shared storage
```bash
# Check mount status
mount | grep jenkins

# Check NFS connectivity
showmount -e storage-server

# Test mount manually
sudo mount -t nfs storage-server:/export/jenkins /mnt/test

# Check file permissions
ls -la /shared/jenkins
```

#### 4. Cloud Upload Failures

**Symptom**: Backup upload to cloud fails
```bash
# Check AWS credentials
aws sts get-caller-identity

# Test S3 connectivity
aws s3 ls s3://backup-bucket/

# Check network connectivity
curl -I https://s3.amazonaws.com

# Manual upload test
aws s3 cp test-file.txt s3://backup-bucket/test/
```

### Restoration Issues

#### 1. Corrupt Backup Files

**Symptom**: Cannot extract backup
```bash
# Test archive integrity
tar tzf backup-file.tar.gz

# Try partial extraction
tar tzf backup-file.tar.gz | head -10

# Check file system
fsck /dev/sdb1

# Try alternative extraction
gunzip -t backup-file.tar.gz
```

#### 2. Permission Issues

**Symptom**: Restored files have wrong permissions
```bash
# Fix Jenkins permissions
chown -R jenkins:jenkins /shared/jenkins

# Fix container permissions
docker exec jenkins-master-1 chown -R jenkins:jenkins /var/jenkins_home

# Check SELinux context
ls -Z /shared/jenkins
restorecon -R /shared/jenkins
```

#### 3. Service Start Failures

**Symptom**: Jenkins won't start after restoration
```bash
# Check container logs
docker logs jenkins-master-1

# Check systemd status
systemctl status jenkins-master-1.service

# Check configuration files
docker exec jenkins-master-1 java -jar /usr/share/jenkins/jenkins.war --version

# Manual container start
docker run -it --rm -v jenkins-home:/var/jenkins_home jenkins/jenkins:lts bash
```

## Best Practices

### Backup Best Practices

1. **Regular Testing**: Test backup and restore procedures monthly
2. **Multiple Locations**: Store backups in multiple geographic locations
3. **Encryption**: Encrypt backups containing sensitive data
4. **Versioning**: Maintain multiple backup versions for point-in-time recovery
5. **Documentation**: Keep backup procedures updated and accessible
6. **Automation**: Automate backup processes to reduce human error
7. **Monitoring**: Continuously monitor backup success and integrity
8. **Security**: Secure backup storage with appropriate access controls

### Recovery Best Practices

1. **Practice Drills**: Regular disaster recovery drills
2. **Documentation**: Detailed recovery procedures and contact information
3. **Communication**: Clear communication plan during incidents
4. **Prioritization**: Focus on critical systems first
5. **Verification**: Always verify restored systems before returning to service
6. **Lessons Learned**: Document and address issues found during recovery

### Operational Guidelines

1. **Change Control**: Always backup before making changes
2. **Retention Policy**: Implement appropriate backup retention policies
3. **Cost Management**: Balance backup frequency with storage costs
4. **Compliance**: Ensure backup procedures meet regulatory requirements
5. **Team Training**: Regular training on backup and recovery procedures

---

This comprehensive backup and recovery documentation ensures business continuity and data protection for the Jenkins HA infrastructure through automated backup systems, tested recovery procedures, and comprehensive disaster recovery capabilities.
