# Dashboard Deployment Architecture Migration Guide

## What Changed

### Removed
- ❌ **Phase 5 API deployment** (phase4-configuration/dashboards.yml) - DELETED
  - Broken file path bug (used .j2 extension incorrectly)
  - Redundant with Phase 3 file-based provisioning
  - Never completed successfully
- ❌ **Legacy static dashboards** (monitoring/grafana/dashboards/) - DELETED
  - jenkins-overview.json (489 bytes, outdated)
  - jenkins-blue-green.json (13 KB, never deployed)
  - jenkins-comprehensive.json (15 KB, superseded by templates)
- ❌ **Backup role** (ansible/roles/monitoring.backup/) - DELETED
  - 39 files from deprecated architecture
  - Never imported in site.yml
  - Caused confusion about source of truth

### Consolidated
- ✅ **Phase 3: Jinja2 Templating (PRIMARY)** - Flag: `dashboard_jinja2_enabled`
  - Production-ready, working perfectly
  - 12 templates in ansible/roles/monitoring/templates/dashboards/
  - File-based provisioning with 10-second refresh
  - Team-specific dashboard generation

- ✅ **Phase 5.5: Grafonnet (OPTIONAL)** - Flag: `grafonnet_enabled`
  - Dashboard-as-Code with Jsonnet
  - Separate output directory (no collision with Jinja2)
  - 2 dashboards: infrastructure-health, jenkins-overview
  - Opt-in modernization track

### New Configuration

#### Enable/Disable Dashboards

```yaml
# In defaults/main.yml or inventory group_vars
dashboard_jinja2_enabled: true    # Jinja2 templates (recommended for production)
grafonnet_enabled: true           # Grafonnet dashboards (optional modernization)
```

#### Output Directories

| System | Host Path | Container Path | Purpose |
|--------|-----------|----------------|---------|
| Jinja2 | `/opt/monitoring/grafana/dashboards/` | `/var/lib/grafana/dashboards` | Primary production dashboards |
| Grafonnet | `/opt/monitoring/grafana/dashboards-generated/` | `/var/lib/grafana/dashboards-generated` | Generated modern dashboards |

#### Grafana Provisioning

```yaml
# Two separate providers (no conflicts)
providers:
  - name: 'Jenkins Infrastructure - Jinja2'
    path: /var/lib/grafana/dashboards          # Jinja2 templates
    folder: ''                                  # Root folder in Grafana

  - name: 'Jenkins Infrastructure - Grafonnet'
    path: /var/lib/grafana/dashboards-generated  # Grafonnet output
    folder: 'Generated'                          # Separate folder in Grafana UI
```

---

## Migration Steps

### For Existing Deployments

#### Step 1: Backup Current Dashboards (Optional)

```bash
# Backup Jinja2 dashboards
cp -r /opt/monitoring/grafana/dashboards /tmp/dashboards-backup-$(date +%Y%m%d)

# Backup Grafonnet dashboards (if exist)
cp -r /opt/monitoring/grafana/dashboards/generated /tmp/dashboards-generated-backup-$(date +%Y%m%d) 2>/dev/null || true
```

#### Step 2: Pull Latest Code

```bash
git pull origin feature/production-monitoring-improvements-v2
```

#### Step 3: Review Configuration

```bash
# Check new flags in defaults
grep -A 2 "dashboard_jinja2_enabled\|grafonnet_enabled" ansible/roles/monitoring/defaults/main.yml

# Check Grafonnet output directory changed
grep "grafonnet_output_dir" ansible/roles/monitoring/defaults/main.yml
```

#### Step 4: Deploy Updated Role

```bash
# Deploy monitoring role with new architecture
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Or deploy just Grafana server updates
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,phase3-servers,grafana
```

#### Step 5: Verify Dashboards in Grafana

1. **Access Grafana:** http://<monitoring-vm-ip>:9300
2. **Check Jinja2 dashboards:**
   - Should see 12 dashboards in root folder
   - Team-specific dashboards in team subfolders
3. **Check Grafonnet dashboards (if enabled):**
   - Should see 2 dashboards in "Generated" folder
   - infrastructure-health-modern, jenkins-overview-modern

#### Step 6: Verify No Errors

```bash
# Check Grafana logs
docker logs grafana-production | grep -i error

# Check dashboard provisioning
docker exec grafana-production ls -la /var/lib/grafana/dashboards/
docker exec grafana-production ls -la /var/lib/grafana/dashboards-generated/

# Check provisioning config
docker exec grafana-production cat /etc/grafana/provisioning/dashboards/dashboard.yml
```

#### Step 7: Cleanup Validation

