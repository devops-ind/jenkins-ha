# JCasC Hot-Reload Implementation Guide

## Overview

This guide explains how to use the JCasC hot-reload playbook for zero-downtime Jenkins configuration updates. Configuration changes are deployed to container volumes, and Jenkins reloads them via the JCasC API without requiring container restarts.

## Architecture

### File-Based Configuration

```
/var/jenkins/{team}/
├── configs/
│   ├── blue.yaml          # Blue environment config
│   ├── green.yaml         # Green environment config
│   └── current.yaml       # Active config (symlink or copy)
├── backups/               # Config backups (keep last 10)
│   ├── current.yaml.20250109_101500
│   ├── current.yaml.20250109_093000
│   └── ...
└── config-state.json      # State tracking file
```

### Deployment Flow

```
1. Existing config in current.yaml (mounted in Jenkins container)
2. new-config.yaml prepared
3. config-file-switch.sh:
   - Backup: current.yaml → backups/current.yaml.{timestamp}
   - Copy: new-config.yaml → current.yaml
   - Update: config-state.json
4. Ansible playbook triggers reload:
   - POST /configuration-as-code/reload (no container restart)
5. Jenkins reloads config from current.yaml
6. Health check validates success
7. Automatic rollback if health check fails
```

## Prerequisites

1. **Jenkins deployed with file-based config mode**
   ```yaml
   jenkins_config_update_mode: "file"
   ```

2. **Blue and green configs prepared**
   - `/var/jenkins/{team}/configs/blue.yaml`
   - `/var/jenkins/{team}/configs/green.yaml`

3. **Existing scripts in place**
   - `/home/jenkins/scripts/config-file-switch.sh`
   - Can call hot-reload API with credentials

4. **Jenkins credentials**
   - Admin user token stored in Vault
   - Accessible via: `{{ jenkins_admin_token }}`

## Usage

### Command Line: All Teams

```bash
# Dry-run (no changes)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/jcasc-hot-reload.yml \
  -e "jcasc_teams_input=all" \
  -e "jcasc_environments_input=both" \
  --check

# Execute update
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/jcasc-hot-reload.yml \
  -e "jcasc_teams_input=all" \
  -e "jcasc_environments_input=both"
```

### Command Line: Specific Teams

```bash
# Single team
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/jcasc-hot-reload.yml \
  -e "jcasc_teams_input=devops"

# Multiple teams
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/jcasc-hot-reload.yml \
  -e "jcasc_teams_input=devops,ma,ba"
```

### Jenkins UI

Access via: **Infrastructure → JCasC-Hot-Reload**

**Parameters:**
- **TEAMS**: all | devops | ma | ba | tw
- **ENVIRONMENTS**: both | blue | green
- **DRY_RUN**: true (preview) | false (execute)

**Example workflow:**
1. Click "Build with Parameters"
2. Select Teams: `all`
3. Select Environments: `both`
4. Set DRY_RUN: `false`
5. Click "Build"
6. Check console output for status
7. Monitor Jenkins audit log for details

## Playbook Behavior

### Pre-flight Checks
- Verifies Jenkins connectivity
- Validates team names exist in configuration
- Checks config files are accessible

### Per-Team Update
For each team:
1. Read current config state
2. Validate blue and green configs exist
3. Call `config-file-switch.sh` to switch config
4. Trigger JCasC reload API
5. Verify Jenkins health (retry 5 times, 5 second delay)
6. Update audit log
7. On failure: Restore from backup + reload + log rollback

### Post-Update
- Final Jenkins health check
- Display completion summary

## Rollback

### Automatic Rollback

Triggered automatically on:
- Config switch failure
- JCasC reload API failure
- Jenkins health check failure (3 consecutive failures)

**Process:**
1. Restore latest backup: `backups/current.yaml.{latest}` → `current.yaml`
2. Trigger JCasC reload with restored config
3. Log rollback action to audit log
4. Playbook fails with error message

### Manual Rollback

```bash
# List available backups
ls -lt /var/jenkins/devops/backups/

# Restore specific backup
cp /var/jenkins/devops/backups/current.yaml.20250109_093000 \
   /var/jenkins/devops/configs/current.yaml

# Trigger reload
curl -X POST -u admin:${JENKINS_TOKEN} \
  http://localhost:8080/configuration-as-code/reload
```

## State Tracking

### State File: `/var/jenkins/{team}/config-state.json`

```json
{
  "active_config": "blue",
  "previous_config": "green",
  "last_update": "2025-01-09T10:15:00Z"
}
```

**Values:**
- `active_config`: Currently loaded configuration (blue|green)
- `previous_config`: Previous configuration (for rollback reference)
- `last_update`: ISO8601 timestamp of last update

### Audit Log: `/var/log/jenkins/jcasc-updates.log`

```
[2025-01-09T10:15:00Z] [devops] [UPDATE] Status: SUCCESS | Operator: ansible-admin | Switch target: green
[2025-01-09T10:00:00Z] [devops] [ROLLBACK] Status: FAILED | Reason: Reload validation failed | Operator: ansible-admin
```

**Log entries:**
- Timestamp (ISO8601)
- Team name
- Action (UPDATE|ROLLBACK)
- Status (SUCCESS|FAILED)
- Operator (user who triggered)
- Additional context

## Variables

Variables are read from `ansible/group_vars/all/jenkins.yml`:

