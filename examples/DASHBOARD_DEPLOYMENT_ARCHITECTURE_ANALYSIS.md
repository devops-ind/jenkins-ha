# Monitoring Dashboard Deployment Architecture Analysis

## Executive Summary

The monitoring role has **dual conflicting dashboard architectures**:

1. **Modern Centralized Deployment** (Active - Primary)
   - Jinja2 templates in `ansible/roles/monitoring/templates/dashboards/`
   - Centralized registry in `grafana_dashboards` variable
   - Two deployment paths: Direct templating (grafana.yml) + API deployment (dashboards.yml)

2. **Legacy Static JSON** (Orphaned - Not Used)
   - Static JSON files in `monitoring/grafana/dashboards/` root directory
   - Referenced in old logs but never actively deployed
   - Outdated and disconnected from current codebase

3. **Modern Grafonnet Dashboard-as-Code** (Emerging)
   - Jsonnet source files in `ansible/roles/monitoring/files/dashboards/jsonnet/`
   - Generates JSON to `grafonnet_output_dir`
   - Phase 5.5 deployment (separate from main dashboards)

## 1. Complete Dashboard File Inventory

### Location 1: Role Templates Directory (PRIMARY)
**Path:** `/Users/jitinchawla/Data/projects/jenkins-ha/ansible/roles/monitoring/templates/dashboards/`

**Jinja2 Template Files (12 total):**
- `infrastructure-health.json.j2` - Core infrastructure monitoring
- `jenkins-overview.json.j2` - Core Jenkins overview
- `jenkins-builds.json.j2` - Core build metrics
- `jenkins-dynamic-agents.json.j2` - Core agent monitoring
- `jenkins-performance-health.json.j2` - Enhanced performance
- `jenkins-build-statistics.json.j2` - Enhanced build stats
- `jenkins-advanced-overview.json.j2` - Enhanced overview
- `jenkins-build-logs.json.j2` - Enhanced log analysis (uses Loki datasource)
- `github-jira-metrics.json.j2` - Enhanced external integrations
- `security-metrics.json.j2` - Core security monitoring
- `node-exporter-full.json.j2` - Core infrastructure (138+ panels)
- `dashboard.yml.j2` - Grafana provisioning configuration

**Status:** ACTIVE - Primary source for dashboard deployment

---

### Location 2: Root Monitoring Directory (LEGACY)
**Path:** `/Users/jitinchawla/Data/projects/jenkins-ha/monitoring/grafana/dashboards/`

**Static JSON Files (3 total):**
- `jenkins-overview.json` - Simple JSON (489 bytes, minimal panels)
- `jenkins-blue-green.json` - Blue-green metrics (13,126 bytes)
- `jenkins-comprehensive.json` - Comprehensive monitoring (15,622 bytes)

**Status:** ORPHANED - Legacy, not deployed by current role, outdated

**Evidence of Legacy Status:**
- Static JSON with no templating support
- jenkins-overview.json contains only 1 panel vs. rich Jinja2 template
- Historical references in ansible.log from August 2025 (old deployments)
- Not referenced in any active task files

---

### Location 3: Grafonnet Jsonnet Source Files (MODERNIZATION)
**Path:** `/Users/jitinchawla/Data/projects/jenkins-ha/ansible/roles/monitoring/files/dashboards/jsonnet/`

**Jsonnet Source Files (4 total):**
- `infrastructure-health.jsonnet` - Generated to `grafonnet_output_dir`
- `jenkins-overview.jsonnet` - Generated to `grafonnet_output_dir`
- `lib/common.libsonnet` - Shared library for dashboard components
- `jsonnetfile.json` - Grafonnet dependencies (references grafonnet library)

**Output Directory:** `{{ monitoring_home_dir }}/grafana/dashboards/generated/`

**Status:** ACTIVE (Phase 5.5) - Separate modernization track, NOT integrated with main dashboards

---

### Location 4: Monitoring.backup Role (DEPRECATED)
**Path:** `/Users/jitinchawla/Data/projects/jenkins-ha/ansible/roles/monitoring.backup/templates/dashboards/`

**Files:** 10 Jinja2 templates (same as Location 1 but outdated)

**Status:** DEPRECATED - Backup of old role structure, not used in site.yml

---

## 2. Dashboard Deployment Tasks & Flow

