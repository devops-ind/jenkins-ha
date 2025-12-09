# Dynamic Configuration Update for Jenkins JCasC

**Status**: File-Based Approach RECOMMENDED (Symlink approach DEPRECATED due to Docker limitations)
**Date**: December 2025
**Mode**: Simplified Hot-Reload Approach
**Complexity**: Low (eliminates blue-green container switching)

---

## IMPORTANT: Docker Symlink Limitation

**The symlink-based approach described below does NOT work with Docker** due to symlink resolution at mount time. Even when mounting parent directories, Docker resolves symlinks to their target directories, breaking hot-reload functionality.

**Recommended Solution**: Use the **File-Copy Based Hot-Reload** approach described below, which uses regular files instead of symlinks.

---

## File-Copy Based Hot-Reload (RECOMMENDED)

### Overview

This approach uses **regular files** instead of symlinks to achieve hot-reload functionality that works reliably with Docker bind mounts.

### Key Features

- Single Jenkins container per team (50% resource reduction)
- Zero-downtime configuration updates via JCasC hot-reload API
- Docker-compatible (no symlink resolution issues)
- Automatic backups with rollback capability
- State tracking for audit trail

### Directory Structure

```
/var/jenkins/
├── devops/
│   ├── configs/
│   │   ├── blue.yaml              # Blue environment config (regular file)
│   │   ├── green.yaml             # Green environment config (regular file)
│   │   └── current.yaml           # Active config mounted in container (regular file)
│   ├── backups/
│   │   ├── current.yaml.20251209_101530
│   │   ├── current.yaml.20251209_102045
│   │   └── current.yaml.20251209_103012
│   └── config-state.json          # Metadata tracking
├── developer/
│   └── (same structure)
└── qa/
    └── (same structure)
```

### Container Mounting

```yaml
Container: jenkins-devops
Volumes:
  - jenkins-devops-home:/var/jenkins_home
  # Mount single file for hot-reload (works reliably with Docker)
  - /var/jenkins/devops/configs/current.yaml:/var/jenkins_home/casc_configs/jenkins.yaml:ro

Environment:
  CASC_JENKINS_CONFIG: /var/jenkins_home/casc_configs/jenkins.yaml
```

**Critical Notes**:
1. **Mount single file**, not directory (avoid symlink resolution issues)
2. **Read-only mount (`:ro`)** for security
3. **File changes are immediately visible** in container
4. **No symlinks involved** - pure file operations

### Configuration Switching

To switch from blue to green configuration:

```bash
# Run the config-file-switch script
./scripts/config-file-switch.sh devops green

# Script performs:
# 1. Validates arguments (team_name, target_config)
# 2. Backs up current config with timestamp
# 3. Copies green.yaml to current.yaml
# 4. Verifies file content matches (diff check)
# 5. Updates state tracking JSON
# 6. Cleans up old backups (keeps last 10)

# Then trigger hot-reload via JCasC API
curl -X POST -u admin:TOKEN http://localhost:8080/configuration-as-code/reload
```

### Deployment Configuration

Set in `ansible/group_vars/all/jenkins.yml`:

```yaml
jenkins_config_update_mode: "file"  # RECOMMENDED
```

### Benefits

| Aspect | Value |
|--------|-------|
| **Downtime** | 0 seconds (hot reload) |
| **Resource Usage** | 1x (single container per team) |
| **Docker Compatibility** | Yes (no symlink issues) |
| **Backup/Rollback** | Automatic with retention |
| **Switch Speed** | <1 second |
| **State Tracking** | JSON audit trail |

---

## Symlink-Based Hot-Reload (DEPRECATED)

**WARNING**: This approach does NOT work with Docker due to symlink resolution at mount time.

### Overview

This document describes the **simplified symlink-based approach** for dynamically updating Jenkins JCasC configurations without container restarts or blue-green switching.

**Known Issue**: Docker resolves symlinks at mount time, even when mounting parent directories. The symlink appears as a directory inside the container, preventing Jenkins from loading JCasC configurations.

### Key Innovation

Instead of running blue/green containers and switching between them, we:
1. Use **symbolic links** to point to active configuration
2. Mount the symlink as **read-only** into Jenkins container
3. Update config by **switching the symlink atomically**
4. **Hot-reload** Jenkins via JCasC API (no restart)

### Benefits Over Blue-Green Container Approach

