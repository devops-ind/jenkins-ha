# Phase 3: Monitoring Modernization - CI/CD Automation & GitOps

## Overview

Phase 3 implements automated dashboard and target deployment through CI/CD pipelines, enabling GitOps-style infrastructure-as-code for the monitoring stack. This phase automates compilation, testing, versioning, and deployment of Grafonnet dashboards and Prometheus target files.

**Goals:**
- Automated Grafonnet compilation in CI/CD pipeline
- Dashboard testing and validation before deployment
- Automated versioning with semantic versioning or timestamps
- GitOps-style deployment (config changes trigger automation)
- Team-based dashboard generation from templates
- Automated rollback on deployment failures
- Change tracking and approval workflows
- Multi-environment deployment (staging → production)

**Timeline:** 2-3 weeks for full implementation
**Complexity:** High (involves CI/CD, Git workflows, automated testing)
**Risk Level:** Medium (requires careful rollback strategy)

---

## Architecture Design

### CI/CD Pipeline Flow

```
GitHub Commit (dashboard changes)
         ↓
GitHub Actions Workflow Triggered
         ↓
1. Checkout Code
         ↓
2. Lint & Validate (Jsonnet syntax, JSON schema)
         ↓
3. Compile Dashboards (jsonnet → JSON)
         ↓
4. Test Dashboards (structure, required fields, variables)
         ↓
5. Generate Change Report (diff dashboards)
         ↓
6. Semantic Versioning (tag commits)
         ↓
7. Create Release
         ↓
8. Deploy to Staging
         ↓
9. Run Smoke Tests
         ↓
10. Deploy to Production (with approval)
         ↓
Commit ✅ Complete
```

### File Organization

```
jenkins-ha/
├── .github/
│   └── workflows/
│       ├── monitoring-lint.yml          (Lint and validate on PR)
│       ├── monitoring-compile.yml       (Compile dashboards)
│       ├── monitoring-test.yml          (Run dashboard tests)
│       ├── monitoring-deploy-staging.yml (Deploy to staging)
│       └── monitoring-deploy-prod.yml   (Deploy to production)
├── ansible/roles/monitoring/
│   ├── tasks/
│   │   ├── phase5-ci-cd/
│   │   │   ├── gitlab-runner-setup.yml (GitLab Runner for self-hosted)
│   │   │   ├── webhook-server.yml      (GitHub webhook receiver)
│   │   │   └── deployment-trigger.yml  (Trigger from Git events)
│   │   ├── phase6-deployment/
│   │   │   ├── deploy-dashboards.yml   (Deploy to Grafana)
│   │   │   ├── deploy-targets.yml      (Deploy to Prometheus)
│   │   │   ├── verify-deployment.yml   (Post-deployment checks)
│   │   │   └── rollback.yml            (Automatic rollback)
│   │   └── phase7-monitoring/
│   │       ├── track-changes.yml       (Change tracking)
│   │       ├── health-checks.yml       (Post-deployment health)
│   │       └── alerts.yml              (Deployment alerts)
│   ├── files/
│   │   ├── dashboards/
│   │   │   ├── jsonnet/
│   │   │   │   ├── team-dashboard.jsonnet    (NEW: template)
│   │   │   │   ├── team-variables.libsonnet (NEW: team data)
│   │   │   │   └── .../
│   │   │   ├── ci-cd/
│   │   │   │   ├── validate.sh         (Validation script)
│   │   │   │   ├── test.sh             (Testing script)
│   │   │   │   ├── compile.sh          (Compilation script)
│   │   │   │   └── generate-changelog.sh
│   │   │   └── deployment/
│   │   │       ├── deploy.sh           (Deployment script)
│   │   │       ├── verify.sh           (Verification script)
│   │   │       └── rollback.sh         (Rollback script)
│   │   └── prometheus/
│   │       └── ci-cd/
│   │           ├── validate-targets.sh (Target validation)
│   │           └── generate-targets.sh (Dynamic generation)
│   └── defaults/
│       ├── phase3-ci-cd-vars.yml       (NEW: CI/CD variables)
│       └── phase3-deployment-vars.yml  (NEW: Deployment config)
└── monitoring/
    ├── dashboards/                      (Source Jsonnet files)
    ├── targets/                         (Source Prometheus targets)
    ├── tests/
    │   ├── dashboard-tests.py          (NEW: Dashboard validation)
    │   ├── target-tests.py             (NEW: Target validation)
    │   ├── integration-tests.py        (NEW: Integration tests)
    │   └── fixtures/
    │       ├── sample-dashboards.json
    │       └── sample-targets.json
    ├── ci-cd/
    │   ├── Makefile                    (NEW: CI/CD automation)
    │   ├── pre-commit-config.yaml      (Enhanced)
    │   ├── .yamllint                   (Lint rules)
    │   └── .jsonnetignore
    ├── .github/
    │   ├── ISSUE_TEMPLATE/
    │   │   └── dashboard-change.md     (NEW: Change proposal)
    │   └── PULL_REQUEST_TEMPLATE/
    │       └── monitoring-changes.md   (NEW: PR template)
    └── docs/
        ├── CI_CD_WORKFLOW.md           (NEW: Workflow documentation)
        ├── DASHBOARD_DEVELOPMENT.md    (NEW: Dev guidelines)
        ├── DEPLOYMENT_RUNBOOK.md       (NEW: Deployment guide)
        └── ROLLBACK_PROCEDURES.md      (NEW: Rollback guide)
```