```bash
# Verify legacy files removed
ls monitoring/grafana/dashboards/ 2>&1 | grep "No such file"  # Should error (deleted)
ls ansible/roles/monitoring.backup/ 2>&1 | grep "No such file"  # Should error (deleted)

# Verify broken API deployment removed
ls ansible/roles/monitoring/tasks/phase4-configuration/dashboards.yml 2>&1 | grep "No such file"  # Should error (deleted)
```

---

## Dashboard Source of Truth

### Deployment Strategy Options

#### **Production (Recommended)**
```yaml
# Use only Jinja2 templates (proven, stable)
dashboard_jinja2_enabled: true
grafonnet_enabled: false
```

**Benefits:**
- Production-ready, battle-tested
- Fast file-based provisioning
- Easy to customize with Jinja2 variables
- Full team-specific dashboard support

---

#### **Modernization Track (Optional)**
```yaml
# Use both systems (migration period)
dashboard_jinja2_enabled: true    # Keep as fallback
grafonnet_enabled: true           # Enable Grafonnet alongside
```

**Benefits:**
- Gradual migration to Dashboard-as-Code
- Compare Jinja2 vs Grafonnet side-by-side
- No disruption to production dashboards
- Separate folders prevent confusion

**Use Case:**
- Evaluating Grafonnet for future adoption
- Developing modern dashboards while maintaining production
- Team training on Dashboard-as-Code practices

---

#### **Grafonnet Only (Future)**
```yaml
# Use only Grafonnet (full modernization)
dashboard_jinja2_enabled: false
grafonnet_enabled: true
```

**Benefits:**
- Version-controlled dashboard source (Jsonnet)
- Reusable dashboard components (lib/common.libsonnet)
- Type-safe dashboard generation
- Easier testing and validation

**Requirements:**
- All dashboards migrated to Jsonnet
- Team trained on Grafonnet syntax
- CI/CD pipeline for dashboard compilation

---

## Configuration Reference

### New Variables in defaults/main.yml

```yaml
# Dashboard Deployment Control Flags (NEW)
dashboard_jinja2_enabled: true   # Enable Jinja2 template-based dashboards (Phase 3)
dashboard_grafonnet_enabled: "{{ grafonnet_enabled | default(true) }}"  # Enable Grafonnet dashboards (Phase 5.5)

# Updated dashboard_deployment section
dashboard_deployment:
  core_enabled: true
  enhanced_enabled: "{{ jenkins_enhanced_dashboards_enabled | default(true) }}"
  update_mode: "always"
  validation_strict: false

  # Jinja2 templating controls (Phase 3)
  jinja2_enabled: "{{ dashboard_jinja2_enabled | default(true) }}"

  # Team-specific dashboard generation
  generate_team_specific: true
  keep_global_dashboards: true
  team_folder_organization: true
  team_dashboard_separator: "-"

# Updated Grafonnet configuration
grafonnet_enabled: true
grafonnet_project_dir: "/opt/grafonnet"
grafonnet_output_dir: "{{ monitoring_home_dir }}/grafana/dashboards-generated"  # CHANGED: Separate directory
grafonnet_container_mount: "/var/lib/grafana/dashboards-generated"  # NEW
grafonnet_backup_retention_days: 30
grafonnet_backup_versions: 7
```

### Inventory Override Examples

#### Per-Environment Configuration

```yaml
# ansible/inventories/production/group_vars/monitoring.yml
dashboard_jinja2_enabled: true
grafonnet_enabled: false  # Disable in production initially

# ansible/inventories/staging/group_vars/monitoring.yml
dashboard_jinja2_enabled: true
grafonnet_enabled: true   # Test Grafonnet in staging
```

#### Per-Host Configuration

```yaml
# ansible/inventories/production/host_vars/monitoring-vm1.yml
dashboard_jinja2_enabled: true
grafonnet_enabled: true
```

---

## Troubleshooting

### Issue: Dashboards not appearing in Grafana

**Symptoms:**
- Grafana UI shows no dashboards
- Empty dashboard list

**Diagnosis:**

1. **Check provisioning config:**
   ```bash
   docker exec grafana-production cat /etc/grafana/provisioning/dashboards/dashboard.yml
   ```

   **Expected:** Should show providers for both Jinja2 and Grafonnet paths

2. **Check dashboard files exist:**
   ```bash
   # Jinja2 dashboards
   ls -la /opt/monitoring/grafana/dashboards/*.json

   # Grafonnet dashboards
   ls -la /opt/monitoring/grafana/dashboards-generated/*.json
   ```

   **Expected:** Jinja2: 12+ JSON files, Grafonnet: 2 JSON files

3. **Check Grafana logs:**
   ```bash
   docker logs grafana-production | grep -i "dashboard\|provisioning"
   ```

   **Look for:** Provisioning errors, file read failures, JSON parse errors

**Resolution:**

