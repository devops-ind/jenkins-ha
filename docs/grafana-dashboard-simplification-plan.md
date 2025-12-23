# Grafana Dashboard Simplification Plan

## Current Problems

### Problem 1: Deployment Dependency
- **Issue**: Must redeploy entire monitoring role to update any dashboard
- **Root Cause**: File-based provisioning requires container restart
- **Impact**: Slow iteration, 5-10 minute deployment cycle for simple dashboard changes

### Problem 2: Complex Variables
- **Issue**: 22K lines of Jinja2 templates (*.json.j2) with many variables
- **Root Cause**: Team-specific dashboard generation uses complex YAML/Jinja2 logic
- **Impact**: Hard to maintain, debug, and modify dashboards

### Problem 3: Dual System Maintenance
- **Issue**: Both Jinja2 (6 dashboards) and Grafonnet (5 dashboards) systems active
- **Root Cause**: Incomplete migration, no clear strategy
- **Impact**: Double maintenance burden, confusion about which approach to use

---

## Proposed Simple Solution

### Phase 1: API-Based Dashboard Deployment (Quick Win - 2-4 hours)
**Goal**: Update dashboards without redeploying monitoring role

#### Implementation Steps
1. Create new Ansible playbook: `ansible/playbooks/update-grafana-dashboards.yml`
   - Use Grafana HTTP API to push dashboards
   - No container restart required
   - 30-second update cycle vs. 10-minute redeployment

2. Add simple management script: `scripts/grafana-dashboard-update.sh`
   ```bash
   # Update single dashboard
   ./scripts/grafana-dashboard-update.sh jenkins-performance-health

   # Update all dashboards
   ./scripts/grafana-dashboard-update.sh --all

   # Update team-specific dashboard
   ./scripts/grafana-dashboard-update.sh jenkins-builds devops
   ```

3. Benefits:
   - No monitoring role redeployment needed
   - Fast iteration (30 seconds)
   - Can be run from laptop/CI/CD
   - Preserves existing dashboard structure

#### API Approach Details
```yaml
# New playbook structure
- name: Update Grafana Dashboard via API
  uri:
    url: "http://{{ monitoring_host }}:9300/api/dashboards/db"
    method: POST
    user: admin
    password: "{{ grafana_admin_password }}"
    body_format: json
    body:
      dashboard: "{{ lookup('template', 'dashboard-file.json.j2') | from_json }}"
      overwrite: true
      message: "Updated via Ansible API"
```

**Effort**: 2-4 hours
**Impact**: Immediate relief from redeployment pain

---

### Phase 2: Simplify Dashboard Variables (Medium Term - 1-2 days)
**Goal**: Reduce complexity in existing Jinja2 dashboards

#### Option A: Static JSON with Minimal Templating (Simplest)
1. Convert large Jinja2 templates to static JSON files
2. Use only 3-5 essential variables:
   - `{{ prometheus_datasource_uid }}`
   - `{{ loki_datasource_uid }}`
   - `{{ jenkins_team }}`
3. Remove complex conditionals and loops
4. Generate team variants at build time, not deployment time

**Example Simplification:**
```
Before: node-exporter-full.json.j2 (16,070 lines with 50+ variables)
After:  node-exporter-full.json (15,500 lines static, 3 variables)
        Reduction: 95% less Jinja2 logic
```

#### Option B: Migrate to Grafonnet (More Effort, Better Long-term)
1. Migrate remaining 6 Jinja2 dashboards to Grafonnet
2. Consolidate to single dashboard system
3. Use common library for code reuse (already have `lib/common.libsonnet`)
4. Generate dashboards at build time with `jsonnet` compiler

**Benefit**: 95% code reduction (894 lines vs. 22K lines)

**Effort**:
- Option A: 1 day
- Option B: 2 days

---

### Phase 3: Remove Team-Specific Generation (Long Term - 1 day)
**Goal**: Eliminate complex team variant logic

#### Current Approach (Complex)
- Generates N copies of each dashboard (N = number of teams)
- Example: `jenkins-builds-devops.json`, `jenkins-builds-ba.json`, `jenkins-builds-ma.json`
- 150+ lines of YAML logic in grafana.yml
- Difficult to maintain