---

## Implementation Sections

### 1. GitHub Actions Workflows

#### 1.1 Lint & Validation Workflow (`monitoring-lint.yml`)

**Triggers:** On PR to `main`/`feature/*`, Push to `main`

**Steps:**
1. Checkout code
2. Install dependencies (jsonnet, yamllint, jsonschema)
3. Lint Jsonnet files (style guide enforcement)
4. Validate YAML (prometheus.yml, monitoring config)
5. Check for security issues (hard-coded secrets, dangerous patterns)
6. Verify file naming conventions
7. Comment on PR with results

**Key Commands:**
```bash
# Jsonnet linting
jsonnet fmt --check dashboards/jsonnet/*.jsonnet

# YAML validation
yamllint ansible/roles/monitoring/templates/

# Security scanning
truffleHog filesystem --json | grep -i "monitoring"

# File naming check
python3 ci-cd/validate-naming.py dashboards/
```

#### 1.2 Compile & Test Workflow (`monitoring-compile.yml`)

**Triggers:** On PR, merge to `main`

**Steps:**
1. Checkout code
2. Install Grafonnet dependencies (jb install)
3. Compile all Grafonnet dashboards to JSON
4. Validate JSON schema (required fields, structure)
5. Generate test reports
6. Upload artifacts (compiled dashboards)
7. Calculate metrics (panels, variables, complexity)

**Output Artifacts:**
- Compiled JSON dashboards
- Test report (HTML)
- Dashboard metadata (panel count, variables, size)
- Compilation log

#### 1.3 Test Workflow (`monitoring-test.yml`)

**Triggers:** After compile workflow, on PR

**Tests:**
1. **Dashboard Structure Tests:**
   - Required fields (title, uid, panels, variables)
   - Panel types validity
   - Variable definitions correctness
   - Data source references validity

2. **Integration Tests:**
   - Mock Prometheus data validation
   - Mock Loki data validation
   - Query syntax validation
   - Variable interpolation testing

3. **Performance Tests:**
   - Dashboard size check (< 5MB)
   - Panel count limits (< 100 panels)
   - Query complexity analysis

4. **Security Tests:**
   - Hard-coded credentials detection
   - SQL injection patterns in queries
   - XSS vulnerable patterns

**Test Framework:** pytest with custom assertions

#### 1.4 Deploy Staging Workflow (`monitoring-deploy-staging.yml`)

**Triggers:** On merge to `main`

**Steps:**
1. Compile dashboards
2. Deploy to staging Grafana instance
3. Deploy target files to staging Prometheus
4. Run smoke tests
5. Generate deployment report
6. Comment on GitHub commit with results

**Staging Environment:**
- Separate Grafana instance (staging.monitoring.internal)
- Separate Prometheus instance with subset of targets
- Team-specific dashboards deployed for testing

#### 1.5 Deploy Production Workflow (`monitoring-deploy-prod.yml`)

**Triggers:** Manual trigger via GitHub dispatch event

**Steps:**
1. Create deployment PR with changelog
2. Require approvals from CODEOWNERS
3. Create Git tag (semantic version)
4. Compile dashboards
5. Deploy to production Grafana
6. Deploy target files to production Prometheus
7. Run health checks
8. Create GitHub Release
9. Post deployment status (Slack, Teams, email)
10. Monitor for issues (5-minute post-deployment check)