| Aspect | Blue-Green Containers | Symlink + Hot-Reload |
|--------|----------------------|---------------------|
| **Complexity** | High (2 containers per team) | Low (1 container per team) |
| **Resource Usage** | 2x memory, 2x CPU | 1x resources |
| **Switch Speed** | 5-10 seconds (container lifecycle) | <1 second (symlink + reload) |
| **Downtime** | ~5 seconds (container start) | 0 seconds (hot reload) |
| **Implementation** | ~1,500 lines of code | ~800 lines of code |
| **Maintenance** | Complex (HAProxy, state tracking) | Simple (symlinks, API call) |

---

## Architecture

### Directory Structure

```
/var/jenkins/
├── devops/
│   ├── configs/
│   │   ├── blue/
│   │   │   └── jenkins.yaml          # Current config
│   │   ├── green/
│   │   │   └── jenkins.yaml          # New config (being validated)
│   │   └── active -> blue            # Symlink to active config
│   ├── backups/
│   │   ├── jenkins.yaml.20251208_101530
│   │   ├── jenkins.yaml.20251208_102045
│   │   └── jenkins.yaml.20251208_103012
│   ├── update.lock/                  # Lock directory for concurrent updates
│   └── config-state.json             # Metadata tracking
├── developer/
│   └── (same structure)
└── qa/
    └── (same structure)
```

### Container Mounting

```yaml
Container: jenkins-devops
Volumes:
  - jenkins-devops-home:/var/jenkins_home
  - jenkins-devops-shared:/var/jenkins_shared
  # Mount parent directory to preserve symlink behavior inside container
  - /var/jenkins/devops/configs:/var/jenkins_home/casc_configs_root:ro  # READ-ONLY!

Environment:
  # Point to the symlink path inside container
  CASC_JENKINS_CONFIG: /var/jenkins_home/casc_configs_root/active
```

**Critical Notes**:
1. **The config mount is read-only (`:ro`)** for security. Jenkins cannot modify its own configuration.
2. **We mount the parent `configs/` directory**, not the symlink directly. This is because Docker resolves symlinks at mount time, which breaks hot-reload.
3. **Inside the container**, the symlink is preserved: `/var/jenkins_home/casc_configs_root/active -> blue/` or `green/`
4. **When we switch the symlink** on the host from `blue` to `green`, the container sees the change immediately.

---

## Deployment Flow

### Initial Setup

```
1. Ansible creates directory structure
   ├── /var/jenkins/{team}/configs/{blue,green}/
   ├── /var/jenkins/{team}/backups/
   └── /var/jenkins/{team}/update.lock/

2. Ansible deploys initial config to both blue and green
   ├── blue/jenkins.yaml (from jenkins-configs/{team}.yml)
   └── green/jenkins.yaml (same)

3. Ansible creates symlink: active -> blue

4. Ansible deploys single container per team
   └── Mounts: /var/jenkins/{team}/configs -> /var/jenkins_home/casc_configs_root:ro

5. Jenkins starts and loads config from /var/jenkins_home/casc_configs_root/active/jenkins.yaml
```

### Configuration Update Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│ Developer commits changes to jenkins-configs/{team}.yml              │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 1. ACQUIRE LOCK                                                      │
│    - Create /var/jenkins/{team}/update.lock/                        │
│    - Prevents concurrent updates                                     │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 2. BACKUP CURRENT CONFIG                                             │
│    - Read current symlink target (blue or green)                    │
│    - Copy to backups/jenkins.yaml.{timestamp}                       │
│    - Keep last 10 backups                                           │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 3. VALIDATION (Parallel)                                             │
│    ├─ YAML Syntax (Jenkins readYaml)                                │
│    ├─ Security Check (Groovy: no hardcoded passwords)               │
│    ├─ JCasC Schema (Jenkins API: /configuration-as-code/check)      │
│    ├─ Plugin Dependencies (verify all plugins installed)            │
│    └─ Dry-Run Test (temporary container with new config)            │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 4. DEPLOY TO STANDBY                                                 │
│    - Determine standby (if active=blue, standby=green)              │
│    - Copy new config: jenkins-configs/{team}.yml -> green/          │
│    - Set ownership: chown 1000:1000                                 │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 5. APPROVAL GATE (Optional for production)                           │
│    - Manual approval required                                        │
│    - Timeout: 15 minutes                                             │
│    - Submitter: admin, devops                                        │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 6. SWITCH SYMLINK (Atomic)                                           │
│    - ln -sfn green /var/jenkins/{team}/configs/active               │
│    - Verify: readlink active == green                               │
│    - Update state file: config-state.json                           │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 7. HOT RELOAD JENKINS                                                │
│    - POST http://localhost:8080/configuration-as-code/reload        │
│    - Jenkins re-reads config from casc_configs/ (now points to green)│
│    - No container restart, no downtime                              │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 8. POST-RELOAD VALIDATION                                            │
│    ├─ API Health Check (/api/json)                                  │
│    ├─ Login Page (/login)                                           │
│    ├─ Job List (/api/json?tree=jobs)                                │
│    └─ System Info (/computer/api/json)                              │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 9. NOTIFICATIONS & CLEANUP                                           │
│    - Send Slack notification                                         │
│    - Create Grafana annotation                                       │
│    - Release lock (rmdir update.lock)                               │
│    - Update metrics (Prometheus)                                     │
└──────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │  IF ANY FAILURE │
                    └────────┬────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │ AUTOMATIC ROLLBACK   │
                  ├──────────────────────┤
                  │ 1. Switch back: blue │
                  │ 2. Hot reload again  │
                  │ 3. Verify health     │
                  │ 4. Alert on failure  │
                  └──────────────────────┘
