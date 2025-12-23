# Simple Dashboard Deployment Plan

## Goal
Create a single, simple task in the monitoring role to deploy JSON dashboards without complex variables or templating.

---

## Current Problems
1. **Complex Jinja2 templates** - 22K lines with 30-50+ variables per dashboard
2. **Team-specific generation logic** - 150+ lines of complex YAML in grafana.yml
3. **Must redeploy entire role** - File-based provisioning requires container restart
4. **Hard to maintain** - Changes require editing large template files

---

## Proposed Simple Solution

### Option 1: Static JSON + Simple Copy Task (Simplest)

#### Directory Structure
```
ansible/roles/monitoring/
├── files/
│   └── dashboards/
│       └── json/                    # NEW: Static JSON dashboards
│           ├── infrastructure.json
│           ├── jenkins-overview.json
│           ├── jenkins-builds.json
│           ├── jenkins-performance.json
│           └── security-metrics.json
└── tasks/
    └── dashboards/
        └── deploy-json.yml          # NEW: Simple deployment task
```

#### Simple Task (`tasks/dashboards/deploy-json.yml`)
```yaml
---
# Simple JSON dashboard deployment
- name: Create dashboard directory
  file:
    path: "{{ monitoring_home_dir }}/grafana/dashboards"
    state: directory
    owner: "{{ monitoring_user }}"
    group: "{{ monitoring_group }}"
    mode: '0755'

- name: Deploy JSON dashboards
  copy:
    src: "dashboards/json/{{ item }}"
    dest: "{{ monitoring_home_dir }}/grafana/dashboards/{{ item }}"
    owner: "{{ monitoring_user }}"
    group: "{{ monitoring_group }}"
    mode: '0644'
  loop:
    - infrastructure.json
    - jenkins-overview.json
    - jenkins-builds.json
    - jenkins-performance.json
    - security-metrics.json
  notify: restart grafana
```

#### Usage
```yaml
# In site.yml or monitoring role main.yml
- import_tasks: dashboards/deploy-json.yml
  tags: [monitoring, dashboards]
```

**Benefits:**
- 10 lines of code vs. 150+ lines
- No variables (or minimal 2-3 variables)
- No templating logic
- Easy to understand and modify
- Can add new dashboards by just adding to the loop

**Limitations:**
- Still requires Grafana restart (file-based provisioning)
- No dynamic team-specific dashboards

---

### Option 2: Static JSON + API Deployment (No Restart Required)

#### Simple Task (`tasks/dashboards/deploy-json-api.yml`)
```yaml
---
# Deploy dashboards via Grafana API (no restart needed)
- name: Wait for Grafana to be ready
  uri:
    url: "http://{{ monitoring_host | default('localhost') }}:{{ grafana_port }}/api/health"
    method: GET
    status_code: 200
  register: grafana_health
  until: grafana_health.status == 200
  retries: 30
  delay: 5

- name: Deploy JSON dashboards via API
  uri:
    url: "http://{{ monitoring_host | default('localhost') }}:{{ grafana_port }}/api/dashboards/db"
    method: POST
    user: "{{ grafana_admin_user }}"
    password: "{{ grafana_admin_password }}"
    body_format: json
    body:
      dashboard: "{{ lookup('file', 'dashboards/json/' + item) | from_json }}"
      overwrite: true
      message: "Deployed via Ansible"
    status_code: 200
    force_basic_auth: yes
  loop:
    - infrastructure.json
    - jenkins-overview.json
    - jenkins-builds.json
    - jenkins-performance.json
    - security-metrics.json
```

#### Standalone Playbook (`playbooks/update-dashboards.yml`)
```yaml
---
# Quick dashboard update without redeploying monitoring
- name: Update Grafana Dashboards
  hosts: monitoring
  gather_facts: no
  tasks:
    - name: Include dashboard deployment
      include_role:
        name: monitoring
        tasks_from: dashboards/deploy-json-api.yml
```

