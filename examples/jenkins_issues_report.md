# Jenkins Infrastructure Issues & Resolutions Report

## Executive Summary

This document outlines two critical Jenkins infrastructure issues encountered during recent deployments and their corresponding solutions. Both issues relate to configuration management and automation workflows within a containerized Jenkins environment.

---

## Issue #1: Jenkins Environment Variable URL Configuration

### Problem Description
**Date**: September 4, 2025  
**Severity**: Medium  
**Impact**: Build notifications, API responses, and dashboard links contain placeholder URLs

During Jenkins job execution, the `printenv` command revealed that the `RUN_CHANGES_DISPLAY_URL` environment variable contained an invalid placeholder URL:

```bash
RUN_CHANGES_DISPLAY_URL=http://unconfigured-jenkins-location/job/event_manager/job/P-118-Restart-VM/200/display/redirect?page=changes
```

### Root Cause Analysis
The Jenkins instance was not properly configured with its actual URL location. When Jenkins is deployed without explicit URL configuration, it defaults to using the placeholder "unconfigured-jenkins-location" in various system-generated URLs.

### Resolution
Three solution approaches were provided to address this configuration issue:

#### Solution 1: Jenkins Web UI Configuration
1. Navigate to **Manage Jenkins** → **Configure System**
2. Locate the **Jenkins Location** section
3. Set the correct **Jenkins URL** (e.g., `https://your-jenkins-domain.com/`)
4. Save configuration

#### Solution 2: Configuration as Code (JCasC)
For infrastructure-as-code deployments, add the following to the Jenkins Configuration as Code YAML:

```yaml
unclassified:
  location:
    url: "https://your-jenkins-domain.com/"
```

#### Solution 3: System Property Configuration
Add the following system properties to Jenkins startup options:
```bash
-Dhudson.model.ParametersAction.keepUndefinedParameters=true
-Djenkins.model.Jenkins.slaveAgentPort=50000
-Dhudson.model.DirectoryBrowserSupport.CSP=
-Djenkins.install.runSetupWizard=false
-Dhudson.model.DownloadService.noSignatureCheck=true
```

### Impact Resolution
- Build notification emails now contain correct URLs
- API responses provide valid Jenkins links
- Dashboard redirects function properly
- Integration with external tools improved

---

## Issue #2: Grafana Dashboard Management & Multi-Team Jenkins Configuration

### Problem Description
**Date**: September 4, 2025  
**Severity**: High  
**Impact**: Dashboard deployment inconsistencies and monitoring configuration errors

Two related sub-issues were identified:

#### Sub-issue 2A: Grafana Dashboard Recreation Instead of Updates
Ansible playbooks were creating new Grafana dashboards on each deployment run instead of updating existing ones, causing:
- Dashboard duplication
- Configuration drift
- Monitoring inconsistencies

#### Sub-issue 2B: Incorrect Prometheus Configuration for Multi-Team Jenkins
The Prometheus scraping configuration had structural issues when handling multiple Jenkins teams:
- Incorrect conditional logic in job configuration
- Missing team-specific metric labeling
- Inconsistent variable templating

### Root Cause Analysis

#### For Dashboard Recreation:
The Ansible tasks were using HTTP POST method to `/api/dashboards/db` endpoint, which always creates new dashboards regardless of existing ones.

#### For Prometheus Configuration:
- Faulty conditional logic: `target.job.startswith('jenkins')` unreliable
- Missing proper team identification in metrics
- Inconsistent Jinja2 templating variables

### Resolution

#### Fix 1: Grafana Dashboard Update Logic
Replace the existing dashboard import task with a more sophisticated approach:

```yaml
- name: Check if dashboard exists
  uri:
    url: "http://{{ ansible_default_ipv4.address }}:{{ grafana_port }}/api/search"
    method: GET
    user: "{{ grafana_admin_user }}"
    password: "{{ grafana_admin_password }}"
    force_basic_auth: yes
    body_format: form-urlencoded
    body:
      query: "{{ dashboard_title }}"
  register: existing_dashboards

- name: Import/Update dashboards
  uri:
    url: "http://{{ ansible_default_ipv4.address }}:{{ grafana_port }}/api/dashboards/db"
    method: POST
    user: "{{ grafana_admin_user }}"
    password: "{{ grafana_admin_password }}"
    force_basic_auth: yes
    body_format: json
    body:
      dashboard: "{{ item.content | b64decode | from_json }}"
      overwrite: true
      folderId: 0
    status_code: [200, 412]
  loop: "{{ dashboard_files.results }}"
  when: item.content is defined
```

