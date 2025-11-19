# Single Team Jenkins Master Deployment Guide

## Overview

This infrastructure supports **independent team deployments** - you can deploy, update, or restart a single Jenkins team master without affecting other teams. This document explains how this functionality works and how to use it.

---

## Architecture Components

### 1. **Multi-Team Configuration**

Teams are defined in `ansible/inventories/production/group_vars/all/jenkins_teams.yml`:

```yaml
jenkins_teams:
  - team_name: "devops"
    active_environment: "green"
    ports:
      web: 8080
      agent: 50000

  - team_name: "ma"
    active_environment: "blue"
    ports:
      web: 8081
      agent: 50001

  - team_name: "ba"
    active_environment: "blue"
    ports:
      web: 8082
      agent: 50002
```

**Key Points**:
- Each team has independent ports
- Each team has independent active_environment (blue/green)
- Each team has separate configuration
- Teams are completely isolated

---

### 2. **Team Filtering Mechanism**

The `jenkins-master-v2` role includes built-in team filtering at `/ansible/roles/jenkins-master-v2/tasks/main.yml:22-42`:

```yaml
# Deploy specific teams only
- name: Filter teams for deployment - Deploy specific teams
  set_fact:
    jenkins_teams_filtered: "{{ jenkins_teams_config | selectattr('team_name', 'in', deploy_teams.split(',') | map('trim') | list) | list }}"
  when: deploy_teams is defined and deploy_teams != ""

# Exclude specific teams from deployment
- name: Filter teams for deployment - Exclude specific teams
  set_fact:
    jenkins_teams_filtered: "{{ jenkins_teams_config | rejectattr('team_name', 'in', exclude_teams.split(',') | map('trim') | list) | list }}"
  when:
    - exclude_teams is defined and exclude_teams != ""
    - deploy_teams is not defined or deploy_teams == ""

# Default: Deploy all teams
- name: Filter teams for deployment - Default (all teams)
  set_fact:
    jenkins_teams_filtered: "{{ jenkins_teams_config }}"
  when:
    - deploy_teams is not defined or deploy_teams == ""
    - exclude_teams is not defined or exclude_teams == ""
```

**How It Works**:
1. **deploy_teams parameter**: Whitelist - deploy ONLY specified teams
2. **exclude_teams parameter**: Blacklist - deploy ALL EXCEPT specified teams
3. **No parameters**: Deploy all teams (default)

---

### 3. **Independent Team Resources**

Each team has completely isolated resources:

#### Docker Containers
```
jenkins-devops-blue       # DevOps blue environment
jenkins-devops-green      # DevOps green environment (ACTIVE)
jenkins-ma-blue           # MA blue environment (ACTIVE)
jenkins-ma-green          # MA green environment
jenkins-ba-blue           # BA blue environment (ACTIVE)
jenkins-ba-green          # BA green environment
```

#### Docker Volumes
```
jenkins-devops-blue-home   # DevOps blue data
jenkins-devops-green-home  # DevOps green data
jenkins-ma-blue-home       # MA blue data
jenkins-ma-green-home      # MA green data
```

#### HAProxy Backends
```
backend jenkins_backend_devops   # Routes to devops green (port 8180)
backend jenkins_backend_ma       # Routes to ma blue (port 8081)
backend jenkins_backend_ba       # Routes to ba blue (port 8082)
```

#### Monitoring Targets
```
jenkins-devops target with is_active="true"
jenkins-ma target with is_active="true"
jenkins-ba target with is_active="true"
```

---

## How to Deploy a Single Team

### Method 1: Using deploy_teams Parameter (Recommended)

Deploy ONLY the DevOps team:

```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "deploy_teams=devops"
```

Deploy multiple specific teams (comma-separated):

```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "deploy_teams=devops,ma"
```

### Method 2: Using exclude_teams Parameter

Deploy all teams EXCEPT DevOps:

```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "exclude_teams=devops"
```

Exclude multiple teams:

```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "exclude_teams=ma,ba,tw"
```

---

## What Gets Updated vs What Stays Unchanged