**Benefits:**
- No Grafana restart needed
- 30-second updates
- Can run independently: `ansible-playbook -i $PROD_INV playbooks/update-dashboards.yml`
- Same simple structure

**Limitations:**
- Requires Grafana to be running
- Need to handle API credentials

---

### Option 3: Hybrid (Best of Both Worlds)

Use **Option 1** for initial deployment and **Option 2** for updates:

```yaml
# During monitoring role deployment
- import_tasks: dashboards/deploy-json.yml
  tags: [monitoring, dashboards, deploy]

# For quick updates only
- import_tasks: dashboards/deploy-json-api.yml
  tags: [monitoring, dashboards, update]
  when: dashboard_update_mode | default(false)
```

**Usage:**
```bash
# Full deployment (includes Grafana restart)
ansible-playbook -i $PROD_INV $SITE_YML --tags monitoring

# Quick dashboard update only (no restart)
ansible-playbook -i $PROD_INV $SITE_YML --tags dashboards,update -e "dashboard_update_mode=true"

# Or use standalone playbook
ansible-playbook -i $PROD_INV playbooks/update-dashboards.yml
```

---

## Dashboard File Format

### Static JSON (No Variables)
```json
{
  "dashboard": {
    "title": "Jenkins Overview",
    "tags": ["jenkins", "overview"],
    "panels": [
      {
        "title": "Build Success Rate",
        "targets": [{
          "expr": "rate(jenkins_job_success_total[5m])"
        }]
      }
    ]
  }
}
```

### Minimal Variables (Only Essential Ones)
If you need dynamic datasource UIDs:

```json
{
  "dashboard": {
    "title": "Jenkins Overview",
    "panels": [{
      "datasource": {
        "type": "prometheus",
        "uid": "${DS_PROMETHEUS}"
      }
    }]
  }
}
```

Then use variable substitution in Grafana provisioning config:
```yaml
# dashboards/dashboard.yml
apiVersion: 1
providers:
  - name: 'default'
    folder: ''
    type: file
    options:
      path: /var/lib/grafana/dashboards
```

Grafana automatically replaces `${DS_PROMETHEUS}` with the correct datasource UID.

---

## Migration Steps

### Step 1: Extract Current Dashboards
Export existing dashboards from Grafana UI:
```bash
# Export dashboard via API
curl -u admin:password \
  "http://localhost:9300/api/dashboards/uid/jenkins-overview" | \
  jq '.dashboard' > files/dashboards/json/jenkins-overview.json
```

### Step 2: Clean Up JSON
Remove Grafana metadata:
```bash
# Remove id, uid, version fields
jq 'del(.id, .uid, .version)' jenkins-overview.json > jenkins-overview-clean.json
```

### Step 3: Create Simple Task
Create `tasks/dashboards/deploy-json.yml` with Option 1 or Option 2 content.

### Step 4: Update Main Task
```yaml
# In tasks/main.yml
- import_tasks: dashboards/deploy-json.yml
  tags: [monitoring, dashboards]
  when: dashboard_deployment_method == 'json'
```

### Step 5: Test
```bash
# Test deployment
ansible-playbook -i $PROD_INV $SITE_YML --tags dashboards --check

# Deploy
ansible-playbook -i $PROD_INV $SITE_YML --tags dashboards
```

### Step 6: Remove Old Complex Tasks (Optional)
Once validated, deprecate:
- Complex Jinja2 templates (*.json.j2)
- Team generation logic in grafana.yml
- Complex variable definitions

---

## Comparison

| Feature | Current | Option 1 | Option 2 | Option 3 |
|---------|---------|----------|----------|----------|
| **Lines of Code** | 150+ | ~10 | ~15 | ~25 |
| **Variables** | 30-50+ | 0-2 | 2-3 | 2-3 |
| **Grafana Restart** | Yes | Yes | No | Initial: Yes, Update: No |
| **Update Time** | 5-10 min | 5-10 min | 30 sec | Deploy: 5-10 min, Update: 30 sec |
| **Complexity** | High | Very Low | Low | Low |
| **Team Variants** | Yes | No | No | No |
| **Standalone Updates** | No | No | Yes | Yes |

