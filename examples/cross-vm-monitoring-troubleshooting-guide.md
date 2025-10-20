# Cross-VM Monitoring Troubleshooting Guide

## Overview

This guide addresses common issues with cross-VM monitoring in Jenkins HA infrastructure where monitoring agents (Node Exporter, Promtail, cAdvisor) deployed on Jenkins VMs communicate with monitoring servers (Prometheus, Loki) on separate monitoring VMs.

**Last Updated**: 2025-10-20
**Architecture**: Separate VM Deployment (`monitoring_deployment_type: separate`)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Network Communication Issues](#network-communication-issues)
3. [Prometheus Target Configuration](#prometheus-target-configuration)
4. [Task Execution Order](#task-execution-order)
5. [Verification Procedures](#verification-procedures)
6. [Common Error Messages](#common-error-messages)
7. [Best Practices](#best-practices)

---

## Architecture Overview

### Component Communication Patterns

```
┌─────────────────────────────────────────────────────────────────┐
│                        Monitoring VM                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│  │ Prometheus  │◄───│  Grafana    │    │    Loki     │◄────┐  │
│  │  (PULL)     │    │             │    │   (PUSH)    │     │  │
│  └─────────────┘    └─────────────┘    └─────────────┘     │  │
│         ▲                                                     │  │
│         │ Scrape Metrics (HTTP)                              │  │
└─────────┼─────────────────────────────────────────────────────┘  │
          │                                                        │
          │ Host Network (Cross-VM capable)                       │
          │                                                        │
┌─────────┼────────────────────────────────────────┬──────────────┘
│         │              Jenkins VM                │              │
│  ┌──────▼──────┐    ┌─────────────┐    ┌────────▼──────┐     │
│  │Node Exporter│    │  cAdvisor   │    │   Promtail    │─────┘
│  │ :9100       │    │  :9200      │    │   :9080       │
│  └─────────────┘    └─────────────┘    └───────────────┘
│                                                                  │
│  Network Mode: host (NOT bridge)                                │
└──────────────────────────────────────────────────────────────────┘
```

### Communication Models

| Component | Direction | Protocol | Network Requirement |
|-----------|-----------|----------|---------------------|
| **Prometheus → Node Exporter** | PULL | HTTP | Host network |
| **Prometheus → cAdvisor** | PULL | HTTP | Host network |
| **Promtail → Loki** | PUSH | HTTP | Host network |

**Critical**: Docker bridge networks are VM-local and cannot route traffic between VMs. All cross-VM agents MUST use `network_mode: host`.

---

## Network Communication Issues

### Issue 1: Promtail Cannot Reach Loki

**Symptoms**:
```bash
# Promtail logs show connection errors
docker logs promtail-jenkins-vm1-production
# Output:
# level=error msg="error sending batch" error="Post http://monitoring.internal.local:9400/loki/api/v1/push: dial tcp: lookup monitoring.internal.local: no such host"
```

**Root Cause**: Promtail container uses Docker bridge network (`monitoring-net`) which is VM-local and cannot route to monitoring VM.

**Solution**: Use host network mode

**Fix Applied** (ansible/roles/monitoring/tasks/cross-vm-exporters.yml:77-105):
```yaml
- name: Deploy Promtail container on Jenkins VMs
  community.docker.docker_container:
    name: "promtail-{{ hostvars[item]['inventory_hostname_short'] }}-{{ deployment_environment | default('local') }}"
    image: "grafana/promtail:{{ promtail_version }}"
    network_mode: host  # FIXED: Use host network for cross-VM communication
    # REMOVED: ports and networks sections
    volumes:
      - "{{ monitoring_home_dir }}/promtail/config:/etc/promtail"
      - "{{ monitoring_home_dir }}/promtail/data:/promtail"
      - "/var/log:/var/log:ro"
      # ... other volumes
    command: ["-config.file=/etc/promtail/promtail-config.yml"]
```

**Verification**:
```bash
# Check Promtail logs for successful connection
docker logs promtail-jenkins-vm1-production | grep -i "loki"
# Expected: "msg="Successfully sent batch"

# Verify Loki receiving logs
curl -s http://monitoring.internal.local:9400/loki/api/v1/label | jq
# Expected: JSON list of labels from Jenkins VM logs
```

### Issue 2: Prometheus Cannot Scrape Node Exporter

**Symptoms**:
```bash
# Prometheus targets show "down" status
curl -s http://monitoring.internal.local:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="node-exporter") | {health: .health, lastError: .lastError}'
# Output:
# {
#   "health": "down",
#   "lastError": "Get \"http://centos9-vm.internal.local:9100/metrics\": dial tcp 192.168.188.142:9100: connect: connection refused"
# }
```

**Root Cause**: Node Exporter container uses Docker bridge network which cannot accept connections from other VMs.

**Solution**: Use host network mode

**Fix Applied** (ansible/roles/monitoring/tasks/cross-vm-exporters.yml:18-42):
```yaml
- name: Deploy Node Exporter on Jenkins VMs
  community.docker.docker_container:
    name: node-exporter-{{ deployment_environment | default('local') }}
    image: "prom/node-exporter:{{ node_exporter_version }}"
    network_mode: host  # FIXED: Use host network for cross-VM communication
    # REMOVED: ports and networks sections
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - '/proc:/host/proc:ro'
      - '/sys:/host/sys:ro'
      - '/:/rootfs:ro'
```

**Verification**:
```bash
# Test from monitoring VM
curl -s http://centos9-vm.internal.local:9100/metrics | head -n 20
# Expected: Prometheus metrics output

# Check Prometheus targets
curl -s http://monitoring.internal.local:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.job=="node-exporter" and .labels.role=="jenkins-vm") | {health: .health, instance: .labels.instance}'
# Expected: {"health": "up", "instance": "centos9-vm.internal.local:9100"}
```

### Issue 3: Prometheus Cannot Scrape cAdvisor

**Symptoms**:
```bash
# Prometheus shows cAdvisor targets as down
curl -s http://monitoring.internal.local:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.job=="cadvisor" and .labels.role=="jenkins-vm")'
# Output shows health: "down"
```

**Root Cause**: cAdvisor container uses Docker bridge network preventing cross-VM scraping.

**Solution**: Use host network mode with explicit port configuration

**Fix Applied** (ansible/roles/monitoring/tasks/cross-vm-cadvisor.yml:31-60):
```yaml
- name: Deploy cAdvisor container on Jenkins VMs
  community.docker.docker_container:
    name: cadvisor-{{ deployment_environment | default('local') }}
    image: "gcr.io/cadvisor/cadvisor:{{ cadvisor_version }}"
    privileged: yes  # Required for cAdvisor system access
    network_mode: host  # FIXED: Use host network for cross-VM communication
    # REMOVED: ports and networks sections
    command:
      - '--docker_only=true'
      - '--housekeeping_interval=30s'
      - '--disable_metrics=percpu,sched,tcp,udp,disk,diskIO,accelerator,hugetlb,referenced_memory,cpu_topology,resctrl'
      - '--port={{ cadvisor_port }}'  # ADDED: Explicit port for host network
    volumes:
      - "/:/rootfs:ro"
      - "/var/run:/var/run:ro"
      - "/sys:/sys:ro"
      - "/var/lib/docker/:/var/lib/docker:ro"
      - "/dev/disk/:/dev/disk:ro"
```

**Verification**:
```bash
# Test from monitoring VM
curl -s http://centos9-vm.internal.local:9200/metrics | grep "^cadvisor" | head -n 10
# Expected: cAdvisor metrics

# Check Prometheus targets
curl -s http://monitoring.internal.local:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.job=="cadvisor" and .labels.role=="jenkins-vm") | {health: .health, instance: .labels.instance}'
# Expected: {"health": "up", "instance": "centos9-vm.internal.local:9200"}
```

---

## Prometheus Target Configuration

### Issue 4: Cross-VM Targets Not Appearing in Prometheus

**Symptoms**:
```bash
# Prometheus config missing cross-VM targets
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep -A 10 "job_name: 'node-exporter'"
# Output only shows monitoring VM target, no Jenkins VM targets
```

**Root Cause 1**: Target variables generated AFTER prometheus.yml template rendering.

**Root Cause 2**: Prometheus template doesn't reference cross-VM target variables.

**Solution 1**: Reorder task execution in main.yml

**Fix Applied** (ansible/roles/monitoring/tasks/main.yml:175-222):
```yaml
- name: Create monitoring network
  community.docker.docker_network:
    name: "{{ monitoring_network_name }}"
    driver: bridge
    ipam_config:
      - subnet: "{{ monitoring_network_subnet }}"

# CRITICAL: Deploy cross-VM exporters BEFORE Prometheus to generate scrape targets
# Cross-VM tasks generate prometheus_cross_vm_targets and prometheus_cadvisor_targets
# which are needed by prometheus.yml.j2 template rendering
- name: Include Cross-VM Exporters deployment tasks
  include_tasks: cross-vm-exporters.yml
  tags: ['cross-vm', 'exporters']
  when: monitoring_deployment_type == 'separate'

- name: Include Cross-VM cAdvisor deployment tasks
  include_tasks: cross-vm-cadvisor.yml
  tags: ['cross-vm', 'cadvisor']
  when:
    - monitoring_deployment_type == 'separate'
    - cadvisor_enabled | default(true)

# NOW Prometheus template has access to cross-VM target variables
- name: Include Prometheus setup tasks
  include_tasks: prometheus.yml
  tags: ['prometheus']
```

**Before (BROKEN)**:
```
1. Prometheus setup (line 183) → Renders template → NO target variables yet
2. Cross-VM exporters (line 209) → Generates prometheus_cross_vm_targets → TOO LATE
```

**After (FIXED)**:
```
1. Cross-VM exporters (line 185) → Generates prometheus_cross_vm_targets
2. Cross-VM cAdvisor (line 190) → Generates prometheus_cadvisor_targets
3. Prometheus setup (line 197) → Renders template → Variables available ✓
```

**Solution 2**: Update prometheus.yml.j2 template to use cross-VM variables

**Fix Applied** (ansible/roles/monitoring/templates/prometheus.yml.j2:24-49):
```yaml
# ======================================================
# BASE MONITORING TARGETS
# ======================================================
{% for target in prometheus_targets %}
{% if target.job is defined and not (target.job.startswith('jenkins-') or target.job == 'jenkins' or target.job == 'jenkins-default') %}
  - job_name: '{{ target.job }}'
    static_configs:
      - targets: {{ target.targets | to_json }}
{% if monitoring_deployment_type == 'separate' and target.job == 'node-exporter' and prometheus_cross_vm_targets is defined and prometheus_cross_vm_targets | length > 0 %}
      # Cross-VM node-exporter targets from Jenkins VMs
      - targets: {{ prometheus_cross_vm_targets | to_json }}
        labels:
          role: 'jenkins-vm'
          deployment_type: 'cross-vm'
{% endif %}
```

**Fix Applied** (ansible/roles/monitoring/templates/prometheus.yml.j2:97-126):
```yaml
# ======================================================
# CONTAINER AND INFRASTRUCTURE MONITORING
# ======================================================
{% if cadvisor_enabled | default(true) %}
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['{{ monitoring_server_address }}:{{ cadvisor_port }}']
{% if monitoring_deployment_type == 'separate' and prometheus_cadvisor_targets is defined and prometheus_cadvisor_targets | length > 0 %}
      # Cross-VM cAdvisor targets from Jenkins VMs
      - targets: {{ prometheus_cadvisor_targets | to_json }}
        labels:
          role: 'jenkins-vm'
          deployment_type: 'cross-vm'
{% endif %}
```

**Verification**:
```bash
# Check Prometheus configuration
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | \
  grep -A 15 "job_name: 'node-exporter'"

# Expected output:
#   - job_name: 'node-exporter'
#     static_configs:
#       - targets: ["monitoring.internal.local:9100"]
#       # Cross-VM node-exporter targets from Jenkins VMs
#       - targets: ["centos9-vm.internal.local:9100"]
#         labels:
#           role: 'jenkins-vm'
#           deployment_type: 'cross-vm'

# Check cAdvisor configuration
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | \
  grep -A 15 "job_name: 'cadvisor'"

# Expected output includes both monitoring VM and Jenkins VM targets
```

**Verify Variables Generated**:
```bash
# Run Ansible with verbose output
ansible-playbook ansible/site.yml --tags monitoring -vv | grep "prometheus_cross_vm_targets"

# Expected: Variable set with list of Jenkins VM targets
# TASK [monitoring : Add Jenkins VMs to Prometheus node_exporter targets] ***
# ok: [monitoring-vm] => {
#     "prometheus_cross_vm_targets": [
#         "centos9-vm.internal.local:9100"
#     ]
# }
```

---

## Task Execution Order

### Critical Task Dependencies

```
┌─────────────────────────────────────────────────────────────┐
│ CORRECT ORDER (Fixed)                                       │
├─────────────────────────────────────────────────────────────┤
│ 1. Create monitoring directories                            │
│ 2. Create monitoring network                                │
│ 3. Deploy cross-VM exporters                                │
│    └─► Generates prometheus_cross_vm_targets variable       │
│ 4. Deploy cross-VM cAdvisor                                 │
│    └─► Generates prometheus_cadvisor_targets variable       │
│ 5. Deploy Prometheus                                        │
│    └─► Renders prometheus.yml with cross-VM targets ✓       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ INCORRECT ORDER (Before Fix)                                │
├─────────────────────────────────────────────────────────────┤
│ 1. Create monitoring directories                            │
│ 2. Create monitoring network                                │
│ 3. Deploy Prometheus                                        │
│    └─► Renders prometheus.yml WITHOUT cross-VM targets ✗    │
│ 4. Deploy cross-VM exporters (TOO LATE)                     │
│    └─► Generates prometheus_cross_vm_targets (UNUSED)       │
└─────────────────────────────────────────────────────────────┘
```

### Ansible Variable Scope

**Important**: Ansible `set_fact` variables are available to all subsequent tasks in the play, but template rendering happens at task execution time.

**Example**:
```yaml
# Task 1: Renders template NOW (variables must exist NOW)
- name: Deploy config
  template:
    src: config.yml.j2
    dest: /etc/app/config.yml

# Task 2: Sets variable (TOO LATE for Task 1)
- name: Generate targets
  set_fact:
    my_targets: ["host1:9100", "host2:9100"]
```

**Fix**: Always generate variables BEFORE templates that use them.

---

## Verification Procedures

### Full Monitoring Stack Health Check

```bash
#!/bin/bash
# Comprehensive cross-VM monitoring verification

set -e

MONITORING_VM="monitoring.internal.local"
JENKINS_VM="centos9-vm.internal.local"

echo "=============================================="
echo "Cross-VM Monitoring Health Check"
echo "=============================================="

# 1. Check agent containers running on Jenkins VM
echo -e "\n[1/7] Checking agent containers on Jenkins VM..."
ssh ${JENKINS_VM} "docker ps --filter 'name=node-exporter' --format '{{.Names}} - {{.Status}}'"
ssh ${JENKINS_VM} "docker ps --filter 'name=promtail' --format '{{.Names}} - {{.Status}}'"
ssh ${JENKINS_VM} "docker ps --filter 'name=cadvisor' --format '{{.Names}} - {{.Status}}'"

# 2. Test agent endpoints from monitoring VM
echo -e "\n[2/7] Testing agent endpoints from monitoring VM..."
curl -sf http://${JENKINS_VM}:9100/metrics > /dev/null && echo "✓ Node Exporter reachable" || echo "✗ Node Exporter FAILED"
curl -sf http://${JENKINS_VM}:9200/metrics > /dev/null && echo "✓ cAdvisor reachable" || echo "✗ cAdvisor FAILED"
curl -sf http://${JENKINS_VM}:9080/ready > /dev/null && echo "✓ Promtail reachable" || echo "✗ Promtail FAILED"

# 3. Check Prometheus configuration
echo -e "\n[3/7] Checking Prometheus configuration..."
ssh ${MONITORING_VM} "docker exec prometheus-production cat /etc/prometheus/prometheus.yml" | \
  grep -q "${JENKINS_VM}:9100" && echo "✓ Node Exporter target configured" || echo "✗ Node Exporter target MISSING"
ssh ${MONITORING_VM} "docker exec prometheus-production cat /etc/prometheus/prometheus.yml" | \
  grep -q "${JENKINS_VM}:9200" && echo "✓ cAdvisor target configured" || echo "✗ cAdvisor target MISSING"

# 4. Check Prometheus target health
echo -e "\n[4/7] Checking Prometheus target health..."
curl -sf http://${MONITORING_VM}:9090/api/v1/targets | \
  jq -r '.data.activeTargets[] | select(.labels.role=="jenkins-vm") | "\(.job): \(.health)"'

# 5. Check Promtail sending logs to Loki
echo -e "\n[5/7] Checking Promtail → Loki communication..."
ssh ${JENKINS_VM} "docker logs promtail-jenkins-vm1-production 2>&1 | tail -n 50" | \
  grep -q "Successfully sent batch" && echo "✓ Promtail sending logs successfully" || echo "✗ Promtail NOT sending logs"

# 6. Check Loki receiving logs from Jenkins VM
echo -e "\n[6/7] Checking Loki receiving logs from Jenkins VM..."
curl -sf "http://${MONITORING_VM}:9400/loki/api/v1/label/hostname/values" | \
  jq -r '.data[]' | grep -q "jenkins-vm1" && echo "✓ Loki receiving Jenkins VM logs" || echo "✗ Loki NOT receiving Jenkins VM logs"

# 7. Query metrics from Jenkins VM
echo -e "\n[7/7] Querying metrics from Jenkins VM..."
QUERY_RESULT=$(curl -sf "http://${MONITORING_VM}:9090/api/v1/query?query=node_uname_info{role=\"jenkins-vm\"}" | \
  jq -r '.data.result | length')
if [ "$QUERY_RESULT" -gt 0 ]; then
  echo "✓ Jenkins VM metrics available in Prometheus (${QUERY_RESULT} results)"
else
  echo "✗ NO Jenkins VM metrics in Prometheus"
fi

echo -e "\n=============================================="
echo "Health check complete"
echo "=============================================="
```

**Expected Output** (all checks passing):
```
==============================================
Cross-VM Monitoring Health Check
==============================================

[1/7] Checking agent containers on Jenkins VM...
node-exporter-production - Up 5 minutes
promtail-jenkins-vm1-production - Up 5 minutes
cadvisor-production - Up 5 minutes

[2/7] Testing agent endpoints from monitoring VM...
✓ Node Exporter reachable
✓ cAdvisor reachable
✓ Promtail reachable

[3/7] Checking Prometheus configuration...
✓ Node Exporter target configured
✓ cAdvisor target configured

[4/7] Checking Prometheus target health...
node-exporter: up
cadvisor: up

[5/7] Checking Promtail → Loki communication...
✓ Promtail sending logs successfully

[6/7] Checking Loki receiving logs from Jenkins VM...
✓ Loki receiving Jenkins VM logs

[7/7] Querying metrics from Jenkins VM...
✓ Jenkins VM metrics available in Prometheus (1 results)

==============================================
Health check complete
==============================================
```

### Ansible Deployment Verification

```bash
# Deploy with verbose output
ansible-playbook ansible/site.yml --tags monitoring -vv

# Check task order in output
ansible-playbook ansible/site.yml --tags monitoring --list-tasks

# Expected order:
# TASK [monitoring : Create monitoring network]
# TASK [monitoring : Include Cross-VM Exporters deployment tasks]
# TASK [monitoring : Include Cross-VM cAdvisor deployment tasks]
# TASK [monitoring : Include Prometheus setup tasks]  ← AFTER cross-VM tasks ✓
```

---

## Common Error Messages

### Error 1: "Connection Refused" from Prometheus

```
Get "http://centos9-vm.internal.local:9100/metrics": dial tcp 192.168.188.142:9100: connect: connection refused
```

**Diagnosis**:
```bash
# Check if Node Exporter container is running
ssh centos9-vm.internal.local "docker ps | grep node-exporter"

# Check container network mode
ssh centos9-vm.internal.local "docker inspect node-exporter-production | jq '.[0].HostConfig.NetworkMode'"
# Expected: "host"
# If shows "monitoring-net" → INCORRECT, needs host network
```

**Solution**: Redeploy with host network mode (fix already applied).

### Error 2: "No Such Host" from Promtail

```
level=error msg="error sending batch" error="Post http://monitoring.internal.local:9400/loki/api/v1/push: dial tcp: lookup monitoring.internal.local: no such host"
```

**Diagnosis**:
```bash
# Check Promtail network mode
ssh centos9-vm.internal.local "docker inspect promtail-jenkins-vm1-production | jq '.[0].HostConfig.NetworkMode'"
# Expected: "host"
# If shows "monitoring-net" → INCORRECT, needs host network

# Check DNS resolution from inside container (if bridge mode)
ssh centos9-vm.internal.local "docker exec promtail-jenkins-vm1-production nslookup monitoring.internal.local"
# If fails → DNS not available in bridge network
```

**Solution**: Redeploy with host network mode (fix already applied).

### Error 3: Prometheus Config Missing Cross-VM Targets

```
# Only shows monitoring VM, no Jenkins VM targets
- job_name: 'node-exporter'
  static_configs:
    - targets: ["monitoring.internal.local:9100"]
# Missing: - targets: ["centos9-vm.internal.local:9100"]
```

**Diagnosis**:
```bash
# Check if cross-VM tasks ran
ansible-playbook ansible/site.yml --tags monitoring -vv | grep "Cross-VM"

# Check variable generation
ansible-playbook ansible/site.yml --tags monitoring -vv | grep "prometheus_cross_vm_targets"
# Expected: Variable with Jenkins VM targets

# Check task execution order
ansible-playbook ansible/site.yml --tags monitoring --list-tasks
# Verify cross-VM tasks run BEFORE Prometheus setup
```

**Solution**: Redeploy after task reordering fix (already applied).

### Error 4: Target Variables Undefined in Template

```
AnsibleUndefinedVariable: 'prometheus_cross_vm_targets' is undefined
```

**Diagnosis**:
```bash
# Check if cross-VM tasks are included
grep -A 5 "Include Cross-VM" ansible/roles/monitoring/tasks/main.yml

# Check when conditions
ansible-playbook ansible/site.yml --tags monitoring -vv | grep "monitoring_deployment_type"
# Verify it's set to 'separate'
```

**Solution**: Ensure `monitoring_deployment_type: separate` in inventory and cross-VM tasks run before Prometheus.

---

## Best Practices

### 1. Network Mode Selection

| Scenario | Network Mode | Reason |
|----------|--------------|--------|
| **Cross-VM agents** | `host` | Agents must be reachable from other VMs |
| **Same-VM services** | `bridge` | Isolation and Docker DNS |
| **Internet-facing services** | `bridge` with explicit ports | Security and port control |

### 2. Task Ordering Principles

1. **Generate configuration variables BEFORE rendering templates**
2. **Deploy infrastructure (network, storage) FIRST**
3. **Deploy agents BEFORE servers that consume their data**
4. **Deploy servers AFTER agents are configured**

### 3. Debugging Workflow

```
1. Container Status
   └─► docker ps (verify running)
       └─► Network Mode
           ├─► host → Check firewall, connectivity
           └─► bridge → Check DNS, inter-container networking

2. Network Connectivity
   └─► curl endpoints from target VM
       ├─► Success → Check Prometheus config
       └─► Failure → Check network mode, firewall

3. Configuration Validation
   └─► Verify template rendering
       ├─► Check variables exist before template
       └─► Check variable values are correct

4. Target Health
   └─► Prometheus /targets endpoint
       ├─► UP → Working correctly
       └─► DOWN → Check connectivity, authentication
```

### 4. Deployment Checklist

- [ ] Verify `monitoring_deployment_type: separate` in inventory
- [ ] Confirm FQDN variables set in inventory (`host_fqdn`, `monitoring_fqdn`)
- [ ] Check DNS resolution between VMs
- [ ] Verify firewall allows traffic on monitoring ports (9100, 9200, 9080, 9400)
- [ ] Confirm cross-VM tasks run before Prometheus deployment
- [ ] Validate Prometheus configuration includes cross-VM targets
- [ ] Test agent endpoints from monitoring VM
- [ ] Verify Prometheus target health shows "up"
- [ ] Check logs for successful data transmission

### 5. Monitoring Commands Reference

```bash
# Container inspection
docker ps --filter "name=node-exporter"
docker inspect <container_name> | jq '.[0].HostConfig.NetworkMode'
docker logs <container_name> --tail 50

# Network testing
curl -s http://<host>:<port>/metrics | head -n 20
curl -s http://<host>:<port>/ready

# Prometheus queries
curl -s "http://<prometheus>:9090/api/v1/targets" | jq '.data.activeTargets[] | select(.job=="node-exporter")'
curl -s "http://<prometheus>:9090/api/v1/query?query=up{job=\"node-exporter\"}" | jq

# Loki queries
curl -s "http://<loki>:9400/loki/api/v1/label/hostname/values" | jq
curl -s "http://<loki>:9400/loki/api/v1/query_range?query={hostname=\"jenkins-vm1\"}&limit=10" | jq

# Ansible verification
ansible-playbook ansible/site.yml --tags monitoring --list-tasks
ansible-playbook ansible/site.yml --tags monitoring --check
ansible-playbook ansible/site.yml --tags monitoring -vv
```

---

## Migration from Bridge to Host Network

If you have existing deployments using bridge networks, follow this migration procedure:

### Step 1: Backup Current Configuration

```bash
# Backup Prometheus data
docker exec prometheus-production tar czf /tmp/prometheus-backup.tar.gz /prometheus

# Backup Loki data
docker exec loki-production tar czf /tmp/loki-backup.tar.gz /tmp/loki
```

### Step 2: Deploy Updated Configuration

```bash
# Pull latest changes with network fixes
git pull

# Review changes
git diff HEAD~5 ansible/roles/monitoring/tasks/cross-vm-exporters.yml
git diff HEAD~5 ansible/roles/monitoring/tasks/cross-vm-cadvisor.yml

# Deploy with monitoring tags
ansible-playbook ansible/site.yml --tags monitoring
```

### Step 3: Verify Agent Redeployment

```bash
# Agents should be recreated with host network
ansible jenkins_masters -m shell -a "docker inspect node-exporter-production | jq '.[0].HostConfig.NetworkMode'"
# Expected: "host" for all Jenkins VMs

ansible jenkins_masters -m shell -a "docker inspect promtail-jenkins-vm1-production | jq '.[0].HostConfig.NetworkMode'"
# Expected: "host"

ansible jenkins_masters -m shell -a "docker inspect cadvisor-production | jq '.[0].HostConfig.NetworkMode'"
# Expected: "host"
```

### Step 4: Verify Prometheus Configuration

```bash
# Check cross-VM targets in Prometheus config
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep -A 10 "jenkins-vm"

# Reload Prometheus
docker exec prometheus-production kill -HUP 1

# Verify targets are up
curl -s http://monitoring.internal.local:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.role=="jenkins-vm") | {job: .job, health: .health, instance: .labels.instance}'
```

### Step 5: Verify Data Flow

```bash
# Wait 2-3 minutes for data collection
sleep 180

# Query Jenkins VM metrics
curl -s "http://monitoring.internal.local:9090/api/v1/query?query=node_uname_info{role=\"jenkins-vm\"}" | jq

# Check Loki logs from Jenkins VMs
curl -s "http://monitoring.internal.local:9400/loki/api/v1/label/hostname/values" | jq
```

---

## Summary of Fixes Applied

| Issue | Component | Fix | File |
|-------|-----------|-----|------|
| **Network Isolation** | Promtail | Changed to `network_mode: host` | `cross-vm-exporters.yml:83` |
| **Network Isolation** | Node Exporter | Changed to `network_mode: host` | `cross-vm-exporters.yml:25` |
| **Network Isolation** | cAdvisor | Changed to `network_mode: host`, added `--port` flag | `cross-vm-cadvisor.yml:38,49` |
| **Task Order** | Prometheus Setup | Moved cross-VM tasks BEFORE Prometheus | `main.yml:182-196` |
| **Target Generation** | Prometheus Config | Added cross-VM target variables | `prometheus.yml.j2:32-37,104-109` |

**Deployment**: All fixes applied automatically when running `ansible-playbook ansible/site.yml --tags monitoring`

**Verification**: Use the health check script above to confirm all cross-VM monitoring is working correctly.

---

## Related Documentation

- [Monitoring FQDN Migration Guide](monitoring-fqdn-migration-guide.md)
- [Promtail Container Naming Fix](promtail-container-naming-fix.md)
- [CLAUDE.md - Monitoring Commands](../CLAUDE.md#monitoring-and-alerting)

**Questions or Issues?** Check logs, run verification commands, and review the debugging workflow above.
