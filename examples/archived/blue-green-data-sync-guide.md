# Blue-Green Data Synchronization Guide

## Overview

Selective data sharing system between blue and green Jenkins environments, enabling safe plugin upgrades while maintaining data consistency.

## Problem Solved

- **Safe Plugin Upgrades**: Test new plugins in inactive environment without affecting active
- **Zero-Downtime Switches**: Seamless environment switching with data continuity
- **Data Consistency**: Job configurations and builds available in both environments
- **Plugin Isolation**: Plugins remain environment-specific to prevent conflicts

## Data Sharing Strategy

### SHARED DATA (Bidirectional Sync)

| Directory | Purpose | Retention | Why Shared |
|-----------|---------|-----------|------------|
| **jobs/** | Job configurations | All | Configuration must be consistent |
| **builds/** | Build history & artifacts | All | Historical data needed in both |
| **workspace/** | Build workspaces | 7-10 days | Recent builds only |

### ISOLATED DATA (Never Synced)

| Directory | Purpose | Why Isolated |
|-----------|---------|--------------|
| **plugins/** | Plugin binaries | Safe upgrade testing without affecting active |
| **logs/** | Jenkins logs | Environment-specific diagnostics |
| **.cache/** | Temp cache files | Environment-specific |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Blue Environment (Active)                     │
│                                                                  │
│  /var/jenkins/devops/data/blue/                                 │
│  ├── jobs/           ◄────┐                                     │
│  ├── builds/         ◄────┤ SHARED (Synced)                    │
│  ├── workspace/      ◄────┤                                     │
│  ├── plugins/             │ ISOLATED (Not Synced)               │
│  ├── logs/                │                                     │
│  └── .cache/              │                                     │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                    ┌───────▼────────┐
                    │  Rsync Sync    │
                    │  - Incremental │
                    │  - Bidirectional│
                    │  - Selective   │
                    └───────┬────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                   Green Environment (Inactive)                   │
│                                                                  │
│  /var/jenkins/devops/data/green/                                │
│  ├── jobs/           (Synced from blue)                         │
│  ├── builds/         (Synced from blue)                         │
│  ├── workspace/      (Recent only, 10 days)                     │
│  ├── plugins/        (Independent - different versions)         │
│  ├── logs/           (Independent)                              │
│  └── .cache/         (Independent)                              │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Components

### 1. Blue-Green Sync Script

File: `ansible/roles/jenkins-master-v2/templates/blue-green-sync.sh.j2`

**Features**:
- Selective directory sync (jobs, builds, workspace)
- Workspace retention (only sync recent workspaces)
- Plugin isolation (never syncs plugins/)
- Dry-run mode for safe testing
- Detailed logging with success/failure tracking

**Usage**:
```bash
# Generic sync script
/usr/local/bin/jenkins-blue-green-sync.sh <team> <source_env> <target_env> [--dry-run]

# Examples:
/usr/local/bin/jenkins-blue-green-sync.sh devops blue green --dry-run
/usr/local/bin/jenkins-blue-green-sync.sh ma green blue
```

### 2. Per-Team Wrapper Scripts

Automatically created for each team during deployment:

```bash
# DevOps team wrapper
/usr/local/bin/jenkins-sync-devops.sh <source_env> <target_env> [--dry-run]

# Marketing Analytics team wrapper
/usr/local/bin/jenkins-sync-ma.sh <source_env> <target_env> [--dry-run]

# Business Analytics team wrapper
/usr/local/bin/jenkins-sync-ba.sh <source_env> <target_env> [--dry-run]

# Test/QA team wrapper
/usr/local/bin/jenkins-sync-tw.sh <source_env> <target_env> [--dry-run]
```

## Configuration

### Global Settings

File: `ansible/roles/jenkins-master-v2/defaults/main.yml`

```yaml
# Blue-Green Data Sync Configuration
jenkins_workspace_retention_days: 10  # Only sync workspaces modified within last N days
jenkins_blue_green_sync_enabled: true  # Enable blue-green data sync scripts
```

## Deployment

```bash
# Deploy blue-green sync scripts
ansible-playbook ansible/site.yml --tags jenkins,blue-green,sync

# Verify scripts created
ls -la /usr/local/bin/jenkins-*sync*.sh

# Check documentation
cat /usr/local/share/doc/jenkins-blue-green-sync-README.md
```

## Blue-Green Switch Workflow

### Step 1: Deploy New Jenkins Version to Inactive Environment

```bash
# Example: DevOps team currently on blue, test new version in green
ansible-playbook ansible/site.yml \
  --tags jenkins,deploy \
  -e "deploy_teams=devops" \
  -e "jenkins_override_version=2.440.1"

# This deploys new Jenkins version to GREEN environment (port 8180)
# BLUE environment (port 8080) remains active and untouched
```

### Step 2: Sync Data from Active to Inactive

```bash
# DRY-RUN first to preview changes
/usr/local/bin/jenkins-sync-devops.sh blue green --dry-run

# Review dry-run output:
# =========================================
# Blue-Green Data Synchronization
# =========================================
# Team: devops
# Direction: blue → green
# Mode: DRY-RUN
# =========================================
#
# Syncing: jobs/
#   Found 245 job configurations
#   Sync successful
#
# Syncing: builds/
#   Found 1,234 build records
#   Sync successful
#
# Syncing: workspace/
#   Found 45 recent workspaces (last 10 days)
#   Sync successful
#
# =========================================
# Isolated Data (Not Synced)
# =========================================
# - plugins/   (Plugin isolation for safe upgrades)
# - logs/      (Environment-specific logs)
# - .cache/    (Environment-specific cache)

# If dry-run looks good, perform actual sync
/usr/local/bin/jenkins-sync-devops.sh blue green
```

### Step 3: Validate Inactive Environment

```bash
# Access green environment directly (port 8180 if blue is 8080)
curl -f http://localhost:8180/login

# Verify job configurations synced
curl -s http://localhost:8180/api/json | jq '.jobs | length'

# Test build execution in green environment
# (access via browser at http://localhost:8180)
```

### Step 4: Switch Active Environment

```bash
# Update inventory configuration
# File: ansible/inventories/production/group_vars/all/main.yml
jenkins_teams_config:
  - team_name: "devops"
    active_environment: "green"  # Change from "blue" to "green"
    # ... rest of config

# Deploy HAProxy configuration update
ansible-playbook ansible/site.yml --tags haproxy-sync

# HAProxy now routes devops team traffic to GREEN environment
# BLUE environment remains running but not receiving traffic
```

### Step 5: Sync Back if Needed

```bash
# After testing green for a while, sync any new builds back to blue
/usr/local/bin/jenkins-sync-devops.sh green blue --dry-run
/usr/local/bin/jenkins-sync-devops.sh green blue

# Now both environments have all data
# Can switch back to blue at any time
```

## Sync Behavior Details

### Workspace Sync (Retention-Based)

Only workspaces modified within retention period are synced:

```bash
# Example: 10 day retention
# Workspaces older than 10 days are NOT synced
# Saves time and disk space

# Source: 500 workspaces (150GB)
# Target: 45 workspaces (12GB) - only recent ones

# This prevents:
# - Wasted disk space on old, unused workspaces
# - Slow sync times for large datasets
# - Unnecessary data duplication
```

### Plugin Isolation Rationale

Plugins are NEVER synced to enable safe upgrades:

```
Blue Environment (Active - Production)
├── plugins/
│   ├── git-plugin.jpi (v4.10.0 - stable)
│   ├── workflow-aggregator.jpi (v2.6 - stable)
│   └── ... (50 other plugins)

Green Environment (Inactive - Testing)
├── plugins/
│   ├── git-plugin.jpi (v5.0.0 - TESTING NEW VERSION)
│   ├── workflow-aggregator.jpi (v3.0 - TESTING NEW VERSION)
│   └── ... (50 other plugins)

Result:
- Green can test new plugins without risk
- If green breaks, blue is unaffected
- Can rollback instantly by switching back to blue
```

## Testing

### Test 1: Dry-Run Sync

```bash
# Dry-run for all teams
for team in devops ma ba tw; do
    echo "Testing $team..."
    /usr/local/bin/jenkins-sync-$team.sh blue green --dry-run
done
```

### Test 2: Plugin Isolation Verification

```bash
# Install different plugin version in green
# Blue: git-plugin v4.10.0
# Green: git-plugin v5.0.0

# Run sync
/usr/local/bin/jenkins-sync-devops.sh blue green

# Verify plugins NOT synced
BLUE_PLUGIN_VERSION=$(docker exec jenkins-devops-blue cat /var/jenkins_home/plugins/git/META-INF/MANIFEST.MF | grep Plugin-Version)
GREEN_PLUGIN_VERSION=$(docker exec jenkins-devops-green cat /var/jenkins_home/plugins/git/META-INF/MANIFEST.MF | grep Plugin-Version)

echo "Blue: $BLUE_PLUGIN_VERSION"
echo "Green: $GREEN_PLUGIN_VERSION"

# Expected: Different versions (isolation confirmed)
```

### Test 3: Workspace Retention

```bash
# Create old workspace (15 days old) in blue
docker exec jenkins-devops-blue bash -c "mkdir -p /var/jenkins_home/workspace/old-job && touch -d '15 days ago' /var/jenkins_home/workspace/old-job"

# Sync to green (10 day retention)
/usr/local/bin/jenkins-sync-devops.sh blue green

# Verify old workspace NOT synced
docker exec jenkins-devops-green ls /var/jenkins_home/workspace/

# Expected: old-job directory does NOT exist in green
```

## Troubleshooting

### Issue 1: Sync Failing

```bash
# Check logs
tail -f /var/log/jenkins-bluegreen-sync-devops.log

# Common causes:
# - Source/target path not accessible
# - Permission errors
# - Disk space full

# Fix permissions
chown -R jenkins:jenkins /var/jenkins/devops/data
```

### Issue 2: Job Not Appearing After Sync

```bash
# Jenkins may cache job list
# Restart Jenkins to reload configuration
docker restart jenkins-devops-green

# Or use Jenkins CLI to reload
docker exec jenkins-devops-green java -jar /var/jenkins_home/war/WEB-INF/jenkins-cli.jar -s http://localhost:8080/ reload-configuration
```

### Issue 3: Sync Too Slow

```bash
# Reduce workspace retention to sync fewer workspaces
# Edit: ansible/roles/jenkins-master-v2/defaults/main.yml
jenkins_workspace_retention_days: 5  # Reduced from 10

# Redeploy sync scripts
ansible-playbook ansible/site.yml --tags jenkins,blue-green,sync

# Or manually adjust in wrapper script:
# Edit /usr/local/bin/jenkins-sync-devops.sh
# Change WORKSPACE_RETENTION_DAYS
```

## Monitoring

### Log Files

```bash
# Per-team sync logs
/var/log/jenkins-bluegreen-sync-<team>.log

# View recent syncs
tail -100 /var/log/jenkins-bluegreen-sync-devops.log
```

### Metrics (Future Enhancement)

```prometheus
# jenkins_bluegreen_sync_duration_seconds{team="devops",direction="blue_to_green"}
# jenkins_bluegreen_sync_bytes_transferred{team="devops"}
# jenkins_bluegreen_sync_files_synced_total{team="devops"}
# jenkins_bluegreen_sync_errors_total{team="devops"}
```

## Benefits

| Aspect | Without Sync | With Sync |
|--------|--------------|-----------|
| **Plugin Testing** | Risk to production | Safe in isolation |
| **Data Consistency** | Manual copy required | Automated sync |
| **Switch Speed** | Manual data migration (hours) | Instant (HAProxy config) |
| **Rollback** | Difficult | Instant (switch back) |
| **Disk Usage** | Full duplication | Selective (30% savings) |

## Best Practices

1. **Always dry-run first**: Test sync before actual execution
2. **Sync before switch**: Ensure inactive environment has latest data
3. **Verify after sync**: Check job count and recent builds
4. **Sync both directions**: After testing in green, sync back to blue
5. **Monitor disk space**: Adjust retention if disk fills up
6. **Document changes**: Note plugin versions tested in each environment

## Integration with Other Solutions

- **Workspace Retention**: Old workspaces automatically cleaned (see [workspace-retention-implementation.md](workspace-retention-implementation.md))
- **Keepalived**: Independent environment switches don't trigger VIP failover (see [keepalived-cascading-failure-solution.md](keepalived-cascading-failure-solution.md))
- **GlusterFS**: Team volumes provide isolated storage (see [glusterfs-implementation-guide.md](glusterfs-implementation-guide.md))

## Related Documentation

- **GlusterFS Volume Setup**: [glusterfs-implementation-guide.md](glusterfs-implementation-guide.md)
- **Workspace Retention**: [workspace-retention-implementation.md](workspace-retention-implementation.md)
- **Multi-Team Independence**: [team-independence-validation.md](team-independence-validation.md)