### Phase 4 (Main.yml): Orchestration
**File:** `ansible/roles/monitoring/tasks/main.yml` (Lines 171-201)

```yaml
# Phase 5: Deploy Dashboards and Datasources (Lines 171-174)
- import_tasks: phase4-configuration/dashboards.yml
  when: inventory_hostname == monitoring_server_host
  tags: ['monitoring', 'phase5', 'configuration', 'dashboards']

# Phase 5.5: Grafonnet Dashboard-as-Code (Lines 177-201)
- import_tasks: phase4-dashboards/setup-grafonnet.yml
- import_tasks: phase4-dashboards/generate-dashboards.yml
- import_tasks: phase4-dashboards/test-dashboards.yml
  when: grafonnet_enabled | default(true)
```

**Execution Order:**
1. Phase 4 (Grafana Server Deployment) - Deploys container
2. Phase 5 (Dashboards.yml) - Template-based deployment
3. Phase 5.5 (Grafonnet) - Jsonnet compilation

---

### Phase 3 - Grafana Server Setup
**File:** `ansible/roles/monitoring/tasks/phase3-servers/grafana.yml` (Lines 1-195)

#### Deployment Step 1: Template Dashboard Provisioning (Lines 110-125)
```yaml
# Deploy global Grafana dashboards from centralized configuration (Lines 110-125)
- template:
    src: "dashboards/{{ item.name }}.j2"
    dest: "{{ monitoring_home_dir }}/grafana/dashboards/{{ item.id }}.json"
    owner: "{{ monitoring_user }}"
    group: "{{ monitoring_group }}"
    mode: '0644'
  loop: "{{ sorted_enabled_dashboards | rejectattr('category', 'match', '.*-team-specific') | list }}"
  notify: restart grafana
```

