# Jenkins HA Shared Storage Integration Guide

## Overview

This document describes the comprehensive shared storage integration implemented for the Jenkins HA blue-green deployment architecture. The integration provides intelligent data sharing between blue-green environments while maintaining plugin isolation and ensuring data consistency.

## Architecture Components

### 1. Shared Storage Role (`shared-storage`)

**Location:** `ansible/roles/shared-storage/`

**Purpose:** Manages NFS and GlusterFS shared storage infrastructure with team-specific directory structures.

**Key Files:**
- `templates/exports.j2` - NFS exports configuration
- `defaults/main.yml` - Comprehensive NFS/GlusterFS defaults
- `handlers/main.yml` - Service management handlers
- `tasks/main.yml` - Storage setup and configuration

### 2. Jenkins Master v2 Integration (`jenkins-master-v2`)

**Location:** `ansible/roles/jenkins-master-v2/tasks/shared-storage-integration.yml`

**Purpose:** Bridges Jenkins containers with shared storage, implementing data synchronization and health monitoring.

**Integration Features:**
- Initial data synchronization
- Continuous sync via cron jobs
- Health monitoring and alerting
- Data consistency validation

## Data Sharing Strategy

### Smart Selective Sharing

The architecture implements intelligent data sharing that:

**✅ SHARED DATA (Team Consistency):**
- `jobs/` - Job configurations shared between blue-green
- `workspace/` - Build workspaces for consistency
- `builds/` - Build history and artifacts
- `userContent/` - User-uploaded content
- `secrets/` - Encrypted credentials and keys

**🔒 ISOLATED DATA (Environment Independence):**
- `plugins/` - Environment-specific plugin versions
- `logs/` - Environment-specific logs
- `war/` - Jenkins WAR files (version isolation)
- `tmp/` - Temporary files

### Directory Structure

```
/opt/jenkins-shared/
├── team1/
│   ├── jobs/           # Shared job configurations
│   ├── workspace/      # Shared workspaces
│   ├── builds/         # Shared build history
│   ├── userContent/    # Shared user content
│   └── secrets/        # Shared encrypted secrets
├── team2/
│   └── [same structure]
└── common/
    └── monitoring/     # Shared monitoring data
```

## Implementation Details

### 1. NFS Configuration

**Exports Template (`templates/exports.j2`):**
```bash
# Jenkins shared storage export
{{ nfs_export_path | default('/exports') }}/jenkins {{ nfs_client_networks | default('*') }}({{ nfs_export_options | default('rw,sync,no_root_squash,no_subtree_check') }})
```

**Default Configuration:**
```yaml
# NFS Server Configuration
nfs_export_path: "/exports"
nfs_export_options: "rw,sync,no_root_squash,no_subtree_check"
nfs_client_networks: "*"

# Storage paths
shared_storage_path: "/opt/jenkins-shared"
shared_storage_type: "nfs"  # or "glusterfs"
```

### 2. Data Synchronization

**Sync Script (`templates/sync-jenkins-data.sh.j2`):**

**Key Features:**
- Selective data type synchronization
- Container-aware operations
- Ownership management
- Error handling and logging
- Performance optimization

**Sync Process:**
1. Verify container and storage accessibility
2. Create team-specific directory structure
3. Sync each data type (jobs, workspace, builds, userContent, secrets)
4. Set proper ownership and permissions
5. Update sync timestamps
6. Log detailed sync results

### 3. Health Monitoring

**Monitor Script (`templates/monitor-shared-storage.sh.j2`):**

**Health Checks:**
- Storage accessibility (read/write permissions)
- Available disk space monitoring
- Team directory structure validation
- Mount status verification (NFS/GlusterFS)
- Performance testing (write/read operations)

**Alert Thresholds:**
- Default: 1000MB minimum free space
- Configurable per environment
- Multiple severity levels (warning/critical)

### 4. Data Consistency Validation

**Validation Script (`templates/validate-data-consistency.sh.j2`):**

**Validation Features:**
- File count comparison between container and shared storage
- Recent modification tracking
- Sample file content validation
- Size mismatch detection
- Comprehensive reporting

**Validation Process:**
1. Check container and storage accessibility
2. Compare file counts with configurable thresholds
3. Validate recent modifications (last hour)
4. Sample random files for content consistency
5. Generate detailed consistency report

## Integration Workflow

### Phase 3.7: Shared Storage Integration

**When:** After blue-green deployment, before HAProxy updates
**Condition:** `shared_storage_enabled: true`

**Tasks Executed:**
1. **Initial Data Sync** - Sync existing data to shared storage
2. **Cron Job Setup** - Configure continuous synchronization
3. **Health Monitoring** - Deploy monitoring scripts
4. **Consistency Validation** - Validate data integrity
5. **Service Integration** - Enable storage health checks

### Cron Job Configuration