---

## Recommendation

**Start with Option 1** (Static JSON + Simple Copy):
1. **Today (1-2 hours)**: Create simple task, export 2-3 dashboards to static JSON
2. **Test**: Deploy to monitoring VM
3. **Validate**: Check dashboards work correctly
4. **Iterate**: Add remaining dashboards one by one

**Then add Option 2** (API Updates):
1. **Next week (2-3 hours)**: Create API deployment task
2. **Create playbook**: `playbooks/update-dashboards.yml`
3. **Document**: Add to CLAUDE.md

**Result**: Option 3 - Best of both worlds
- Simple codebase (10-25 lines vs. 150+)
- Fast updates when needed (30 sec via API)
- Reliable initial deployment (file-based provisioning)

---

## Dashboard Variables Strategy

### Use Grafana Template Variables Instead of Ansible Variables

**Instead of generating N team dashboards, create ONE dashboard with a variable:**

```json
{
  "dashboard": {
    "title": "Jenkins Overview",
    "templating": {
      "list": [{
        "name": "team",
        "type": "query",
        "label": "Team",
        "query": "label_values(jenkins_up, team)",
        "current": {
          "selected": true,
          "text": "All",
          "value": "$__all"
        }
      }]
    },
    "panels": [{
      "targets": [{
        "expr": "jenkins_up{team=\"$team\"}"
      }]
    }]
  }
}
```

**Benefits:**
- 1 dashboard instead of N dashboards
- Users select team from dropdown
- No Ansible templating needed
- Easier to maintain

---

## Files to Create

### New Files
1. `ansible/roles/monitoring/tasks/dashboards/deploy-json.yml` - Simple copy task
2. `ansible/roles/monitoring/tasks/dashboards/deploy-json-api.yml` - API deployment task
3. `ansible/roles/monitoring/files/dashboards/json/*.json` - Static JSON dashboards
4. `ansible/playbooks/update-dashboards.yml` - Standalone update playbook
5. `docs/simple-dashboard-deployment-plan.md` - This document

### Modified Files
1. `ansible/roles/monitoring/tasks/main.yml` - Add import for new task
2. `ansible/roles/monitoring/defaults/main.yml` - Add simple variables (2-3 only)
3. `CLAUDE.md` - Document new workflow

### Files to Deprecate (After Migration)
1. `ansible/roles/monitoring/templates/dashboards/*.json.j2` - Complex Jinja2 templates
2. Complex team generation logic in `grafana.yml` (lines 38-150+)

---

## Quick Start Commands

### Export Existing Dashboards
```bash
# List all dashboards
curl -u admin:password http://localhost:9300/api/search?type=dash-db | jq '.[].uid'

# Export each dashboard
for uid in $(curl -s -u admin:password http://localhost:9300/api/search?type=dash-db | jq -r '.[].uid'); do
  curl -s -u admin:password "http://localhost:9300/api/dashboards/uid/$uid" | \
  jq '.dashboard | del(.id, .uid, .version)' > "dashboard-${uid}.json"
done
```

### Deploy Dashboards (Option 1)
```bash
# Deploy via file provisioning
ansible-playbook -i $PROD_INV $SITE_YML --tags dashboards
```

### Update Dashboards (Option 2)
```bash
# Quick update via API
ansible-playbook -i $PROD_INV playbooks/update-dashboards.yml
```

---

## Success Criteria

- [ ] Single task file (~10-15 lines)
- [ ] Static JSON files (no Jinja2 templating)
- [ ] 0-3 variables maximum
- [ ] Can deploy all dashboards with one command
- [ ] Can update dashboards without monitoring role redeployment (Option 2/3)
- [ ] Dashboard update time < 1 minute
- [ ] Code reduction: 150+ lines → 10-25 lines (85-95% reduction)
