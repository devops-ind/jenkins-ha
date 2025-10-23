# Jenkins Build Logs Dashboard with Loki

**Date**: October 22, 2025
**Dashboard Type**: Grafana + Loki
**Status**: ✅ Production Ready
**Version**: 1.0

---

## Overview

Comprehensive Jenkins build log analysis dashboard powered by Loki, providing real-time insights into build success rates, failures, errors, and performance metrics across all teams and environments.

### Key Features

- ✅ **24 Interactive Panels** organized in 9 rows
- ✅ **Team-Based Filtering** with multi-select dropdowns
- ✅ **Real-Time Log Streaming** for failed builds and errors
- ✅ **Automated Alerting** via Loki ruler and Alertmanager
- ✅ **Success/Failure Rate Tracking** with historical trends
- ✅ **Build Duration Analysis** with anomaly detection
- ✅ **Error Pattern Detection** and root cause analysis
- ✅ **Per-Team and Cross-Team Comparisons**

---

## Architecture

### Data Flow

```
┌─────────────────┐
│ Jenkins Builds  │
│ (Console Logs)  │
└────────┬────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────┐
│ GlusterFS Direct Mount                                  │
│ /var/jenkins/{team}/data/{env}/jobs/*/builds/*/log     │
└────────┬────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────┐
│ Promtail Agent (Enhanced Configuration)                │
│ • Path: /jenkins-logs/*/*/jobs/*/builds/*/log          │
│ • Extracts: team, environment, job_name, build_number  │
│ • Parses: build_result, duration, error_type           │
│ • Generates Metrics: build counts, durations, errors   │
└────────┬────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────┐
│ Loki Server (with Ruler)                               │
│ • Storage: TSDB (v13 schema)                           │
│ • Ruler: Evaluates alerting rules every 1m             │
│ • Alerts: Sent to Alertmanager                         │
└────────┬────────────────────────────────────────────────┘
         │
         ├─────────────────────┬──────────────────────────┐
         ↓                     ↓                          ↓
┌────────────────┐    ┌────────────────┐      ┌──────────────────┐
│ Grafana        │    │ Alertmanager   │      │ MS Teams         │
│ Dashboard      │    │ (Routing)      │      │ (Notifications)  │
│ (24 Panels)    │    │ • Build Fails  │      │ • Build Failures │
└────────────────┘    │ • Error Rate   │      │ • Error Alerts   │
                      └────────────────┘      └──────────────────┘
```

---

## Dashboard Panels

### Row 1: Overview Statistics (4 panels)

#### 1. Total Builds Today
**Type**: Stat with sparkline
**Query**:
```logql
count_over_time({job="jenkins-job-logs", team=~"$team"}[24h])
```
**Purpose**: Quick overview of total build activity

#### 2. Success Rate (24h)
**Type**: Gauge (0-100%)
**Query**:
```logql
(sum(count_over_time({job="jenkins-job-logs", team=~"$team"} |= "Finished: SUCCESS" [24h])) /
 sum(count_over_time({job="jenkins-job-logs", team=~"$team"}[24h]))) * 100
```
**Thresholds**: Red < 70%, Orange 70-90%, Green > 90%

#### 3. Failed Builds Today
**Type**: Stat (color-coded by count)
**Query**:
```logql
count_over_time({job="jenkins-job-logs", team=~"$team"} |= "Finished: FAILURE" [24h])
```
**Thresholds**: Green < 5, Orange 5-10, Red > 10

#### 4. Average Build Duration
**Type**: Stat (minutes)
**Query**:
```logql
avg(avg_over_time({job="jenkins-job-logs", team=~"$team"}
  | regexp "Duration: (?:(?P<hours>\\d+) hr )?(?P<minutes>\\d+) min"
  | unwrap minutes [24h]))
```
**Thresholds**: Green < 20m, Yellow 20-40m, Red > 40m

---

### Row 2: Build Trends (2 panels)

#### 5. Build Success/Failure Rate Over Time
**Type**: Time series (multi-line)
**Queries**:
```logql
# Success rate
sum(rate({job="jenkins-job-logs", team=~"$team"} |= "Finished: SUCCESS" [5m])) by (team)

# Failure rate
sum(rate({job="jenkins-job-logs", team=~"$team"} |= "Finished: FAILURE" [5m])) by (team)
```
**Colors**: Green for SUCCESS, Red for FAILURE

