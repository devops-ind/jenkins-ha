# Prometheus Targets Discovery Implementation & Troubleshooting Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture Changes](#architecture-changes)
3. [Problem Statement](#problem-statement)
4. [Solution Implementation](#solution-implementation)
5. [Deployment Guide](#deployment-guide)
6. [Validation Procedures](#validation-procedures)
7. [Troubleshooting](#troubleshooting)
8. [Common Issues & Solutions](#common-issues--solutions)
9. [Rollback Procedures](#rollback-procedures)

---

## Overview

This guide covers the comprehensive Prometheus targets discovery modernization implemented in the Jenkins HA infrastructure. The solution addresses multiple critical issues related to target discovery, host IP resolution, blue-green environment monitoring, and FQDN-based service discovery.

**Branch**: `claude/fix-prometheus-targets-discovery-v2-011CUnvsAdsqPq77u68eMLuu`

### Key Improvements

✅ **File-Based Service Discovery**: Modern file_sd_configs replacing static_configs
✅ **Zero-Downtime Updates**: Dynamic target reload without Prometheus restart
✅ **Both-Environment Monitoring**: Monitor blue AND green with intelligent alert suppression
✅ **Robust Host Resolution**: Multi-level IP fallback mechanism
✅ **FQDN Support**: Dual-mode IP/FQDN target addressing
✅ **Pre-Switch Validation**: Verify passive environment health before switching
✅ **Automatic Cleanup**: Prevent stale target accumulation
✅ **Comprehensive Validation**: Multi-layer target validation framework

---

## Architecture Changes

### Before: Static Configuration

**Problems**:
- Targets hardcoded in prometheus.yml
- Required Prometheus restart for target updates
- Single environment monitoring (active only)
- ansible_default_ipv4 failures without facts gathering
- No FQDN support
- Stale targets from previous deployments

```yaml
# Old approach (prometheus.yml)
scrape_configs:
  - job_name: 'jenkins-team-alpha'
    static_configs:
      - targets: ['192.168.1.10:8080']  # Hardcoded IP
        labels:
          team: 'team-alpha'
          environment: 'blue'
```

### After: File-Based Service Discovery

**Benefits**:
- Dynamic target files in targets.d/ directory
- Zero-downtime updates via HTTP reload
- Both blue and green environment monitoring
- Cascading IP resolution fallback
- Optional FQDN-based addressing
- Automatic stale target cleanup

```yaml
# New approach (prometheus.yml)
scrape_configs:
  - job_name: 'jenkins'
    file_sd_configs:
      - files:
          - targets.d/jenkins-*.json
        refresh_interval: 30s
```

**Generated Target File** (`targets.d/jenkins-team-alpha.json`):
```json
[
  {
    "targets": ["192.168.1.10:8080"],
    "labels": {
      "job": "jenkins-team-alpha",
      "team": "team-alpha",
      "environment": "blue",
      "active_environment": "blue",
      "is_active": "true",
      "deployment_mode": "local",
      "blue_green_enabled": "true"
    }
  },
  {
    "targets": ["192.168.1.10:8180"],
    "labels": {
      "job": "jenkins-team-alpha",
      "team": "team-alpha",
      "environment": "green",
      "active_environment": "blue",
      "is_active": "false",
      "deployment_mode": "local",
      "blue_green_enabled": "true"
    }
  }
]
```

---

## Problem Statement

### Issue 1: ansible_default_ipv4 Undefined Errors

**Error Message**:
```
fatal: [monitoring]: FAILED! =>
  msg: "'dict object' has no attribute 'ansible_default_ipv4'"
```

**Root Cause**:
- Direct usage of `{{ ansible_default_ipv4.address }}` without existence checks
- Fact gathering disabled in some playbooks
- Networking facts unavailable in containerized environments

**Impact**:
- Deployment failures during target generation
- Templates unable to resolve host IPs
- Monitoring setup incomplete

### Issue 2: Missing Prometheus Targets Discovery

**Symptoms**:
```
# Prometheus UI shows
Active Targets: 0
Dropped Targets: 0
```

**Root Causes**:
1. targets.d/ directory not mounted into Prometheus container
2. Verification ran before Prometheus reloaded configuration
3. No retry logic for file_sd discovery timing issues

**Impact**:
- Complete monitoring failure
- No metrics collection
- Dashboard alerts non-functional

### Issue 3: Blue-Green Monitoring Blind Spots

**Problem**: Only active environment monitored

**Operational Issues**:
- ❌ Deploy to passive environment without health verification
- ❌ Blue-green switches without pre-validation (risky)
- ❌ Discover passive environment failures only after switching
- ❌ No metrics history when switching blue ↔ green
- ❌ Poor troubleshooting without passive metrics

### Issue 4: Stale Target Files

**Problem**: Old target files accumulate in targets.d/

**Scenario**:
1. Deploy team-alpha with active=blue
2. Switch to active=green
3. Old jenkins-team-alpha-blue.json remains
4. Prometheus monitors inactive port (DOWN alert)

**Result**: False positive alerts from inactive environments

### Issue 5: FQDN Support Limitations

**Problem**: Only IP-based targets supported

**Limitations**:
- Cannot use DNS-based service discovery
- Manual IP updates when hosts change
- No integration with external DNS systems

---

## Solution Implementation

### 1. Robust Host IP Resolution

**File**: `ansible/roles/jenkins-master-v2/defaults/main.yml`

**Implementation**: Cascading fallback mechanism

```yaml
jenkins_master_host_ip: >-
  {{
    hostvars[inventory_hostname]['ansible_host'] |
    default(
      ansible_default_ipv4.address |
      default(
        ansible_all_ipv4_addresses[0] |
        default(
          host_fqdn |
          default('127.0.0.1')
        )
      )
    )
  }}
```

**Fallback Priority**:
1. `ansible_host` - Explicit inventory configuration (highest priority)
2. `ansible_default_ipv4.address` - Primary network interface IP
3. `ansible_all_ipv4_addresses[0]` - First available IP
4. `host_fqdn` - FQDN-based addressing
5. `127.0.0.1` - Local development fallback

**Usage in Templates**:
```yaml
# generate-file-sd.yml (line 40)
"targets": ["{% if monitoring_use_fqdn and hostvars[host]['host_fqdn'] is defined %}{{ hostvars[host]['host_fqdn'] }}{% else %}{{ hostvars[host]['ansible_default_ipv4']['address'] }}{% endif %}:{{ env_port }}"]
```

### 2. File-Based Service Discovery

**Files Modified**:
- `ansible/roles/monitoring/tasks/phase3-targets/generate-file-sd.yml`
- `ansible/roles/monitoring/tasks/phase3-targets/validate-targets.yml`
- `ansible/roles/monitoring/templates/prometheus.yml.j2`

**Key Changes**:

#### A. Directory Structure
```bash
/opt/monitoring/prometheus/
├── prometheus.yml
├── rules/
│   └── jenkins.yml
└── targets.d/                    # NEW: File-SD directory
    ├── jenkins-team-alpha.json
    ├── jenkins-team-beta.json
    ├── node-exporter.json
    ├── cadvisor.json
    ├── loki.json
    ├── promtail.json
    ├── grafana.json
    └── .backups/                 # NEW: Automatic backup rotation
        ├── jenkins-team-alpha.json-20251117_143022
        └── jenkins-team-beta.json-20251117_143022
```

#### B. Prometheus Configuration
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'jenkins'
    file_sd_configs:
      - files:
          - targets.d/jenkins-*.json
        refresh_interval: 30s
    metrics_path: /prometheus
    scrape_interval: 30s
    scrape_timeout: 10s
    honor_labels: true
```

#### C. Container Volume Mount
```yaml
# ansible/roles/monitoring/tasks/phase3-servers/prometheus.yml
volumes:
  - /opt/monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
  - /opt/monitoring/prometheus/rules:/etc/prometheus/rules:ro
  - /opt/monitoring/prometheus/targets.d:/etc/prometheus/targets.d:ro  # NEW
```

### 3. Both-Environment Monitoring

**File**: `ansible/roles/monitoring/tasks/phase3-targets/generate-file-sd.yml`

**Strategy**: Monitor BOTH blue and green, suppress passive alerts

**Target Generation** (lines 32-71):
```yaml
- name: Generate Jenkins team targets for BOTH blue and green environments
  copy:
    content: |
      [
      {% for host in monitoring_jenkins_hosts %}
      {% for env in ['blue', 'green'] %}
      {% set env_port = team_web_port if env == 'blue' else (team_web_port | int + 100) %}
        {
          "targets": ["{{ host_ip }}:{{ env_port }}"],
          "labels": {
            "job": "jenkins-{{ team.team_name }}",
            "team": "{{ team.team_name }}",
            "environment": "{{ env }}",
            "active_environment": "{{ team_active_env }}",
            "is_active": "{{ 'true' if env == team_active_env else 'false' }}",
            "deployment_mode": "{{ deployment_mode | default('local') }}",
            "blue_green_enabled": "{{ team_bg_enabled }}"
          }
        }{% if not (loop.last and loop.index0 == 1) %},{% endif %}
      {% endfor %}
      {% endfor %}
      ]
    dest: "{{ monitoring_home_dir }}/prometheus/targets.d/jenkins-{{ team.team_name }}.json"
```

**Key Labels**:
- `environment`: "blue" or "green" (current target)
- `active_environment`: Team's configured active environment
- `is_active`: "true" for active, "false" for passive
- `blue_green_enabled`: Whether blue-green is enabled for team

### 4. Intelligent Alert Suppression

**File**: `monitoring/prometheus/rules/jenkins.yml`

**Active Environment Alerts** (lines 98-110):
```yaml
- alert: JenkinsMasterDown
  expr: up{job=~"jenkins-.*", is_active="true"} == 0
  for: 2m
  labels:
    severity: critical
    alert_type: "active_environment"
    team: "{{ $labels.team }}"
    environment: "{{ $labels.environment }}"
  annotations:
    summary: "Jenkins {{ $labels.team }} {{ $labels.environment }} (ACTIVE) is DOWN"
    description: "Critical: Active Jenkins master is unreachable"
```

**Passive Environment Alerts** (informational):
```yaml
- alert: JenkinsPassiveEnvironmentDown
  expr: up{job=~"jenkins-.*", is_active="false"} == 0
  for: 5m
  labels:
    severity: info
    alert_type: "passive_environment"
  annotations:
    summary: "Jenkins {{ $labels.team }} {{ $labels.environment }} (PASSIVE) is DOWN"
    description: "Info: Passive environment is down (expected if resource-optimized deployment)"
```

**Alert Routing Strategy**:
- **Critical**: Active environment down → Page ops team
- **Warning**: Active environment degraded → Notify ops team
- **Info**: Passive environment down → Log only (no notification)

### 5. Comprehensive Validation

**File**: `ansible/roles/monitoring/tasks/phase3-targets/generate-file-sd.yml`

**Multi-Layer Validation** (lines 271-357):

#### A. Port Validation
```bash
# Verify BOTH blue and green ports exist
if ! grep -q ":{{ blue_port }}" "$TARGET_FILE"; then
  VALIDATION_ERRORS="${VALIDATION_ERRORS}\n❌ Missing blue environment port"
fi
if ! grep -q ":{{ green_port }}" "$TARGET_FILE"; then
  VALIDATION_ERRORS="${VALIDATION_ERRORS}\n❌ Missing green environment port"
fi
```

#### B. Environment Label Validation
```bash
# Verify environment labels present
if ! grep -q "\"environment\": \"blue\"" "$TARGET_FILE"; then
  VALIDATION_ERRORS="${VALIDATION_ERRORS}\n❌ Missing blue environment label"
fi
if ! grep -q "\"environment\": \"green\"" "$TARGET_FILE"; then
  VALIDATION_ERRORS="${VALIDATION_ERRORS}\n❌ Missing green environment label"
fi
```

#### C. Active Environment Validation
```bash
# Verify active_environment label matches configuration
if ! grep -q "\"active_environment\": \"{{ team_active_env }}\"" "$TARGET_FILE"; then
  VALIDATION_ERRORS="${VALIDATION_ERRORS}\n❌ active_environment label mismatch"
fi
```

#### D. is_active Label Validation
```bash
# Verify exactly ONE active, ONE passive
ACTIVE_COUNT=$(grep -c "\"is_active\": \"true\"" "$TARGET_FILE" || true)
PASSIVE_COUNT=$(grep -c "\"is_active\": \"false\"" "$TARGET_FILE" || true)

if [ "$ACTIVE_COUNT" -ne 1 ] || [ "$PASSIVE_COUNT" -ne 1 ]; then
  VALIDATION_ERRORS="${VALIDATION_ERRORS}\n❌ Expected 1 active and 1 passive target"
fi
```

### 6. FQDN Migration Support

**File**: `ansible/roles/monitoring/tasks/phase5-fqdn-migration/prometheus-fqdn-targets.yml`

**FQDN-Based Targets**:
```json
{
  "targets": ["jenkins-team-alpha-blue.example.com:8080"],
  "labels": {
    "job": "jenkins-team-alpha",
    "team": "team-alpha",
    "environment": "blue"
  }
}
```

**Enable FQDN Mode**:
```yaml
# ansible/inventories/production/group_vars/all/main.yml
monitoring_use_fqdn: true
monitoring_domain: "example.com"
```

**Conditional Logic**:
```yaml
# generate-file-sd.yml
"targets": [
  "{% if monitoring_use_fqdn and hostvars[host]['host_fqdn'] is defined %}
    {{ hostvars[host]['host_fqdn'] }}
   {% else %}
    {{ hostvars[host]['ansible_default_ipv4']['address'] }}
   {% endif %}:{{ env_port }}"
]
```

### 7. Automatic Backup and Cleanup

**File**: `ansible/roles/monitoring/tasks/phase3-targets/generate-file-sd.yml`

**Backup Rotation** (lines 245-269):
```bash
# Backup existing targets before generation
if [ -f "{{ monitoring_home_dir }}/prometheus/targets.d/jenkins-*.json" ]; then
  BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
  for file in {{ monitoring_home_dir }}/prometheus/targets.d/jenkins-*.json; do
    if [ -f "$file" ]; then
      cp "$file" "{{ monitoring_home_dir }}/prometheus/targets.d/.backups/$(basename $file)-${BACKUP_DATE}"
    fi
  done

  # Keep only last N versions
  find "{{ monitoring_home_dir }}/prometheus/targets.d/.backups" -type f -name "*.json-*" | \
    sort -r | tail -n +{{ prometheus_targets_backup_versions | default(10) + 1 }} | xargs -r rm
fi
```

**Configuration**:
```yaml
# ansible/roles/monitoring/defaults/main.yml
prometheus_targets_backup_versions: 10  # Keep last 10 versions
```

---

## Deployment Guide

### Prerequisites

1. **Ansible Version**: ≥ 2.9
2. **Python**: ≥ 3.6
3. **Access**: SSH access to monitoring and Jenkins hosts
4. **Inventory**: Properly configured hosts.yml

### Step 1: Verify Inventory Configuration

**File**: `ansible/inventories/production/hosts.yml`

```yaml
all:
  children:
    monitoring:
      hosts:
        monitoring01:
          ansible_host: 192.168.1.50
          host_fqdn: monitoring.example.com  # Optional FQDN

    jenkins_masters:
      hosts:
        jenkins01:
          ansible_host: 192.168.1.10
          host_fqdn: jenkins.example.com  # Optional FQDN
```

**Validation**:
```bash
ansible-inventory -i ansible/inventories/production/hosts.yml --list
```

### Step 2: Configure Team Variables

**File**: `ansible/inventories/production/group_vars/all/jenkins_teams.yml`

```yaml
jenkins_teams:
  - team_name: team-alpha
    active_environment: blue
    blue_green_enabled: true
    ports:
      web: 8080
      agent: 50000

  - team_name: team-beta
    active_environment: green
    blue_green_enabled: true
    ports:
      web: 8090
      agent: 50010
```

### Step 3: Configure Monitoring Variables

**File**: `ansible/inventories/production/group_vars/all/main.yml`

```yaml
# Monitoring Configuration
monitoring_deployment_type: separate  # 'separate' or 'colocated'
monitoring_use_fqdn: false           # Set to true for FQDN-based targets
monitoring_domain: "example.com"     # Required if monitoring_use_fqdn=true

# Service Discovery Configuration
prometheus_scrape_interval: 30s
prometheus_evaluation_interval: 30s
prometheus_targets_backup_versions: 10

# Enable/Disable Components
cadvisor_enabled: true
loki_enabled: true
promtail_enabled: true
grafana_enabled: true
alertmanager_enabled: true
```

### Step 4: Deploy Monitoring Stack

**Full Deployment**:
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags monitoring \
  -v
```

**Targets-Only Update** (zero-downtime):
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags phase1-file-sd,targets \
  -v
```

**Expected Output**:
```
PLAY [monitoring] ******************************************************

TASK [monitoring : Create Prometheus file-sd targets directory] ********
ok: [monitoring01]

TASK [monitoring : Generate Jenkins team targets for BOTH blue and green] ***
changed: [monitoring01] => (jenkins-team-alpha.json)
changed: [monitoring01] => (jenkins-team-beta.json)

TASK [monitoring : Validate generated targets contain BOTH environments] ***
ok: [monitoring01]

TASK [monitoring : Display validation results] *************************
ok: [monitoring01] => {
    "msg": [
        "✅ Validation PASSED: All targets contain both blue and green environments",
        "Team team-alpha: Found 2 targets (blue:8080, green:8180)",
        "Team team-beta: Found 2 targets (blue:8090, green:8190)"
    ]
}

RUNNING HANDLER [monitoring : reload prometheus] ***********************
changed: [monitoring01]

PLAY RECAP *************************************************************
monitoring01 : ok=15 changed=3
```

### Step 5: Verify Deployment

#### A. Check Target Files
```bash
# SSH to monitoring server
ssh monitoring01

# List generated target files
ls -lh /opt/monitoring/prometheus/targets.d/

# Expected output:
# -rw-r--r-- 1 prometheus prometheus 1.2K jenkins-team-alpha.json
# -rw-r--r-- 1 prometheus prometheus 1.2K jenkins-team-beta.json
# -rw-r--r-- 1 prometheus prometheus  512 node-exporter.json
# -rw-r--r-- 1 prometheus prometheus  512 cadvisor.json

# Validate JSON syntax
python3 -m json.tool /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json

# Check target content
cat /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json | jq .
```

#### B. Verify Prometheus Discovery
```bash
# Check Prometheus logs
docker logs prometheus 2>&1 | grep "file_sd"

# Expected output:
# level=info ts=2025-11-17T14:30:22.123Z component=discovery msg="File SD refresh" files=[targets.d/jenkins-*.json]
# level=info ts=2025-11-17T14:30:22.456Z component=discovery msg="File SD refresh completed" targets=12

# Query Prometheus API
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
# Expected: > 0 (number of active targets)

# Check specific team targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.team=="team-alpha")'
```

#### C. Verify in Prometheus UI
```
1. Open browser: http://monitoring01:9090
2. Navigate to: Status → Targets
3. Verify:
   ✅ jenkins-team-alpha job shows 2 endpoints (blue:8080, green:8180)
   ✅ jenkins-team-beta job shows 2 endpoints (blue:8090, green:8190)
   ✅ Both UP (green) or 1 UP + 1 DOWN (gray) if passive not deployed
   ✅ Labels show is_active="true" for active, "false" for passive
```

#### D. Verify Grafana Dashboards
```
1. Open browser: http://monitoring01:3000
2. Login: admin / <vault_grafana_admin_password>
3. Navigate to: Dashboards → Jenkins Comprehensive
4. Verify:
   ✅ "Environment Status" panel shows both blue and green
   ✅ Active environment marked clearly
   ✅ Metrics displayed for both environments
```

---

## Validation Procedures

### 1. Pre-Deployment Validation

**Syntax Check**:
```bash
ansible-playbook ansible/site.yml --syntax-check
```

**Inventory Validation**:
```bash
ansible-inventory -i ansible/inventories/production/hosts.yml --graph
```

**Variables Validation**:
```bash
ansible -i ansible/inventories/production/hosts.yml monitoring -m debug -a "var=jenkins_teams"
```

**Expected Output**:
```json
{
  "jenkins_teams": [
    {
      "team_name": "team-alpha",
      "active_environment": "blue",
      "blue_green_enabled": true,
      "ports": {
        "web": 8080,
        "agent": 50000
      }
    }
  ]
}
```

### 2. Post-Deployment Validation

**A. Automated Validation** (included in deployment):
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags validation \
  -v
```

**Validation Tasks**:
- ✅ JSON syntax validation for all target files
- ✅ File permissions verification (644, prometheus:prometheus)
- ✅ Target count validation (> 0)
- ✅ Both-environment validation (blue AND green present)
- ✅ Active environment label matching
- ✅ is_active label correctness (1 true, 1 false per team)

**B. Manual Validation Script**:
```bash
#!/bin/bash
# validate-prometheus-targets.sh

set -e

TARGETS_DIR="/opt/monitoring/prometheus/targets.d"
ERRORS=0

echo "=== Prometheus Targets Validation ==="

# Check directory exists
if [ ! -d "$TARGETS_DIR" ]; then
  echo "❌ ERROR: Targets directory not found: $TARGETS_DIR"
  exit 1
fi

# Check for target files
TARGET_COUNT=$(find "$TARGETS_DIR" -maxdepth 1 -name "*.json" | wc -l)
if [ "$TARGET_COUNT" -eq 0 ]; then
  echo "❌ ERROR: No target files found in $TARGETS_DIR"
  exit 1
fi
echo "✅ Found $TARGET_COUNT target files"

# Validate JSON syntax
echo ""
echo "=== JSON Syntax Validation ==="
for file in "$TARGETS_DIR"/*.json; do
  if python3 -m json.tool "$file" > /dev/null 2>&1; then
    TARGETS=$(python3 -c "import json; print(len(json.load(open('$file'))))")
    echo "✅ $(basename $file): Valid JSON ($TARGETS targets)"
  else
    echo "❌ $(basename $file): INVALID JSON"
    ERRORS=$((ERRORS + 1))
  fi
done

# Validate team targets (both blue and green)
echo ""
echo "=== Blue-Green Environment Validation ==="
for file in "$TARGETS_DIR"/jenkins-*.json; do
  if [ -f "$file" ]; then
    TEAM=$(basename "$file" .json | sed 's/jenkins-//')

    # Check for both environments
    BLUE_COUNT=$(grep -c "\"environment\": \"blue\"" "$file" || true)
    GREEN_COUNT=$(grep -c "\"environment\": \"green\"" "$file" || true)

    if [ "$BLUE_COUNT" -eq 1 ] && [ "$GREEN_COUNT" -eq 1 ]; then
      echo "✅ $TEAM: Both environments present (blue + green)"
    else
      echo "❌ $TEAM: Missing environments (blue: $BLUE_COUNT, green: $GREEN_COUNT)"
      ERRORS=$((ERRORS + 1))
    fi

    # Check is_active labels
    ACTIVE_COUNT=$(grep -c "\"is_active\": \"true\"" "$file" || true)
    PASSIVE_COUNT=$(grep -c "\"is_active\": \"false\"" "$file" || true)

    if [ "$ACTIVE_COUNT" -eq 1 ] && [ "$PASSIVE_COUNT" -eq 1 ]; then
      echo "✅ $TEAM: Correct is_active labels (1 active, 1 passive)"
    else
      echo "❌ $TEAM: Invalid is_active labels (active: $ACTIVE_COUNT, passive: $PASSIVE_COUNT)"
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

# Check Prometheus discovery
echo ""
echo "=== Prometheus Target Discovery ==="
if command -v curl > /dev/null 2>&1; then
  ACTIVE_TARGETS=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | \
    python3 -c "import sys, json; print(len(json.load(sys.stdin)['data']['activeTargets']))" 2>/dev/null || echo "0")

  if [ "$ACTIVE_TARGETS" -gt 0 ]; then
    echo "✅ Prometheus discovered $ACTIVE_TARGETS active targets"
  else
    echo "❌ WARNING: Prometheus has 0 active targets"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "⚠️  SKIP: curl not available for Prometheus API check"
fi

echo ""
if [ $ERRORS -eq 0 ]; then
  echo "=========================================="
  echo "✅ VALIDATION PASSED: All checks successful"
  echo "=========================================="
  exit 0
else
  echo "=========================================="
  echo "❌ VALIDATION FAILED: $ERRORS error(s) detected"
  echo "=========================================="
  exit 1
fi
```

**Usage**:
```bash
chmod +x validate-prometheus-targets.sh
./validate-prometheus-targets.sh
```

### 3. Continuous Validation

**Prometheus Rules** (automatic monitoring):
```yaml
# ansible/roles/monitoring/templates/prometheus.yml.j2 (custom rules)
groups:
  - name: prometheus.self-monitoring
    rules:
      - alert: PrometheusNoTargets
        expr: count(up) == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Prometheus has no active targets"
          description: "File-SD discovery may have failed"

      - alert: PrometheusTargetsMissing
        expr: count(up{job=~"jenkins-.*"}) < 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Jenkins targets count below expected"
          description: "Expected at least 2 targets (blue + green) per team"
```

---

## Troubleshooting

### Issue 1: Prometheus Shows 0 Active Targets

**Symptoms**:
```
Prometheus UI → Status → Targets
Active Targets: 0
Dropped Targets: 0
```

**Diagnosis Steps**:

1. **Check target files exist**:
```bash
ls -lh /opt/monitoring/prometheus/targets.d/
```

Expected: Multiple .json files

2. **Validate JSON syntax**:
```bash
for file in /opt/monitoring/prometheus/targets.d/*.json; do
  echo "Checking $file..."
  python3 -m json.tool "$file" || echo "INVALID JSON"
done
```

3. **Check volume mount**:
```bash
docker inspect prometheus | jq '.[0].Mounts[] | select(.Destination=="/etc/prometheus/targets.d")'
```

Expected output:
```json
{
  "Type": "bind",
  "Source": "/opt/monitoring/prometheus/targets.d",
  "Destination": "/etc/prometheus/targets.d",
  "Mode": "ro",
  "RW": false,
  "Propagation": "rprivate"
}
```

4. **Check Prometheus logs**:
```bash
docker logs prometheus 2>&1 | grep -i "file_sd\|error\|warning"
```

Look for errors like:
```
level=error component=file_sd msg="Error reading file" file=targets.d/jenkins-team-alpha.json err="permission denied"
```

**Solutions**:

**A. Missing Volume Mount**:
```yaml
# Fix in: ansible/roles/monitoring/tasks/phase3-servers/prometheus.yml
volumes:
  - /opt/monitoring/prometheus/targets.d:/etc/prometheus/targets.d:ro
```

Redeploy:
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags monitoring \
  -v
```

**B. File Permissions Issue**:
```bash
# Fix permissions
chown -R prometheus:prometheus /opt/monitoring/prometheus/targets.d/
chmod 755 /opt/monitoring/prometheus/targets.d/
chmod 644 /opt/monitoring/prometheus/targets.d/*.json
```

**C. Invalid JSON Syntax**:
```bash
# Regenerate target files
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags phase1-file-sd,targets \
  -v
```

**D. Configuration Reload Issue**:
```bash
# Manual reload
docker exec prometheus kill -HUP 1

# Or restart Prometheus
docker restart prometheus
```

### Issue 2: ansible_default_ipv4 Undefined Error

**Error Message**:
```
TASK [monitoring : Generate Jenkins team targets] *********************
fatal: [monitoring01]: FAILED! => {
    "msg": "The task includes an option with an undefined variable.
            The error was: 'dict object' has no attribute 'ansible_default_ipv4'"
}
```

**Root Cause**: Ansible facts not gathered or unavailable

**Solutions**:

**A. Enable Facts Gathering**:
```yaml
# Add to playbook
- hosts: all
  gather_facts: yes  # Ensure this is set
```

**B. Explicit ansible_host in Inventory**:
```yaml
# ansible/inventories/production/hosts.yml
jenkins_masters:
  hosts:
    jenkins01:
      ansible_host: 192.168.1.10  # Explicit IP (highest priority in fallback)
```

**C. Use Fallback Variable**:
```yaml
# Already implemented in v2 branch
# ansible/roles/jenkins-master-v2/defaults/main.yml
jenkins_master_host_ip: >-
  {{
    hostvars[inventory_hostname]['ansible_host'] |
    default(
      ansible_default_ipv4.address |
      default(
        ansible_all_ipv4_addresses[0] |
        default('127.0.0.1')
      )
    )
  }}
```

**D. Manual Fact Gathering**:
```bash
# Gather facts manually
ansible -i ansible/inventories/production/hosts.yml jenkins_masters -m setup

# Check available facts
ansible -i ansible/inventories/production/hosts.yml jenkins01 -m debug -a "var=ansible_default_ipv4"
```

### Issue 3: Only Active Environment Showing in Targets

**Symptoms**:
```
# Prometheus UI shows only 1 target per team instead of 2
jenkins-team-alpha:
  - 192.168.1.10:8080 (UP)   # Blue environment only

# Missing:
  - 192.168.1.10:8180 (?)    # Green environment
```

**Diagnosis**:
```bash
# Check target file content
cat /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json | jq .

# Count environments
grep -c "\"environment\": \"blue\"" /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json
grep -c "\"environment\": \"green\"" /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json
```

**Expected**: Both should return 1

**Root Cause**: Old version of generate-file-sd.yml deployed

**Solution**:
```bash
# Verify branch
git branch
# Should show: * claude/fix-prometheus-targets-discovery-v2-011CUnvsAdsqPq77u68eMLuu

# Redeploy with correct version
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags phase1-file-sd,targets \
  -v
```

### Issue 4: Passive Environment Shows as DOWN

**Symptoms**:
```
# Prometheus UI
jenkins-team-alpha:
  - 192.168.1.10:8080 (UP)    # Blue (active)
  - 192.168.1.10:8180 (DOWN)  # Green (passive)
```

**Diagnosis**:

Check if passive environment is actually deployed:
```bash
# SSH to Jenkins host
ssh jenkins01

# Check running containers
docker ps | grep jenkins-team-alpha

# Expected for blue active:
# jenkins-team-alpha-blue   Up 2 hours   0.0.0.0:8080->8080/tcp

# Green might not be running (resource-optimized deployment)
```

**This is NORMAL Behavior if**:
- Team uses resource-optimized deployment (only active environment running)
- Passive environment not yet deployed after recent switch

**Verify Alerts Suppressed**:
```bash
# Check Prometheus alerts
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.team=="team-alpha")'

# Should see:
# - JenkinsMasterDown: NOT firing (active is UP)
# - JenkinsPassiveEnvironmentDown: Firing but severity=info (no notification)
```

**If Alerts Are NOT Suppressed**:
```yaml
# Check alert rules
docker exec prometheus cat /etc/prometheus/rules/jenkins.yml | grep -A 10 "JenkinsMasterDown"

# Should have filter: is_active="true"
expr: up{job=~"jenkins-.*", is_active="true"} == 0
```

**Fix**:
```bash
# Redeploy monitoring rules
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags monitoring \
  -v
```

### Issue 5: Stale Targets After Blue-Green Switch

**Scenario**:
1. Team-alpha switches from blue → green
2. Prometheus still shows blue as active

**Diagnosis**:
```bash
# Check team configuration
ansible -i ansible/inventories/production/hosts.yml all -m debug -a "var=jenkins_teams"

# Check target file
cat /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json | jq '.[] | select(.labels.is_active=="true") | .labels.environment'
# Should output: "green"
```

**Root Cause**: Targets not regenerated after switch

**Solution**:
```bash
# Regenerate targets after blue-green switch
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/blue-green-switch.yml \
  -e "team_name=team-alpha" \
  -e "target_environment=green" \
  -v

# This should automatically regenerate targets
# Verify:
cat /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json | jq '.[] | .labels | {environment, is_active}'
```

**Automation**: Add post-switch hook to regenerate targets

### Issue 6: FQDN Resolution Failures

**Symptoms**:
```
# Prometheus UI shows targets as DOWN
jenkins-team-alpha:
  - jenkins-team-alpha-blue.example.com:8080 (DOWN)
```

**Diagnosis**:
```bash
# Check DNS resolution from monitoring server
ssh monitoring01
nslookup jenkins-team-alpha-blue.example.com

# Expected: Should resolve to Jenkins host IP
# Actual: NXDOMAIN (DNS not configured)
```

**Solutions**:

**A. Use IP-Based Targets** (default):
```yaml
# ansible/inventories/production/group_vars/all/main.yml
monitoring_use_fqdn: false  # Use IPs instead of FQDNs
```

**B. Configure DNS**:
```bash
# Add DNS records or /etc/hosts entries
echo "192.168.1.10 jenkins-team-alpha-blue.example.com" >> /etc/hosts
echo "192.168.1.10 jenkins-team-alpha-green.example.com" >> /etc/hosts
```

**C. Verify FQDN Variables**:
```yaml
# ansible/inventories/production/hosts.yml
jenkins_masters:
  hosts:
    jenkins01:
      ansible_host: 192.168.1.10
      host_fqdn: jenkins.example.com  # Ensure this is correct
```

---

## Common Issues & Solutions

### 1. Permission Denied Errors

**Issue**: Prometheus cannot read target files

**Error**:
```
level=error component=file_sd msg="Error reading file" err="permission denied"
```

**Solution**:
```bash
# Fix ownership and permissions
chown -R prometheus:prometheus /opt/monitoring/prometheus/targets.d/
chmod 755 /opt/monitoring/prometheus/targets.d/
chmod 644 /opt/monitoring/prometheus/targets.d/*.json

# Restart Prometheus
docker restart prometheus
```

### 2. JSON Syntax Errors

**Issue**: Invalid JSON in target files

**Error**:
```
level=error component=file_sd msg="Error reading file" err="invalid character"
```

**Diagnosis**:
```bash
# Validate JSON
python3 -m json.tool /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json

# Or use jq
jq . /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json
```

**Solution**:
```bash
# Regenerate target files
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags phase1-file-sd,targets \
  -v
```

### 3. Targets Not Auto-Refreshing

**Issue**: Changes to target files not picked up

**Diagnosis**:
```bash
# Check file_sd refresh_interval
docker exec prometheus cat /etc/prometheus/prometheus.yml | grep -A 3 "file_sd_configs"

# Should show:
#   refresh_interval: 30s
```

**Solution**:
```bash
# Manual reload
docker exec prometheus kill -HUP 1

# Or wait for auto-refresh (30 seconds)
sleep 35

# Verify discovery
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
```

### 4. Port Conflicts

**Issue**: Blue and green environments both trying to use same port

**Error**:
```
Error starting userland proxy: listen tcp 0.0.0.0:8080: bind: address already in use
```

**Root Cause**: Incorrect port calculation

**Diagnosis**:
```bash
# Check configured ports
cat /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json | jq '.[] | .targets'

# Should show:
# ["192.168.1.10:8080"]  # Blue
# ["192.168.1.10:8180"]  # Green (blue_port + 100)
```

**Verify Port Calculation**:
```yaml
# In generate-file-sd.yml:
{% set env_port = team_web_port if env == 'blue' else (team_web_port | int + 100) %}
```

### 5. Missing Team Targets

**Issue**: Some teams not appearing in Prometheus

**Diagnosis**:
```bash
# Check team configuration loaded
ansible -i ansible/inventories/production/hosts.yml all -m debug -a "var=jenkins_teams" | grep team_name

# List target files
ls /opt/monitoring/prometheus/targets.d/jenkins-*.json
```

**Solution**:
```bash
# Verify jenkins_teams variable defined
cat ansible/inventories/production/group_vars/all/jenkins_teams.yml

# Regenerate all targets
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags phase1-file-sd,targets \
  -v
```

---

## Rollback Procedures

### Emergency Rollback to IP-Based Static Config

**If file-sd completely fails**, rollback to static configuration:

**Step 1: Backup Current State**
```bash
# SSH to monitoring server
ssh monitoring01

# Backup current targets
cp -r /opt/monitoring/prometheus/targets.d /opt/monitoring/prometheus/targets.d.bak-$(date +%Y%m%d_%H%M%S)

# Backup prometheus.yml
cp /opt/monitoring/prometheus/prometheus.yml /opt/monitoring/prometheus/prometheus.yml.bak-$(date +%Y%m%d_%H%M%S)
```

**Step 2: Revert to Static Config**
```yaml
# Edit: /opt/monitoring/prometheus/prometheus.yml
scrape_configs:
  # Revert jenkins job to static_configs
  - job_name: 'jenkins-team-alpha'
    static_configs:
      - targets:
          - '192.168.1.10:8080'  # Blue environment only
        labels:
          team: 'team-alpha'
          environment: 'blue'
```

**Step 3: Reload Prometheus**
```bash
docker exec prometheus kill -HUP 1

# Verify targets discovered
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
```

### Restore from Backup

**Target Files**:
```bash
# List available backups
ls -lht /opt/monitoring/prometheus/targets.d/.backups/

# Restore specific version
BACKUP_DATE="20251117_143022"
cp /opt/monitoring/prometheus/targets.d/.backups/jenkins-team-alpha.json-$BACKUP_DATE \
   /opt/monitoring/prometheus/targets.d/jenkins-team-alpha.json

# Reload Prometheus
docker exec prometheus kill -HUP 1
```

### Rollback to Previous Git Commit

```bash
# Identify last working commit
git log --oneline -10

# Checkout previous version
git checkout <previous-commit-hash>

# Redeploy
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags monitoring \
  -v
```

---

## Additional Resources

### Quick Reference Commands

**Check Prometheus Status**:
```bash
curl -s http://localhost:9090/api/v1/status/config | jq .
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

**Reload Prometheus Configuration**:
```bash
# Method 1: HUP signal
docker exec prometheus kill -HUP 1

# Method 2: HTTP reload (if --web.enable-lifecycle)
curl -X POST http://localhost:9090/-/reload

# Method 3: Restart container
docker restart prometheus
```

**Generate Targets Manually**:
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags phase1-file-sd,targets \
  -v
```

**Validate Targets**:
```bash
# JSON syntax
for f in /opt/monitoring/prometheus/targets.d/*.json; do
  python3 -m json.tool "$f" > /dev/null && echo "✅ $f" || echo "❌ $f"
done

# Target count
for f in /opt/monitoring/prometheus/targets.d/jenkins-*.json; do
  echo "$f: $(jq '. | length' $f) targets"
done
```

### Monitoring Tags

**Deployment Tags**:
- `monitoring` - Full monitoring stack deployment
- `phase1-file-sd` - File-based service discovery setup
- `targets` - Target file generation only
- `validation` - Validation tasks only
- `phase3-targets` - Phase 3 target generation
- `phase5-fqdn` - FQDN migration tasks

**Usage Examples**:
```bash
# Deploy only target generation (fastest)
ansible-playbook -i inventory.yml site.yml --tags targets

# Deploy file-sd infrastructure + targets
ansible-playbook -i inventory.yml site.yml --tags phase1-file-sd

# Run validation only
ansible-playbook -i inventory.yml site.yml --tags validation
```

### Key Files Reference

**Ansible Roles**:
- `ansible/roles/monitoring/tasks/phase3-targets/generate-file-sd.yml` - Target generation
- `ansible/roles/monitoring/tasks/phase3-targets/validate-targets.yml` - Target validation
- `ansible/roles/monitoring/tasks/phase3-servers/prometheus.yml` - Prometheus deployment
- `ansible/roles/monitoring/tasks/phase4-configuration/verification.yml` - Post-deploy verification
- `ansible/roles/monitoring/templates/prometheus.yml.j2` - Prometheus config template

**Configuration Files**:
- `ansible/inventories/production/group_vars/all/jenkins_teams.yml` - Team definitions
- `ansible/inventories/production/group_vars/all/main.yml` - Monitoring variables
- `monitoring/prometheus/rules/jenkins.yml` - Alert rules

**Scripts**:
- `scripts/validate-prometheus-targets.sh` - Manual validation script (create from guide)

### Support Contacts

**Escalation Path**:
1. Check this guide's troubleshooting section
2. Review Prometheus logs: `docker logs prometheus`
3. Run validation: `ansible-playbook site.yml --tags validation`
4. Create GitHub issue with:
   - Full error messages
   - Validation output
   - Prometheus logs
   - Ansible playbook output

---

## Changelog

**Version 2.0** (Branch: claude/fix-prometheus-targets-discovery-v2-011CUnvsAdsqPq77u68eMLuu)
- ✅ Implemented file-based service discovery
- ✅ Added both-environment monitoring (blue + green)
- ✅ Implemented intelligent alert suppression
- ✅ Fixed ansible_default_ipv4 undefined errors
- ✅ Added comprehensive validation framework
- ✅ Implemented automatic backup rotation
- ✅ Added FQDN support with conditional logic
- ✅ Enhanced Prometheus configuration with retry logic
- ✅ Added volume mount for targets.d directory

**Previous Issues** (Commit: 4ba6576):
- ⚠️ Active-only monitoring (operational blind spots)
- ⚠️ No passive environment visibility

**Previous Issues** (Commit: dc59850):
- ⚠️ Missing targets.d volume mount
- ⚠️ No retry logic for discovery
- ⚠️ Timing issues with verification

---

## License

This guide is part of the Jenkins HA Infrastructure project.
