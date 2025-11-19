# Dashboard Deployment Architecture - Quick Reference

## Three Conflicting Systems

### 1. Phase 3: Jinja2 Templating (ACTIVE & WORKING)
- **Source:** `ansible/roles/monitoring/templates/dashboards/*.j2` (12 templates)
- **Process:** Rendered by `phase3-servers/grafana.yml`
- **Output:** `/opt/monitoring/grafana/dashboards/{id}.json` + `teams/{team}/{id}-{team}.json`
- **Discovery:** File-based provisioning (every 10 seconds)
- **Status:** Working correctly, all dashboards deployed

### 2. Phase 5: API Deployment (BROKEN)
- **Source:** Same Phase 3 output files
- **Process:** Read by `phase4-configuration/dashboards.yml`
- **Bug:** Lines 73-76 use `file_path: "{{ config.template_file }}"` which includes `.j2` extension
- **Failure Point:** Tries to read `.j2` files as JSON → file not found
- **Status:** Never completes, throws error

### 3. Phase 5.5: Grafonnet (SEPARATE MODERNIZATION)
- **Source:** `ansible/roles/monitoring/files/dashboards/jsonnet/*.jsonnet` (2 dashboards)
- **Process:** Compiled by `phase4-dashboards/generate-dashboards.yml`
- **Output:** `/opt/monitoring/grafana/dashboards/generated/{name}.json`
- **Discovery:** File-based provisioning (if path included)
- **Collision:** Overwrites Phase 3 output if same filename
- **Status:** Generates successfully, but not integrated with main dashboards

## Critical Bugs Found

### BUG 1: File Path with .j2 Extension (CRITICAL)
**Location:** `phase4-configuration/dashboards.yml` line 75
```yaml
"file_path": "{{ config.template_file }}"  # WRONG: "infrastructure-health.json.j2"
```
**Should Be:**
```yaml
"file_path": "{{ dashboard_id }}.json"  # CORRECT: "infrastructure-health.json"
```

### BUG 2: Reading .j2 File as JSON
**Location:** `phase4-configuration/dashboards.yml` line 120
```yaml
src: "{{ monitoring_home_dir }}/grafana/dashboards/{{ item.file_path | default(item.template_file) }}"
```
Attempts to read `/opt/monitoring/grafana/dashboards/infrastructure-health.json.j2` (doesn't exist)

### BUG 3: Unclear Grafonnet Integration
**Location:** `ansible/roles/monitoring/defaults/main.yml` lines 458-473
- `grafonnet_dashboards` list has no metadata (enabled, output location, etc.)
- Output to `generated/` subdirectory not validated
- Provisioning config doesn't explicitly include `generated/` path

## Orphaned Code

### 1. Legacy Static Dashboards
**Path:** `monitoring/grafana/dashboards/` (3 files)
- jenkins-overview.json (489 bytes, 1 panel - outdated)
- jenkins-blue-green.json (13,126 bytes)
- jenkins-comprehensive.json (15,622 bytes)
**Status:** Never deployed, never referenced, just sitting there

### 2. Deprecated Backup Role
**Path:** `ansible/roles/monitoring.backup/` (39 files)
- Complete copy of old role architecture
- Never imported in site.yml
- Causes confusion about source of truth

## Recommended Fixes (Priority Order)

### 1. FIX THE FILE PATH BUG (5 minutes)
Edit `ansible/roles/monitoring/tasks/phase4-configuration/dashboards.yml`:
- Line 75: Change `"file_path": "{{ config.template_file }}"` to `"file_path": "{{ dashboard_id }}.json"`

### 2. REMOVE API DEPLOYMENT (Optional)
- Phase 5 (dashboards.yml) is broken and unnecessary
- Phase 3 already deploys dashboards successfully
- Option: Delete phase5 or rename to verification-only

### 3. SEPARATE GRAFONNET OUTPUT
- Change output directory from `/dashboards/generated/` to `/dashboards-generated/`
- Add second provisioning provider for Grafonnet
- Or move Grafonnet files to root with `-modern` suffix

### 4. DELETE ORPHANED CODE
- Remove `monitoring/grafana/dashboards/` directory
- Remove `ansible/roles/monitoring.backup/` directory
- Clean up old commented variables

### 5. ADD VALIDATION
- Create `phase4-configuration/validate-dashboards.yml`
- Verify all dashboard files exist
- Verify JSON structure is valid
- Verify Grafana discovered all dashboards

## Current Deployment Flow (With Bugs)

```
Phase 3: ✓ Success
  - Renders all 12 Jinja2 templates
  - Deploys to /opt/monitoring/grafana/dashboards/
  - Grafana discovers them via file watcher
  - Users see all dashboards in Grafana

Phase 5: ✗ FAILS
  - Tries to read .j2 files from disk
  - File paths have .j2 extension (wrong)
  - JSON parsing fails
  - Error logged, but Phase 3 already worked so nothing breaks

Phase 5.5: ✓ Partial Success
  - Generates 2 Grafonnet dashboards
  - Places in /dashboards/generated/
  - May or may not be discovered by Grafana
  - Overwrites Phase 3 if same filename

Result: Users see Phase 3 + 5.5 dashboards, never know Phase 5 failed
```

## Files to Review (Most Critical)

1. **Absolute Priority:** `ansible/roles/monitoring/tasks/phase4-configuration/dashboards.yml` (lines 54-125)
   - Bug is here
   - Controls file path generation and reading

2. **High Priority:** `ansible/roles/monitoring/defaults/main.yml` (lines 104-232)
   - Registry with .j2 in template_file values
   - Dashboard deployment controls
   - Grafonnet configuration

3. **High Priority:** `ansible/roles/monitoring/tasks/main.yml` (lines 171-201)
   - Phase ordering
   - Conditional execution logic

4. **Medium Priority:** `ansible/roles/monitoring/tasks/phase3-servers/grafana.yml` (lines 100-125)
   - Where Phase 3 rendering happens
   - Working correctly, but referenced by broken Phase 5

5. **Cleanup:** 
   - Delete `monitoring/grafana/dashboards/`
   - Delete `ansible/roles/monitoring.backup/`

## Quick Stats

- **Total Dashboard Sources:** 3 systems (Jinja2, Grafonnet, Legacy static)
- **Total Dashboard Files:** 29 files across 4 locations
- **Active Dashboards:** 12 (Jinja2) + 2 (Grafonnet)
- **Broken Deployment Paths:** 1 (Phase 5 API)
- **Orphaned Code:** 2 (monitoring/, .backup role)
- **Critical Bugs:** 1 (file path with .j2)
- **Lines of Code in Analysis:** 916 lines