**Approval Requirements:**
- ✅ 2 approvals from monitoring team
- ✅ CI/CD checks passing
- ✅ Staging deployment successful
- ✅ Change log updated

---

### 2. Ansible Playbooks (CI/CD Integration)

#### 2.1 GitHub Webhook Receiver (`webhook-server.yml`)

**Purpose:** Receive GitHub webhook events and trigger local deployments

**Implementation:**
```yaml
- name: Setup GitHub webhook server
  block:
    # Install Python flask app for webhook listening
    - name: Create webhook handler application
      copy:
        content: |
          # Flask app that listens for GitHub webhooks
          # Validates HMAC signature
          # Triggers Ansible playbook on changes
          # Logs all webhook events
        dest: /opt/monitoring/ci-cd/webhook-server.py

    # Setup systemd service
    - name: Create webhook service
      systemd:
        name: github-webhook-monitoring
        enabled: yes
        state: started

    # Configure firewall
    - name: Allow webhook port
      firewalld:
        port: 5000/tcp
        state: enabled

    # Setup log rotation
    - name: Configure webhook log rotation
      template:
        src: logrotate-webhook.j2
        dest: /etc/logrotate.d/github-webhook-monitoring
```

#### 2.2 Deployment Trigger (`deployment-trigger.yml`)

**Purpose:** Automatically trigger deployments on dashboard changes

**Workflow:**
```yaml
- name: Monitor Git repository for changes
  block:
    # Git polling (every 5 minutes)
    - name: Fetch latest changes from Git
      command: git fetch origin main
      args:
        chdir: /opt/monitoring

    # Detect what changed
    - name: Check for dashboard changes
      shell: |
        git diff origin/main..HEAD -- \
          '*.jsonnet' \
          'targets.d/*.json' \
          'prometheus/rules/*.yml'
      register: changed_files

    # Trigger compilation
    - name: Trigger dashboard compilation
      command: make compile-dashboards
      when: "'jsonnet' in changed_files.stdout"

    # Trigger deployment
    - name: Trigger deployment
      command: ansible-playbook phase6-deployment/deploy-dashboards.yml
      when: "'jsonnet' in changed_files.stdout"
```

#### 2.3 Dashboard Deployment (`deploy-dashboards.yml`)

**Purpose:** Deploy compiled dashboards to Grafana

**Steps:**
```yaml
- name: Deploy Grafonnet dashboards to Grafana
  block:
    # Backup existing dashboards
    - name: Backup current dashboards
      shell: |
        curl -u admin:{{ grafana_password }} \
          http://{{ grafana_host }}:{{ grafana_port }}/api/dashboards/uid/{{ item }} \
          > /opt/monitoring/dashboards/.backups/{{ item }}-$(date +%s).json
      loop: "{{ dashboard_uids }}"

    # Upload new dashboards
    - name: Upload dashboards via API
      grafana_dashboard:
        grafana_url: "http://{{ grafana_host }}:{{ grafana_port }}"
        grafana_api_key: "{{ grafana_api_key }}"
        state: present
        dashboard: "{{ lookup('file', item) }}"
        overwrite: yes
      loop: "{{ compiled_dashboards }}"
      register: dashboard_upload

    # Verify deployment
    - name: Verify dashboards deployed
      uri:
        url: "http://{{ grafana_host }}:{{ grafana_port }}/api/dashboards/uid/{{ item.dashboard.uid }}"
        method: GET
        user: "admin"
        password: "{{ grafana_password }}"
      register: verification
      until: verification.status == 200
      retries: 3
      delay: 5
```

#### 2.4 Target Deployment (`deploy-targets.yml`)

**Purpose:** Deploy Prometheus target files

**Steps:**
```yaml
- name: Deploy Prometheus target files
  block:
    # Validate targets
    - name: Validate target JSON syntax
      command: python3 -m json.tool {{ item }}
      loop: "{{ target_files }}"

    # Backup existing targets
    - name: Backup existing targets
      shell: |
        cp -r /opt/monitoring/prometheus/targets.d \
           /opt/monitoring/prometheus/targets.d.backup-$(date +%s)

    # Deploy new targets
    - name: Deploy target files
      copy:
        src: "{{ item.src }}"
        dest: "/opt/monitoring/prometheus/targets.d/{{ item.dest }}"
      loop: "{{ target_deployments }}"
      notify: reload prometheus

    # Verify in Prometheus
    - name: Verify targets in Prometheus
      uri:
        url: "http://{{ prometheus_host }}:{{ prometheus_port }}/api/v1/targets"
        method: GET
      register: prometheus_targets
      until: prometheus_targets.status == 200
      retries: 3
```

