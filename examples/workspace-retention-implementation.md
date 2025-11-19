# Workspace Data Retention Implementation

## Overview

Automated workspace cleanup system for Jenkins GlusterFS volumes with configurable retention policies per team.

## Problem Solved

- **Disk Space Management**: Prevents unbounded workspace growth
- **Performance**: Reduces GlusterFS volume size and improves I/O performance
- **Cost**: Minimizes storage costs for old, unused build workspaces
- **Compliance**: Enforces data retention policies

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Cron Schedule (Daily 2 AM)                │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
┌────────▼────────┐ ┌────▼────────┐ ┌────▼────────┐
│ DevOps Cleanup  │ │ MA Cleanup  │ │ BA Cleanup  │
│ Retention: 10d  │ │ Retention: 7d│ │ Retention: 7d│
└────────┬────────┘ └────┬────────┘ └────┬────────┘
         │               │               │
         ▼               ▼               ▼
┌─────────────────────────────────────────────────────────────┐
│           GlusterFS Mounted Volumes                          │
│  /var/jenkins/devops/data/workspace/                        │
│  /var/jenkins/ma/data/workspace/                            │
│  /var/jenkins/ba/data/workspace/                            │
│  /var/jenkins/tw/data/workspace/                            │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│              Cleanup Logs & Monitoring                       │
│  /var/log/glusterfs-retention/devops-cleanup.log           │
│  /var/log/glusterfs-retention/ma-cleanup.log               │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Components

### 1. Workspace Cleanup Script

File: `ansible/roles/glusterfs-server/templates/workspace-cleanup.sh.j2`

**Features**:
- Age-based deletion (mtime)
- Dry-run mode for safe testing
- Per-workspace size and age reporting
- Detailed logging with rotation
- Error handling and recovery

**Usage**:
```bash
# Dry-run for devops team (10 day retention)
/usr/local/bin/glusterfs-workspace-cleanup.sh devops 10 --dry-run

# Actual cleanup
/usr/local/bin/glusterfs-workspace-cleanup.sh devops 10

# Check logs
tail -f /var/log/glusterfs-retention/devops-cleanup.log
```

### 2. Workspace Monitoring Script

File: `ansible/roles/glusterfs-server/templates/workspace-cleanup-monitor.sh.j2`

**Features**:
- Monitors cleanup execution status
- Alerts on missed cleanups (>48 hours)
- Reports disk usage per team
- Identifies cleanup candidates
- Overall system health summary

**Usage**:
```bash
# Generate monitoring report
/usr/local/bin/glusterfs-workspace-monitor.sh

# Sample output:
# ======================================================
# GlusterFS Workspace Cleanup Monitoring Report
# ======================================================
# Team: devops
# ----------------------------------------
# Last cleanup: 2025-01-07 02:00:00 (6 hours ago)
# STATUS: OK
# Deletions today: 15 workspaces
# Current workspaces: 245 (8.2G)
# Cleanup candidates (>10 days): 12
```

### 3. Workspace Retention Report

File: `/usr/local/bin/glusterfs-workspace-report.sh`

**Features**:
- Generates comprehensive retention reports
- Shows disk usage per team
- Lists cleanup candidates
- Provides actionable insights

**Usage**:
```bash
# Generate retention report for all teams
/usr/local/bin/glusterfs-workspace-report.sh

# Sample output:
# ======================================================
# GlusterFS Workspace Retention Report
# ======================================================
# Team: devops
# Path: /var/jenkins/devops/data/workspace
# Retention: 10 days
# Total disk usage: 8.2G
# Total workspaces: 245
# Cleanup candidates (>10 days): 12 workspaces (1.5G)
#
# Team: ma
# Path: /var/jenkins/ma/data/workspace
# Retention: 7 days
# Total disk usage: 3.1G
# Total workspaces: 89
# Cleanup candidates (>7 days): 8 workspaces (450M)
```

## Configuration

### Global Settings

File: `ansible/roles/glusterfs-server/defaults/main.yml`

```yaml
# Workspace Data Retention (Automatic Cleanup)
glusterfs_workspace_retention_enabled: true
glusterfs_workspace_retention_days: 7  # Default retention
glusterfs_workspace_cleanup_schedule: "0 2 * * *"  # Daily at 2 AM
```

### Per-Team Settings

File: `ansible/inventories/production/group_vars/all/main.yml`

```yaml
jenkins_teams_config:
  - team_name: "devops"
    workspace_retention_days: 10  # Override default
    # ... other team config

  - team_name: "ma"
    workspace_retention_days: 7  # Use default
    # ... other team config
```

## Deployment

```bash
# Deploy workspace retention scripts to glusterfs servers
ansible-playbook ansible/site.yml --tags glusterfs,retention

# Verify cron jobs created
ansible glusterfs_servers -m command -a "crontab -l | grep glusterfs-workspace-cleanup"

# Expected output:
# 0 2 * * * /usr/local/bin/glusterfs-workspace-cleanup.sh devops 10 >> /var/log/glusterfs-retention/devops-cleanup.log 2>&1
# 0 2 * * * /usr/local/bin/glusterfs-workspace-cleanup.sh ma 7 >> /var/log/glusterfs-retention/ma-cleanup.log 2>&1
# 0 2 * * * /usr/local/bin/glusterfs-workspace-cleanup.sh ba 7 >> /var/log/glusterfs-retention/ba-cleanup.log 2>&1
# 0 2 * * * /usr/local/bin/glusterfs-workspace-cleanup.sh tw 7 >> /var/log/glusterfs-retention/tw-cleanup.log 2>&1
```

