# Monitoring Stack - Separate VM Deployment Guide

## Overview

Deploy Prometheus, Grafana, and Loki stack to a dedicated monitoring VM, separate from Jenkins infrastructure for better resource isolation and scalability.

## Architecture

```
┌─────────────────────────────────────────┐
│ Monitoring VM (Dedicated)               │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ Prometheus (9090)                  │ │
│  │  - Scrapes Jenkins VMs            │ │
│  │  - Scrapes HAProxy                │ │
│  │  - Scrapes Node Exporters         │ │
│  └────────────────────────────────────┘ │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ Grafana (9300)                     │ │
│  │  - Datasource: Prometheus          │ │
│  │  - Datasource: Loki                │ │
│  └────────────────────────────────────┘ │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ Loki (9400)                        │ │
│  │  - Receives logs from all VMs     │ │
│  │  - 30-day retention                │ │
│  └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
                    ▲
                    │ Network (TCP)
         ┌──────────┴──────────┐
         │                     │
┌────────▼──────┐    ┌────────▼──────┐
│ Jenkins VM1   │    │ Jenkins VM2   │
│               │    │               │
│ Node Exporter │    │ Node Exporter │
│ Promtail      │    │ Promtail      │
│ Jenkins       │    │ Jenkins       │
└───────────────┘    └───────────────┘
```

## Implementation Steps

### Step 1: Update Inventory

Edit `ansible/inventories/production/hosts.yml`:

```yaml
monitoring:
  hosts:
    monitoring-vm:
      ansible_host: 192.168.188.150  # Separate VM IP
      ansible_user: your_user

jenkins_masters:
  hosts:
    jenkins-vm1:
      ansible_host: 192.168.188.141
    jenkins-vm2:
      ansible_host: 192.168.188.142
```

### Step 2: Deploy Monitoring Stack

```bash
# Deploy to monitoring VM
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring --limit monitoring

# Verify deployment type detection
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring -e "monitoring_deployment_type=separate" --check
```

### Step 3: Configure Firewall

Monitoring stack automatically configures firewall when `monitoring_deployment_type=separate`:

```bash
# Deploy firewall rules
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,firewall --limit monitoring

# Verify firewall rules (RHEL/CentOS)
sudo firewall-cmd --list-all

# Verify firewall rules (Debian/Ubuntu)
sudo ufw status verbose
```

**Ports opened**:
- 9090/tcp - Prometheus
- 9300/tcp - Grafana
- 9100/tcp - Node Exporter
- 9200/tcp - cAdvisor
- 9400/tcp - Loki
- 9401/tcp - Promtail

### Step 4: Deploy Cross-VM Exporters

Deploy Node Exporter and Promtail on all Jenkins VMs:

```bash
# Deploy exporters to Jenkins VMs
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,cross-vm --limit jenkins_masters

# Verify Node Exporter on Jenkins VMs
curl http://192.168.188.141:9100/metrics
curl http://192.168.188.142:9100/metrics

# Verify Promtail on Jenkins VMs
curl http://192.168.188.141:9401/ready
curl http://192.168.188.142:9401/ready
```

## Configuration Variables

All changes are automatic based on inventory. Manual overrides available in `defaults/main.yml`:

```yaml
# Monitoring server addressing (auto-detected)
monitoring_server_address: "{{ ansible_default_ipv4.address | default('localhost') }}"
prometheus_host: "{{ monitoring_server_address }}"
grafana_host: "{{ monitoring_server_address }}"
loki_host: "{{ monitoring_server_address }}"

# Deployment type (auto-detected from inventory)
monitoring_deployment_type: "{{ 'separate' if ... else 'colocated' }}"
```

## Verification

### 1. Check Prometheus Targets

```bash
# Access Prometheus UI
http://<monitoring-vm>:9090/targets

# Or via API
curl http://<monitoring-vm>:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'
```

**Expected targets**:
- `prometheus` - Prometheus self-monitoring
- `node-exporter` - Monitoring VM + all Jenkins VMs
- `cadvisor` - Container metrics
- `jenkins-{team}` - Jenkins metrics from all VMs
- `haproxy` - Load balancer metrics

### 2. Check Grafana Datasources

```bash
# Access Grafana
http://<monitoring-vm>:9300

# Login: admin / admin123 (default)

# Verify datasources
curl -u admin:admin123 http://<monitoring-vm>:9300/api/datasources
```