#### 2.5 Rollback Playbook (`rollback.yml`)

**Purpose:** Automatic or manual rollback on deployment failure

**Triggers:**
- Health check failures (5 minutes post-deployment)
- High error rate detected
- Manual trigger from operations team

**Steps:**
```yaml
- name: Rollback monitoring stack
  block:
    # Determine rollback point
    - name: Find last known good version
      shell: |
        ls -t /opt/monitoring/dashboards/.backups/ | head -1
      register: last_good_backup

    # Restore dashboards
    - name: Restore dashboards from backup
      copy:
        src: "/opt/monitoring/dashboards/.backups/{{ last_good_backup.stdout }}"
        dest: "/opt/monitoring/dashboards/{{ item }}.json"
      loop: "{{ dashboard_names }}"

    # Restore targets
    - name: Restore target files from backup
      shell: |
        rm -rf /opt/monitoring/prometheus/targets.d
        cp -r /opt/monitoring/prometheus/targets.d.backup-{{ backup_timestamp }} \
              /opt/monitoring/prometheus/targets.d

    # Verify rollback
    - name: Verify rollback successful
      uri:
        url: "http://{{ grafana_host }}:{{ grafana_port }}/api/health"
        method: GET
      register: health_check
      until: health_check.status == 200
      retries: 3

    # Notify team
    - name: Send rollback notification
      slack:
        token: "{{ slack_token }}"
        channel: "#monitoring"
        msg: "Rollback completed. Version: {{ last_good_backup.stdout }}"
```

---

### 3. Testing Framework

#### 3.1 Dashboard Validation Tests (`tests/dashboard-tests.py`)

```python
import json
import pytest
from pathlib import Path

class TestDashboardStructure:
    """Validate dashboard JSON structure and required fields"""

    @pytest.fixture
    def dashboards(self):
        """Load all compiled dashboards"""
        return [json.load(open(f)) for f in Path('dashboards/generated/').glob('*.json')]

    def test_required_fields(self, dashboards):
        """Test all required dashboard fields exist"""
        required = {'title', 'uid', 'panels', 'templating'}
        for dashboard in dashboards:
            assert required.issubset(dashboard.keys()), \
                f"Dashboard {dashboard.get('uid')} missing required fields"

    def test_panel_structure(self, dashboards):
        """Test panel structure validity"""
        for dashboard in dashboards:
            for i, panel in enumerate(dashboard.get('panels', [])):
                if not panel.get('collapsed'):
                    assert 'type' in panel, f"Panel {i} missing type field"
                    assert panel['type'] in VALID_PANEL_TYPES

    def test_datasource_references(self, dashboards):
        """Test datasource UIDs are valid"""
        for dashboard in dashboards:
            for panel in dashboard.get('panels', []):
                datasource = panel.get('datasource')
                if datasource:
                    assert validate_datasource_uid(datasource)

    def test_variable_definitions(self, dashboards):
        """Test variable definitions are correct"""
        for dashboard in dashboards:
            for var in dashboard.get('templating', {}).get('list', []):
                assert 'name' in var
                assert 'type' in var
                assert var['type'] in VALID_VAR_TYPES

class TestDashboardIntegration:
    """Integration tests with real data sources"""

    @pytest.fixture
    def prometheus_mock(self):
        """Mock Prometheus responses"""
        return PrometheusTestFixture()

    @pytest.fixture
    def loki_mock(self):
        """Mock Loki responses"""
        return LokiTestFixture()

    def test_prometheus_queries(self, dashboards, prometheus_mock):
        """Test Prometheus queries execute successfully"""
        for dashboard in dashboards:
            for target in get_prometheus_targets(dashboard):
                result = prometheus_mock.query(target['expr'])
                assert result is not None, f"Query failed: {target['expr']}"

    def test_loki_queries(self, dashboards, loki_mock):
        """Test Loki LogQL queries execute successfully"""
        for dashboard in dashboards:
            for target in get_loki_targets(dashboard):
                result = loki_mock.query(target['expr'])
                assert result is not None, f"LogQL query failed"

    def test_dashboard_rendering(self, dashboards):
        """Test dashboards render without errors"""
        for dashboard in dashboards:
            rendered = render_dashboard(dashboard, sample_data)
            assert rendered is not None
            assert 'error' not in rendered.lower()
```