```

---

## Usage

### Enable Symlink Mode

In your inventory or group_vars:

```yaml
# ansible/group_vars/all/jenkins.yml
jenkins_config_update_mode: "symlink"  # Options: 'symlink' or 'blue-green'
```

### Deploy Infrastructure

```bash
# Full deployment with symlink mode
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml \
  -e jenkins_config_update_mode=symlink

# Update only container configuration
ansible-playbook ansible/site.yml --tags container \
  -e jenkins_config_update_mode=symlink
```

### Update Configuration via Pipeline

1. **Edit configuration file**:
   ```bash
   vim jenkins-configs/devops.yml
   # Make your changes
   git add jenkins-configs/devops.yml
   git commit -m "Update devops Jenkins config: add new plugin"
   git push
   ```

2. **Run pipeline**:
   - Go to Jenkins → "Update Team Configuration" job
   - Select Parameters:
     - TEAM: `devops`
     - CONFIG_FILE: `jenkins-configs/devops.yml`
     - SKIP_DRY_RUN: `false` (recommended)
     - AUTO_APPROVE: `false` (for production)
   - Click "Build"

3. **Approve** (if approval gate enabled):
   - Pipeline will pause at approval stage
   - Review changes
   - Click "Proceed with switch"

4. **Monitor**:
   - Watch build console output
   - Check Jenkins is responsive: http://jenkins.example.com
   - Verify config changes took effect

### Manual Operations

#### Check Current Config
```bash
# What config is currently active?
readlink /var/jenkins/devops/configs/active
# Output: blue

# View current config
cat /var/jenkins/devops/configs/blue/jenkins.yaml
```

#### Manual Switch (Emergency)
```bash
# Switch to green config
/home/jenkins/scripts/config-symlink-switch.sh devops green

# Hot reload Jenkins
export JENKINS_ADMIN_TOKEN="your-token"
/home/jenkins/scripts/jenkins-hot-reload.sh devops http://localhost:8080 admin $JENKINS_ADMIN_TOKEN
```

#### Manual Rollback
```bash
# Check what was previous config
jq '.previous_config' /var/jenkins/devops/config-state.json

# Switch back
/home/jenkins/scripts/config-symlink-switch.sh devops blue

# Reload
/home/jenkins/scripts/jenkins-hot-reload.sh devops
```

#### View Backup History
```bash
ls -lht /var/jenkins/devops/backups/
# Output:
# jenkins.yaml.20251208_103012
# jenkins.yaml.20251208_102045
# jenkins.yaml.20251208_101530
```

---

## Configuration Variables

### Ansible Variables

```yaml
# Deployment mode
jenkins_config_update_mode: "symlink"  # or "blue-green"

# Directory locations (defaults)
jenkins_base_dir: "/var/jenkins"
jenkins_config_dir: "{{ jenkins_base_dir }}/{{ team_name }}/configs"
jenkins_backup_dir: "{{ jenkins_base_dir }}/{{ team_name }}/backups"

# Container settings
jenkins_master_user_id: 1000
jenkins_master_group_id: 1000
jenkins_master_startup_wait_time: 30

# JCasC settings
jenkins_casc_mount_path: "/var/jenkins_home/casc_configs"
jenkins_casc_read_only: true  # CRITICAL: Always keep read-only

