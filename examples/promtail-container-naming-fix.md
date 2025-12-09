# Promtail Container Naming Fix - Implementation Summary

## Problem Identified

**Issue:** Container name collision between two Promtail deployments in separate VM monitoring architecture.

**Reporter:** User identified during code review

**Impact:**
- Both `loki.yml` and `cross-vm-exporters.yml` deployed Promtail with same container name: `promtail-{{ deployment_environment }}`
- This caused conflicts when deploying to separate VMs
- Monitoring VM's Promtail would be overwritten OR Jenkins VM deployments would fail

## Root Cause Analysis

### Deployment Architecture
In separate VM monitoring setup:

**Monitoring VM:**
- Loki (receives logs)
- Prometheus (scrapes metrics)
- Grafana (visualization)
- Promtail (collects logs from monitoring VM itself)

**Jenkins VMs (multiple):**
- Node Exporter (system metrics)
- Promtail (collects Jenkins job logs + system logs)
- cAdvisor (container metrics)

### The Conflict

**File 1: `ansible/roles/monitoring/tasks/loki.yml`**
- Deploys Promtail on monitoring VM (where task runs)
- Container name: `promtail-{{ deployment_environment }}`
- Purpose: Collect Loki, Prometheus, Grafana logs

**File 2: `ansible/roles/monitoring/tasks/cross-vm-exporters.yml`**
- Deploys Promtail on Jenkins VMs via `delegate_to`
- Container name: `promtail-{{ deployment_environment }}` (SAME!)
- Purpose: Collect Jenkins job logs + system logs

**Result:** Name collision causing deployment failures or overwrites.

## Solution Implemented: Option 1 - Different Container Names

### Design Decision

Chosen approach: **Unique container names based on purpose and hostname**

**Why this approach:**
1. ✅ Both VMs can run Promtail independently
2. ✅ Clear naming convention shows purpose
3. ✅ Monitoring VM collects its own logs (Loki/Prometheus/Grafana)
4. ✅ Each Jenkins VM collects Jenkins + system logs
5. ✅ No complex conditionals needed
6. ✅ Easy to identify which Promtail is which

### Naming Convention

**Monitoring VM Promtail:**
```
promtail-monitoring-{{ deployment_environment }}
```
Examples: `promtail-monitoring-production`, `promtail-monitoring-local`

**Jenkins VM Promtail:**
```
promtail-{{ inventory_hostname_short }}-{{ deployment_environment }}
```
Examples:
- `promtail-jenkins-vm1-production`
- `promtail-jenkins-vm2-production`
- `promtail-jenkins-vm1-local`

## Files Modified

### 1. ansible/roles/monitoring/tasks/loki.yml

**Change:** Updated Promtail container name

**Before:**
```yaml
- name: Deploy Promtail container
  community.docker.docker_container:
    name: promtail-{{ deployment_environment | default('local') }}
```

**After:**
```yaml
- name: Deploy Promtail container on Monitoring VM
  community.docker.docker_container:
    name: promtail-monitoring-{{ deployment_environment | default('local') }}
```

**Impact:** Monitoring VM Promtail now has unique name identifying its purpose

### 2. ansible/roles/monitoring/tasks/cross-vm-exporters.yml

**Change:** Updated Promtail container name to include hostname

**Before:**
```yaml
- name: Deploy Promtail container on Jenkins VMs
  community.docker.docker_container:
    name: promtail-{{ deployment_environment | default('local') }}
  delegate_to: "{{ item }}"
  loop: "{{ groups['jenkins_masters'] }}"
```

**After:**
```yaml
- name: Deploy Promtail container on Jenkins VMs
  community.docker.docker_container:
    name: "promtail-{{ hostvars[item]['inventory_hostname_short'] }}-{{ deployment_environment | default('local') }}"
  delegate_to: "{{ item }}"
  loop: "{{ groups['jenkins_masters'] }}"
```

**Impact:** Each Jenkins VM gets unique Promtail container name based on hostname

### 3. ansible/roles/monitoring/handlers/main.yml

**Change:** Updated restart handler for Promtail