#### 3.2 Target Validation Tests (`tests/target-tests.py`)

```python
import json
import pytest
from pathlib import Path

class TestTargetFiles:
    """Validate Prometheus target files"""

    @pytest.fixture
    def target_files(self):
        """Load all target files"""
        return {f.name: json.load(open(f))
                for f in Path('targets.d/').glob('*.json')}

    def test_json_syntax(self, target_files):
        """Test all target files have valid JSON"""
        for name, targets in target_files.items():
            assert isinstance(targets, list), f"{name} is not a list"

    def test_target_structure(self, target_files):
        """Test target structure is correct"""
        for name, targets in target_files.items():
            for i, target in enumerate(targets):
                assert 'targets' in target, f"{name}[{i}] missing targets"
                assert 'labels' in target, f"{name}[{i}] missing labels"
                assert isinstance(target['targets'], list)

    def test_label_validity(self, target_files):
        """Test labels follow Prometheus naming conventions"""
        for name, targets in target_files.items():
            for i, target in enumerate(targets):
                for label_name in target.get('labels', {}).keys():
                    assert is_valid_label_name(label_name), \
                        f"Invalid label name: {label_name}"

    def test_target_connectivity(self, target_files):
        """Test targets are reachable"""
        for name, targets in target_files.items():
            for target_addr in flatten_targets(targets):
                assert is_reachable(target_addr), \
                    f"Target unreachable: {target_addr}"
```

---

### 4. CI/CD Scripts

#### 4.1 Compilation Script (`files/dashboards/ci-cd/compile.sh`)

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/generated"
LOG_FILE="/var/log/monitoring/compile-$(date +%s).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Starting dashboard compilation..."