#### Fix 2: Enhanced Prometheus Configuration
Corrected the Prometheus scraping configuration for multi-team Jenkins environments:

```yaml
scrape_configs:
{% for target in prometheus_targets %}
  - job_name: '{{ target.job }}'
    static_configs:
      - targets:
{% for target_host in target.targets %}
        - '{{ target_host }}'
{% endfor %}
{% if 'jenkins' in target.job %}
    # Jenkins-specific configuration
    metrics_path: /prometheus
    scrape_interval: 30s
    scrape_timeout: 10s
{% if target.team_name is defined %}
    # Team-specific labels for better metrics organization
    metric_relabel_configs:
      - source_labels: [__name__]
        target_label: jenkins_team
        replacement: '{{ target.team_name }}'
      - source_labels: [__name__]
        target_label: jenkins_environment
        replacement: '{{ target.active_environment | default("blue") }}'
{% endif %}
{% endif %}
{% endfor %}
```

#### Fix 3: Template Variable Consistency
Standardized variable naming across all dashboard templates:

```json
{
  "title": "Jenkins Overview - {{ deployment_environment | default('local') | title }}",
  "tags": ["jenkins", "{{ deployment_environment | default('local') }}"]
}
```

### Additional Considerations

#### Alerting Rule Template Fixes
Updated Prometheus alerting rules with proper variable escaping:

```yaml
groups:
  - name: infrastructure_alerts
    rules:
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 10m
        labels:
          severity: critical
          service: infrastructure
          environment: "{{ deployment_environment | default('local') }}"
        annotations:
          summary: "High memory usage detected"
          description: {% raw %}"Memory usage is {{ $value | printf \"%.2f\" }}% on {{ $labels.instance }}."{% endraw %}
```

### Testing & Validation

#### Dashboard Update Testing
1. Deploy initial dashboard configuration
2. Modify dashboard templates
3. Re-run Ansible playbook
4. Verify dashboards are updated, not duplicated

#### Multi-Team Metrics Validation
1. Configure multiple Jenkins teams in inventory
2. Deploy Prometheus configuration
3. Verify team-specific labels appear in metrics
4. Confirm proper metric segregation

---

## Lessons Learned

### Technical Insights
1. **URL Configuration**: Jenkins URL configuration is critical for proper integration with external tools
2. **Dashboard Management**: Grafana API requires careful handling for update vs. create operations
3. **Multi-Tenancy**: Prometheus configurations need explicit team isolation for multi-team environments

### Process Improvements
1. **Pre-deployment Validation**: Implement configuration checks before Jenkins deployment
2. **Dashboard Versioning**: Consider using dashboard UIDs for consistent updates
3. **Monitoring Strategy**: Establish team-based metric namespaces from the start

### Automation Recommendations
1. Add dashboard existence checks before creation/update
2. Implement proper variable validation in Ansible templates
3. Use Grafana's dashboard versioning features for change tracking

---

## Future Prevention Measures

### Configuration Management
- Implement comprehensive validation checks in deployment pipelines
- Use infrastructure-as-code principles for all Jenkins configurations
- Establish naming conventions for multi-team environments

### Monitoring & Alerting
- Create alerts for misconfigured Jenkins URLs
- Monitor dashboard deployment success/failure rates
- Implement automated testing for Prometheus configurations

### Documentation
- Maintain deployment runbooks with configuration requirements
- Document team-specific configuration patterns
- Create troubleshooting guides for common issues

---

## Conclusion

Both issues have been successfully resolved with comprehensive solutions that address not only the immediate problems but also improve the overall infrastructure automation maturity. The implemented fixes ensure reliable deployments and proper multi-team isolation while maintaining operational consistency across environments.