**Critical Issues:**
- `item.name` is set from `config.template_file` in grafana_dashboards registry
- Points to `dashboards/{{ item.name }}.j2` → resolves to templates/dashboards/*.j2
- Generates output to `{{ monitoring_home_dir }}/grafana/dashboards/{{ item.id }}.json`
- **No direct reference to monitoring/grafana/dashboards/ legacy files**

#### Deployment Step 2: Team-Specific Dashboard Deployment (Lines 154-170)
```yaml
- template:
    src: "dashboards/{{ item.name }}.j2"
    dest: "{{ monitoring_home_dir }}/grafana/dashboards/{% if item.team_name is defined %}teams/{{ item.team_name }}/{% endif %}{{ item.id }}.json"
    owner: "{{ monitoring_user }}"
    group: "{{ monitoring_group }}"
    mode: '0644'
  loop: "{{ sorted_enabled_dashboards | selectattr('category', 'match', '.*-team-specific') | list }}"
  notify: restart grafana
```

**Output Locations:**
- Global dashboards: `/opt/monitoring/grafana/dashboards/{id}.json`
- Team dashboards: `/opt/monitoring/grafana/dashboards/teams/{team_name}/{id}-{team}.json`

#### Provisioning Configuration (Line 35)
```yaml
- template:
    src: "{{ item }}.j2"
    dest: "{{ monitoring_home_dir }}/grafana/provisioning/{{ item }}"
  loop:
    - dashboards/dashboard.yml
```

**Deployment Artifact:** 
- Template: `ansible/roles/monitoring/templates/dashboards/dashboard.yml.j2`
- Output: `/opt/monitoring/grafana/provisioning/dashboards/dashboard.yml`
- Configuration: Points Grafana to `/var/lib/grafana/dashboards` (mounted as `/opt/monitoring/grafana/dashboards`)

---

### Phase 5 - API Dashboard Deployment
**File:** `ansible/roles/monitoring/tasks/phase4-configuration/dashboards.yml` (Lines 1-188)

#### Step 1: Dashboard List Generation (Lines 54-81)
```yaml
- set_fact:
    api_dashboard_list: |
      [
      {% for dashboard_id, config in grafana_dashboards.items() %}
      {% if config.enabled and ((config.category == 'core' and dashboard_deployment.core_enabled) or (config.category == 'enhanced' and dashboard_deployment.enhanced_enabled)) %}
        {% if config.team_specific | default(false) %}
          {% for team in jenkins_teams_config | default(jenkins_teams) %}
        {
          "name": "{{ dashboard_id }}-{{ team.team_name }}",
          "title": "{{ config.title }} - {{ team.team_name | title }} Team",
          "template_file": "{{ config.template_file }}",
          "file_path": "teams/{{ team.team_name }}/{{ dashboard_id }}-{{ team.team_name }}.json",
          "team_name": "{{ team.team_name }}"
        },
          {% endfor %}
        {% else %}
        {
          "name": "{{ dashboard_id }}",
          "title": "{{ config.title }}",
          "template_file": "{{ config.template_file }}",
          "file_path": "{{ config.template_file }}"
        },
        {% endif %}
      {% endif %}
      {% endfor %}
      ]
```

**Key Observation:** `file_path` generates incorrect paths for global dashboards:
- Expected: `infrastructure-health.json` (filename only)
- Generated: `infrastructure-health.json` (template_file value)
- **BUG: Line 75 uses `file_path: "{{ config.template_file }}"` which is ".j2" filename, not output JSON**

#### Step 2: Dashboard File Reading (Lines 118-125)
```yaml
- slurp:
    src: "{{ monitoring_home_dir }}/grafana/dashboards/{{ item.file_path | default(item.template_file) }}"
  register: dashboard_content
  loop: "{{ sorted_api_dashboards }}"
```

**CRITICAL BUG:** 
- Reads from `file_path` which defaults to `template_file`
- `template_file` = "infrastructure-health.json.j2" (WRONG - source file, not output)
- Should read from `{{ item.id }}.json` (the templated output)
- **Will fail when trying to read .j2 files as JSON**

#### Step 3: API Deployment (Lines 143-171)
```yaml
- uri:
    url: "http://{{ grafana_host }}:{{ grafana_port }}/api/dashboards/db"
    method: POST
    body:
      dashboard: "{{ (dashboard_content.results | selectattr('item.name', 'equalto', item.name) | first).content | b64decode | from_json | json_query('dashboard') }}"
      overwrite: true
```

**Depends on:** dashboard_content being valid JSON (fails due to bug above)

---

### Phase 5.5 - Grafonnet Generation
**File:** `ansible/roles/monitoring/tasks/phase4-dashboards/generate-dashboards.yml` (Lines 1-110)

#### Step 1: Find Jsonnet Files (Lines 5-11)
```yaml
- find:
    path: "{{ grafonnet_project_dir }}"
    patterns: '*.jsonnet'
    depth: 1
  register: grafonnet_files
```

**Output Location:** `/opt/grafonnet/` contains jsonnet source files

#### Step 2: Compile Jsonnet to JSON (Lines 33-55)
```yaml
- shell: |
    cd "{{ grafonnet_project_dir }}"
    jsonnet -J vendor "{{ item.path }}" -o "{{ grafonnet_output_dir }}/${DASHBOARD_NAME}.json"
  loop: "{{ grafonnet_files.files }}"
```

**Output:**
- `{{ grafonnet_output_dir }}/infrastructure-health.json`
- `{{ grafonnet_output_dir }}/jenkins-overview.json`
- Default: `/opt/monitoring/grafana/dashboards/generated/`

#### Step 3: Validation (Lines 57-79)
```yaml
- shell: |
    python3 -m json.tool "$file" > /dev/null 2>&1
```

---

## 3. Dashboard Registry Configuration

**File:** `ansible/roles/monitoring/defaults/main.yml` (Lines 104-232)

### Registry Structure
```yaml
grafana_dashboards:
  # Entry format:
  dashboard_id:
    category: "core|enhanced"
    enabled: true|false
    title: "Display Title"
    template_file: "filename.json|filename.json.j2"  # For templated dashboards
    team_specific: true|false
    priority: number
    description: "Details"
    datasource: "prometheus|loki"  # Optional
    datasources: ["ds1", "ds2"]    # For multi-datasource
    tags: ["tag1", "tag2"]
```

### Registered Dashboards (12 total)

#### Core Category (6)
1. `infrastructure-health` → `infrastructure-health.json.j2`
2. `security-metrics` → `security-metrics.json.j2`
3. `node-exporter-full` → `node-exporter-full.json.j2`
4. `jenkins-overview` → `jenkins-overview.json.j2` (team_specific: true)
5. `jenkins-builds` → `jenkins-builds.json.j2` (team_specific: true)
6. `jenkins-dynamic-agents` → `jenkins-dynamic-agents.json.j2` (team_specific: true)

#### Enhanced Category (6)
7. `jenkins-performance-health` → `jenkins-performance-health.json.j2` (team_specific: true)
8. `jenkins-build-statistics` → `jenkins-build-statistics.json.j2` (team_specific: true)
9. `jenkins-advanced-overview` → `jenkins-advanced-overview.json.j2` (team_specific: true)
10. `jenkins-build-logs` → `jenkins-build-logs.json.j2` (team_specific: true, datasource: loki)
11. `github-jira-metrics` → `github-jira-metrics.json.j2` (team_specific: false)

### Deployment Controls
```yaml
dashboard_deployment:
  core_enabled: true
  enhanced_enabled: true
  update_mode: "always"  # always, skip_existing, update_only
  validation_strict: false
  generate_team_specific: true
  keep_global_dashboards: true
  team_folder_organization: true
  team_dashboard_separator: "-"
```

---

## 4. Grafana Provisioning Configuration

**File:** `ansible/roles/monitoring/templates/dashboards/dashboard.yml.j2`

```yaml
apiVersion: 1
providers:
  - name: 'Jenkins Infrastructure'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
```

**Mounted Paths:**
- Host: `/opt/monitoring/grafana/dashboards`
- Container: `/var/lib/grafana/dashboards`
- Check interval: 10 seconds
- Allow UI updates: True (allows manual edits in Grafana)

**Discovery:**
- Grafana reads all `.json` files from this path
- 2 sources contribute to this directory:
  1. **Templated dashboards** from Phase 3 (grafana.yml) → `{id}.json`
  2. **Grafonnet-generated** from Phase 5.5 → `generated/*.json`

---

## 5. Identified Conflicts & Misconfigurations

### CONFLICT 1: Dual Dashboard Sources in Same Directory

**Problem:**
```
/opt/monitoring/grafana/dashboards/
├── infrastructure-health.json        [From Phase 3 templating]
├── teams/
│   ├── devops/
│   │   └── jenkins-overview-devops.json
│   └── ...
└── generated/
    ├── infrastructure-health.json    [From Phase 5.5 Grafonnet]
    └── jenkins-overview.json         [From Phase 5.5 Grafonnet]
```

**Impact:**
- **Name collision:** Both Phase 3 and Phase 5.5 generate `infrastructure-health.json`
- **Load order unclear:** Grafonnet runs AFTER Phase 3, so it overwrites the templated dashboard
- **Grafonnet output in subdirectory:** Dashboard provisioning path is parent directory, `generated/` subdirectory may not be auto-discovered

**Root Cause:** Architecture evolved from Phase 3 templating to Phase 5.5 Grafonnet modernization without consolidation

---

### CONFLICT 2: API Deployment Bug with File Paths

**Problem:** In `phase4-configuration/dashboards.yml` (Line 75 & 120):
```yaml
# For global dashboards:
"file_path": "{{ config.template_file }}"

# Later reads:
src: "{{ monitoring_home_dir }}/grafana/dashboards/{{ item.file_path | default(item.template_file) }}"
```

**Actual Behavior:**
- `config.template_file` = "infrastructure-health.json.j2" (source template)
- `item.file_path` = "infrastructure-health.json.j2" (J2 extension!)
- Read attempts: `/opt/monitoring/grafana/dashboards/infrastructure-health.json.j2`
- **Error:** File doesn't exist (templating happens in Phase 3)

**Expected Behavior:**
- Should be: `"file_path": "{{ dashboard_id }}.json"` for global dashboards
- Or: `"file_path": "{{ item.id }}.json"` in the API read task

**Verification:** Lines 73-76 of defaults/main.yml confirm template_file includes `.j2` suffix

---

### CONFLICT 3: Orphaned Legacy Static Dashboards

**Problem:**
```
monitoring/grafana/dashboards/          [LEGACY - Not used]
├── jenkins-overview.json               [489 bytes, 1 panel]
├── jenkins-blue-green.json             [13,126 bytes]
└── jenkins-comprehensive.json          [15,622 bytes]

ansible/roles/monitoring/templates/     [ACTIVE - Primary]
├── dashboards/
│   ├── jenkins-overview.json.j2        [Rich template, multi-panel]
│   └── ...
```

**Evidence:**
- No task imports or copies from `monitoring/grafana/dashboards/`
- Prometheus task (phase3-servers/prometheus.yml) correctly reads from `playbook_dir/../monitoring/prometheus/rules/` but dashboards NOT imported this way
- Old ansible.log shows these files existed but never deployed post-refactor
- `jenkins-overview.json` in both locations with different content

**Impact:**
- Confusion about dashboard source of truth
- Risk of accidentally copying outdated dashboards
- Dead code maintenance burden

---

### CONFLICT 4: Grafana Provisioning Path Ambiguity

**Problem:**
```yaml
# dashboard.yml.j2 provisioning config:
path: /var/lib/grafana/dashboards

# But output goes to:
/opt/monitoring/grafana/dashboards/
/opt/monitoring/grafana/dashboards/teams/
/opt/monitoring/grafana/dashboards/generated/
```

**Question:** Does Grafana discover:
- All files in `/var/lib/grafana/dashboards/` ?
- Only root level (missing `teams/` and `generated/` subdirectories) ?

**Assumption Required:**
- `path` refers to root directory
- Grafonnet `generated/` subdirectory MUST be at root level to be discovered
- Team folders `teams/` MUST be at root level to be discovered

**Lack of Evidence:** No task validates dashboard discovery after provisioning runs

---

### CONFLICT 5: Phase Execution Timing Issue

**Problem:** Phases run in order:
1. Phase 3: Grafana container deploys (hot start, may read old dashboards)
2. Phase 5: Template dashboards deploy (file-based provisioning discovers them)
3. Phase 5.5: Grafonnet dashboards generate (overwrites Phase 5 files)

**Risk:** 
- Phase 3 reads from empty/old dashboard directory during container startup
- Grafonnet output directory may not be watched initially
- `updateIntervalSeconds: 10` means eventual consistency, not immediate

**Mitigation:** Requires Grafana refresh after Phase 5.5 completion

---

### CONFLICT 6: Misalignment Between Registry and Actual Files

**Problem:** Registry metadata missing for Grafonnet dashboards
```yaml
# grafana_dashboards registry lists:
- infrastructure-health (generated by Phase 3 templating)
- jenkins-overview (generated by Phase 3 templating)

# But ALSO generated by Phase 5.5 Grafonnet:
- infrastructure-health.json (from grafonnet/)
- jenkins-overview.json (from grafonnet/)

# No registry entry for:
grafonnet_dashboards:
  - name: "infrastructure-health"
    enabled: true
    (only lists name, not lifecycle info)
```

**Disconnect:** `grafana_dashboards` registry doesn't distinguish between:
- Templated source (Jinja2)
- Generated source (Grafonnet)
- Output location expectations

---

## 6. Current vs. Intended Dashboard Deployment Flow

### CURRENT (BROKEN) FLOW

```
Defaults: grafana_dashboards registry (12 dashboards)
    ↓
Phase 3: Grafana Server
  ├─→ Template dashboards/*.j2 → /opt/monitoring/grafana/dashboards/*.json
  ├─→ Deploy container with mount to this directory
  └─→ Register provisioning config at /etc/grafana/provisioning/dashboards/dashboard.yml
    ↓
Phase 5: API Deployment (Broken!)
  ├─→ Generate list from grafana_dashboards registry
  ├─→ Try to read files using template_file (WRONG: .j2 extension!)
  ├─→ **FAILS**: Cannot read .j2 files as JSON
  └─→ API deployment never completes
    ↓
Phase 5.5: Grafonnet (Separate)
  ├─→ Compile jsonnet files → /opt/monitoring/grafana/dashboards/generated/
  ├─→ Validates JSON output
  ├─→ Triggers Grafana restart (if provisioning detects new files)
  └─→ Grafana discovers these dashboards via file watcher
    ↓
Result: Dashboards in /dashboards/*.json (Phase 3) + /dashboards/generated/*.json (Phase 5.5)
        API import never completes (Phase 5 broken)
        Legacy monitoring/ dashboards never used
```

### INTENDED (CLEAN) FLOW

**Option A: Unified Templating Pipeline**
```
Defaults: grafana_dashboards registry
    ↓
Phase 3: Grafana Server
  ├─→ Template all dashboards/*.j2 → /opt/monitoring/grafana/dashboards/
  ├─→ Deploy container
  └─→ Register provisioning config
    ↓
Phase 4: Optional Validation
  └─→ Verify all dashboard JSON files exist and are valid
    ↓
Result: Single source of truth (Jinja2 templates)
        File-based provisioning discovers all dashboards
        No API deployment needed
        Grafonnet completely separate (opt-in modernization)
```

**Option B: Unified API Pipeline**
```
Defaults: grafana_dashboards registry
    ↓
Phase 3: Grafana Server (no dashboard templating)
  ├─→ Deploy container
  ├─→ Register provisioning config (empty initially)
  └─→ Configure datasources via API
    ↓
Phase 5: API Deployment (Fixed!)
  ├─→ Generate correct list with file_path = {id}.json
  ├─→ Read templated files correctly
  ├─→ Deploy all dashboards via API with validation
  └─→ Verify deployment status
    ↓
Phase 5.5: Grafonnet (Separate)
  └─→ Optional modern dashboard source
    ↓
Result: Single API deployment pipeline
        No file-based provisioning conflicts
        Grafonnet output can go to separate directory
```

**Option C: Stratified Approach (Recommended)**
```
Defaults: grafana_dashboards registry
    ↓
Phase 3: Grafana Server
  ├─→ Template dashboards/*.j2 → /opt/monitoring/grafana/dashboards/
  ├─→ Deploy container
  └─→ Register provisioning config (path: /dashboards)
    ↓
Phase 5: Verification Only
  ├─→ No API deployment
  ├─→ Verify templated dashboard files exist
  ├─→ Trigger Grafana reload for hot-reload
  └─→ Display deployment summary
    ↓
Phase 5.5: Grafonnet (Optional Modernization)
  ├─→ Only runs if grafonnet_enabled: true
  ├─→ Output to separate directory: /opt/monitoring/grafana/dashboards/generated/
  ├─→ Update provisioning config to include generated/ path
  └─→ Trigger Grafana reload
    ↓
Result: Primary source = Jinja2 (backward compatible)
        Optional modernization = Grafonnet (separate track)
        API deployment removed (eliminates bug source)
```

---

## 7. Root Cause Analysis

### Why These Conflicts Exist

1. **Architecture Evolution Without Consolidation**
   - Started: Simple Jinja2 templating (Phase 3)
   - Added: API deployment (Phase 5) - BUGGY
   - Added: Grafonnet modernization (Phase 5.5) - separate approach
   - Never merged: Different deployment paths for same dashboards

2. **Missing Validation Layer**
   - No task verifies file paths match registry
   - No task validates API deployment completion
   - No task checks for filename collisions
   - Grafonnet output location not validated against provisioning config

3. **Registry Design Flaw**
   - `template_file` includes `.j2` extension (source file, not output)
   - API task reads `template_file` directly (wrong data type)
   - No distinction between templated vs. generated source
   - File path generation logic duplicated across multiple tasks

4. **Legacy Code Not Cleaned Up**
   - monitoring/grafana/dashboards/ never removed
   - monitoring.backup role still exists (deprecated)
   - Old commented-out variables left in defaults
   - Historical references confusing (jenkins-overview-old vs. jenkins-overview)

---

## 8. Recommendations to Fix Conflicts

### PRIORITY 1: Fix File Path Bug (CRITICAL)

**Current (Broken) Code:**
```yaml
# defaults/main.yml, lines 73-75
{
  "name": "{{ dashboard_id }}",
  "title": "{{ config.title }}",
  "template_file": "{{ config.template_file }}",
  "file_path": "{{ config.template_file }}"   # WRONG: .j2 extension!
},
```

**Fix:**
```yaml
{
  "name": "{{ dashboard_id }}",
  "title": "{{ config.title }}",
  "template_file": "{{ config.template_file }}",
  "file_path": "{{ dashboard_id }}.json"  # CORRECT: Output filename
},
```

**Validation:** Confirm `.j2` is removed from file_path values

---

### PRIORITY 2: Clarify Dashboard Provisioning Paths

**Current Problem:**
- Grafonnet output in `generated/` subdirectory
- Provisioning config points to root only
- No validation that provisioning discovers all files

**Fix:**
```yaml
# In dashboard.yml.j2 provisioning config:
providers:
  - name: 'Jenkins Infrastructure - Templated'
    path: /var/lib/grafana/dashboards  # Root level (Phase 3)
  - name: 'Jenkins Infrastructure - Generated'
    path: /var/lib/grafana/dashboards/generated  # Grafonnet (Phase 5.5)
```

**Or Consolidate:**
```yaml
# Single provider, Grafana auto-discovers subdirectories
providers:
  - name: 'Jenkins Infrastructure'
    path: /var/lib/grafana/dashboards
    # Grafonnet files placed at root, not in subdirectory
```

---

### PRIORITY 3: Separate Grafonnet Output Path

**Current:**
- Grafonnet outputs to same directory as Phase 3 templates
- Causes name collision and confusion
- Unclear which version is active

**Fix - Option A (Clean Separation):**
```yaml
# Phase 5.5 only:
grafonnet_output_dir: "{{ monitoring_home_dir }}/grafana/dashboards-generated"

# Provisioning includes both:
- name: 'Templated Dashboards'
  path: /var/lib/grafana/dashboards
- name: 'Generated Dashboards'  
  path: /var/lib/grafana/dashboards-generated
```

**Fix - Option B (Explicit Naming):**
```yaml
# Phase 5.5 uses suffix:
OUTPUT_FILE="{{ grafonnet_output_dir }}/${DASHBOARD_NAME}-modern.json"

# No collision with Phase 3 names
# Both live in same directory with clear naming
```

---

### PRIORITY 4: Remove Legacy Code

**Files to Delete:**
1. `/Users/jitinchawla/Data/projects/jenkins-ha/monitoring/grafana/dashboards/` (entire directory)
   - Jenkins-overview.json (outdated)
   - Jenkins-blue-green.json (superseded by blue-green rules)
   - Jenkins-comprehensive.json (replaced by templates)

2. `/Users/jitinchawla/Data/projects/jenkins-ha/ansible/roles/monitoring.backup/` (entire role)
   - Old backup of deprecated architecture
   - Confuses deployments
   - Never imported in site.yml

**Rationale:**
- These are not used by any active task
- Single source of truth should be role templates
- Removing reduces confusion

---

### PRIORITY 5: Consolidate Deployment Paths

**Option A: Remove API Deployment (Recommended)**

**Current:** Phase 5 (API) conflicts with Phase 3 (File-based)

```yaml
# In main.yml, remove Phase 5 entirely or rename to verification
- import_tasks: phase4-configuration/verification.yml  # Renamed from dashboards.yml
  tasks:
    - Verify Prometheus ready
    - Verify Grafana ready
    - Verify dashboard files exist
    - Verify JSON is valid
    - Display summary
```

**Why:** 
- File-based provisioning already discovered dashboards in Phase 3
- API deployment adds complexity without benefit
- Bug in API task blocks its use anyway

---

**Option B: Keep API but Fix It (If needed for specific use case)**

```yaml
# Fix dashboard list generation:
- set_fact:
    api_dashboard_list: |
      [
      {% for dashboard_id, config in grafana_dashboards.items() %}
      {% if config.enabled %}
        {
          "name": "{{ dashboard_id }}",
          "id": "{{ dashboard_id }}",
          "title": "{{ config.title }}",
          "file_path": "{{ dashboard_id }}.json"  # FIXED: Correct output filename
        },
      {% endif %}
      {% endfor %}
      ]

# Fix file reading to use correct path:
- slurp:
    src: "{{ monitoring_home_dir }}/grafana/dashboards/{{ item.id }}.json"  # FIXED: Use ID not template_file
  register: dashboard_content
  loop: "{{ sorted_api_dashboards }}"
```

---

### PRIORITY 6: Create Deployment Validation Task

**New File:** `phase4-configuration/validate-dashboards.yml`

```yaml
---
# Validate dashboard deployment before completion

- name: Validate dashboard template files were rendered correctly
  stat:
    path: "{{ monitoring_home_dir }}/grafana/dashboards/{{ item.id }}.json"
  register: rendered_dashboard_check
  loop: "{{ sorted_enabled_dashboards }}"
  failed_when: not rendered_dashboard_check.stat.exists
  loop_control:
    label: "{{ item.id }}"

- name: Validate all dashboard JSON files are valid
  shell: |
    python3 -m json.tool "{{ monitoring_home_dir }}/grafana/dashboards/{{ item.id }}.json" > /dev/null 2>&1
  register: json_validation
  loop: "{{ sorted_enabled_dashboards }}"
  loop_control:
    label: "{{ item.id }}"
  failed_when: json_validation.rc != 0

- name: Verify Grafana has discovered all dashboards
  uri:
    url: "http://{{ grafana_host }}:{{ grafana_port }}/api/search?query=*"
    method: GET
    user: "{{ grafana_admin_user }}"
    password: "{{ grafana_admin_password }}"
    force_basic_auth: yes
  register: grafana_search_result
  retries: 3
  delay: 5
  until: grafana_search_result.json | length >= (sorted_enabled_dashboards | length)
  failed_when: grafana_search_result.json | length < (sorted_enabled_dashboards | length)

- name: Display validation results
  debug:
    msg: |
      Dashboard Validation Results:
      • Template files rendered: {{ rendered_dashboard_check.results | length }}
      • JSON valid: {{ json_validation.results | selectattr('rc', 'equalto', 0) | list | length }}
      • Grafana discovered: {{ grafana_search_result.json | length }}
      • Expected: {{ sorted_enabled_dashboards | length }}
```

---

## 9. Summary Table: Dashboard Sources

| Location | Type | Status | Count | Path | Used By |
|----------|------|--------|-------|------|---------|
| Role Templates | Jinja2 | ACTIVE | 12 | `ansible/roles/monitoring/templates/dashboards/*.j2` | Phase 3 Grafana task |
| Grafonnet Sources | Jsonnet | ACTIVE | 2 | `ansible/roles/monitoring/files/dashboards/jsonnet/*.jsonnet` | Phase 5.5 Generate |
| Root Monitoring | Static JSON | ORPHANED | 3 | `monitoring/grafana/dashboards/*.json` | NONE |
| Backup Role | Jinja2 | DEPRECATED | 10 | `ansible/roles/monitoring.backup/templates/dashboards/*.j2` | NONE |

---

## 10. Deployment Path Clarification

```yaml
# PHASE 3: Templating (File-based provisioning)
Input:  ansible/roles/monitoring/templates/dashboards/infrastructure-health.json.j2
        ├─ Variables from grafana_dashboards registry
        ├─ Team data from jenkins_teams
        └─ Deployment variables
Process: Jinja2 template rendering
Output: /opt/monitoring/grafana/dashboards/infrastructure-health.json
        /opt/monitoring/grafana/dashboards/teams/devops/jenkins-overview-devops.json
        (and others)

Mount:  /opt/monitoring/grafana/dashboards → /var/lib/grafana/dashboards (Grafana container)
Provisioning: Grafana watches /var/lib/grafana/dashboards every 10 seconds

---

# PHASE 5: API Deployment (Currently Broken)
Input:  /opt/monitoring/grafana/dashboards/{id}.json (rendered from Phase 3)
Process: Read JSON files, deploy via Grafana API
Output:  Grafana dashboard objects (if API succeeds)
Status:  BROKEN - File path bug prevents execution

---

# PHASE 5.5: Grafonnet (Separate pipeline)
Input:  ansible/roles/monitoring/files/dashboards/jsonnet/*.jsonnet
Process: Compile with jsonnet compiler (-J vendor)
Output: /opt/monitoring/grafana/dashboards/generated/*.json
        (Should be included in provisioning config)
Mounted: Same mount as Phase 3, but in subdirectory
Provisioning: Currently NOT explicitly configured for /generated/

---

# LEGACY (Not used)
Input:  monitoring/grafana/dashboards/*.json (static, outdated)
Process: None - files never imported
Output:  Nowhere
Status:  Dead code
```

---

## 11. Next Steps

1. **Immediate (Fix Bugs):**
   - Fix file_path bug in phase4-configuration/dashboards.yml (Priority 1)
   - Either remove API deployment or fix it (Priority 5)
   - Add dashboard validation task (Priority 6)

2. **Short Term (Clean Up):**
   - Delete orphaned monitoring/grafana/dashboards/ directory
   - Delete deprecated monitoring.backup role
   - Update documentation

3. **Medium Term (Clarify Architecture):**
   - Decide: Keep file-based provisioning, API deployment, or both?
   - Separate Grafonnet output if keeping both paths
   - Add Grafonnet output to provisioning config

4. **Long Term (Modernize):**
   - Migrate all dashboards to Grafonnet/Jsonnet (Dashboard-as-Code)
   - Remove Jinja2 templated dashboards
   - Leverage full Grafonnet ecosystem for dashboard generation