# Create output directory
mkdir -p "$OUTPUT_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Compile each Grafonnet file
COMPILE_ERRORS=0
for jsonnet_file in ${PROJECT_DIR}/jsonnet/*.jsonnet; do
    if [ -f "$jsonnet_file" ]; then
        DASHBOARD_NAME=$(basename "$jsonnet_file" .jsonnet)
        OUTPUT_FILE="${OUTPUT_DIR}/${DASHBOARD_NAME}.json"

        log "Compiling: $DASHBOARD_NAME"

        if jsonnet -J vendor "$jsonnet_file" -o "$OUTPUT_FILE" >> "$LOG_FILE" 2>&1; then
            FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE")
            log "✓ Compiled: $DASHBOARD_NAME ($(echo "scale=1; $FILE_SIZE / 1024" | bc)KB)"
        else
            log "✗ FAILED: $DASHBOARD_NAME"
            COMPILE_ERRORS=$((COMPILE_ERRORS + 1))
        fi
    fi
done

# Report results
if [ $COMPILE_ERRORS -eq 0 ]; then
    log "✅ Compilation completed successfully"
    exit 0
else
    log "❌ Compilation failed with $COMPILE_ERRORS error(s)"
    exit 1
fi
```

#### 4.2 Validation Script (`files/dashboards/ci-cd/validate.sh`)

```bash
#!/bin/bash
set -euo pipefail

DASHBOARD_DIR="${1:-.}"
VALIDATION_ERRORS=0

validate_json() {
    local file=$1
    if ! python3 -m json.tool "$file" > /dev/null 2>&1; then
        echo "❌ Invalid JSON: $file"
        return 1
    fi
    return 0
}

validate_dashboard_structure() {
    local file=$1
    python3 << EOF
import json
import sys

try:
    with open("$file") as f:
        dashboard = json.load(f)

    required = {'title', 'uid', 'panels', 'templating'}
    if not required.issubset(dashboard.keys()):
        print("Missing required fields: {required - dashboard.keys()}")
        sys.exit(1)

    print("✓ Valid structure: $(basename $file)")
    sys.exit(0)
except Exception as e:
    print(f"✗ Validation failed: {e}")
    sys.exit(1)
EOF
}

# Validate all dashboards
for dashboard in "$DASHBOARD_DIR"/*.json; do
    if [ -f "$dashboard" ]; then
        if ! validate_json "$dashboard"; then
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        fi

        if ! validate_dashboard_structure "$dashboard"; then
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        fi
    fi
done

if [ $VALIDATION_ERRORS -eq 0 ]; then
    echo "✅ All dashboards validated"
    exit 0
else
    echo "❌ Validation failed with $VALIDATION_ERRORS error(s)"
    exit 1
fi
```

---

### 5. Configuration Variables

#### 5.1 Phase 3 CI/CD Variables (`defaults/phase3-ci-cd-vars.yml`)

```yaml
# GitHub Integration
github_webhook_enabled: true
github_webhook_port: 5000
github_webhook_secret: "{{ vault_github_webhook_secret }}"
github_repo_url: "https://github.com/{{ github_org }}/jenkins-ha"
github_branch: "main"

# CI/CD Triggers
cicd_auto_deploy_staging: true
cicd_auto_deploy_production: false  # Require manual approval
cicd_deployment_approval_required: true
cicd_deployment_approvers:
  - "monitoring-team"
  - "devops-leads"

# Compilation Settings
grafonnet_compile_timeout: 30  # seconds
grafonnet_compile_retries: 3
jsonnet_optimization_level: 2

# Testing Configuration
cicd_run_integration_tests: true
cicd_run_performance_tests: true
cicd_run_security_tests: true
cicd_test_timeout: 300  # seconds

# Deployment Strategy
cicd_deployment_strategy: "blue-green"  # or "canary", "rolling"
cicd_pre_deployment_check_timeout: 300
cicd_post_deployment_check_timeout: 300
cicd_post_deployment_check_interval: 30

# Rollback Configuration
cicd_auto_rollback_on_error: true
cicd_auto_rollback_timeout: 600  # 10 minutes
cicd_rollback_retention_versions: 5

# Versioning
cicd_semantic_versioning: true
cicd_version_prefix: "v"
cicd_changelog_auto_generate: true

# Notifications
cicd_slack_notifications_enabled: true
cicd_slack_channel: "#monitoring"
cicd_slack_webhook: "{{ vault_slack_webhook_monitoring }}"
cicd_email_notifications_enabled: true
cicd_email_recipients:
  - "monitoring-team@company.com"
  - "ops-lead@company.com"

# Logging
cicd_log_level: "INFO"
cicd_log_retention_days: 30
cicd_log_archive_enabled: true
cicd_log_archive_location: "/var/log/monitoring/archive"
```

---

## Implementation Sequence

### Week 1: Foundation & GitHub Workflows
1. **Day 1-2:** Setup GitHub Actions workflows structure
   - Create `.github/workflows/` directory
   - Implement monitoring-lint.yml
   - Implement monitoring-compile.yml
   - Test with sample changes

2. **Day 3-4:** Testing framework
   - Create pytest test suite (dashboard-tests.py, target-tests.py)
   - Implement monitoring-test.yml
   - Add test fixtures and sample data
   - Test framework with existing dashboards

3. **Day 5:** CI/CD scripts
   - Implement validation, compilation, and testing scripts
   - Add error handling and logging
   - Test scripts locally before committing

### Week 2: Deployment & Integration
1. **Day 1-2:** Ansible playbooks for deployment
   - Create phase5-ci-cd tasks
   - Implement webhook server setup
   - Implement deployment triggers
   - Setup Grafana and Prometheus API integration

2. **Day 3-4:** GitHub webhook integration
   - Setup webhook receiver service
   - Test GitHub → webhook → Ansible flow
   - Implement signature validation
   - Add logging and error handling

3. **Day 5:** Staging deployment workflow
   - Implement monitoring-deploy-staging.yml
   - Setup staging Grafana instance
   - Setup staging Prometheus instance
   - Test end-to-end staging deployment

### Week 3: Production & Automation
1. **Day 1-2:** Production deployment workflow
   - Implement monitoring-deploy-prod.yml
   - Setup approval requirements
   - Implement semantic versioning
   - Create GitHub Release automation

2. **Day 3:** Rollback automation
   - Implement automatic health checks
   - Implement auto-rollback logic
   - Test rollback procedures
   - Document rollback runbook

3. **Day 4-5:** Documentation & hardening
   - Write CI/CD workflow documentation
   - Create deployment runbook
   - Create rollback procedures
   - Security audit of workflows
   - User training and handoff

---

## Testing Strategy

### Unit Tests
- Dashboard JSON structure validation
- Target file format validation
- Jsonnet syntax compilation
- Variable and datasource reference validation

### Integration Tests
- Mock Prometheus data queries
- Mock Loki LogQL queries
- Dashboard rendering with sample data
- Target connectivity verification

### Staging Tests
- Deploy to staging Grafana/Prometheus
- Run health checks
- Verify dashboards appear in UI
- Verify targets load successfully

### Production Tests
- 5-minute post-deployment health check
- Query sample metrics from dashboards
- Verify no increase in error rates
- Monitor resource utilization

---

## Rollback Strategy

**Automatic Rollback Triggers:**
1. Health check failures (3 consecutive failures)
2. High error rate (> 5% requests failing)
3. Prometheus scrape failures (> 50% targets down)
4. Manual trigger from operations

**Rollback Procedure:**
1. Identify last known good version
2. Restore dashboards from backup
3. Restore target files from backup
4. Verify health checks pass
5. Notify monitoring team
6. Post-incident review

**Rollback Testing:**
- Test rollback on staging weekly
- Document any issues found
- Update runbook based on learnings

---

## Risk Assessment

### Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|-----------|
| CI/CD failure breaks production | High | Medium | Comprehensive testing, staging deployment, manual approvals |
| Webhook secret exposure | Critical | Low | Vault-based secret management, rotation policy |
| Dashboard incompatibility | Medium | Medium | Integration tests, staging validation before production |
| Target file syntax errors | Medium | Low | JSON validation, syntax checking in CI |
| Rollback failure | High | Low | Automated backup, version control, runbook testing |
| Team workflow disruption | Medium | Medium | Clear documentation, gradual rollout, training sessions |

---

## Success Metrics

- ✅ 100% of dashboard changes go through CI/CD pipeline
- ✅ Zero production incidents caused by dashboard/target changes
- ✅ < 5 minute deployment time (staging)
- ✅ < 2 minute rollback time
- ✅ All automated tests passing before production deployment
- ✅ Zero manual Grafana/Prometheus configuration changes
- ✅ Complete Git audit trail of all changes

---

## Future Enhancements (Phase 3.5+)

1. **Multi-Environment Support**
   - Dev/Staging/Production separate environments
   - Environment-specific variables
   - Promotion workflows (dev → staging → prod)

2. **Team-Based Dashboards**
   - Dynamic dashboard generation per team
   - Team-specific variables (retention, environments)
   - Automated team dashboard updates

3. **Dashboard Distribution**
   - Team approval workflows for dashboard changes
   - Dashboard versioning per team
   - Team-specific rollback capability

4. **Advanced GitOps**
   - Complete config-as-code for all settings
   - Drift detection and auto-remediation
   - Policy enforcement (e.g., no hardcoded secrets)

5. **Observability Improvement**
   - Metrics on deployment frequency/duration
   - DORA metrics integration
   - Change failure rate tracking

---

## Documentation Deliverables

1. **CI_CD_WORKFLOW.md** - Complete workflow documentation
2. **DASHBOARD_DEVELOPMENT.md** - Developer guidelines
3. **DEPLOYMENT_RUNBOOK.md** - Step-by-step deployment guide
4. **ROLLBACK_PROCEDURES.md** - Rollback procedures and testing
5. **TROUBLESHOOTING.md** - Common issues and solutions
6. **WEBHOOK_SETUP.md** - GitHub webhook configuration
7. **GITHUB_ACTIONS_GUIDE.md** - Custom workflow development

---

## Conclusion

Phase 3 transforms manual monitoring stack management into a fully automated GitOps-based workflow. With comprehensive testing, multiple approval gates, and robust rollback procedures, it enables rapid iteration while maintaining production stability.

**Estimated Effort:**
- Development: 15-20 engineer-days
- Testing: 5-10 engineer-days
- Documentation & Training: 5 engineer-days
- **Total: 25-35 engineer-days (~5-7 weeks for 1 engineer)**

**Recommended Approach:**
- Start with GitHub Actions workflows (Week 1-2)
- Add staging deployment validation (Week 2)
- Gradually enable production deployments with approvals
- Monitor closely for first 2 weeks in production
- Iterate based on team feedback