# Backup retention
jenkins_config_backup_retention: 10
```

### Pipeline Parameters

```groovy
parameters {
    choice(name: 'TEAM', choices: ['devops', 'developer', 'qa'])
    string(name: 'CONFIG_FILE', defaultValue: 'jenkins-configs/${TEAM}.yml')
    booleanParam(name: 'SKIP_DRY_RUN', defaultValue: false)
    booleanParam(name: 'AUTO_APPROVE', defaultValue: false)
}
```

### Environment Variables

```bash
# For manual operations
export JENKINS_BASE_DIR="/var/jenkins"
export JENKINS_ADMIN_TOKEN="your-api-token"
export JENKINS_URL="http://localhost:8080"

# For notifications
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
export GRAFANA_URL="http://grafana:3000"
export GRAFANA_API_KEY="your-grafana-key"
```

---

## Security Considerations

### 1. Read-Only Mount
```yaml
# ALWAYS mount config as read-only
volumes:
  - "/var/jenkins/devops/configs/active:/var/jenkins_home/casc_configs:ro"
```

**Why?** Prevents Jenkins from modifying its own configuration, enforcing GitOps workflow.

### 2. No Hardcoded Secrets
```yaml
# ❌ BAD
credentials:
  - id: "github-token"
    password: "ghp_1234567890abcdef"  # NEVER DO THIS

# ✅ GOOD
credentials:
  - id: "github-token"
    password: "${GITHUB_TOKEN}"  # Use environment variables
```

### 3. Lock Mechanism
```bash
# Prevents race conditions
mkdir /var/jenkins/{team}/update.lock  # Atomic operation
# Update config...
rmdir /var/jenkins/{team}/update.lock
```

### 4. Validation Gates
- **YAML syntax**: Prevents malformed configs
- **JCasC schema**: Validates against JCasC plugin schema
- **Security scan**: Detects hardcoded passwords/tokens
- **Dry-run test**: Catches runtime errors before production

### 5. Approval for Production
```yaml
when:
  expression { !params.AUTO_APPROVE }
steps:
  input(message: "Proceed?", submitter: 'admin,devops')
```

---

## Troubleshooting

### Problem: Hot Reload Failed

**Symptoms**: `curl POST /configuration-as-code/reload` returns non-200

**Diagnosis**:
```bash
# Check Jenkins logs
docker logs jenkins-devops | tail -100

# Check config syntax
curl -u admin:token -X POST \
  -H 'Content-Type: application/x-yaml' \
  --data-binary @/var/jenkins/devops/configs/green/jenkins.yaml \
  http://localhost:8080/configuration-as-code/check
```

**Solution**:
1. Review validation errors in logs
2. Fix config file
3. Re-run pipeline or manual switch + reload

### Problem: Symlink Not Switching

**Symptoms**: `readlink active` still shows old target

**Diagnosis**:
```bash
# Check permissions
ls -l /var/jenkins/devops/configs/
# Should show: active -> blue

# Check if lock exists
ls -d /var/jenkins/devops/update.lock 2>/dev/null
```

**Solution**:
```bash
# Remove stale lock
rmdir /var/jenkins/devops/update.lock

# Manual switch
ln -sfn green /var/jenkins/devops/configs/active
```

### Problem: Container Not Reading New Config

**Symptoms**: Config changes don't appear after reload

**Diagnosis**:
```bash
# Check what container sees (note the updated path)
docker exec jenkins-devops ls -l /var/jenkins_home/casc_configs_root/
docker exec jenkins-devops ls -l /var/jenkins_home/casc_configs_root/active
docker exec jenkins-devops cat /var/jenkins_home/casc_configs_root/active/jenkins.yaml

# Verify the symlink is preserved inside container
docker exec jenkins-devops readlink /var/jenkins_home/casc_configs_root/active
# Should output: blue or green (NOT a full path)
```

**Solution**:
1. Verify symlink points to correct target on host:
   ```bash
   readlink /var/jenkins/devops/configs/active
   ```
2. Verify symlink is preserved inside container (should be relative symlink):
   ```bash
   docker exec jenkins-devops readlink /var/jenkins_home/casc_configs_root/active
   ```
3. If symlink is resolved to absolute path inside container, redeploy with correct mount

### Problem: Docker Resolves Symlink (Mount Issue)

**Symptoms**:
- Symlink appears as a directory inside container
- Config updates don't take effect even after symlink switch
- `ls -l` inside container shows directory instead of symlink

**Example**:
```bash
# On host
ls -l /var/jenkins/devops/configs/
# active -> blue (correct symlink)