**Before:**
```yaml
- name: restart promtail
  community.docker.docker_container:
    name: promtail-{{ deployment_environment | default('local') }}
    state: started
    restart: yes
  listen: "restart promtail"
```

**After:**
```yaml
- name: restart promtail
  community.docker.docker_container:
    name: promtail-monitoring-{{ deployment_environment | default('local') }}
    state: started
    restart: yes
  listen: "restart promtail"
```

**Impact:** Handler now restarts correct Promtail container on monitoring VM

**Note:** Jenkins VM Promtail containers are restarted via cross-vm tasks, not handlers

### 4. CLAUDE.md

**Changes:** Updated all Promtail docker commands to reflect new naming

**Sections Updated:**
- Monitoring Verification commands
- Monitoring Health Checks commands

**Before:**
```bash
docker logs promtail-production
docker exec promtail-production ls -la /jenkins-logs/
```

**After:**
```bash
# Monitoring VM
docker logs promtail-monitoring-production

# Jenkins VMs
docker logs promtail-jenkins-vm1-production
docker exec promtail-jenkins-vm1-production ls -la /jenkins-logs/
```

### 5. examples/monitoring-separate-vm-deployment-guide.md

**Changes:** Updated troubleshooting commands

**Section:** "Issue: Loki not receiving logs"

**After:**
```bash
# Check Promtail status on Jenkins VMs (note: container name includes hostname)
docker logs promtail-jenkins-vm1-production
docker logs promtail-jenkins-vm2-production

# Check Promtail on Monitoring VM
docker logs promtail-monitoring-production
```

### 6. examples/jenkins-job-logs-with-loki-guide.md

**Changes:** Updated verification and troubleshooting commands

**Sections Updated:**
- "Check Volume Mounts" verification
- "Issue: No job logs in Loki" troubleshooting
- "Issue: Logs not updating" troubleshooting

**After:**
```bash
# Verify Promtail on Jenkins VMs has access to Jenkins volumes
# Note: Container name includes hostname (e.g., promtail-jenkins-vm1-production)
docker exec promtail-jenkins-vm1-production ls -la /jenkins-logs/

docker logs promtail-jenkins-vm1-production | grep "jenkins-job-logs"
docker exec promtail-jenkins-vm1-production cat /promtail/positions.yaml
```

## Deployment Impact

### Backward Compatibility

**⚠️ BREAKING CHANGE** for existing separate VM deployments:

**Existing Deployments:**
- Old Promtail containers will remain with old names
- New deployment will create new containers with new names
- Old containers should be manually stopped and removed

**Migration Steps:**
```bash
# On Monitoring VM
docker stop promtail-production
docker rm promtail-production

# On each Jenkins VM
docker stop promtail-production
docker rm promtail-production

# Redeploy monitoring
ansible-playbook ansible/site.yml --tags monitoring
```

### New Deployments

No impact - new naming convention applies automatically.

### Colocated Deployments

**No impact** - colocated deployments (monitoring + Jenkins on same VM) only deploy monitoring VM Promtail from `loki.yml`, so naming change is transparent.

## Verification

### 1. Check Container Names

**Monitoring VM:**
```bash
docker ps | grep promtail
# Expected: promtail-monitoring-production
```

**Jenkins VM 1:**
```bash
docker ps | grep promtail
# Expected: promtail-jenkins-vm1-production
```

**Jenkins VM 2:**
```bash
docker ps | grep promtail
# Expected: promtail-jenkins-vm2-production
```

### 2. Verify Functionality

**All Promtail containers should:**
- Be running
- Have correct volume mounts
- Be pushing logs to Loki
- Show in Loki targets

**Test:**
```bash
# Check Loki receives logs from all Promtails
curl http://monitoring-vm:9400/loki/api/v1/label/hostname/values

# Should show: monitoring-vm, jenkins-vm1, jenkins-vm2
```

### 3. Verify No Conflicts

**Check for duplicate containers:**
```bash
# On any VM - should NOT see multiple promtail containers with same name
docker ps -a | grep promtail
```

## Benefits

### 1. Clear Identification
Container names now clearly show:
- **Purpose:** `monitoring` vs VM-specific
- **Location:** Which VM the container runs on
- **Environment:** production/local