```bash
# Restart Grafana to reload provisioning
docker restart grafana-production

# Wait 30 seconds for startup
sleep 30

# Verify dashboards loaded
curl -s http://localhost:9300/api/search | jq '.[] | {title, type}'
```

---

### Issue: Duplicate dashboards

**Symptoms:**
- Two dashboards with same name
- infrastructure-health appears twice

**Diagnosis:**

```bash
# Check if both systems generating same filename
ls -la /opt/monitoring/grafana/dashboards/ | grep infrastructure-health
ls -la /opt/monitoring/grafana/dashboards-generated/ | grep infrastructure-health
```

**Cause:** Both Jinja2 and Grafonnet generating `infrastructure-health.json`

**Resolution - Option A (Disable Grafonnet):**
```yaml
# In inventory or defaults
grafonnet_enabled: false
```

**Resolution - Option B (Rename Grafonnet output):**
```bash
# Edit Grafonnet Jsonnet files to add suffix
# e.g., infrastructure-health-modern.json
```

**Resolution - Option C (Use separate folders):**
Already implemented - Grafonnet dashboards go to "Generated" folder in Grafana UI

---

### Issue: Old dashboards still showing

**Symptoms:**
- Dashboards show old data
- Changes not reflected in Grafana

**Cause:** Grafana cached old provisioning

**Resolution:**

```bash
# Full Grafana restart
docker restart grafana-production

# Or reload provisioning via API
curl -X POST http://admin:admin123@localhost:9300/api/admin/provisioning/dashboards/reload
```

---

### Issue: Grafonnet dashboards not generating

**Symptoms:**
- `/opt/monitoring/grafana/dashboards-generated/` is empty
- Phase 5.5 tasks show "skipped"

**Diagnosis:**

1. **Check flag:**
   ```bash
   ansible-playbook ansible/site.yml --tags monitoring -e "grafonnet_enabled=true" --check
   ```

2. **Check Jsonnet files exist:**
   ```bash
   ls -la /opt/grafonnet/*.jsonnet
   ls -la ansible/roles/monitoring/files/dashboards/jsonnet/
   ```

3. **Check Grafonnet tools installed:**
   ```bash
   which jsonnet jb
   ```

**Resolution:**

```bash
# Enable Grafonnet
# In defaults/main.yml or inventory:
grafonnet_enabled: true

# Run Grafonnet setup
ansible-playbook ansible/site.yml --tags monitoring,grafonnet,setup

# Generate dashboards
ansible-playbook ansible/site.yml --tags monitoring,grafonnet,generate
```

---

### Issue: Permission denied on dashboard files

**Symptoms:**
- Grafana logs show "permission denied"
- Dashboard files exist but not readable

**Diagnosis:**

```bash
# Check file ownership
ls -la /opt/monitoring/grafana/dashboards/
ls -la /opt/monitoring/grafana/dashboards-generated/

# Check Grafana container user
docker exec grafana-production id
```

**Resolution:**

```bash
# Fix ownership
sudo chown -R 1004:1004 /opt/monitoring/grafana/dashboards/
sudo chown -R 1004:1004 /opt/monitoring/grafana/dashboards-generated/

# Fix permissions
sudo chmod -R 755 /opt/monitoring/grafana/dashboards/
sudo chmod 644 /opt/monitoring/grafana/dashboards/*.json
sudo chmod 644 /opt/monitoring/grafana/dashboards-generated/*.json

# Restart Grafana
docker restart grafana-production
```

---

## Performance Impact

### Before Migration
- **3 deployment systems** running:
  - Phase 3: Jinja2 templating ✅ (working)
  - Phase 5: API deployment ❌ (broken, failing silently)
  - Phase 5.5: Grafonnet ⚠️ (working but overlapping)
- **Processing:** 3× redundant deployment logic
- **Conflicts:** Name collisions, unclear source of truth
- **Maintenance:** Bug in API deployment requiring tracking

### After Migration
- **1-2 deployment systems** (configurable):
  - Phase 3: Jinja2 templating (if enabled)
  - Phase 5.5: Grafonnet (if enabled)
- **Processing:** Only enabled systems run
- **No conflicts:** Separate output directories
- **Maintenance:** Clean architecture, no broken code

### Grafana Performance
- **Load time:** Unchanged (file-based provisioning, 10s refresh)
- **Memory:** Slightly reduced (no duplicate dashboards)
- **API calls:** Reduced (no broken API deployment attempts)

---

## Rollback Plan

If issues occur after migration:

### Immediate Rollback (Git)

```bash
# Find previous commit
git log --oneline -5

# Rollback to previous commit
git checkout <previous-commit-hash>

# Redeploy
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring
```

### Partial Rollback (Configuration)

```bash
# Disable new features, keep old behavior
# Edit ansible/inventories/production/group_vars/all/main.yml:

dashboard_jinja2_enabled: true   # Keep Jinja2 working
grafonnet_enabled: false         # Disable Grafonnet

# Redeploy
ansible-playbook ansible/site.yml --tags monitoring
```