### ✅ Components Updated (for specified team only)

1. **Jenkins Container**:
   - Only the specified team's active environment container is restarted
   - Example: `jenkins-devops-green` if active_environment is "green"

2. **Docker Volumes**:
   - Team's volume is mounted and accessible
   - Other teams' volumes are untouched

3. **Custom Docker Image** (if configured):
   - Only the specified team's custom image is rebuilt/pulled
   - Other teams' images remain unchanged

4. **Jenkins Configuration**:
   - Team-specific Job DSL seed jobs updated
   - Team-specific plugins updated
   - Team-specific credentials updated

5. **Team-Specific Dashboards**:
   - Grafana dashboards for the specified team regenerated
   - Unique UIDs ensure no conflicts with other teams

### ❌ Components NOT Updated (other teams unaffected)

1. **Other Teams' Containers**:
   - DevOps deployment does NOT touch MA, BA, TW containers
   - Containers keep running without restart

2. **HAProxy Configuration**:
   - HAProxy continues routing to all teams
   - No HAProxy restart required (unless you explicitly update it)
   - Other teams' backends remain active

3. **Shared Resources**:
   - Monitoring stack (Prometheus, Grafana, Loki) - not restarted
   - Docker networks - remain unchanged
   - Storage volumes - other teams' volumes untouched

4. **Other Teams' Dashboards**:
   - Unique UIDs prevent dashboard conflicts
   - Each team's dashboards remain independent

---

## Deployment Flow for Single Team

When you run `deploy_teams=devops`, here's what happens:

```
1. Team Filtering
   ├─ jenkins_teams_config loaded (all 4 teams)
   ├─ jenkins_teams_filtered = ["devops"] (filtered to 1 team)
   └─ Validation: Ensure "devops" exists in config

2. Container Deployment
   ├─ Check current active environment → "green"
   ├─ Deploy jenkins-devops-green container
   ├─ Mount jenkins-devops-green-home volume
   ├─ Skip jenkins-devops-blue (inactive)
   └─ Other teams skipped entirely (ma, ba, tw)

3. Configuration
   ├─ Apply DevOps-specific env vars
   ├─ Configure DevOps Job DSL repos
   ├─ Setup DevOps-specific plugins
   └─ Configure DevOps credentials

4. Health Checks
   ├─ Wait for jenkins-devops-green to be ready
   ├─ Verify port 8180 accessible (green environment port)
   └─ Validate Jenkins API responds

5. HAProxy (Optional)
   ├─ If --tags includes 'haproxy':
   │  ├─ Update HAProxy config for all teams
   │  └─ Restart HAProxy
   └─ If not: HAProxy continues routing unchanged

6. Monitoring (Optional)
   ├─ If --tags includes 'monitoring':
   │  ├─ Regenerate DevOps dashboard
   │  ├─ Update Prometheus target for DevOps
   │  └─ Other teams' monitoring unchanged
   └─ If not: Monitoring continues unchanged
```

---

## Verification After Deployment

### 1. Verify Only Target Team Was Updated

Check Docker containers:

```bash
# Show DevOps containers
docker ps --filter "name=jenkins-devops" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Verify other teams still running
docker ps --filter "name=jenkins-ma" --format "table {{.Names}}\t{{.Status}}"
docker ps --filter "name=jenkins-ba" --format "table {{.Names}}\t{{.Status}}"
```

Expected output:
```
jenkins-devops-green    Up 2 minutes    0.0.0.0:8180->8080/tcp  ← RECENTLY RESTARTED
jenkins-ma-blue         Up 5 days       0.0.0.0:8081->8080/tcp  ← UNCHANGED
jenkins-ba-blue         Up 5 days       0.0.0.0:8082->8080/tcp  ← UNCHANGED
```

### 2. Verify HAProxy Routing

```bash
# Check HAProxy stats
curl -u admin:admin123 http://192.168.1.100:8404/stats

# Or check backend health
echo "show stat" | socat stdio /run/haproxy/admin.sock | grep jenkins_backend
```

Expected: All backends remain UP, only DevOps shows recent restart time.

