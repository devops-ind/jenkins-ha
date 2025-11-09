# Infrastructure Deployment Plan

## Overview

Unified Jenkins pipeline for deploying infrastructure components (Jenkins Masters, HAProxy, Monitoring) with support for blue-green deployment, data recovery from GlusterFS, validation, and manual approval gates.

---

## Architecture

### VM Layout
```
VM1 (jenkins_hosts_01)
├── Jenkins Masters (4 teams: devops, ma, ba, tw)
├── HAProxy
└── GlusterFS client mounts

VM2 (jenkins_hosts_02)
├── Jenkins Masters (4 teams: devops, ma, ba, tw)
├── HAProxy
└── GlusterFS client mounts

VM3 (monitoring)
├── Prometheus
├── Grafana
├── Loki
├── Alertmanager
└── Cross-VM agents
```

### Active/Passive Strategy
**Hybrid Model:** Combination of per-team and VM-level
- **Per-Team:** Each team has `active_environment: blue|green` in inventory
- **VM-Level:** Entire VM can be active or passive for disaster recovery
- **Example:**
  ```yaml
  # Team A: blue active on VM1, green passive on VM1
  # Team B: green active on VM2, blue passive on VM2
  # Team C: blue active on VM1, green passive on VM1
  # Team D: green active on VM1, blue passive on VM1
  ```

### GlusterFS Data Flow
```
Active Jenkins Container (Docker Volume)
    │
    ↓ (rsync every 5 min via cron)
GlusterFS Sync Layer (/var/jenkins/{team}/sync/{env})
    │
    ↓ (GlusterFS replication)
VM1 ↔ VM2 (automatic replication)
    │
    ↓ (during deployment)
Passive Jenkins Container (Docker Volume)
    ← (recovery script: jenkins-recover-from-gluster.sh)
```

---

## Job 1: Unified Infrastructure Deployment Pipeline

### Job Name
`Infrastructure-Deployment`

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `COMPONENT` | Choice | jenkins-masters | Component to deploy: jenkins-masters, haproxy, monitoring, all |
| `TARGET_VM` | Choice | jenkins_hosts_01 | Target VM: jenkins_hosts_01, jenkins_hosts_02, monitoring, all |
| `DEPLOY_TEAMS` | String | all | Teams to deploy (comma-separated): devops,ma OR all |
| `TARGET_ENVIRONMENT` | Choice | auto | Blue-green environment: blue, green, auto (detect passive) |
| `SKIP_DATA_RECOVERY` | Boolean | false | Skip GlusterFS data recovery (for fresh deployment) |
| `SKIP_VALIDATION` | Boolean | false | Skip post-deployment validation tests |
| `DRY_RUN` | Boolean | false | Dry-run mode (Ansible --check) |
| `AUTO_SWITCH` | Boolean | false | Automatically switch after validation (no approval gate) |
| `NOTIFICATION_CHANNEL` | String | teams | Notification channel: teams, email, both |

### Pipeline Stages

#### Stage 1: Pre-Flight Validation (3-5 min)
**Purpose:** Validate repository, inventory, and current state before deployment

**Tasks:**
- ✅ Clone repository (or use SCM checkout)
- ✅ Validate Ansible syntax (`ansible-playbook --syntax-check`)
- ✅ Validate inventory structure
- ✅ SSH connectivity check to target VMs
- ✅ Detect current active/passive state per team
- ✅ Verify GlusterFS mounts are accessible
- ✅ Check disk space on target VMs (>20GB free)

**Ansible Playbook:** Leverage existing `ansible/site.yml --tags validate`

**Output:**
```
Pre-Flight Validation Results:
✓ Ansible syntax: PASSED
✓ Inventory: PASSED (4 teams, 3 VMs)
✓ SSH connectivity: jenkins_hosts_01 ✓, jenkins_hosts_02 ✓, monitoring ✓
✓ Current state:
  - devops: blue (VM1 active), green (VM1 passive)
  - ma: green (VM2 active), blue (VM2 passive)
  - ba: blue (VM1 active), green (VM1 passive)
  - tw: green (VM1 active), blue (VM1 passive)
✓ GlusterFS: /var/jenkins/devops/sync/blue accessible
✓ Disk space: VM1 (45GB free), VM2 (52GB free), VM3 (38GB free)
```