```yaml
# Jenkins connection
jenkins_url: "http://localhost:8080"
jenkins_admin_user: "admin"
jenkins_admin_token: "{{vault_jenkins_admin_token}}"  # From Vault

# Configuration paths
jenkins_base_path: "/var/jenkins"

# Reload settings
jenkins_reload_timeout: 60                     # API call timeout
jenkins_reload_health_retries: 5               # Health check attempts
jenkins_reload_health_delay: 5                 # Delay between attempts
jenkins_audit_log: "/var/log/jenkins/jcasc-updates.log"

# Teams list
jenkins_teams: [...]                           # From jenkins.yml
```

**Override variables per environment:**

```bash
# In ansible/inventories/production/group_vars/jenkins_masters.yml
jenkins_reload_timeout: 120  # Longer timeout for production
jenkins_reload_health_retries: 10
```

## Troubleshooting

### Playbook Fails with "Team not found"

**Cause:** Team name doesn't match `jenkins_teams` configuration

**Fix:**
```bash
# List available teams
ansible-inventory -i ansible/inventories/production/hosts.yml --list | jq '.all.vars.jenkins_teams'

# Use correct team name
ansible-playbook ... -e "jcasc_teams_input=correct_team_name"
```

### "Jenkins health check failed"

**Cause:** Jenkins is not responding to API calls after reload

**Debug:**
```bash
# Check Jenkins is running
docker ps | grep jenkins

# Test API connectivity
curl -u admin:${TOKEN} http://localhost:8080/api/json

# Check Jenkins logs
docker logs jenkins-devops

# Check config was actually switched
cat /var/jenkins/devops/configs/current.yaml | head -10
```

**Fix:**
- Wait for Jenkins to fully start (can take 30+ seconds)
- Check config file syntax
- Verify all required plugins are installed
- Manual rollback if health check fails

### "Config switch script failed"

**Cause:** Permission issues or script missing

**Debug:**
```bash
# Verify script exists
ls -la /home/jenkins/scripts/config-file-switch.sh

# Check directory permissions
ls -la /var/jenkins/devops/configs/

# Check backup directory
ls -la /var/jenkins/devops/backups/
```

**Fix:**
- Ensure Jenkins user owns `/var/jenkins/{team}/`
- Ensure configs are readable
- Ensure backup directory is writable

### "Connection refused" on hot-reload API

**Cause:** Jenkins not accepting connections on port 8080

**Debug:**
```bash
# Check port is listening
netstat -tlnp | grep 8080

# Test connectivity
telnet localhost 8080

# Check firewall
sudo iptables -L -n | grep 8080
```

**Fix:**
- Wait for Jenkins to fully start
- Check firewall rules
- Verify Jenkins URL in variables

## Best Practices

### Pre-Update Checklist

1. **Test Configuration Locally**
   ```bash
   docker run --rm \
     -v /var/jenkins/devops/configs/green.yaml:/var/jenkins_home/casc_configs/jenkins.yaml:ro \
     jenkins:latest
   ```

2. **Backup Current Config**
   ```bash
   cp /var/jenkins/devops/configs/current.yaml \
      /var/jenkins/devops/configs/current.yaml.pre-update.$(date +%s)
   ```

3. **Use Dry-Run First**
   ```bash
   ansible-playbook ... --check -e "jcasc_teams_input=devops"
   ```

### Monitoring During Update

1. Watch Jenkins audit log:
   ```bash
   tail -f /var/log/jenkins/jcasc-updates.log
   ```

2. Monitor Jenkins health:
   ```bash
   watch -n 1 'curl -s http://localhost:8080/api/json | jq .version'
   ```

3. Check container status:
   ```bash
   docker ps | grep jenkins
   ```

### Scheduled Updates

Use Jenkins cron to schedule updates:
```groovy
triggers {
    cron('0 2 * * 0')  // Sunday at 2 AM
}
```

## Integration with CI/CD

### GitHub Webhook

Trigger update on config repo push:

```groovy
pipeline {
    triggers {
        githubPush()  // Requires GitHub plugin
    }
    stages {
        stage('Update JCasC') {
            steps {
                // Call jcasc-hot-reload job
            }
        }
    }
}
```

### Configuration Repository

Store configs in Git:
```bash
git clone https://github.com/org/jenkins-config.git
cp jenkins-config/teams/devops.yaml \
   /var/jenkins/devops/configs/green.yaml
# Run playbook to activate
```

## Limitations

1. **Single Team per Execution** - Playbook loops through teams sequentially
2. **No Dynamic Config Generation** - Configs must be pre-prepared (use Ansible templates elsewhere)
3. **Manual Config Editing** - JCasC only, Jenkins UI changes not persisted
4. **No A/B Testing** - Can't maintain different config versions simultaneously

## Support

### Common Commands

```bash
# Check deployment status
ansible-inventory -i ansible/inventories/production/hosts.yml --list

# Validate playbook syntax
ansible-playbook --syntax-check ansible/playbooks/jcasc-hot-reload.yml

# Dry-run with verbose output
ansible-playbook -vvv --check ansible/playbooks/jcasc-hot-reload.yml

# View audit trail
cat /var/log/jenkins/jcasc-updates.log

# Check config state
cat /var/jenkins/devops/config-state.json | jq .
```

### Debugging

```bash
# Enable Ansible debug
export ANSIBLE_DEBUG=1
ansible-playbook -vvv ...

# Check variable values
ansible all -m debug -a "var=jenkins_reload_timeout"

# Test individual tasks
ansible-playbook -vv --step ...
```

## See Also

- CLAUDE.md - Quick reference for deployment commands
- docs/ARCHITECTURE.md - System architecture overview
- docs/BLUE-GREEN-DEPLOYMENT.md - Blue-green deployment details
- examples/jcasc-configuration-examples.md - JCasC config examples