#### Proposed Approach (Simple)
**Option 1: Single Dashboard with Team Variable**
- One dashboard with Grafana template variable: `$team`
- Users select team from dropdown
- No duplicate dashboards
- **Recommended for most use cases**

```json
{
  "templating": {
    "list": [{
      "name": "team",
      "type": "query",
      "query": "label_values(jenkins_up, team)"
    }]
  }
}
```

**Option 2: Team Folders with Dynamic Dashboards**
- One dashboard per category (not per team)
- Grafana's folder permissions control team access
- Filter data by team using Prometheus labels

**Benefit**:
- 1 dashboard instead of N dashboards
- No generation logic needed
- Easier to maintain and update

**Effort**: 1 day

---

## Recommended Implementation Timeline

### Week 1: Quick Wins
**Day 1-2**: Phase 1 - API-Based Deployment
- Create `update-grafana-dashboards.yml` playbook
- Add `grafana-dashboard-update.sh` script
- Test with 2-3 dashboards
- Document usage in CLAUDE.md

**Result**: Can update dashboards without redeploying monitoring role

### Week 2: Simplification
**Day 3-4**: Phase 2 - Simplify Variables
- Choose Option A (static JSON) OR Option B (Grafonnet migration)
- Start with largest dashboard (node-exporter-full)
- Reduce variable count from 50+ to 3-5 essential ones
- Test and validate

**Day 5**: Phase 3 - Remove Team-Specific Generation
- Implement single dashboard with `$team` variable
- Remove team generation logic from grafana.yml
- Migrate 2-3 dashboards to new approach

**Result**: 90% reduction in complexity, 95% less code

---

## Comparison: Current vs. Proposed

| Metric | Current | Proposed (After All Phases) | Improvement |
|--------|---------|---------------------------|-------------|
| **Dashboard Update Time** | 5-10 min (redeploy) | 30 sec (API) | 20x faster |
| **Lines of Dashboard Code** | 22,120 (Jinja2) | 1,200 (Grafonnet) or 15,500 (static JSON) | 95% reduction |
| **Number of Dashboard Files** | 11 templates + N*5 team variants | 11 dashboards (no variants) | 50-75% fewer files |
| **Variables per Dashboard** | 30-50+ | 3-5 | 90% reduction |
| **Deployment Complexity** | File-based provisioning | API-based push | Simple |
| **Maintenance Effort** | High (dual system) | Low (single system) | 50% reduction |

---

## Migration Strategy

### Option 1: Conservative (Keep Jinja2, Add API)
**Best for**: Teams with limited time or complex existing dashboards
```
Phase 1 only → Can update dashboards quickly via API
Keep existing Jinja2 templates → No migration risk
Simplify variables gradually → Low effort, incremental improvement
```
**Effort**: 2-4 hours
**Benefit**: 20x faster updates

### Option 2: Moderate (Simplify Jinja2)
**Best for**: Teams wanting cleaner templates without learning Grafonnet
```
Phase 1 → API deployment
Phase 2 Option A → Static JSON with minimal variables
Phase 3 → Remove team generation
```
**Effort**: 2-3 days
**Benefit**: 20x faster updates + 90% less complexity

### Option 3: Complete (Migrate to Grafonnet)
**Best for**: Teams wanting best long-term maintainability
```
Phase 1 → API deployment
Phase 2 Option B → Full Grafonnet migration
Phase 3 → Single dashboards with $team variable
Deprecate Jinja2 system → Remove old code
```
**Effort**: 4-5 days
**Benefit**: 20x faster updates + 95% code reduction + modern dashboard-as-code

---

## Immediate Next Steps (Today)

### Step 1: Choose Migration Strategy
**Question**: How much effort can you invest?
- **2-4 hours**: Option 1 (API only)
- **2-3 days**: Option 2 (Simplify Jinja2)
- **4-5 days**: Option 3 (Full Grafonnet)