**Exit Criteria:**
- All checks must pass
- If any check fails, pipeline stops with detailed error message

---

#### Stage 2: Component-Specific Deployment

##### Stage 2A: Jenkins Masters Deployment (15-25 min)
**Condition:** `COMPONENT == 'jenkins-masters' || COMPONENT == 'all'`

**Sub-Stage 2A.1: Data Recovery from GlusterFS (5-10 min)**
**Purpose:** Copy latest data from GlusterFS to passive environment Docker volumes

**Tasks:**
- Determine passive environment for each team
- Run recovery script: `/usr/local/bin/jenkins-recover-from-gluster-{team}.sh`
- Verify data integrity (check critical files exist)
- Compare data size between active and passive

**Ansible Playbook:** Create new playbook `ansible/playbooks/jenkins-data-recovery.yml`
```yaml
---
- name: Recover Jenkins data from GlusterFS
  hosts: "{{ target_vm | default('jenkins_masters') }}"
  tasks:
    - name: Run GlusterFS recovery for each team
      command: >
        /usr/local/bin/jenkins-recover-from-gluster-{{ item.team_name }}.sh
        {{ item.team_name }}
        {{ passive_environment }}
      loop: "{{ jenkins_teams_filtered }}"
      when: not skip_data_recovery | default(false)
```

**Output:**
```
Data Recovery Results:
✓ devops: Recovered 2.3GB from GlusterFS to green environment
  - Jobs: 45 jobs recovered
  - Plugins: 78 plugins verified
  - Config: jenkins.xml present
✓ ma: Recovered 1.8GB from GlusterFS to blue environment
✓ ba: Recovered 2.1GB from GlusterFS to green environment
✓ tw: Recovered 1.5GB from GlusterFS to blue environment
```

**Sub-Stage 2A.2: Deploy Jenkins Containers (10-15 min)**
**Purpose:** Deploy Jenkins masters to passive environment

**Tasks:**
- Deploy Jenkins containers to passive environment
- Use existing `ansible/site.yml --tags jenkins`
- Leverage team filtering: `-e "deploy_teams=${DEPLOY_TEAMS}"`
- Deploy to specific VM: `--limit ${TARGET_VM}`

**Ansible Command:**
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "deploy_teams=${DEPLOY_TEAMS}" \
  --limit ${TARGET_VM} \
  ${DRY_RUN ? '--check' : ''}
```

**Output:**
```
Jenkins Deployment Results:
✓ VM: jenkins_hosts_01
  ✓ devops-green: Container started, health check passed
  ✓ ba-green: Container started, health check passed
  ✓ tw-blue: Container started, health check passed