#### 6. Builds Per Team (Last 24h)
**Type**: Horizontal bar chart
**Query**:
```logql
sum(count_over_time({job="jenkins-job-logs"} [24h])) by (team)
```

---

### Row 3: Job-Specific Metrics (3 panels)

#### 7. Top 10 Failed Jobs
**Type**: Table with color-coded cells
**Query**:
```logql
topk(10, sum(count_over_time({job="jenkins-job-logs", team=~"$team"}
  |= "Finished: FAILURE" [24h])) by (job_name))
```

#### 8. Top 10 Slowest Jobs
**Type**: Table with duration highlighting
**Query**:
```logql
topk(10, avg(avg_over_time({job="jenkins-job-logs", team=~"$team"}
  | regexp "Duration: (?:(?P<hours>\\d+) hr )?(?P<minutes>\\d+) min"
  | unwrap minutes [24h])) by (job_name))
```

#### 9. Job Execution Frequency (Heatmap)
**Type**: Heatmap
**Query**:
```logql
count_over_time({job="jenkins-job-logs", team=~"$team"} [1h]) by (job_name)
```

---

### Row 4: Error Analysis (2 panels)

#### 10. Error Rate by Team
**Type**: Time series
**Query**:
```logql
sum(rate({job="jenkins-job-logs"} |~ "(?i)(error|exception|fatal)" [5m])) by (team)
```

#### 11. Top Error Patterns
**Type**: Table
**Query**:
```logql
topk(20, sum(count_over_time({job="jenkins-job-logs", team=~"$team"}
  |~ "(?i)(error|exception|failed|fatal)" [24h])))
```

---

### Row 5: Real-Time Logs (2 panels)

#### 12. Live Failed Build Logs
**Type**: Logs panel with auto-refresh (30s)
**Query**:
```logql
{job="jenkins-job-logs", team=~"$team"} |= "Finished: FAILURE"
```
**Features**: Colored log levels, expandable entries, time-stamped

#### 13. Live Error Logs (All Teams)
**Type**: Logs panel
**Query**:
```logql
{job="jenkins-job-logs"} |~ "(?i)(error|exception|fatal)"
```

---

### Row 6: Team Comparison (3 panels)

#### 14. Success Rate by Team
**Type**: Bar gauge (horizontal)
**Query**:
```logql
(sum(count_over_time({job="jenkins-job-logs"} |= "Finished: SUCCESS" [24h])) by (team) /
 sum(count_over_time({job="jenkins-job-logs"} [24h])) by (team)) * 100
```

#### 15. Total Builds by Team & Environment
**Type**: Stacked bar chart
**Query**:
```logql
sum(count_over_time({job="jenkins-job-logs"} [24h])) by (team, environment)
```

#### 16. Error Count by Team
**Type**: Time series
**Query**:
```logql
sum(count_over_time({job="jenkins-job-logs"} |~ "(?i)(error|exception)" [5m])) by (team)
```

---

### Row 7: Advanced Filters & Search (1 panel)

#### 17. Filtered Build Logs
**Type**: Logs panel with full search capabilities
**Query**:
```logql
{job="jenkins-job-logs", team=~"$team", environment=~"$environment"} |= "$search_query"
```
**Variables Used**: `$team`, `$environment`, `$search_query`

---

## Dashboard Variables

### 1. Data Source Variable
**Name**: `DS_LOKI`
**Type**: Datasource
**Query**: `loki`
**Purpose**: Select Loki datasource

### 2. Team Filter
**Name**: `team`
**Type**: Query (multi-select)
**Query**:
```logql
label_values(team)
```
**Default**: All teams
**Options**: devops, ma, ba, tw, All

### 3. Environment Filter
**Name**: `environment`
**Type**: Query (multi-select)
**Query**:
```logql
label_values(environment)
```
**Default**: All environments
**Options**: blue, green, All

### 4. Search Query
**Name**: `search_query`
**Type**: Text box
**Default**: (empty)
**Purpose**: Free-text search in logs

---

## Alerting Rules