# Inside container (WRONG - if mounted incorrectly)
docker exec jenkins-devops ls -lad /var/jenkins_home/casc_configs
# drwxr-xr-x 2 root root 4096 Dec 9 12:14 /var/jenkins_home/casc_configs
# ^^^ This is a DIRECTORY, not a symlink! WRONG!

# Inside container (CORRECT - with parent directory mount)
docker exec jenkins-devops ls -lad /var/jenkins_home/casc_configs_root/active
# lrwxrwxrwx 1 root root 4 Dec 9 12:14 /var/jenkins_home/casc_configs_root/active -> blue
# ^^^ This is a SYMLINK! CORRECT!
```

**Root Cause**:
Docker resolves symlinks at mount time. When you mount `/var/jenkins/devops/configs/active` directly, Docker resolves the symlink to its target (`blue/` or `green/`) and mounts that target as a directory.

**Solution**:
Mount the **parent directory** containing the symlink, not the symlink itself:

```yaml
# WRONG - Docker resolves the symlink
volumes:
  - "/var/jenkins/devops/configs/active:/var/jenkins_home/casc_configs:ro"

# CORRECT - Mount parent directory to preserve symlink
volumes:
  - "/var/jenkins/devops/configs:/var/jenkins_home/casc_configs_root:ro"

# Update environment variable to point to symlink path inside container
environment:
  CASC_JENKINS_CONFIG: "/var/jenkins_home/casc_configs_root/active"
```

**Verification**:
```bash
# Test with a simple alpine container
docker run --rm -it \
  -v /var/jenkins/devops/configs:/test:ro \
  alpine sh -c "ls -l /test/active && readlink /test/active"

# Should show:
# lrwxrwxrwx 1 root root 4 Dec 9 12:14 /test/active -> blue
# blue
```

### Problem: Concurrent Update Conflict

**Symptoms**: Pipeline stuck at "Waiting for lock"

**Diagnosis**:
```bash
# Check lock status
ls -d /var/jenkins/*/update.lock 2>/dev/null

# Check lock age
stat /var/jenkins/devops/update.lock
```

**Solution**:
```bash
# If lock is stale (>30 minutes), remove it
find /var/jenkins/*/update.lock -mmin +30 -type d -exec rmdir {} \;
```

### Problem: Rollback Failed

**Symptoms**: Automatic rollback couldn't restore previous config

**Manual Rollback**:
```bash
# 1. Check backup
ls -lht /var/jenkins/devops/backups/ | head -1

# 2. Restore from backup
LATEST_BACKUP=$(ls -t /var/jenkins/devops/backups/jenkins.yaml.* | head -1)
cp $LATEST_BACKUP /var/jenkins/devops/configs/blue/jenkins.yaml

# 3. Switch to blue
ln -sfn blue /var/jenkins/devops/configs/active

# 4. Reload
curl -X POST -u admin:$TOKEN http://localhost:8080/configuration-as-code/reload
```

---

## Monitoring & Metrics

### Prometheus Metrics

```yaml
# Custom metrics (add to Prometheus config)
- job_name: 'jenkins-config-updates'
  static_configs:
    - targets: ['jenkins-exporter:9118']
  metric_relabel_configs:
    - source_labels: [__name__]
      regex: 'jenkins_config_(updates|rollbacks|failures)_total'
      action: keep
```

### Grafana Dashboard

Key metrics to track:
- Config update success rate (per team)
- Hot reload latency
- Rollback frequency
- Time since last update
- Validation failure rate

### Alerting Rules

```yaml
groups:
  - name: jenkins_config_updates
    rules:
      - alert: HighConfigUpdateFailureRate
        expr: |
          rate(jenkins_config_failures_total[1h]) > 0.2
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "High config update failure rate"

      - alert: ConfigUpdateRollbackDetected
        expr: |
          increase(jenkins_config_rollbacks_total[5m]) > 0
        labels:
          severity: info
        annotations:
          summary: "Config update rolled back for {{ $labels.team }}"
```

---

## Migration Guide

### From Blue-Green Containers to Symlink Mode

**Step 1: Backup Current State**
```bash
# Backup current configs
for team in devops developer qa; do
  docker cp jenkins-${team}-blue:/var/jenkins_home/casc_configs/jenkins.yaml \
    /tmp/${team}-config-backup.yaml