### Step 2: Implement Phase 1 (Recommended)
Create API-based deployment regardless of long-term choice:
1. Create playbook: `ansible/playbooks/update-grafana-dashboards.yml`
2. Add script: `scripts/grafana-dashboard-update.sh`
3. Test with existing dashboards
4. Update documentation

**Estimated Time**: 2-4 hours
**Immediate Benefit**: No more monitoring role redeployments for dashboard changes

### Step 3: Plan Simplification (Optional)
Based on chosen strategy, plan next phases for next week

---

## Example: Simplified Dashboard Update Workflow

### Current Workflow (Slow)
```bash
# 1. Edit dashboard template
vi ansible/roles/monitoring/templates/dashboards/jenkins-builds.json.j2

# 2. Redeploy entire monitoring role (5-10 minutes)
ansible-playbook -i $PROD_INV $SITE_YML --tags monitoring

# 3. Wait for container restart and provisioning
# 4. Check Grafana UI
```
**Total Time**: 10-15 minutes

### Proposed Workflow (Fast)
```bash
# 1. Edit dashboard template (or JSON file)
vi ansible/roles/monitoring/templates/dashboards/jenkins-builds.json.j2

# 2. Push via API (30 seconds)
./scripts/grafana-dashboard-update.sh jenkins-builds

# 3. Check Grafana UI (instant refresh)
```
**Total Time**: 1 minute

**Improvement**: 15x faster iteration

---

## Files to Create/Modify

### New Files (Phase 1)
1. `ansible/playbooks/update-grafana-dashboards.yml` (new playbook)
2. `scripts/grafana-dashboard-update.sh` (new script)
3. `docs/grafana-dashboard-simplification-plan.md` (this document)

### Modified Files (Phase 2)
1. `ansible/roles/monitoring/templates/dashboards/*.json.j2` (simplify variables)
2. `ansible/roles/monitoring/defaults/main.yml` (reduce dashboard config)
3. `ansible/roles/monitoring/tasks/phase3-servers/grafana.yml` (remove team generation)

### Deprecated Files (Phase 3, if Grafonnet chosen)
1. All `*.json.j2` templates (migrate to Grafonnet)
2. Team-specific generation logic in grafana.yml

---

## Success Criteria

### Phase 1 Success
- [ ] Can update any dashboard in <1 minute without monitoring role redeployment
- [ ] Script supports single dashboard or bulk update
- [ ] API authentication works correctly
- [ ] Documentation updated in CLAUDE.md

### Phase 2 Success
- [ ] Dashboard variable count reduced from 30-50 to 3-5
- [ ] Dashboard templates easier to read and modify
- [ ] Single dashboard system (either Jinja2 or Grafonnet, not both)
- [ ] All existing dashboards still work correctly

### Phase 3 Success
- [ ] No team-specific dashboard variants (use `$team` variable instead)
- [ ] 50-75% fewer dashboard files
- [ ] Team generation logic removed from grafana.yml
- [ ] Dashboard maintenance effort reduced by 50%

---

## Recommendation

**Start with Phase 1 (API-Based Deployment) today**
- Lowest effort (2-4 hours)
- Immediate benefit (20x faster updates)
- No risk to existing dashboards
- Can implement other phases later

Then evaluate long-term strategy:
- If you prefer simplicity and minimal learning curve → Option 2 (Simplify Jinja2)
- If you want modern dashboard-as-code → Option 3 (Migrate to Grafonnet)

---

## Questions to Answer Before Proceeding

1. **How much time can you invest?**
   - 2-4 hours → Phase 1 only
   - 2-3 days → Phases 1-3 with Option A
   - 4-5 days → Phases 1-3 with Option B

2. **Do you want to learn Grafonnet/Jsonnet?**
   - Yes → Option 3 (best long-term)
   - No → Option 2 (simpler, good enough)

3. **Do you need team-specific dashboard variants?**
   - Yes → Keep current generation, simplify Phase 2 only
   - No → Implement Phase 3, use `$team` variable

4. **Do you allow UI edits to dashboards?**
   - Yes → Keep `allowUiUpdates: true`, use Jinja2 or static JSON
   - No → Use Grafonnet with `allowUiUpdates: false`, version control everything