**Expected datasources**:
- Prometheus: `http://<monitoring-vm>:9090`
- Loki: `http://<monitoring-vm>:9400`

### 3. Check Loki Log Ingestion

```bash
# Query Loki labels
curl http://<monitoring-vm>:9400/loki/api/v1/labels

# Query Jenkins container logs
curl -G http://<monitoring-vm>:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins"}' \
  --data-urlencode 'limit=10'

# Query Jenkins job logs
curl -G http://<monitoring-vm>:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins-job-logs", team="devops"}' \
  --data-urlencode 'limit=10'
```

## Troubleshooting

### Issue: Prometheus can't scrape Jenkins

**Symptoms**: Targets showing as "DOWN" in Prometheus UI

**Check**:
```bash
# From monitoring VM, test connectivity to Jenkins
curl http://192.168.188.141:8080/prometheus
curl http://192.168.188.142:8080/prometheus

# Check firewall on Jenkins VMs
sudo firewall-cmd --list-ports  # RHEL/CentOS
sudo ufw status                 # Debian/Ubuntu
```

**Solution**: Ensure Jenkins web ports (8080-8280) are accessible from monitoring VM

### Issue: Loki not receiving logs

**Symptoms**: No logs in Grafana Explore

**Check**:
```bash
# Check Promtail status on Jenkins VMs (note: container name includes hostname)
docker logs promtail-jenkins-vm1-production
docker logs promtail-jenkins-vm2-production

# Check Promtail on Monitoring VM
docker logs promtail-monitoring-production

# Check Promtail can reach Loki
curl http://<monitoring-vm>:9400/ready

# Check Loki logs
docker logs loki-production
```

**Solution**: Verify Promtail configuration has correct Loki URL (`loki_host` variable)

### Issue: Grafana datasource unhealthy

**Symptoms**: Datasource shows red in Grafana

**Check**:
```bash
# Test datasource connectivity
curl http://<monitoring-vm>:9090/-/healthy  # Prometheus
curl http://<monitoring-vm>:9400/ready      # Loki
```

**Solution**: Check `prometheus_host` and `loki_host` variables in deployment

## Network Requirements

### Monitoring VM → Jenkins VMs (Outbound)
- Port 8080-8280/tcp - Jenkins metrics endpoints
- Port 8404/tcp - HAProxy stats
- Port 9100/tcp - Node Exporter on Jenkins VMs

### Jenkins VMs → Monitoring VM (Outbound)
- Port 9400/tcp - Loki log ingestion

### Client → Monitoring VM (Inbound)
- Port 9300/tcp - Grafana UI access

## Performance Considerations

### Resource Requirements (Monitoring VM)

**Minimum**:
- CPU: 2 cores
- RAM: 4GB
- Disk: 50GB (for 30-day Loki retention + 15-day Prometheus retention)

**Recommended** (for 4 teams, 10 Jenkins instances):
- CPU: 4 cores
- RAM: 8GB
- Disk: 100GB SSD

### Disk Usage Estimates

- **Prometheus**: ~2GB per day (15-day retention = 30GB)
- **Loki**: ~1GB per day (30-day retention = 30GB)
- **Grafana**: <1GB (dashboards and configs)

## Rollback to Co-located Deployment

If needed, revert to co-located deployment:

```bash
# Update inventory to point monitoring group to Jenkins VM
# Then redeploy
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Deployment type auto-detects as 'colocated'
# Firewall and cross-VM tasks are skipped
```

## Related Documentation

- `jenkins-job-logs-with-loki-guide.md` - Jenkins job log collection
- `CLAUDE.md` - Monitoring commands reference
- `docs/MONITORING.md` - Comprehensive monitoring documentation

## Summary

✅ **Separate VM deployment provides**:
- Better resource isolation
- Independent scaling
- Reduced load on Jenkins VMs
- Centralized monitoring for multiple Jenkins instances

✅ **Automatic configuration**:
- Deployment type auto-detected from inventory
- Localhost references replaced with actual IPs
- Firewall rules configured automatically
- Cross-VM exporters deployed as needed

✅ **Zero breaking changes**:
- Co-located deployment still supported
- Backward compatible with existing setups
- Same commands for both deployment types