done
```

**Step 2: Update Inventory**
```yaml
# ansible/group_vars/all/jenkins.yml
jenkins_config_update_mode: "symlink"
```

**Step 3: Deploy Symlink Infrastructure**
```bash
ansible-playbook ansible/site.yml --tags config-symlinks
```

**Step 4: Migrate Containers**
```bash
# Stop old blue-green containers
for team in devops developer qa; do
  docker stop jenkins-${team}-blue jenkins-${team}-green
  docker rm jenkins-${team}-blue jenkins-${team}-green
done

# Deploy new single-container setup
ansible-playbook ansible/site.yml --tags container \
  -e jenkins_config_update_mode=symlink
```

**Step 5: Verify**
```bash
# Check containers running
docker ps | grep jenkins

# Verify configs
for team in devops developer qa; do
  echo "Team: $team"
  readlink /var/jenkins/${team}/configs/active
  docker exec jenkins-${team} ls -l /var/jenkins_home/casc_configs/
done
```

---

## Comparison with Other Approaches

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Symlink + Hot-Reload** | Zero downtime, simple, fast, low resources | Requires JCasC plugin, hot-reload may fail | **Production (recommended)** |
| **Blue-Green Containers** | Full isolation, can test VM changes | Complex, 2x resources, slower switch | Testing infrastructure changes |
| **Container Restart** | Simple, no JCasC required | 30-60s downtime, user impact | Development only |
| **Manual Updates** | Full control | Error-prone, no validation, no audit trail | Never (avoid) |

---

## Best Practices

### 1. Always Use Dry-Run
```bash
# Never skip dry-run in production
SKIP_DRY_RUN: false
```

### 2. Version Control Everything
```bash
git add jenkins-configs/
git commit -m "Update devops config: add Docker plugin"
git push
```

### 3. Small, Incremental Changes
```yaml
# ✅ GOOD: One change at a time
# Add one plugin, test, commit

# ❌ BAD: Multiple unrelated changes
# Add 5 plugins, change security, modify jobs
```

### 4. Test in Non-Prod First
```bash
# 1. Test in dev environment
ansible-playbook -i inventories/dev/hosts.yml site.yml

# 2. Verify changes work
# Run smoke tests

# 3. Deploy to production
ansible-playbook -i inventories/production/hosts.yml site.yml
```

### 5. Monitor After Updates
```bash
# Check metrics after update
curl http://prometheus:9090/api/v1/query?query=jenkins_health

# Check logs for errors
docker logs jenkins-devops | grep -i error
```

---

## FAQ

### Q: Can I switch back and forth between blue and green?
**A**: Yes! You can switch multiple times:
```bash
active -> blue  (initial)
active -> green (update 1)
active -> blue  (update 2, using blue as standby)
active -> green (update 3, using green as standby)
```

### Q: What happens if Jenkins is restarted during update?
**A**: Jenkins will read from wherever `active` symlink points. If update was in progress:
- If symlink switched but reload failed: Manual reload needed
- If symlink not yet switched: Old config still active
- Always safe due to read-only mount

### Q: Can multiple teams update simultaneously?
**A**: Yes! Each team has its own lock:
```bash
/var/jenkins/devops/update.lock    # Devops updating
/var/jenkins/developer/update.lock # Developer updating (independent)
```

### Q: How fast is the switch?
**A**:
- Symlink switch: <0.1 seconds
- Hot reload: 1-5 seconds (depending on config size)
- Total: <10 seconds typically

### Q: What if a plugin is missing?
**A**: Validation catches this:
```bash
Stage: Plugin Dependencies Check
✗ Required plugin not installed: docker-plugin
```
Install plugin first, then retry update.

### Q: Can I rollback to any previous version?
**A**: Yes, from backups:
```bash
# List available backups
ls /var/jenkins/devops/backups/

# Restore specific backup
cp /var/jenkins/devops/backups/jenkins.yaml.20251208_101530 \
   /var/jenkins/devops/configs/blue/jenkins.yaml

# Switch and reload
ln -sfn blue /var/jenkins/devops/configs/active
curl -X POST http://localhost:8080/configuration-as-code/reload
```

---

## References

- Jenkins Configuration as Code: https://github.com/jenkinsci/configuration-as-code-plugin
- JCasC Reload API: https://github.com/jenkinsci/configuration-as-code-plugin/blob/master/docs/features/configExport.md
- Ansible File Module: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html
- Container Best Practices: https://docs.docker.com/develop/dev-best-practices/

---

**Document Status**: Production Ready
**Last Updated**: December 2025
**Owner**: DevOps Team
**Review Cycle**: Quarterly