```

**Sub-Stage 2A.3: Post-Deployment Validation (5-10 min)**
**Purpose:** Verify passive environment is identical to active

**Validation Tests:**

1. **Container Health Check**
   - Container running
   - HTTP 200/403 on `/login` endpoint
   - Jenkins process active inside container

2. **Data Integrity Check**
   - Compare job count: active vs passive
   - Compare plugin count: active vs passive
   - Verify critical files exist (config.xml, credentials.xml)

3. **Configuration Drift Detection**
   - Compare JCasC configuration
   - Compare system configuration
   - Compare security settings

4. **Startup Validation**
   - Check Jenkins logs for errors
   - Verify no plugin failures
   - Verify Job DSL seed job present

5. **Performance Baseline**
   - Measure startup time
   - Check memory usage
   - Check CPU usage

**Ansible Playbook:** Create `ansible/playbooks/jenkins-validation.yml`

**Validation Script:** Create `scripts/jenkins-deployment-validator.sh`
```bash
#!/bin/bash
# Validates passive Jenkins is identical to active
# Returns 0 if validation passes, 1 if fails
```

**Output:**
```
Validation Results (Passive Environment):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Team: devops (green environment on VM1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Container Health:    PASSED (HTTP 200, process running)
✓ Job Count:           PASSED (45 jobs - matches active)
✓ Plugin Count:        PASSED (78 plugins - matches active)
✓ Configuration Drift: PASSED (no drift detected)
✓ Startup Time:        PASSED (45 seconds)
✓ Memory Usage:        PASSED (1.2GB / 3GB limit)

Active vs Passive Comparison:
┌──────────────────┬─────────────┬──────────────┬─────────┐
│ Metric           │ Active (blue)│ Passive (green)│ Status │
├──────────────────┼─────────────┼──────────────┼─────────┤
│ Jobs             │ 45          │ 45           │ ✓       │
│ Plugins          │ 78          │ 78           │ ✓       │
│ Running Builds   │ 0           │ 0            │ ✓       │
│ Config Files     │ 127         │ 127          │ ✓       │
│ Data Size        │ 2.3GB       │ 2.3GB        │ ✓       │
└──────────────────┴─────────────┴──────────────┴─────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall Result: ✅ VALIDATION PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Exit Criteria:**
- All validation checks must pass
- If validation fails, offer rollback option

---

##### Stage 2B: HAProxy Deployment (5-8 min)
**Condition:** `COMPONENT == 'haproxy' || COMPONENT == 'all'`

**Purpose:** Deploy HAProxy with rolling update and zero downtime

**Tasks:**
- Generate new HAProxy configuration
- Validate configuration syntax
- Deploy to HAProxy VMs (VM1 and VM2)
- Graceful reload
- Verify backend health

**Ansible Command:**
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags high-availability,haproxy \
  --limit ${TARGET_VM}
```

**Health Checks:**
- HAProxy stats page accessible
- All backend servers responding
- SSL certificates valid
- No 5xx errors in logs

**Output:**
```
HAProxy Deployment Results:
✓ VM1 (jenkins_hosts_01):
  ✓ Configuration validated
  ✓ Graceful reload completed
  ✓ Backend health: 4/4 teams healthy
✓ VM2 (jenkins_hosts_02):
  ✓ Configuration validated
  ✓ Graceful reload completed
  ✓ Backend health: 4/4 teams healthy
```

---

##### Stage 2C: Monitoring Deployment (10-15 min)
**Condition:** `COMPONENT == 'monitoring' || COMPONENT == 'all'`

**Purpose:** Deploy monitoring stack with rolling update

**Tasks:**
- Deploy Prometheus
- Deploy Grafana (with plugin installation)
- Deploy Loki
- Deploy Alertmanager
- Deploy cross-VM agents
- Update Prometheus targets (active-only)
- Verify datasources

**Ansible Command:**
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags monitoring \
  --limit monitoring
```

**Health Checks:**
- All services running
- Prometheus targets up (active Jenkins only)
- Grafana datasources connected
- Dashboards loading
- Alertmanager rules loaded

**Output:**
```
Monitoring Deployment Results:
✓ Prometheus:
  ✓ Service running
  ✓ Targets: 12/12 up (active Jenkins only)
  ✓ Scrape duration: <1s
✓ Grafana:
  ✓ Service running
  ✓ Plugins installed: github, jira
  ✓ Datasources: 4/4 connected
  ✓ Dashboards: 8/8 loading
✓ Loki:
  ✓ Service running
  ✓ Log ingestion: active
✓ Alertmanager:
  ✓ Service running
  ✓ Alert rules: 130 loaded
  ✓ Teams webhook: configured
```

---

#### Stage 3: Manual Approval Gate ⏸️ (User Action Required)
**Condition:** `AUTO_SWITCH == false && COMPONENT == 'jenkins-masters'`

**Purpose:** Allow manual review before switching traffic to passive environment

**Display Information:**
- Deployment summary
- Validation results
- Active vs Passive comparison
- Estimated downtime (0 seconds for blue-green switch)
- Rollback plan

**Actions:**
- ✅ **APPROVE:** Proceed to blue-green switch
- ❌ **REJECT:** Stop pipeline (passive environment remains deployed for testing)
- 🔄 **ROLLBACK:** Remove passive deployment, restore previous state

**Timeout:** 24 hours (configurable)

**Approval Message:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
APPROVAL REQUIRED: Blue-Green Switch
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Deployment validated successfully. Ready to switch traffic to passive environment.

Teams to Switch:
• devops: blue → green (VM1)
• ma: green → blue (VM2)
• ba: blue → green (VM1)
• tw: green → blue (VM1)

Validation Summary:
✅ All containers healthy
✅ Data integrity verified
✅ Configuration drift: NONE
✅ Performance: within baseline

Estimated Downtime: 0 seconds (zero-downtime switch)

Rollback Plan:
1. Switch back to current active environment (1 command)
2. Estimated rollback time: <30 seconds

Actions:
✅ APPROVE - Switch to passive environment
❌ REJECT - Keep current active environment
🔄 ROLLBACK - Remove passive deployment

Approval expires in: 24 hours
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

#### Stage 4: Blue-Green Switch (2-3 min)
**Condition:** `Approval granted || AUTO_SWITCH == true`

**Purpose:** Switch traffic from active to passive environment with zero downtime

**Sub-Stage 4.1: Update Team Configuration**
**Tasks:**
- Update inventory: toggle `active_environment` for each team
- Commit inventory changes to Git (optional)

**Sub-Stage 4.2: Execute Blue-Green Switch**
**Tasks:**
- Run blue-green switch script per team
- Update HAProxy backends (points to new active environment)
- Update Prometheus targets (monitors new active environment only)
- Stop old active containers (now passive)

**Script:** Use existing `/var/jenkins/scripts/zero-downtime-blue-green-switch-{team}.sh`

**Ansible Playbook:** Create `ansible/playbooks/blue-green-switch.yml`
```yaml
---
- name: Blue-Green Switch
  hosts: "{{ target_vm }}"
  tasks:
    - name: Execute zero-downtime switch for each team
      command: >
        /var/jenkins/scripts/zero-downtime-blue-green-switch-{{ item.team_name }}.sh switch
      loop: "{{ jenkins_teams_filtered }}"

    - name: Update HAProxy configuration
      import_tasks: ../roles/high-availability-v2/tasks/main.yml
      tags: haproxy

    - name: Update Prometheus targets
      import_tasks: ../roles/monitoring/tasks/phase1-file-sd/generate-targets.yml
      tags: monitoring,targets
```

**Output:**
```
Blue-Green Switch Results:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ devops: Switched blue → green
  - Traffic routing: Updated
  - HAProxy backend: devops-vm1-green (UP)
  - Prometheus target: devops-green:8080 (UP)
  - Old container: devops-blue (STOPPED)

✓ ma: Switched green → blue
  - Traffic routing: Updated
  - HAProxy backend: ma-vm2-blue (UP)
  - Prometheus target: ma-blue:8081 (UP)
  - Old container: ma-green (STOPPED)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Switch completed in 47 seconds
Downtime: 0 seconds (zero-downtime switch)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

#### Stage 5: Post-Switch Validation (5 min)
**Purpose:** Verify new active environment is functioning correctly

**Tasks:**
- Verify containers running
- Health check all teams (HTTP 200)
- Verify HAProxy routing (correct backends active)
- Verify Prometheus targets (monitoring new active only)
- Check for errors in logs (past 5 minutes)
- Test sample job execution (optional)

**Output:**
```
Post-Switch Validation:
✓ All teams: HTTP 200 on /login
✓ HAProxy routing: Correct backends active
✓ Prometheus targets: 12/12 up (new active environment)
✓ Log errors: 0 errors in past 5 minutes
✓ Sample job test: PASSED (devops test job executed successfully)
```

**Rollback Trigger:**
- If validation fails, automatic rollback to previous active environment

---

#### Stage 6: Notification (1 min)
**Purpose:** Send deployment summary to configured channels

**Channels:**
- Microsoft Teams webhook
- Email (optional)
- Jenkins job console log

**Notification Template:**
```
🚀 Infrastructure Deployment Complete

Component: Jenkins Masters
Target VMs: jenkins_hosts_01, jenkins_hosts_02
Teams Deployed: devops, ma, ba, tw

Deployment Summary:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Data Recovery: 4/4 teams (7.7GB total)
✅ Container Deployment: 4/4 containers
✅ Validation: PASSED (100% checks)
✅ Blue-Green Switch: 4/4 teams switched
✅ Post-Switch Validation: PASSED

Total Duration: 32 minutes
Downtime: 0 seconds

Team Status:
• devops: green (VM1) - 45 jobs, 78 plugins ✓
• ma: blue (VM2) - 38 jobs, 65 plugins ✓
• ba: green (VM1) - 52 jobs, 72 plugins ✓
• tw: blue (VM1) - 29 jobs, 58 plugins ✓

Access URLs:
• devops: http://devopsjenkins.dev.net
• ma: http://majenkins.dev.net
• ba: http://bajenkins.dev.net
• tw: http://twjenkins.dev.net

Jenkins Job: http://devopsjenkins.dev.net/job/Infrastructure-Deployment/42
Triggered by: John Doe
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Dependency Management

### Dependency Matrix

| Deployment | Requires | Validation |
|------------|----------|------------|
| Jenkins Masters | GlusterFS mounted | Check `/var/jenkins/{team}/sync/` accessible |
| Jenkins Masters | Docker running | Check `docker info` succeeds |
| HAProxy | Jenkins running (optional) | Check backend health before reload |
| Monitoring | Jenkins running (optional) | Check targets accessible before scraping |

### Dependency Check Strategy (Best Practice)

**Option A: Soft Dependencies (Recommended)**
- Deploy components independently
- Warn if dependencies not met but continue
- Example: Deploy HAProxy even if Jenkins not running (backends will be DOWN but HAProxy runs)

**Option B: Hard Dependencies**
- Check dependencies before deployment
- Fail pipeline if dependencies not met
- Example: Refuse to deploy HAProxy if Jenkins not running

**Recommended Approach:**
- Use **Soft Dependencies** with warnings
- Each component should be deployable independently
- Post-deployment health checks will catch issues
- Allows for parallel deployment and disaster recovery scenarios

**Implementation:**
```groovy
stage('Dependency Check') {
    steps {
        script {
            def warnings = []

            // Check GlusterFS for Jenkins deployment
            if (params.COMPONENT in ['jenkins-masters', 'all']) {
                def glusterCheck = sh(script: "ansible jenkins_masters -m stat -a 'path=/var/jenkins/devops/sync'", returnStatus: true)
                if (glusterCheck != 0) {
                    warnings.add("⚠️ GlusterFS mounts not accessible - data recovery may fail")
                }
            }

            // Check Jenkins for HAProxy deployment
            if (params.COMPONENT in ['haproxy', 'all']) {
                def jenkinsCheck = sh(script: "curl -sf http://jenkins_hosts_01:8080/login", returnStatus: true)
                if (jenkinsCheck != 0) {
                    warnings.add("⚠️ Jenkins not responding - HAProxy backends will be DOWN")
                }
            }

            // Display warnings but continue
            if (warnings.size() > 0) {
                echo "Dependency Warnings (non-blocking):"
                warnings.each { echo it }
            }
        }
    }
}
```

---

## Rollback Strategy

### Automatic Rollback Triggers
- Post-deployment validation fails
- Health check fails after switch
- Critical errors in Jenkins logs
- HTTP 5xx errors detected

### Manual Rollback
- Separate job: `Infrastructure-Rollback`
- Or via approval gate during deployment

### Rollback Procedure
1. Switch back to previous active environment
2. Update HAProxy backends
3. Update Prometheus targets
4. Verify previous active environment still healthy
5. Notify team of rollback

**Rollback Time:** <30 seconds (blue-green architecture advantage)

**Rollback Script:** Use existing blue-green switch mechanism
```bash
/var/jenkins/scripts/zero-downtime-blue-green-switch-{team}.sh switch
```

---

## Avoiding Duplication with Ansible

### Current Ansible Validations (Leverage These)
- ✅ Ansible syntax check: `--syntax-check`
- ✅ Pre-deployment validation: `--tags validation`
- ✅ Container health checks: Built into `fixed-health-checks.yml`
- ✅ Port conflict detection: In `setup-and-validate.yml`
- ✅ GlusterFS mount check: In `gluster-sync.yml`

### Jenkins Job Focus (Orchestration, Not Duplication)
- ✅ Workflow orchestration
- ✅ Approval gates
- ✅ Data comparison (active vs passive)
- ✅ Blue-green switch coordination
- ✅ Cross-component coordination (Jenkins + HAProxy + Monitoring)
- ✅ Notifications and reporting
- ✅ Rollback orchestration

### Strategy
- **Jenkins Job:** High-level orchestration and decision-making
- **Ansible:** Low-level deployment and validation tasks
- **Scripts:** Reusable utilities (validation, comparison, switching)

---

## Performance Estimates

| Stage | Jenkins Masters | HAProxy | Monitoring |
|-------|----------------|---------|------------|
| Pre-Flight Validation | 3-5 min | 2-3 min | 2-3 min |
| Data Recovery | 5-10 min | N/A | N/A |
| Deployment | 10-15 min | 3-5 min | 10-15 min |
| Validation | 5-10 min | 2 min | 5 min |
| Approval Gate | User dependent | N/A | N/A |
| Blue-Green Switch | 2-3 min | N/A | N/A |
| Post-Switch Validation | 5 min | 2 min | 5 min |
| Notification | 1 min | 1 min | 1 min |
| **Total** | **31-49 min** | **10-13 min** | **22-29 min** |

**Full Infrastructure Deployment (all components):** ~40-60 minutes

---

## Security Considerations

### Credentials Management
- Use Jenkins credentials for Ansible Vault password
- SSH keys stored in Jenkins credentials
- No hardcoded passwords in Jenkinsfile

### Approval Authorization
- Restrict approval to specific users/groups
- Audit log of who approved
- Timeout on approvals (24 hours)

### Deployment Audit Trail
- Git commit for inventory changes
- Jenkins job console log
- Ansible log output
- Deployment notification with details

---

## Future Enhancements

### Phase 2 (Future)
1. **Automated Canary Deployment**
   - Route 10% traffic to passive before full switch
   - Monitor error rates and latency
   - Auto-rollback if metrics degrade

2. **Progressive Team Rollout**
   - Switch one team at a time
   - Validate between each team
   - Continue or rollback per team

3. **Automated Smoke Tests**
   - Execute sample jobs on passive environment
   - Test agent provisioning
   - Test webhook integration

4. **Disaster Recovery Testing**
   - Scheduled DR tests (monthly)
   - Simulate VM failure
   - Measure RTO/RPO compliance

5. **Multi-Region Deployment**
   - Deploy to multiple data centers
   - Cross-region traffic routing
   - Geo-redundancy

---

## Next Steps

1. ✅ Create Jenkinsfile for unified deployment pipeline
2. ✅ Create Job DSL script to provision the job
3. ✅ Create supporting Ansible playbooks:
   - `ansible/playbooks/jenkins-data-recovery.yml`
   - `ansible/playbooks/jenkins-validation.yml`
   - `ansible/playbooks/blue-green-switch.yml`
4. ✅ Create validation script: `scripts/jenkins-deployment-validator.sh`
5. ✅ Create rollback job (separate pipeline)
6. ✅ Update CLAUDE.md with new deployment commands
7. ✅ Test deployment in local environment
8. ✅ Document in deployment guide

---

## Summary

This plan provides:
- ✅ Unified pipeline for all infrastructure components
- ✅ Support for full/team-specific/VM-specific deployments
- ✅ GlusterFS data recovery integration
- ✅ Comprehensive validation without duplicating Ansible
- ✅ Manual approval gates for safety
- ✅ Zero-downtime blue-green switching
- ✅ Automatic rollback on failures
- ✅ Rich notifications and audit trails
- ✅ Extensible for future enhancements

**Ready for implementation!**
