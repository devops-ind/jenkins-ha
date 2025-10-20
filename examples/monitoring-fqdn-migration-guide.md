# Monitoring FQDN Infrastructure Migration Guide

## Overview

This guide covers migrating the Jenkins HA monitoring stack from IP-based addressing to FQDN-based infrastructure addressing. The implementation supports seamless migration with backward compatibility and rollback capabilities.

**Feature:** Infrastructure-level FQDN support for monitoring components
**Impact:** Enables DNS-based service discovery, HA failover, and network flexibility
**Status:** Implemented with toggle-based migration support

---

## Table of Contents
1. [Understanding the Change](#understanding-the-change)
2. [DNS Requirements](#dns-requirements)
3. [Configuration Guide](#configuration-guide)
4. [Migration Procedure](#migration-procedure)
5. [Verification](#verification)
6. [Rollback](#rollback)
7. [Troubleshooting](#troubleshooting)

---

## Understanding the Change

### Two Levels of Addressing

The Jenkins HA infrastructure uses **two distinct addressing levels**:

#### 1. Application-Level (Client Access)
**Purpose:** External client access to web services
**Examples:**
- `devopsjenkins.devops.example.com` → Jenkins UI
- `grafana.devops.example.com` → Grafana dashboard
- `prometheus.devops.example.com` → Prometheus UI

**Configuration:**
```yaml
jenkins_domain: "devops.example.com"
monitoring_domain: "devops.example.com"
```

**Status:** Already implemented and working ✅

#### 2. Infrastructure-Level (Internal Communication)
**Purpose:** Inter-service communication between components
**Examples:**
- Prometheus → Jenkins metrics scraping
- Promtail → Loki log shipping
- Node Exporter → Prometheus target monitoring

**Configuration:**
```yaml
# NEW: FQDN variables for infrastructure addressing
host_fqdn: centos9-vm.internal.local
monitoring_fqdn: monitoring.internal.local
```

**Status:** NEW - Implemented in this update 🆕

### What Changed

**Before (IP-Based):**
```yaml
# Prometheus scrapes Jenkins at IP
jenkins-devops:
  targets: ['192.168.188.142:8080']

# Promtail sends logs to Loki at IP
clients:
  - url: http://192.168.188.142:9400/loki/api/v1/push
```

**After (FQDN-Based):**
```yaml
# Prometheus scrapes Jenkins at FQDN
jenkins-devops:
  targets: ['centos9-vm.internal.local:8080']

# Promtail sends logs to Loki at FQDN
clients:
  - url: http://monitoring.internal.local:9400/loki/api/v1/push
```

### Benefits

✅ **DNS-Based Service Discovery:** Services resolve to correct IPs automatically
✅ **HA/Failover Support:** Use DNS for VIP/floating IP resolution
✅ **Network Flexibility:** Survive IP changes via DNS updates
✅ **Cloud Ready:** Works with dynamic IP allocation
✅ **Better Readability:** FQDNs more readable than IPs
✅ **Certificate Compatibility:** SSL certificates can match FQDNs

---

## DNS Requirements

### Option 1: Production DNS Server (Recommended)

Configure A records in your DNS server:

```dns
; Infrastructure FQDNs
centos9-vm.internal.local.         A    192.168.188.142
centos9-vm2.internal.local.        A    192.168.188.143
monitoring.internal.local.         A    192.168.188.142

; Optional: CNAME for service discovery
prometheus.internal.local.         CNAME monitoring.internal.local.
grafana.internal.local.            CNAME monitoring.internal.local.
loki.internal.local.               CNAME monitoring.internal.local.
```

**Test DNS Resolution:**
```bash
# On monitoring VM
dig +short centos9-vm.internal.local
# Should return: 192.168.188.142

# On Jenkins VM
dig +short monitoring.internal.local
# Should return: 192.168.188.142
```

### Option 2: /etc/hosts (Development/Testing)

Add entries to `/etc/hosts` on **all VMs**:

```bash
# Edit /etc/hosts on monitoring VM
sudo tee -a /etc/hosts <<EOF
# Infrastructure FQDNs
192.168.188.142 centos9-vm.internal.local centos9-vm
192.168.188.143 centos9-vm2.internal.local centos9-vm2
192.168.188.142 monitoring.internal.local monitoring
EOF

# Edit /etc/hosts on Jenkins VMs
sudo tee -a /etc/hosts <<EOF
# Monitoring server FQDN
192.168.188.142 monitoring.internal.local monitoring
192.168.188.142 centos9-vm.internal.local centos9-vm
192.168.188.143 centos9-vm2.internal.local centos9-vm2
EOF
```

**Test /etc/hosts Resolution:**
```bash
# On any VM
ping -c 2 monitoring.internal.local
ping -c 2 centos9-vm.internal.local
```

### Option 3: Local DNS Server (Advanced)

Deploy dnsmasq or BIND on your network for dynamic DNS management.

---

## Configuration Guide

### Step 1: Update Inventory Files

#### Production Inventory

**File:** `ansible/inventories/production/hosts.yml`

Add FQDN variables to each host:

```yaml
jenkins_masters:
  hosts:
    centos9-vm:
      ansible_host: 192.168.188.142  # Keep for SSH connection
      ansible_port: 22
      # NEW: Infrastructure FQDNs
      host_fqdn: centos9-vm.internal.local        # This host's FQDN
      monitoring_fqdn: monitoring.internal.local  # Monitoring server FQDN

    centos9-vm2:
      ansible_host: 192.168.188.143
      ansible_port: 22
      host_fqdn: centos9-vm2.internal.local
      monitoring_fqdn: monitoring.internal.local

monitoring:
  hosts:
    centos9-vm:
      ansible_host: 192.168.188.142
      host_fqdn: monitoring.internal.local        # This is the monitoring server
      monitoring_fqdn: monitoring.internal.local  # Self-reference
```

**Notes:**
- `ansible_host` remains IP for SSH connection (no change)
- `host_fqdn` is the FQDN for **this specific host**
- `monitoring_fqdn` is the FQDN of the **monitoring server** (same for all)

#### Local Development Inventory

**File:** `ansible/inventories/local/hosts.yml`

```yaml
jenkins_masters:
  hosts:
    jenkins-master-local:
      ansible_connection: local
      ansible_host: localhost
      host_fqdn: localhost            # Use localhost for local dev
      monitoring_fqdn: localhost

monitoring:
  hosts:
    monitoring-local:
      ansible_connection: local
      ansible_host: localhost
      host_fqdn: localhost
      monitoring_fqdn: localhost
```

### Step 2: Configure FQDN Settings

The defaults are already configured in `ansible/roles/monitoring/defaults/main.yml`:

```yaml
# FQDN Configuration
monitoring_use_fqdn: true  # Set to false for IP-based (backward compatibility)
monitoring_fqdn_suffix: "internal.local"  # Default domain suffix
```

**To use IP-based addressing (migration step 1):**
```yaml
monitoring_use_fqdn: false
```

**To use FQDN-based addressing (migration step 3):**
```yaml
monitoring_use_fqdn: true
```

### Step 3: FQDN Resolution Hierarchy

The monitoring role resolves FQDNs in this order:

1. **Explicit monitoring_fqdn** (if defined in inventory)
2. **Explicit host_fqdn** (if defined in inventory)
3. **inventory_hostname** (if contains a dot, e.g., "vm.example.com")
4. **inventory_hostname + suffix** (e.g., "centos9-vm" + ".internal.local")
5. **IP address fallback** (ansible_default_ipv4.address)

**Example Resolution:**
```yaml
# Inventory:
host_fqdn: centos9-vm.internal.local

# Result: Uses "centos9-vm.internal.local"
```

```yaml
# Inventory:
inventory_hostname: vm1.example.com
# (no host_fqdn defined)

# Result: Uses "vm1.example.com"
```

---

## Migration Procedure

### Phase 1: Add FQDN Variables (No Behavioral Change)

**Objective:** Add FQDN configuration while keeping IP-based addressing

**Steps:**

1. **Add FQDN variables to inventory** (completed above)

2. **Verify configuration without deployment:**
```bash
# Dry-run to check syntax
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring --check --diff
```

3. **Set FQDN mode to FALSE** (if not already):
```bash
# In ansible/inventories/production/group_vars/all/main.yml
# OR ansible/roles/monitoring/defaults/main.yml
monitoring_use_fqdn: false
```

4. **Deploy with IP-based addressing:**
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring
```

5. **Verify system still uses IPs:**
```bash
# Check Prometheus targets
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep -A 3 "targets:"

# Should show IPs like:
# targets: ['192.168.188.142:8080']
```

**Result:** System behaves exactly as before, FQDNs configured but not used ✅

### Phase 2: Setup DNS Infrastructure

**Objective:** Ensure DNS resolution works before switching

**Steps:**

1. **Configure DNS** (choose one):
   - Production DNS server (recommended)
   - /etc/hosts entries
   - Local dnsmasq

2. **Test DNS from monitoring VM:**
```bash
# Test all Jenkins VM FQDNs
for host in centos9-vm.internal.local centos9-vm2.internal.local; do
  echo "Testing: $host"
  dig +short $host || nslookup $host || getent hosts $host
done
```

3. **Test DNS from Jenkins VMs:**
```bash
# Test monitoring server FQDN
dig +short monitoring.internal.local || nslookup monitoring.internal.local
```

4. **Test connectivity via FQDN:**
```bash
# From monitoring VM
ping -c 2 centos9-vm.internal.local
curl -v http://centos9-vm.internal.local:9100/metrics

# From Jenkins VM
ping -c 2 monitoring.internal.local
curl -v http://monitoring.internal.local:9400/ready
```

**Result:** All FQDNs resolve correctly and services are reachable ✅

### Phase 3: Enable FQDN Mode

**Objective:** Switch monitoring stack to use FQDNs

**Steps:**

1. **Enable FQDN mode:**
```yaml
# In ansible/inventories/production/group_vars/all/main.yml
# OR set via command line
monitoring_use_fqdn: true
```

2. **Deploy with FQDN addressing:**
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring -e "monitoring_use_fqdn=true"
```

3. **Monitor deployment output:**
```
TASK [monitoring : Display cross-VM exporters deployment summary]
ok: [centos9-vm] => {
    "msg": "
      Verification:
      - Node Exporter on centos9-vm: http://centos9-vm.internal.local:9100/metrics
      - Promtail on centos9-vm: http://centos9-vm.internal.local:9401/ready
```

**Result:** System now uses FQDNs for all internal communication ✅

### Phase 4: Validation

**Objective:** Verify FQDN-based monitoring works correctly

See [Verification](#verification) section below.

---

## Verification

### 1. Check Prometheus Targets

```bash
# View Prometheus configuration
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep -A 5 "targets:"

# Expected FQDN format:
# - targets:
#   - centos9-vm.internal.local:8080
#   - centos9-vm2.internal.local:8080
```

**Via Prometheus UI:**
```
http://monitoring.internal.local:9090/targets
# Or
http://192.168.188.142:9090/targets

# Check target status - should show FQDNs like:
# centos9-vm.internal.local:8080 (UP)
# centos9-vm.internal.local:9100 (UP)
```

### 2. Check Promtail Configuration

```bash
# On Jenkins VM
docker exec promtail-centos9-vm-production cat /etc/promtail/promtail-config.yml | grep -A 2 "clients:"

# Expected output:
# clients:
#   - url: http://monitoring.internal.local:9400/loki/api/v1/push
```

**Test log shipping:**
```bash
# Check Promtail logs for FQDN usage
docker logs promtail-centos9-vm-production 2>&1 | grep -i "loki"

# Should show: http://monitoring.internal.local:9400/loki/api/v1/push
```

### 3. Check Grafana Datasources

```bash
# Check datasource configuration
curl -s -u admin:admin http://monitoring.internal.local:9300/api/datasources | jq

# Prometheus datasource should show:
# "url": "http://monitoring.internal.local:9090"

# Loki datasource should show:
# "url": "http://monitoring.internal.local:9400"
```

### 4. Verify Metrics Collection

```bash
# Query Jenkins metrics via Prometheus
curl -s 'http://monitoring.internal.local:9090/api/v1/query?query=up{job="jenkins-devops"}' | jq

# Should return: "value": [timestamp, "1"]  (indicating UP status)

# Query logs via Loki
curl -s 'http://monitoring.internal.local:9400/loki/api/v1/query?query={job="jenkins-job-logs"}' | jq
```

### 5. Check Agent Health

```bash
# On Jenkins VMs - check agent health monitor
sudo tail -f /var/log/monitoring-agents/health-check.log

# Should show:
# [INFO] Monitoring server: monitoring.internal.local
# [OK] Loki Server: http://monitoring.internal.local:9400/ready
```

---

## Rollback

If issues arise, revert to IP-based addressing:

### Quick Rollback

```bash
# 1. Disable FQDN mode
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring -e "monitoring_use_fqdn=false"

# 2. Verify IP-based configuration
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep targets:

# Should show IPs: 192.168.188.142:8080
```

### Persistent Rollback

```yaml
# Edit group_vars/all/main.yml or inventory
monitoring_use_fqdn: false

# Redeploy
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring
```

### Remove FQDN Variables (Full Rollback)

If you want to completely remove FQDN support:

```yaml
# Remove from inventory
# Delete these lines:
# host_fqdn: ...
# monitoring_fqdn: ...

# Set defaults back
monitoring_use_fqdn: false

# Redeploy
ansible-playbook ansible/site.yml --tags monitoring
```

---

## Troubleshooting

### Issue 1: Targets show as DOWN in Prometheus

**Symptoms:** Prometheus shows FQDN targets as DOWN/UNAVAILABLE

**Diagnosis:**
```bash
# Test DNS resolution from monitoring VM
dig +short centos9-vm.internal.local

# Test connectivity
curl -v http://centos9-vm.internal.local:9100/metrics
```

**Solutions:**
1. **DNS not configured:** Add DNS entries or /etc/hosts
2. **Firewall blocking:** Open ports 8080, 9100, 9401, 9200
3. **Wrong FQDN:** Check inventory `host_fqdn` matches DNS records

### Issue 2: Promtail can't send logs to Loki

**Symptoms:** No logs in Grafana, Promtail shows connection errors

**Diagnosis:**
```bash
# Check Promtail logs
docker logs promtail-centos9-vm-production 2>&1 | grep -i error

# Test Loki connectivity
curl -v http://monitoring.internal.local:9400/ready
```

**Solutions:**
1. **DNS issues:** Verify `monitoring_fqdn` in inventory
2. **Network issues:** Check routing between Jenkins VM and monitoring VM
3. **Loki down:** Check Loki container status

### Issue 3: Mixed IP/FQDN in configuration

**Symptoms:** Some targets use FQDNs, others use IPs

**Diagnosis:**
```bash
# Check all Prometheus targets
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep "targets:" -A 2
```

**Solutions:**
1. **Incomplete migration:** Ensure all hosts have `host_fqdn` defined
2. **Missing monitoring_fqdn:** Add to all Jenkins master hosts
3. **Stale configuration:** Redeploy monitoring role

### Issue 4: DNS resolution fails on some VMs

**Symptoms:** Some VMs can't resolve FQDNs

**Diagnosis:**
```bash
# On affected VM
cat /etc/resolv.conf
nslookup monitoring.internal.local
getent hosts monitoring.internal.local
```

**Solutions:**
1. **/etc/hosts:** Add entries on all VMs
2. **DNS server:** Configure nameserver in /etc/resolv.conf
3. **Network config:** Check systemd-resolved or NetworkManager DNS settings

### Issue 5: Ansible deployment fails with "host not found"

**Symptoms:** Ansible deployment fails during URI tasks

**Diagnosis:**
```bash
# From Ansible control machine
ansible -i inventories/production/hosts.yml monitoring -m shell -a "dig +short monitoring.internal.local"
```

**Solutions:**
1. **DNS on Ansible host:** Ensure Ansible control node can resolve FQDNs
2. **Wrong host_fqdn:** Check inventory variable spelling/format
3. **Fallback:** Set `monitoring_use_fqdn: false` temporarily

---

## Best Practices

### 1. DNS Management
- Use production DNS server for production deployments
- Keep /etc/hosts as backup for critical services
- Document DNS records in repository (dns-records.txt)
- Test DNS changes before applying to monitoring

### 2. Migration Planning
- Migrate non-production environments first (dev, staging)
- Schedule migration during maintenance window
- Have rollback plan ready
- Test thoroughly before production

### 3. Monitoring During Migration
- Watch Prometheus targets during migration
- Monitor Loki log ingestion rates
- Check Grafana dashboards for gaps
- Set up alerts for target down events

### 4. Documentation
- Document FQDN scheme (e.g., {hostname}.internal.local)
- Keep DNS records up to date
- Update runbooks with FQDN information
- Train team on FQDN troubleshooting

---

## Related Documentation

- [Separate VM Monitoring Deployment Guide](monitoring-separate-vm-deployment-guide.md)
- [Jenkins Job Logs with Loki Guide](jenkins-job-logs-with-loki-guide.md)
- [Monitoring Agent Architecture](monitoring-agent-architecture-implementation.md)
- [Promtail Container Naming Fix](promtail-container-naming-fix.md)

---

## References

- [Ansible Variables Documentation](https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Grafana Datasource Configuration](https://grafana.com/docs/grafana/latest/datasources/)
- [DNS Best Practices](https://www.rfc-editor.org/rfc/rfc1912)

---

**Document Version:** 1.0
**Last Updated:** 2025-01-15
**Author:** Jenkins HA Infrastructure Team
**Status:** Production Ready
