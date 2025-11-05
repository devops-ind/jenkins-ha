# Blue-Green Monitoring Strategy: Both Environments with Passive Alert Suppression

## Overview

This guide explains how to monitor BOTH active and passive blue-green Jenkins environments while suppressing alerts from the passive environment. This approach provides complete visibility while preventing false alerts.

## Architecture Decision

### Previous Approach (Active-Only Monitoring)
- ❌ Only monitor active environment
- ❌ Passive environment completely unmonitored
- ❌ Blind deployment to passive
- ❌ Risky switches without pre-validation

### New Approach (Both with Passive Alert Suppression)
- ✅ Monitor both active and passive environments
- ✅ Alert only on active environment issues
- ✅ Suppress alerts from passive environment
- ✅ Pre-validate passive before switching
- ✅ Complete infrastructure visibility

## Implementation

### Step 1: Revert Target Generation Cleanup

**File**: `ansible/roles/monitoring/tasks/phase3-targets/generate-file-sd.yml`

**Remove** the stale target cleanup that was added in commit 4ba6576:

```yaml
# REMOVE THIS SECTION (lines 26-63):
- name: Backup and clean stale Jenkins target files before regeneration
  shell: |
    # This was cleaning up targets for inactive environments
    rm -f {{ monitoring_home_dir }}/prometheus/targets.d/jenkins-*.json
```

This will allow Prometheus to discover targets for both environments.

### Step 2: Generate Targets for BOTH Environments

**File**: `ansible/roles/monitoring/tasks/phase3-targets/generate-file-sd.yml`

**Modify** the target generation to include both blue AND green:

```yaml
- name: Generate Jenkins targets for both blue and green environments
  copy:
    content: |
      [
      {% for host in monitoring_jenkins_hosts %}
      {% for env in ['blue', 'green'] %}
      {% set port = team_web_port if env == 'blue' else (team_web_port | int + 100) %}
        {
          "targets": ["{% if monitoring_use_fqdn and hostvars[host]['host_fqdn'] is defined %}{{ hostvars[host]['host_fqdn'] }}{% else %}{{ hostvars[host]['ansible_default_ipv4']['address'] }}{% endif %}:{{ port }}"],
          "labels": {
            "job": "jenkins-{{ team.team_name }}",
            "team": "{{ team.team_name }}",
            "environment": "{{ env }}",
            "active_environment": "{{ team.active_environment | default('blue') }}",
            "is_active": "{{ 'true' if env == team.active_environment else 'false' }}",
            "deployment_mode": "{{ deployment_mode | default('local') }}",
            "blue_green_enabled": "{{ team.blue_green_enabled | default(false) }}"
          }
        }{% if not loop.last or not outer_loop.last %},{% endif %}
      {% endfor %}
      {% endfor %}
      ]
    dest: "{{ monitoring_home_dir }}/prometheus/targets.d/jenkins-{{ team.team_name }}.json"
  loop: "{{ prometheus_teams_validated }}"
  loop_control:
    loop_var: team
    extended: yes
```