### 2. Easier Debugging
```bash
# Immediately know which Promtail you're debugging
docker logs promtail-jenkins-vm1-production   # Jenkins VM 1 logs
docker logs promtail-monitoring-production    # Monitoring VM logs
```

### 3. Independent Scaling
Each Jenkins VM can independently:
- Restart Promtail without affecting others
- Configure different scrape configs (if needed)
- Troubleshoot without impacting monitoring VM

### 4. Monitoring Visibility
Monitoring dashboards can now:
- Show per-VM Promtail status
- Track log collection per source VM
- Alert on specific VM Promtail failures

## Alternative Solutions Considered

### Option 2: Deploy Promtail Only on Jenkins VMs

**Approach:** Remove Promtail from monitoring VM entirely

**Pros:**
- Simpler - only one Promtail deployment
- Logs collected at source

**Cons:**
- ❌ Monitoring VM's own logs not collected (Loki, Prometheus, Grafana)
- ❌ Incomplete observability

**Verdict:** Rejected - need complete log collection

### Option 3: Conditional Deployment Based on Host

**Approach:** Deploy different Promtail based on host group membership

**Pros:**
- Single deployment task
- Conditional logic handles differences

**Cons:**
- ❌ Complex Jinja2 conditionals in templates
- ❌ Harder to understand/maintain
- ❌ Still need different container names

**Verdict:** Rejected - unnecessary complexity

## Testing Recommendations

### Unit Testing
```bash
# Test template rendering
ansible-playbook ansible/site.yml --tags monitoring --check --diff

# Verify no syntax errors
ansible-playbook ansible/site.yml --syntax-check
```

### Integration Testing

**Local Environment:**
```bash
# Deploy to local test environment
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags monitoring

# Verify container names
docker ps | grep promtail

# Check logs flow to Loki
curl http://localhost:9400/loki/api/v1/label/hostname/values
```

**Separate VM Environment:**
```bash
# Deploy to separate VM setup
ansible-playbook -i ansible/inventories/test/hosts.yml ansible/site.yml --tags monitoring

# Verify on monitoring VM
ssh monitoring-vm "docker ps | grep promtail"
# Expected: promtail-monitoring-local

# Verify on Jenkins VMs
ssh jenkins-vm1 "docker ps | grep promtail"
ssh jenkins-vm2 "docker ps | grep promtail"
# Expected: promtail-<hostname>-local

# Test log collection
curl http://monitoring-vm:9400/loki/api/v1/query --data-urlencode 'query={job="jenkins-job-logs"}' | jq
```

## Rollback Procedure

If issues arise:

### 1. Stop New Containers
```bash
# Monitoring VM
docker stop promtail-monitoring-production
docker rm promtail-monitoring-production

# Jenkins VMs
docker stop promtail-jenkins-vm1-production
docker rm promtail-jenkins-vm1-production
```

### 2. Revert Code
```bash
git revert <commit-hash>
```

### 3. Redeploy Old Version
```bash
ansible-playbook ansible/site.yml --tags monitoring
```

### 4. Start Old Containers (if still present)
```bash
docker start promtail-production
```

## Future Enhancements

### 1. Dynamic Container Discovery
Update Prometheus/Grafana dashboards to auto-discover Promtail containers by pattern matching `promtail-*`.

### 2. Health Check Aggregation
Create aggregated health check showing status of all Promtail containers across all VMs.

### 3. Centralized Configuration
Consider shared Promtail configuration with VM-specific overrides to reduce duplication.

## Conclusion

**Status:** ✅ Implementation Complete

**Result:**
- No more Promtail container name conflicts
- Clear identification of Promtail purpose and location
- Complete log collection from both monitoring and Jenkins VMs
- Improved debuggability and operational clarity

**Documentation Updated:**
- CLAUDE.md commands
- Monitoring deployment guide
- Jenkins job logs guide

**Next Steps:**
1. Test in local environment
2. Test in staging with separate VMs
3. Document migration procedure for existing deployments
4. Deploy to production

---

**Document Version:** 1.0
**Date:** 2025-01-15
**Issue:** Promtail container name collision
**Resolution:** Unique naming convention per VM and purpose
**Status:** Complete