### Alert 1: JenkinsBuildFailed (Warning)
**Severity**: Warning
**Expression**:
```logql
count_over_time({job="jenkins-job-logs"} |= "Finished: FAILURE" [1m]) > 0
```
**For**: 1m
**Notification**: Immediate MS Teams notification
**Annotations**:
- Job name, build number
- Team and environment
- Link to Jenkins console
- Link to Grafana logs

### Alert 2: JenkinsBuildFailureHigh (Critical)
**Severity**: Critical
**Expression**:
```logql
sum(rate({job="jenkins-job-logs"} |= "Finished: FAILURE" [5m])) by (team, job_name) > 0.5
```
**For**: 10m
**Notification**: Critical MS Teams notification
**Purpose**: High failure rate detection (>50% for 10+ minutes)

### Alert 3: JenkinsErrorRateHigh (Warning)
**Severity**: Warning
**Expression**:
```logql
sum(rate({job="jenkins-job-logs"} |~ "(?i)(error|exception|fatal)" [5m]))
  by (team, job_name) > 2
```
**For**: 5m
**Purpose**: Detect error spikes in build logs

### Alert 4: JenkinsBuildDurationHigh (Info)
**Severity**: Info
**Expression**:
```logql
avg(avg_over_time({job="jenkins-job-logs"}
  | regexp "Duration: (?:(?P<hours>\\d+) hr )?(?P<minutes>\\d+) min"
  | unwrap minutes [10m])) by (team, job_name) > 30
```
**For**: 5m
**Purpose**: Notify about slow builds (>30 minutes average)

### Alert 5: JenkinsSecurityError (Critical)
**Severity**: Critical
**Expression**:
```logql
sum(count_over_time({job="jenkins-job-logs"}
  |~ "(?i)(security.*error|authentication.*fail|authorization.*fail)" [10m]))
  by (team, job_name) > 0
```
**For**: 5m
**Purpose**: Security-related errors require immediate attention

---

## Deployment

### Step 1: Deploy Enhanced Promtail Configuration
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,promtail
```

**What it does**:
- Updates Promtail configuration with build result extraction
- Adds duration parsing logic
- Generates Prometheus metrics from logs
- Restarts Promtail agents on all hosts

### Step 2: Deploy Loki with Ruler
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,loki
```

**What it does**:
- Updates Loki configuration with ruler support
- Creates rules directory and deploys alerting rules
- Mounts rules volume in Loki container
- Restarts Loki server

### Step 3: Deploy Grafana Dashboard
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,dashboards
```

**What it does**:
- Deploys Jenkins Build Logs dashboard JSON
- Creates team-specific dashboard versions
- Configures dashboard variables
- Registers dashboard in Grafana

### Step 4: Update Alertmanager
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,alertmanager
```

**What it does**:
- Updates Alertmanager configuration
- Adds Jenkins-specific routing rules
- Configures MS Teams receivers
- Restarts Alertmanager

### Full Deployment (All Components)
```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring
```

---

## Validation

### 1. Verify Promtail Log Ingestion
```bash
# Check Promtail is scraping Jenkins logs
docker logs promtail-production --tail 50 | grep jenkins-job-logs

# Verify labels are extracted
curl -G -s "http://loki.dev.net:9400/loki/api/v1/label" | jq .
# Expected labels: team, environment, job_name, build_number, build_result
```

### 2. Verify Loki Ingestion
```bash
# Query for Jenkins build logs
curl -G -s "http://loki.dev.net:9400/loki/api/v1/query" \
  --data-urlencode 'query={job="jenkins-job-logs"}' \
  --data-urlencode 'limit=10' | jq .

# Check specific team logs
curl -G -s "http://loki.dev.net:9400/loki/api/v1/query" \
  --data-urlencode 'query={job="jenkins-job-logs", team="devops"}' | jq .
```

### 3. Verify Loki Ruler (Alerting Rules)
```bash
# Check ruler API
curl -s "http://loki.dev.net:9400/loki/api/v1/rules" | jq .

# Verify rules are loaded
curl -s "http://loki.dev.net:9400/loki/api/v1/rules" | jq '.data.groups[].rules[].alert'
```