**Key changes**:
- Added `{% for env in ['blue', 'green'] %}` loop
- Calculate port for each environment
- Added `active_environment` label (team's configured active env)
- Added `is_active` label (true/false based on match)

### Step 3: Update Alert Rules with Active Environment Filtering

**File**: `monitoring/prometheus/rules/jenkins.yml`

**Replace** the JenkinsMasterDown alert with this version:

```yaml
- alert: JenkinsMasterDown
  # Only alert when DOWN environment is the ACTIVE environment for the team
  expr: |
    up{job=~"jenkins-.*|jenkins|jenkins-default"} == 0
    AND ON(team, environment)
    label_replace(
      jenkins_team_active_environment_info{},
      "environment", "$1", "active_environment", "(.*)"
    ) > 0
  for: 2m
  labels:
    severity: critical
    service: jenkins
    component: master
    team: "{{ $labels.team }}"
    environment: "{{ $labels.environment }}"
    alert_type: "active_environment"
  annotations:
    summary: "Jenkins Master {{ $labels.instance }} ({{ $labels.team }}-{{ $labels.environment }}) is down"
    description: |
      Jenkins Master {{ $labels.instance }} for team {{ $labels.team }} is down.
      This is the ACTIVE {{ $labels.environment }} environment serving production traffic.

      Passive environment: Monitored but alerts suppressed
      Impact: Production traffic affected

      Troubleshooting:
      1. Check container status: docker ps | grep jenkins-{{ $labels.team }}-{{ $labels.environment }}
      2. View logs: docker logs jenkins-{{ $labels.team }}-{{ $labels.environment }}
      3. Check HAProxy routing: curl http://haproxy:8404/stats
    runbook_url: "https://wiki.company.com/jenkins-ha/runbooks/master-down"
```

**Alternative simpler approach** if you have the `is_active` label:

```yaml
- alert: JenkinsMasterDown
  expr: |
    up{job=~"jenkins-.*|jenkins|jenkins-default", is_active="true"} == 0
  for: 2m
  labels:
    severity: critical
    service: jenkins
    component: master
    team: "{{ $labels.team }}"
    environment: "{{ $labels.environment }}"
  annotations:
    summary: "Active Jenkins Master {{ $labels.instance }} is down"
    description: "Active {{ $labels.environment }} environment for team {{ $labels.team }} is down. Passive environment alerts are suppressed."
```

### Step 4: Add Informational Alert for Passive Environment

**File**: `monitoring/prometheus/rules/jenkins.yml`

Add a **non-critical informational alert** for passive environment issues:

```yaml
- alert: JenkinsPassiveEnvironmentDown
  expr: |
    up{job=~"jenkins-.*|jenkins|jenkins-default", is_active="false"} == 0
  for: 10m  # Longer delay - not urgent
  labels:
    severity: info  # Informational only
    service: jenkins
    component: master
    team: "{{ $labels.team }}"
    environment: "{{ $labels.environment }}"
    alert_type: "passive_environment"
  annotations:
    summary: "Passive Jenkins environment {{ $labels.environment }} is down (team: {{ $labels.team }})"
    description: |
      The passive {{ $labels.environment }} environment for team {{ $labels.team }} is down.

      This is NOT serving production traffic - no immediate action required.

      Impact: None (passive environment)
      Recommended Action: Fix before next blue-green switch

      Before switching to this environment:
      1. Verify it's running: docker ps | grep jenkins-{{ $labels.team }}-{{ $labels.environment }}
      2. Start if needed: docker start jenkins-{{ $labels.team }}-{{ $labels.environment }}
      3. Wait for health checks to pass
    runbook_url: "https://wiki.company.com/jenkins-ha/runbooks/passive-environment-down"
```

### Step 5: Update Grafana Dashboards to Show Both Environments

**File**: `ansible/roles/monitoring/templates/dashboards/jenkins-overview.json.j2`

Update panels to show both environments with visual distinction:

```json
{
  "title": "Jenkins Status - All Environments",
  "type": "stat",
  "targets": [
    {
      "expr": "up{job=~\"jenkins.*\", team=\"{{ dashboard_team }}\"}"
    }
  ],
  "fieldConfig": {
    "overrides": [
      {
        "matcher": { "id": "byName", "options": "environment" },
        "properties": [
          {
            "id": "mappings",
            "value": [
              {
                "options": {
                  "pattern": "{{ team_environment }}",
                  "result": {
                    "color": "green",
                    "text": "🟢 {{ team_environment | upper }} (ACTIVE)"
                  }
                }
              },
              {
                "options": {
                  "pattern": "*",
                  "result": {
                    "color": "yellow",
                    "text": "🟡 PASSIVE"
                  }
                }
              }
            ]
          }
        ]
      }
    ]
  }
}
```

### Step 6: Alertmanager Routing (Optional)

**File**: `ansible/roles/monitoring/templates/alertmanager.yml.j2`

Route passive environment alerts to a separate channel:

```yaml
route:
  receiver: 'default-receiver'
  group_by: ['alertname', 'team', 'environment']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    # Active environment critical alerts - send immediately
    - match:
        alert_type: active_environment
        severity: critical
      receiver: 'teams-critical'
      group_wait: 10s

    # Passive environment info alerts - batched, low priority
    - match:
        alert_type: passive_environment
        severity: info
      receiver: 'teams-info'
      group_wait: 1h
      repeat_interval: 24h

receivers:
  - name: 'teams-critical'
    msteams_configs:
      - webhook_url: '{{ vault_teams_webhook_critical }}'
        title: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'

  - name: 'teams-info'
    msteams_configs:
      - webhook_url: '{{ vault_teams_webhook_info }}'
        title: 'ℹ️ INFO: {{ .GroupLabels.alertname }}'
```

## Usage Examples

### Pre-Switch Validation

Before switching from blue to green:

```bash
# Check passive (green) environment health
curl -s http://monitoring-vm:9090/api/v1/query?query='up{job="jenkins-devops",environment="green"}' | jq '.data.result[0].value[1]'
# Expected: "1" (up)

# Check for any alerts on green (should be info only)
curl -s http://monitoring-vm:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.team=="devops" and .labels.environment=="green")'

# If green is healthy, safe to switch
./scripts/blue-green-switch.sh devops green
```

### Monitoring Both Environments

```promql
# See status of both environments
up{job="jenkins-devops"}

# Active environment only
up{job="jenkins-devops", is_active="true"}

# Passive environment only
up{job="jenkins-devops", is_active="false"}

# Build rate comparison (active vs passive)
rate(jenkins_builds_total[5m]) by (environment)
```

### Grafana Queries

```logql
# Show active environment in green, passive in yellow
up{job="jenkins-devops"} * on(environment) group_left(is_active) jenkins_is_active_info
```

## Validation Steps

### 1. Verify Both Environments Monitored

```bash
# Check Prometheus targets
curl -s http://monitoring-vm:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job | startswith("jenkins")) | {team: .labels.team, environment: .labels.environment, is_active: .labels.is_active, health: .health}'

# Expected output (for devops team with active=green):
# {team: "devops", environment: "blue", is_active: "false", health: "up"}
# {team: "devops", environment: "green", is_active: "true", health: "up"}
```

### 2. Test Alert Suppression

```bash
# Stop passive (blue) environment
docker stop jenkins-devops-blue

# Wait 10+ minutes, check alerts
curl -s http://monitoring-vm:9090/api/v1/alerts | \
  jq '.data.alerts[] | select(.labels.team=="devops")'

# Expected:
# - JenkinsPassiveEnvironmentDown (severity: info)
# - NO JenkinsMasterDown critical alert

# Stop active (green) environment
docker stop jenkins-devops-green

# Wait 2+ minutes, check alerts
# Expected:
# - JenkinsMasterDown (severity: critical) ← THIS should fire
```

### 3. Verify Grafana Visibility

```bash
# Access Grafana
http://monitoring-vm:9300/d/jenkins-overview-devops

# Verify you see:
# - Status for both blue and green
# - Active environment highlighted (green badge)
# - Passive environment marked (yellow badge)
# - Metrics for both environments visible
```

## Migration Plan

### Phase 1: Enable Monitoring for Both (No Alert Changes)

```bash
# Revert the target cleanup from commit 4ba6576
git revert 4ba6576d07f55b3a98a40d9a93dfaedb0277708e --no-commit

# Deploy changes
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,targets

# Verify both environments visible in Prometheus
```

### Phase 2: Update Alert Rules

```bash
# Update jenkins.yml with new alert rules
# Deploy rules
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,prometheus

# Verify alert rules loaded
curl http://monitoring-vm:9090/api/v1/rules | jq '.data.groups[] | select(.name=="jenkins.infrastructure")'
```

### Phase 3: Update Dashboards

```bash
# Update dashboard templates with both environment panels
# Deploy dashboards
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,grafana

# Verify dashboards show both environments
```

### Phase 4: Configure Alertmanager (Optional)

```bash
# Update alertmanager routing
# Deploy alertmanager config
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,alertmanager
```

## Benefits Summary

| Aspect | Active-Only | Both with Suppression |
|--------|------------|---------------------|
| **Visibility** | ❌ Passive blind | ✅ Full visibility |
| **Pre-switch validation** | ❌ No | ✅ Yes |
| **Deployment verification** | ❌ Deploy blind | ✅ Immediate feedback |
| **Rollback confidence** | ❌ Unknown state | ✅ Known healthy |
| **Troubleshooting** | ❌ Limited | ✅ Complete |
| **Historical data** | ❌ Gaps on switch | ✅ Continuous |
| **False alerts** | ✅ None | ✅ None (suppressed) |
| **Alert noise** | ✅ Low | ✅ Low (info only) |

## Conclusion

Monitoring both environments with passive alert suppression provides:
- ✅ **Complete visibility** into infrastructure state
- ✅ **Pre-deployment validation** before switching
- ✅ **No false alerts** from passive environments
- ✅ **Better operational confidence** during switches
- ✅ **Faster incident response** with full context

This approach is **strongly recommended** over active-only monitoring for production blue-green deployments.