### 3. Verify Other Teams Accessible

```bash
# DevOps team (should work)
curl -f http://192.168.1.100/devopsjenkins.example.com/login

# MA team (should work - unchanged)
curl -f http://192.168.1.100/majenkins.example.com/login

# BA team (should work - unchanged)
curl -f http://192.168.1.100/bajenkins.example.com/login
```

All should return HTTP 200. If other teams fail, deployment affected more than intended.

### 4. Check Prometheus Targets

```bash
# View Prometheus targets
curl -s http://monitoring-vm:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job | contains("jenkins")) | {team: .labels.team, environment: .labels.environment, health: .health}'
```

Expected: All teams show `"health": "up"`, only DevOps shows recent scrape time.

---

## Common Use Cases

### 1. Update Jenkins Plugin for One Team

```bash
# Update DevOps team Jenkins plugins without affecting others
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins,plugins \
  -e "deploy_teams=devops"
```

**Impact**: Only DevOps Jenkins restarted, MA/BA/TW continue running.

### 2. Switch Blue-Green Environment for One Team

```bash
# 1. Update team config (edit jenkins_teams.yml)
# Change devops active_environment: "green" → "blue"

# 2. Deploy only DevOps team
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins,high-availability \
  -e "deploy_teams=devops"
```

**Impact**:
- DevOps switches from green (8180) to blue (8080)
- HAProxy updated to route devops traffic to blue
- MA, BA, TW remain unchanged

### 3. Test Infrastructure Changes on One Team

```bash
# Deploy experimental changes to TW (test team) only
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "deploy_teams=tw" \
  -e "jenkins_master_image_tag=lts-alpine"  # Test new image
```

**Impact**: Only TW team gets new image, all others stay on existing image.

### 4. Emergency Restart of Single Team

```bash
# Restart only MA team after incident
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "deploy_teams=ma"
```

**Impact**: MA team Jenkins restarted, DevOps/BA/TW unaffected.

---

## Safety Mechanisms

### 1. Validation Before Deployment

```yaml
- name: Validate requested teams exist
  assert:
    that:
      - item in (jenkins_teams_config | map(attribute='team_name') | list)
    fail_msg: "Team '{{ item }}' not found in configuration."
  loop: "{{ deploy_teams.split(',') | map('trim') | list }}"
```

**Protection**: Deployment fails if you specify non-existent team name.

### 2. Zero Teams Protection

```yaml
- name: Check if any teams are selected
  assert:
    that:
      - jenkins_teams_filtered | length > 0
    fail_msg: "ERROR: No teams selected for deployment!"
```

**Protection**: Deployment fails if filtering results in zero teams (prevents accidental no-op).

### 3. Dry Run Option

```bash
# Preview what would be deployed without making changes
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "deploy_teams=devops" \
  --check --diff
```

**Protection**: See exactly what changes before applying them.

---

## Advanced Scenarios

### Scenario 1: Deploy to Multiple Teams But Not All

```bash
# Deploy to DevOps and MA only (skip BA and TW)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "deploy_teams=devops,ma"
```

### Scenario 2: Exclude One Team from Mass Deployment

```bash
# Deploy to all teams EXCEPT production DevOps team
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "exclude_teams=devops"
```

### Scenario 3: Deploy Team with Custom Tags

```bash
# Deploy DevOps team with monitoring updates too
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins,monitoring \
  -e "deploy_teams=devops"
```

**Note**: Monitoring tag will regenerate ALL team dashboards, not just DevOps.

---

## Troubleshooting

### Issue: "Team 'xyz' not found in configuration"

**Cause**: Typo in team name or team doesn't exist.

**Solution**:
```bash
# List available teams
grep "team_name:" ansible/inventories/production/group_vars/all/jenkins_teams.yml
```

### Issue: All teams restarted instead of just one

**Cause**: Forgot to specify `deploy_teams` parameter.

**Verification**:
```bash
# Check Ansible verbose output
ansible-playbook ... -e "deploy_teams=devops" -vv | grep "Filtered teams"
```