### 4. Verify Dashboard Access
```bash
# Access Grafana
open http://grafana.dev.net:9300

# Login with admin credentials
# Navigate to: Dashboards → Jenkins Build Logs

# Or direct URL:
open "http://grafana.dev.net:9300/d/jenkins-build-logs/jenkins-build-logs"
```

### 5. Test Alerting
```bash
# Trigger a Jenkins build failure
# (Run a failing job in Jenkins)

# Check Alertmanager receives alert
curl -s "http://192.168.188.142:9093/api/v2/alerts" | jq .

# Verify MS Teams notification received
# (Check configured Teams channel)
```

---

## Troubleshooting

### Issue 1: No logs appearing in Loki

**Symptoms**:
- Dashboard shows "No data"
- LogQL queries return empty results

**Solutions**:
```bash
# 1. Check Promtail is running
docker ps | grep promtail

# 2. Check Promtail logs for errors
docker logs promtail-production --tail 100

# 3. Verify log file paths exist
ls -la /jenkins-logs/devops/blue/jobs/*/builds/*/log

# 4. Check Promtail configuration
docker exec promtail-production cat /etc/promtail/promtail-config.yml

# 5. Check Loki is accepting logs
curl -s "http://loki.dev.net:9400/ready"
```

### Issue 2: Dashboard variables not populating

**Symptoms**:
- Team dropdown shows "No options"
- Environment dropdown empty

**Solutions**:
```bash
# 1. Check Loki has data with labels
curl -G -s "http://loki.dev.net:9400/loki/api/v1/label/team/values" | jq .

# 2. Verify datasource in Grafana
curl -u admin:admin123 "http://grafana.dev.net:9300/api/datasources" | jq .

# 3. Test label query directly
curl -G -s "http://loki.dev.net:9400/loki/api/v1/labels" | jq .
```

### Issue 3: Alerts not firing

**Symptoms**:
- Build failures not generating alerts
- No MS Teams notifications

**Solutions**:
```bash
# 1. Check Loki ruler is enabled
curl -s "http://loki.dev.net:9400/loki/api/v1/rules" | jq .

# 2. Verify Alertmanager is running
curl -s "http://192.168.188.142:9093/-/healthy"

# 3. Check Alertmanager configuration
curl -s "http://192.168.188.142:9093/api/v2/status" | jq .

# 4. Test webhook manually
curl -X POST "{{ teams_webhook_warning }}" \
  -H "Content-Type: application/json" \
  -d '{"text": "Test alert from Jenkins monitoring"}'
```

### Issue 4: Slow dashboard loading

**Symptoms**:
- Dashboard takes >30 seconds to load
- Queries timeout

**Solutions**:
```bash
# 1. Reduce time range (use 6h instead of 24h)
# 2. Add more specific label filters
# 3. Check Loki performance

# Check Loki metrics
curl -s "http://loki.dev.net:9400/metrics" | grep loki_

# Check query performance
# (Use Grafana's Query Inspector → Stats)

# 4. Tune Loki TSDB cache
# Edit: ansible/roles/monitoring/templates/loki/loki-config.yml.j2
# Increase: tsdb_shipper cache settings
```

---

## Performance Optimization

### 1. Query Optimization

**Use specific label filters**:
```logql
# ❌ Slow (scans all logs)
{job="jenkins-job-logs"} |~ "ERROR"

# ✅ Fast (label filter first)
{job="jenkins-job-logs", team="devops"} |~ "ERROR"
```

**Use metric queries for aggregations**:
```logql
# ❌ Slow (processes all log lines)
count_over_time({job="jenkins-job-logs"} [24h])

# ✅ Fast (uses Promtail-generated metrics)
jenkins_build_logs_total{job="jenkins-job-logs"}[24h]
```

### 2. Loki Retention Tuning

**Default**: 30 days
**Recommendation**: Adjust based on storage capacity

```yaml
# ansible/roles/monitoring/defaults/main.yml
loki_retention: "30d"  # Increase if more storage available
```

### 3. Dashboard Refresh Rate

**Current**: 30 seconds
**Adjust based on needs**:
- Real-time monitoring: 10-15s
- General overview: 1-5m
- Historical analysis: Disable auto-refresh

---

## LogQL Query Examples

