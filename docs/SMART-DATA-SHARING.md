# Smart Data Sharing for Jenkins Blue-Green Deployment

This document describes the smart data sharing architecture implemented in the Jenkins HA infrastructure, ensuring true zero-downtime deployments with data consistency while maintaining plugin isolation for safe upgrades.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Shared vs Isolated Data](#shared-vs-isolated-data)
- [Implementation](#implementation)
- [Migration Guide](#migration-guide)
- [Benefits](#benefits)
- [Troubleshooting](#troubleshooting)

## Overview

The smart data sharing solution addresses a critical issue in blue-green deployments: **data consistency between environments**. Traditional blue-green setups often suffer from data inconsistency when switching environments, as each environment has its own isolated data storage.

### The Problem
```
Traditional Blue-Green (Broken):
Blue Environment:   jenkins-devops-blue-home (Volume A - Complete isolation)
Green Environment:  jenkins-devops-green-home (Volume B - Complete isolation)
Result: When switching from blue to green, the green environment starts with empty/outdated data!
```

### The Solution
```
Smart Sharing (Fixed):
SHARED DATA:
Blue Environment:   /opt/jenkins-shared/devops/jobs (Consistent job configurations)
Green Environment:  /opt/jenkins-shared/devops/jobs (Same job configurations)

ISOLATED DATA:
Blue Environment:   jenkins-devops-blue-plugins (Independent plugins)
Green Environment:  jenkins-devops-green-plugins (Independent plugins)

Result: Zero-downtime switches with consistent data + safe upgrades!
```

## Architecture

### Smart Sharing Principle

The architecture selectively shares data between blue and green environments:

- **✅ SHARED**: Data that should be consistent across environments
- **❌ ISOLATED**: Data that must remain environment-specific for safety

### Storage Layout

```
/opt/jenkins-shared/
├── devops/
│   ├── jobs/          # ✅ Job configurations (shared)
│   ├── workspace/     # ✅ Build workspaces (shared)
│   ├── builds/        # ✅ Build artifacts (shared)
│   ├── userContent/   # ✅ User content (shared)
│   └── secrets/       # ✅ Credentials (shared)
├── dev-qa/
│   ├── jobs/
│   ├── workspace/
│   ├── builds/
│   ├── userContent/
│   └── secrets/
└── backup/            # ✅ Backup storage (shared)

Docker Volumes (Isolated):
├── jenkins-devops-blue-plugins    # ❌ Blue plugins (isolated)
├── jenkins-devops-green-plugins   # ❌ Green plugins (isolated)
├── jenkins-devops-blue-logs       # ❌ Blue logs (isolated)
├── jenkins-devops-green-logs      # ❌ Green logs (isolated)
├── jenkins-dev-qa-blue-plugins    # ❌ Blue plugins (isolated)
└── jenkins-dev-qa-green-plugins   # ❌ Green plugins (isolated)
```

## Shared vs Isolated Data

### ✅ Shared Data (Consistent Across Blue/Green)

| Data Type | Path | Reason for Sharing |
|-----------|------|-------------------|
| **Jobs** | `/jobs` | Job configurations must be consistent |
| **Workspace** | `/workspace` | Source code and build workspaces |
| **Builds** | `/builds` | Build artifacts and history |
| **User Content** | `/userContent` | Custom files and documentation |
| **Secrets** | `/secrets` | Encrypted credentials and certificates |

### ❌ Isolated Data (Environment-Specific)

| Data Type | Volume | Reason for Isolation |
|-----------|--------|---------------------|
| **Plugins** | `jenkins-{team}-{env}-plugins` | Version conflicts during upgrades |
| **Logs** | `jenkins-{team}-{env}-logs` | Environment-specific troubleshooting |

### Critical: Plugin Isolation

**Why plugins must be isolated:**

1. **Upgrade Safety**: Different Jenkins versions may require different plugin versions
2. **Rollback Safety**: If green environment upgrade fails, blue environment remains unaffected
3. **Testing**: New plugin versions can be tested in green before switching
4. **Compatibility**: Plugin dependencies may vary between environments

## Implementation

### Container Volume Configuration

**Before (Problematic):**
```yaml
_active_volumes:
  - "jenkins-{{ item.team_name }}-{{ item.active_environment }}-home:/var/jenkins_home"
```

**After (Smart Sharing):**
```yaml
_active_volumes:
  # SHARED DATA: Consistent across blue/green environments
  - "{{ shared_storage_path }}/{{ item.team_name }}/jobs:/var/jenkins_home/jobs"
  - "{{ shared_storage_path }}/{{ item.team_name }}/workspace:/var/jenkins_home/workspace"
  - "{{ shared_storage_path }}/{{ item.team_name }}/builds:/var/jenkins_home/builds"
  - "{{ shared_storage_path }}/{{ item.team_name }}/userContent:/var/jenkins_home/userContent"
  - "{{ shared_storage_path }}/{{ item.team_name }}/secrets:/var/jenkins_home/secrets"
  
  # ISOLATED DATA: Environment-specific for safe upgrades
  - "jenkins-{{ item.team_name }}-{{ item.active_environment }}-plugins:/var/jenkins_home/plugins"
  - "jenkins-{{ item.team_name }}-{{ item.active_environment }}-logs:/var/jenkins_home/logs"
```

### Ansible Configuration

**Shared Storage Role Updates:**
```yaml
- name: Create team-specific shared directories (selective sharing)
  file:
    path: "{{ shared_storage_path }}/{{ item[0].team_name }}/{{ item[1] }}"
    state: directory
    owner: "{{ jenkins_user }}"
    group: "{{ jenkins_group }}"
    mode: '0755'
  loop: "{{ jenkins_teams | product(shared_data_dirs) | list }}"
  vars:
    shared_data_dirs:
      - "jobs"          # ✅ Job configurations
      - "workspace"     # ✅ Build workspaces
      - "builds"        # ✅ Build artifacts
      - "userContent"   # ✅ User content
      - "secrets"       # ✅ Encrypted credentials
      # NOTE: plugins excluded for safe upgrades
```

## Migration Guide

### Prerequisites

1. **Backup Current Data**: Always create backups before migration
2. **Shared Storage**: Ensure shared storage is properly configured
3. **Maintenance Window**: Plan for brief downtime during migration

### Migration Process

#### Step 1: Preview Migration (Dry Run)
```bash
# Preview what will be migrated
scripts/migrate-to-smart-sharing.sh --dry-run

# Preview specific team
scripts/migrate-to-smart-sharing.sh --team devops --dry-run
```

#### Step 2: Execute Migration
```bash
# Migrate all teams
scripts/migrate-to-smart-sharing.sh --force

# Migrate specific team
scripts/migrate-to-smart-sharing.sh --team devops
```

#### Step 3: Validate Migration
```bash
# Validate shared storage structure
ansible-playbook ansible/site.yml --tags shared-storage,validation

# Check directory structure
ls -la /opt/jenkins-shared/devops/
```

#### Step 4: Deploy with New Configuration
```bash
# Deploy with smart sharing volumes
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags containers
```

### Rollback Process

If migration fails or causes issues:

```bash
# Rollback specific team
scripts/rollback-smart-sharing.sh --team devops

# Rollback all teams
scripts/rollback-smart-sharing.sh --force
```

## Benefits

### 1. True Zero-Downtime Deployments
- **Job Continuity**: Running jobs continue seamlessly during environment switches
- **Data Consistency**: No loss of job configurations or build history
- **User Experience**: No interruption to user workflows

### 2. Safe Upgrade Path
- **Plugin Isolation**: Each environment maintains independent plugins
- **Rollback Safety**: Failed upgrades don't affect the stable environment
- **Testing**: New versions can be thoroughly tested before switching

### 3. Operational Efficiency
- **Simplified Backup**: Single backup point for job data
- **Reduced Complexity**: Consistent job configurations across environments
- **Faster Recovery**: Shared data reduces recovery time

### 4. Multi-Team Support
- **Team Isolation**: Each team has dedicated shared storage
- **Independent Operations**: Teams can migrate independently
- **Scalable Architecture**: Easy to add new teams

## Troubleshooting

### Common Issues

#### 1. Permission Errors
```bash
# Fix ownership
sudo chown -R jenkins:jenkins /opt/jenkins-shared/

# Check permissions
ls -la /opt/jenkins-shared/devops/
```

#### 2. Missing Directories
```bash
# Recreate directories
ansible-playbook ansible/site.yml --tags shared-storage,directories
```

#### 3. Data Not Appearing
```bash
# Verify volume mounts
docker inspect jenkins-devops-blue | grep -A 10 Mounts

# Check shared storage connectivity
docker exec jenkins-devops-blue ls -la /var/jenkins_home/jobs/
```

#### 4. Plugin Issues After Migration
```bash
# Plugins are environment-specific by design
# Reinstall plugins in the new environment if needed
docker exec jenkins-devops-green jenkins-plugin-cli --plugins <plugin-list>
```

### Validation Commands

#### Check Shared Data
```bash
# Verify job sharing between environments
ls /opt/jenkins-shared/devops/jobs/
docker exec jenkins-devops-blue ls /var/jenkins_home/jobs/
docker exec jenkins-devops-green ls /var/jenkins_home/jobs/
```

#### Check Isolated Data
```bash
# Verify plugin isolation
docker volume ls | grep plugins
docker exec jenkins-devops-blue ls /var/jenkins_home/plugins/
docker exec jenkins-devops-green ls /var/jenkins_home/plugins/
```

### Performance Monitoring

Monitor shared storage performance:
```bash
# Check I/O performance
iostat -x 1 5

# Monitor disk usage
df -h /opt/jenkins-shared/

# Check NFS performance (if using NFS)
nfsstat -c
```

## Security Considerations

### Access Controls
- **File Permissions**: Ensure proper jenkins user/group ownership
- **Network Security**: Secure NFS/GlusterFS communications
- **Credential Isolation**: Shared secrets remain encrypted

### Backup Strategy
- **Shared Data**: Regular backups of `/opt/jenkins-shared/`
- **Isolated Data**: Volume-specific backups for plugins and configs
- **Migration Backups**: Automated backups during migration process

## Conclusion

Smart data sharing provides the best of both worlds for Jenkins blue-green deployments:

1. **Data Consistency** where it matters (jobs, builds, workspace)
2. **Safety Isolation** where it's critical (plugins, logs, runtime)
3. **True Zero-Downtime** deployments with no data loss
4. **Safe Upgrade Path** with plugin and configuration isolation

This architecture ensures that blue-green deployments deliver their promised benefits without compromising data integrity or upgrade safety.