### Manual Rollback (Restore Legacy Files)

**If you backed up legacy files:**

```bash
# Restore legacy dashboards (if backed up before migration)
cp -r /tmp/dashboards-backup-YYYYMMDD/* /opt/monitoring/grafana/dashboards/

# Restart Grafana
docker restart grafana-production
```

**Note:** API deployment (Phase 5) cannot be restored as it was broken. Jinja2 provisioning is sufficient.

---

## Migration Validation Checklist

After completing migration:

### Configuration
- [ ] `dashboard_jinja2_enabled` flag exists in defaults/main.yml
- [ ] `grafonnet_enabled` flag exists and referenced
- [ ] `grafonnet_output_dir` updated to `/dashboards-generated/`
- [ ] `monitoring_directories` includes dashboards-generated
- [ ] `dashboard_deployment.jinja2_enabled` controls Phase 3 deployment

### Code Cleanup
- [ ] `phase4-configuration/dashboards.yml` file deleted
- [ ] `monitoring/grafana/dashboards/` directory deleted
- [ ] `ansible/roles/monitoring.backup/` directory deleted
- [ ] No references to deleted files in active code
- [ ] Phase 5 import removed from main.yml

### Provisioning
- [ ] `dashboard.yml.j2` has two providers (Jinja2 + Grafonnet)
- [ ] Provider 1 points to `/var/lib/grafana/dashboards`
- [ ] Provider 2 points to `/var/lib/grafana/dashboards-generated`
- [ ] Grafana container has both volume mounts

### Deployment
- [ ] Ansible syntax check passes
- [ ] Jinja2 dashboards deploy to correct directory
- [ ] Grafonnet dashboards deploy to separate directory
- [ ] Grafana discovers both dashboard sources
- [ ] No duplicate dashboard names in Grafana UI

### Functionality
- [ ] All 12 Jinja2 dashboards visible in Grafana
- [ ] Team-specific dashboards generated correctly
- [ ] Grafonnet dashboards in "Generated" folder (if enabled)
- [ ] Disabling `dashboard_jinja2_enabled` stops Jinja2 deployment
- [ ] Disabling `grafonnet_enabled` stops Grafonnet deployment
- [ ] Dashboards update within 10 seconds of file changes

---

## Future Roadmap

### Short Term (1-3 months)
- [ ] Evaluate Grafonnet dashboards in staging
- [ ] Compare Jinja2 vs Grafonnet dashboard quality
- [ ] Train team on Grafonnet/Jsonnet syntax
- [ ] Migrate 2-3 dashboards to Grafonnet

### Medium Term (3-6 months)
- [ ] Migrate all core dashboards to Grafonnet
- [ ] Establish Dashboard-as-Code best practices
- [ ] Set up CI/CD for dashboard validation
- [ ] Implement automated dashboard testing

### Long Term (6-12 months)
- [ ] Full Grafonnet migration (disable Jinja2)
- [ ] Unified dashboard component library
- [ ] Automated dashboard generation from metrics
- [ ] Integration with monitoring-as-code pipeline

---

## Support and References

### Documentation
- Grafana Provisioning: https://grafana.com/docs/grafana/latest/administration/provisioning/
- Grafonnet Library: https://github.com/grafana/grafonnet
- Jsonnet Language: https://jsonnet.org/

### Internal Resources
- Dashboard Architecture Analysis: `examples/DASHBOARD_DEPLOYMENT_ARCHITECTURE_ANALYSIS.md`
- Quick Reference Guide: `examples/DASHBOARD_DEPLOYMENT_QUICK_REFERENCE.md`
- Architecture Diagram: `examples/DASHBOARD_DEPLOYMENT_ARCHITECTURE_DIAGRAM.txt`

### Getting Help
- Check Grafana logs: `docker logs grafana-production`
- Check provisioning: `docker exec grafana-production cat /etc/grafana/provisioning/dashboards/dashboard.yml`
- Verify files: `ls -la /opt/monitoring/grafana/dashboards*`
- Review role defaults: `ansible/roles/monitoring/defaults/main.yml`

---

## Summary

This migration consolidates three conflicting dashboard deployment systems into a clean, configurable architecture:

**Removed:**
- Broken API deployment (Phase 5)
- Orphaned legacy dashboards
- Deprecated backup role

**Consolidated:**
- Jinja2 templating (proven, production-ready)
- Grafonnet modernization (optional, separate)

**Benefits:**
- Clear separation of concerns
- No name collisions or conflicts
- Configurable deployment strategies
- Clean codebase for future development

The architecture now supports flexible deployment strategies from proven Jinja2 templates to modern Dashboard-as-Code with Grafonnet, with smooth migration paths between them.