**Sync Schedule:**
```bash
# Continuous data synchronization (every 15 minutes)
*/15 * * * * /usr/local/bin/sync-jenkins-data-{{ team_name }}.sh

# Health monitoring (every 30 minutes)
*/30 * * * * /usr/local/bin/monitor-shared-storage.sh

# Consistency validation (hourly)
0 * * * * /usr/local/bin/validate-data-consistency-{{ team_name }}.sh
```

## Service Management

### Handlers Available

**NFS Handlers:**
- `restart nfs-server` - Restart NFS server service
- `exportfs` - Reload NFS exports
- `restart rpcbind` - Restart RPC binding service

**GlusterFS Handlers:**
- `restart glusterfs` - Restart GlusterFS daemon

**General Handlers:**
- `restart shared-storage` - Restart generic storage service

### Service Dependencies

**NFS Requirements:**
- `nfs-server` service
- `rpcbind` service  
- Network connectivity between storage and Jenkins nodes

**GlusterFS Requirements:**
- `glusterd` service
- Cluster peer connectivity
- Volume mount configurations

## Configuration Variables

### Required Variables

```yaml
# Enable shared storage integration
shared_storage_enabled: true

# Storage type selection
shared_storage_type: "nfs"  # or "glusterfs"

# Team configuration with shared storage paths
jenkins_teams:
  - team_name: "devops"
    active_environment: "blue"
    shared_storage_path: "/opt/jenkins-shared/devops"
```

### Optional Variables

```yaml
# Storage paths
shared_storage_path: "/opt/jenkins-shared"
nfs_export_path: "/exports"

# Sync configuration
sync_method: "rsync"  # or "cp"
storage_alert_threshold_mb: 1000

# User/Group settings
jenkins_user: "jenkins"
jenkins_group: "jenkins"

# Network settings
nfs_client_networks: "10.0.0.0/8"
nfs_export_options: "rw,sync,no_root_squash,no_subtree_check"
```

## Monitoring and Alerting

### Log Files

**Data Sync Logs:**
- `/var/log/jenkins-{team}-sync.log` - Per-team sync operations
- Rotation: >10MB files auto-rotated

**Health Monitor Logs:**
- `/var/log/jenkins-shared-storage-health.log` - Storage health status
- Comprehensive accessibility and performance metrics

**Consistency Validation Logs:**
- `/var/log/jenkins-{team}-consistency.log` - Data validation results
- Detailed consistency reports and issue tracking

### Health Check Integration

**Jenkins Master v2 Integration:**
The shared storage health monitoring integrates with the main Jenkins deployment flow:

1. **Pre-deployment:** Validate storage accessibility
2. **Post-deployment:** Verify data synchronization
3. **Continuous:** Monitor storage health and consistency
4. **Alert Generation:** Automated notifications for storage issues

## Best Practices

### 1. Storage Performance

- Use dedicated storage networks for NFS/GlusterFS traffic
- Configure appropriate NFS mount options for performance
- Monitor storage latency and throughput
- Implement storage caching where appropriate

### 2. Data Consistency

- Schedule regular consistency validation
- Monitor sync operation success rates
- Implement automated remediation for minor inconsistencies
- Plan for disaster recovery scenarios

### 3. Security

- Restrict NFS exports to specific network ranges
- Use proper file ownership and permissions
- Encrypt sensitive data before storage
- Implement access logging and auditing

### 4. Scalability

- Plan storage capacity for team growth
- Implement storage monitoring and alerting
- Consider distributed storage for large deployments
- Optimize sync operations for large datasets

## Troubleshooting

### Common Issues

**Storage Not Accessible:**
```bash
# Check NFS mount status
findmnt /opt/jenkins-shared

# Verify NFS exports
showmount -e nfs-server-ip

# Test storage write permissions
touch /opt/jenkins-shared/test-file
```

**Sync Failures:**
```bash
# Check sync logs
tail -f /var/log/jenkins-{team}-sync.log

# Manual sync execution
/usr/local/bin/sync-jenkins-data-{team}.sh

# Verify container accessibility
docker ps | grep jenkins-{team}
```

**Data Consistency Issues:**
```bash
# Run consistency validation
/usr/local/bin/validate-data-consistency-{team}.sh

# Check file counts manually
docker exec jenkins-{team}-{env} find /var/jenkins_home/jobs -type f | wc -l
find /opt/jenkins-shared/{team}/jobs -type f | wc -l
```

## Benefits Achieved

### 1. True Zero-Downtime Deployment
- Shared job configurations ensure consistency
- No job loss during blue-green switches
- Workspace preservation across deployments

### 2. Enhanced Data Protection
- Centralized backup from shared storage
- Disaster recovery simplification
- Data redundancy across environments

### 3. Operational Efficiency
- Automated data synchronization
- Health monitoring and alerting
- Consistency validation automation

### 4. Scalability and Flexibility
- Team-specific storage isolation
- Multiple storage backend support
- Configurable sync strategies

This shared storage integration completes the enterprise-grade Jenkins HA architecture, providing robust data management while maintaining the benefits of blue-green deployment patterns.