Should show:
```
Filtered teams count: 1
Filtered teams: devops
```

### Issue: HAProxy routing broken after team deployment

**Cause**: Deployed team without updating HAProxy configuration.

**Solution**:
```bash
# Redeploy HAProxy to update routing
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags high-availability
```

---

## Performance Considerations

### Single Team Deployment Time

| Component | Time | Notes |
|-----------|------|-------|
| Container stop | ~5s | Graceful shutdown |
| Container start | ~10s | Image already pulled |
| Jenkins startup | ~30s | Plugins already installed |
| Health check wait | ~20s | Until Jenkins API ready |
| **Total** | **~65s** | For one team |

### Full Deployment Time (All Teams)

| Teams | Time | Calculation |
|-------|------|-------------|
| 1 team | ~65s | Base time |
| 4 teams | ~4min | 65s × 4 (parallel possible) |
| 10 teams | ~11min | 65s × 10 (parallel possible) |

**Optimization**: Teams are deployed sequentially by default, but can be parallelized with `strategy: free` if needed.

---

## Best Practices

### 1. Always Specify Team Name Explicitly

```bash
# Good - explicit team specification
-e "deploy_teams=devops"

# Bad - relying on defaults
# (might deploy all teams unintentionally)
```

### 2. Use Dry Run for Production Changes

```bash
# Always check what will change first
ansible-playbook ... --check --diff -e "deploy_teams=devops"
```

### 3. Deploy to Test Team First

```bash
# Test changes on TW team before production teams
-e "deploy_teams=tw"

# If successful, deploy to production
-e "deploy_teams=devops,ma,ba"
```

### 4. Document Team Deployments

```bash
# Add deployment to changelog
echo "$(date) - Deployed Jenkins update to devops team" >> CHANGELOG.md
git add CHANGELOG.md && git commit -m "Deploy: DevOps Jenkins update"
```

### 5. Monitor Other Teams During Deployment

```bash
# In separate terminal, watch container status
watch -n 2 'docker ps --filter "name=jenkins" --format "table {{.Names}}\t{{.Status}}"'

# Expected: Only specified team shows recent restart
```

---

## Summary

### Key Capabilities

✅ **Deploy single team**: Use `deploy_teams=devops`
✅ **Deploy multiple specific teams**: Use `deploy_teams=devops,ma`
✅ **Exclude teams from deployment**: Use `exclude_teams=ba,tw`
✅ **Zero downtime for other teams**: Independent containers
✅ **Independent blue-green switching**: Per-team active_environment
✅ **Safe validation**: Prevents invalid team names
✅ **Flexible tag control**: Combine with --tags for precision

### What Makes This Possible

1. **Per-team configuration**: Each team fully defined in jenkins_teams.yml
2. **Independent containers**: Separate Docker containers per team per environment
3. **Isolated volumes**: Each team has dedicated data volumes
4. **Port separation**: Each team on unique ports (8080, 8081, 8082, etc.)
5. **HAProxy per-team backends**: Each team has independent routing
6. **Team filtering logic**: Built-in Ansible filtering at role level
7. **Validation checks**: Ensures only valid teams are deployed

### Quick Reference

```bash
# Deploy one team
-e "deploy_teams=devops"

# Deploy multiple teams
-e "deploy_teams=devops,ma"

# Exclude teams
-e "exclude_teams=ba,tw"

# With specific tags
--tags jenkins,monitoring -e "deploy_teams=devops"

# Dry run
--check --diff -e "deploy_teams=devops"
```

---

## Related Documentation

- **Blue-Green Deployment**: See `examples/blue-green-deployment-guide.md`
- **Team Configuration**: See `ansible/inventories/production/group_vars/all/jenkins_teams.yml`
- **HAProxy Routing**: See `ansible/roles/high-availability-v2/README.md`
- **Monitoring Per Team**: See `ansible/roles/monitoring/README.md`
- **Troubleshooting**: See `docs/troubleshooting-guide.md`

---

**Last Updated**: 2025-01-09
**Author**: DevOps Team
**Version**: 2.0