## Testing

### Test 1: Dry-Run Cleanup

```bash
# Test cleanup for devops team (dry-run)
/usr/local/bin/glusterfs-workspace-cleanup.sh devops 10 --dry-run

# Expected output:
# =========================================
# Workspace Cleanup Dry-Run Complete
# =========================================
# Team: devops
# Would delete: 12 workspaces
# Space to reclaim: 1.5G
# Run without --dry-run to perform actual cleanup
# =========================================
```

### Test 2: Actual Cleanup

```bash
# Run actual cleanup
/usr/local/bin/glusterfs-workspace-cleanup.sh devops 10

# Verify cleanup in logs
grep "Successfully deleted" /var/log/glusterfs-retention/devops-cleanup.log

# Check disk space reclaimed
df -h /var/jenkins/devops/data
```

### Test 3: Monitoring

```bash
# Check monitoring status
/usr/local/bin/glusterfs-workspace-monitor.sh

# Check for alerts (exit code)
if /usr/local/bin/glusterfs-workspace-monitor.sh; then
    echo "All cleanups healthy"
else
    echo "Cleanup warnings or errors detected"
fi
```

## Retention Policy Guidelines

| Team Type | Recommended Retention | Rationale |
|-----------|----------------------|-----------|
| **Production** | 10-14 days | Longer retention for troubleshooting |
| **Staging** | 7 days | Standard retention |
| **Development** | 5 days | Shorter retention for frequent builds |
| **Test/QA** | 7 days | Standard retention |

### Disk Space Estimation

Average workspace sizes:
- Maven project: 50-200MB
- Node.js project: 100-500MB (node_modules)
- Docker build: 500MB-2GB (layer cache)

Example calculation for DevOps team:
```
Builds per day: 50
Average workspace size: 200MB
Retention: 10 days

Total workspaces: 50 × 10 = 500
Total disk usage: 500 × 200MB = 100GB

With 7 day retention: 70GB (30% savings)
```

## Monitoring & Alerting

### Log Files

```bash
# Per-team cleanup logs
/var/log/glusterfs-retention/<team>-cleanup.log

# Log rotation
# Automatically rotates when log exceeds 10MB
```

### Prometheus Metrics (Future Enhancement)

```prometheus
# glusterfs_workspace_total{team="devops"}
# glusterfs_workspace_size_bytes{team="devops"}
# glusterfs_workspace_cleanup_candidates{team="devops"}
# glusterfs_workspace_cleanup_last_run_timestamp{team="devops"}
# glusterfs_workspace_cleanup_deleted_total{team="devops"}
# glusterfs_workspace_cleanup_errors_total{team="devops"}
```

### Grafana Dashboard (Future Enhancement)

Panels:
- Workspace disk usage per team (pie chart)
- Cleanup trends (time series)
- Cleanup candidates per team (gauge)
- Failed cleanups (alert panel)

## Troubleshooting

### Issue 1: Cleanup Not Running

```bash
# Check cron service
systemctl status cron

# Check cron logs
grep glusterfs-workspace-cleanup /var/log/syslog

# Manually trigger cleanup
/usr/local/bin/glusterfs-workspace-cleanup.sh devops 10
```

### Issue 2: Permission Errors

```bash
# Check GlusterFS mount permissions
ls -la /var/jenkins/devops/data/workspace

# Expected: jenkins:jenkins ownership
# If wrong, fix with:
chown -R jenkins:jenkins /var/jenkins/devops/data/workspace
```

### Issue 3: Cleanup Too Aggressive

```bash
# Increase retention period temporarily
# Edit cron job:
crontab -e

# Change retention days: 7 → 14
0 2 * * * /usr/local/bin/glusterfs-workspace-cleanup.sh devops 14 >> /var/log/glusterfs-retention/devops-cleanup.log 2>&1

# Or update inventory and redeploy:
# group_vars/all/main.yml:
# jenkins_teams_config:
#   - team_name: devops
#     workspace_retention_days: 14
```

## Integration with Blue-Green Sync

Workspace retention works seamlessly with blue-green data sync:

```bash
# During blue-green switch:
# 1. Sync recent workspaces only (last 10 days)
/usr/local/bin/jenkins-blue-green-sync.sh devops blue green

# 2. Old workspaces (>10 days) are NOT synced
# 3. Cleanup runs independently on each environment
```

See [blue-green-data-sync-guide.md](blue-green-data-sync-guide.md) for integration details.

## Benefits

| Metric | Before | After |
|--------|--------|-------|
| **Disk Usage** | Unbounded growth | Stable (7-10 day retention) |
| **Storage Costs** | High (100GB+) | Reduced by 30-50% |
| **I/O Performance** | Degraded over time | Consistent |
| **Operational Overhead** | Manual cleanup required | Fully automated |

## Related Documentation

- **GlusterFS Implementation**: [glusterfs-implementation-guide.md](glusterfs-implementation-guide.md)
- **Blue-Green Data Sync**: [blue-green-data-sync-guide.md](blue-green-data-sync-guide.md)
- **Keepalived Solution**: [keepalived-cascading-failure-solution.md](keepalived-cascading-failure-solution.md)