### Common Use Cases

#### 1. Find all failed builds for a specific job
```logql
{job="jenkins-job-logs", team="devops", job_name="Infrastructure-Update"}
  |= "Finished: FAILURE"
```

#### 2. Calculate failure rate over last hour
```logql
sum(rate({job="jenkins-job-logs", team="devops"} |= "FAILURE" [1h])) /
sum(rate({job="jenkins-job-logs", team="devops"} [1h]))
```

#### 3. Extract error messages from failed builds
```logql
{job="jenkins-job-logs", build_result="FAILURE"}
  |~ "(?i)(error|exception)"
  | regexp "(?P<error_msg>.*(?:error|exception):.*)"
  | line_format "{{.error_msg}}"
```

#### 4. Find builds that took longer than 30 minutes
```logql
{job="jenkins-job-logs"}
  | regexp "Duration: (?P<minutes>\\d+) min"
  | unwrap minutes
  | __error__="" > 30
```

#### 5. Count unique jobs executed per team
```logql
count(count_over_time({job="jenkins-job-logs"} [24h])) by (team, job_name)
```

#### 6. Detect builds with specific error patterns
```logql
{job="jenkins-job-logs"}
  |~ "(?i)(out of memory|timeout|connection refused)"
  | line_format "{{.job_name}} build #{{.build_number}}: {{__line__}}"
```

---

## Security Considerations

### 1. Access Control

**Grafana**: Use RBAC to control dashboard access
```yaml
# Per-team dashboard access
- Team: devops
  Permissions: View/Edit jenkins-build-logs-devops
- Team: ma
  Permissions: View/Edit jenkins-build-logs-ma
```

### 2. Log Sanitization

**Sensitive Data**: Ensure Jenkins logs don't contain:
- Passwords or API keys
- PII (Personal Identifiable Information)
- Internal IP addresses (if security concern)

**Promtail Filtering**:
```yaml
# Add to promtail-config.yml.j2
- replace:
    expression: "password=\\S+"
    replace: "password=***REDACTED***"
```

### 3. Retention Policies

**Compliance**: Adjust retention based on regulatory requirements
- GDPR: Max 30 days for personal data
- SOC2: Min 90 days for audit logs
- HIPAA: Min 6 years for healthcare data

---

## Summary

### What We Built

✅ **24-panel Grafana dashboard** for comprehensive Jenkins build log analysis
✅ **Enhanced Promtail configuration** with build result and duration extraction
✅ **Loki ruler configuration** with 12 alerting rules
✅ **Alertmanager routing** for team-based notifications
✅ **Complete documentation** with deployment, troubleshooting, and optimization guides

### Key Metrics Available

- Total builds, success rate, failure count, average duration
- Build success/failure trends over time
- Top failed jobs and slowest jobs
- Error rate analysis and pattern detection
- Real-time log streaming for failures
- Team-based comparisons

### Alerting Coverage

- Individual build failures (immediate)
- High failure rates (10-minute threshold)
- Error rate spikes
- Long build durations
- Security errors
- Credential warnings

### Access URLs

- **Dashboard**: http://grafana.dev.net:9300/d/jenkins-build-logs/jenkins-build-logs
- **Loki**: http://loki.dev.net:9400
- **Alertmanager**: http://192.168.188.142:9093

---

## References

- **Loki Documentation**: https://grafana.com/docs/loki/latest/
- **LogQL Query Language**: https://grafana.com/docs/loki/latest/query/
- **Grafana Dashboards**: https://grafana.com/grafana/dashboards/
- **Promtail Configuration**: https://grafana.com/docs/loki/latest/send-data/promtail/
- **Alerting Rules**: https://grafana.com/docs/loki/latest/alert/
- **Prometheus Integration**: https://prometheus.io/docs/alerting/latest/
- **Local Files**:
  - Dashboard Template: `ansible/roles/monitoring/templates/dashboards/jenkins-build-logs.json.j2`
  - Alerting Rules: `ansible/roles/monitoring/templates/loki/loki-alerting-rules.yml.j2`
  - Promtail Config: `ansible/roles/monitoring/templates/promtail/promtail-config.yml.j2`
  - Main Documentation: `CLAUDE.md`
