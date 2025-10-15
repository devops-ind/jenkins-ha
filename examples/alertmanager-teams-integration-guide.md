# Alertmanager Microsoft Teams Integration Guide

## Overview

This guide covers the complete setup and configuration of Prometheus Alertmanager with Microsoft Teams webhook integration for the Jenkins HA infrastructure.

**Features:**
- Native Microsoft Teams support via `msteams_configs`
- Three notification strategies: single, per-team, hybrid
- Severity-based routing (critical, warning, info)
- Team-based alert routing
- Intelligent alert grouping and inhibition
- Rich formatted alert messages

**Architecture:**
```
Prometheus → Alert Rules → Alertmanager → Teams Webhooks → Microsoft Teams Channels
```

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Microsoft Teams Setup](#microsoft-teams-setup)
3. [Configuration Strategies](#configuration-strategies)
4. [Deployment](#deployment)
5. [Testing](#testing)
6. [Alert Management](#alert-management)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Components
- Prometheus with alert rules configured
- Microsoft Teams with appropriate channels created
- Channel permissions to add connectors/webhooks
- Ansible vault access for storing webhook URLs

### Alert Rules
The infrastructure includes 130+ pre-configured alert rules across 4 files:

```
ansible/roles/monitoring/files/prometheus/rules/
├── jenkins.yml                 # 40+ Jenkins-specific alerts
├── infrastructure.yml          # 30+ infrastructure alerts
├── blue-green.yml             # 20+ blue-green deployment alerts
└── logs.yml                    # 15+ log monitoring alerts
```

**Alert Severities:**
- `critical`: Immediate action required (page on-call)
- `warning`: Attention needed (notify team)
- `info`: Informational (awareness)

---

## Microsoft Teams Setup

### Step 1: Create Channels

Create dedicated channels based on your notification strategy:

**Option A: Single Strategy**
- `#jenkins-critical` - Critical alerts only
- `#jenkins-warnings` - Warning alerts
- `#jenkins-info` - Info and monitoring notifications

**Option B: Per-Team Strategy**
- `#devops-alerts` - DevOps team alerts (all severities)
- `#dev-qa-alerts` - Dev-QA team alerts
- `#infrastructure-alerts` - Infrastructure team alerts

**Option C: Hybrid Strategy (RECOMMENDED)**
Both severity channels AND team channels for flexible routing.

### Step 2: Generate Incoming Webhooks

For each channel:

1. **Open Channel Settings**
   - Click `...` on channel → `Connectors` → `Configure`

2. **Add Incoming Webhook**
   - Search for "Incoming Webhook"
   - Click `Add` → `Configure`
   - Provide a name: "Jenkins Alertmanager"
   - Optional: Upload Jenkins logo

3. **Copy Webhook URL**
   ```
   https://company.webhook.office.com/webhookb2/12345678-1234-1234-1234-123456789abc@...
   ```

4. **Save to Vault**
   Store webhook URL in encrypted vault file

### Step 3: Update Ansible Vault

#### Production Environment

```bash
# Edit production vault (encrypted)
ansible-vault edit ansible/inventories/production/group_vars/all/vault.yml
```

Add the following variables:

```yaml
# Severity-based webhooks
vault_teams_webhook_critical: "https://company.webhook.office.com/webhookb2/CRITICAL_WEBHOOK_URL"
vault_teams_webhook_warning: "https://company.webhook.office.com/webhookb2/WARNING_WEBHOOK_URL"
vault_teams_webhook_info: "https://company.webhook.office.com/webhookb2/INFO_WEBHOOK_URL"

# Per-team webhooks
vault_teams_devops_webhook: "https://company.webhook.office.com/webhookb2/DEVOPS_WEBHOOK_URL"
vault_teams_dev_qa_webhook: "https://company.webhook.office.com/webhookb2/DEV_QA_WEBHOOK_URL"
vault_teams_infrastructure_webhook: "https://company.webhook.office.com/webhookb2/INFRA_WEBHOOK_URL"
```

#### Local Environment

For local testing (unencrypted for convenience):

```bash
# Edit local vault
nano ansible/inventories/local/group_vars/all/vault.yml
```

Add test channel webhooks (use dedicated test channels).

---

## Configuration Strategies

The monitoring role supports three notification strategies configured via `teams_notification_strategy`:

### 1. Single Strategy

**Best For:** Small teams, simple alert routing

**Configuration:**
```yaml
# ansible/roles/monitoring/defaults/main.yml
teams_notification_strategy: "single"
```

**Behavior:**
- Critical alerts → `vault_teams_webhook_critical`
- Warning alerts → `vault_teams_webhook_warning`
- Info alerts → `vault_teams_webhook_info`
- All alerts go to severity-specific channels only

**Pros:**
- Simple setup (3 webhooks)
- Easy to manage
- Clear severity separation

**Cons:**
- No team-specific filtering
- All teams see all alerts

### 2. Per-Team Strategy

**Best For:** Large organizations, team autonomy

**Configuration:**
```yaml
teams_notification_strategy: "per-team"
```

**Behavior:**
- Alerts routed based on `team` label
- Each team gets ALL severities in their channel
- Teams webhooks required:
  - `vault_teams_devops_webhook`
  - `vault_teams_dev_qa_webhook`
  - `vault_teams_infrastructure_webhook`

**Pros:**
- Team isolation
- Reduced alert noise per team
- Team ownership of alerts

**Cons:**
- More webhooks to manage
- Critical alerts might be missed if team channel not monitored

### 3. Hybrid Strategy (RECOMMENDED)

**Best For:** Production environments, complete coverage

**Configuration:**
```yaml
teams_notification_strategy: "hybrid"
```

**Behavior:**
- Critical alerts → Severity channel + Team channel (duplicate notification)
- Warning/Info → Severity channel only (team can subscribe if needed)
- Infrastructure alerts → Global channels

**Routing Logic:**
```
Critical Alert (DevOps Jenkins) → #jenkins-critical + #devops-alerts
Warning Alert (Dev-QA Jenkins) → #jenkins-warnings
Info Alert (Infrastructure) → #jenkins-info
```

**Pros:**
- Best of both worlds
- Critical alerts always visible globally
- Teams still get their alerts
- Flexible alert coverage

**Cons:**
- More complex configuration
- Requires all webhooks (6+ total)

### Configuration Variables

```yaml
# Enable/disable Teams notifications
teams_notifications_enabled: true

# Choose notification strategy
teams_notification_strategy: "hybrid"  # single, per-team, hybrid

# Severity-based webhooks
teams_webhook_critical: "{{ vault_teams_webhook_critical | default('') }}"
teams_webhook_warning: "{{ vault_teams_webhook_warning | default('') }}"
teams_webhook_info: "{{ vault_teams_webhook_info | default('') }}"

# Per-team webhooks
teams_webhooks:
  devops:
    webhook_url: "{{ vault_teams_devops_webhook | default('') }}"
    enabled: true
  dev-qa:
    webhook_url: "{{ vault_teams_dev_qa_webhook | default('') }}"
    enabled: true
  infrastructure:
    webhook_url: "{{ vault_teams_infrastructure_webhook | default('') }}"
    enabled: true
```

---

## Deployment

### Step 1: Review Configuration

```bash
# Check monitoring defaults
cat ansible/roles/monitoring/defaults/main.yml | grep -A 20 "teams_notification"
```

### Step 2: Deploy Alertmanager

```bash
# Deploy to production with Alertmanager
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Deploy only Alertmanager updates
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,alertmanager
```

### Step 3: Verify Deployment

```bash
# Check Alertmanager container status
docker ps | grep alertmanager

# View Alertmanager logs
docker logs alertmanager-production -f

# Verify configuration
docker exec alertmanager-production amtool config show

# Check configuration validity
docker exec alertmanager-production amtool check-config /etc/alertmanager/alertmanager.yml
```

### Step 4: Access Alertmanager UI

```bash
# Local access
http://monitoring-vm-ip:9093

# Check status page
curl http://monitoring-vm-ip:9093/api/v1/status
```

---

## Testing

### Test 1: Fire Test Alert

Create a test alert via Prometheus:

```bash
# Port forward to Prometheus
kubectl port-forward svc/prometheus 9090:9090

# Send test alert
curl -X POST http://localhost:9090/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [{
      "labels": {
        "alertname": "TestAlert",
        "severity": "warning",
        "team": "devops",
        "service": "test"
      },
      "annotations": {
        "summary": "This is a test alert",
        "description": "Testing Teams integration"
      }
    }]
  }'
```

### Test 2: Trigger Real Alert

Temporarily adjust alert thresholds to trigger alerts:

```bash
# Temporarily stop Jenkins to trigger JenkinsMasterDown
docker stop jenkins-devops-blue

# Wait for alert (usually 1-2 minutes)
# Check Alertmanager: http://monitoring-vm:9093/#/alerts

# Restart Jenkins
docker start jenkins-devops-blue
```

### Test 3: Verify Routing

Check which Teams channels received alerts based on strategy:

**Single Strategy:**
- Only severity channel receives alert

**Per-Team Strategy:**
- Only team channel receives alert

**Hybrid Strategy:**
- Critical: Both severity + team channel
- Warning/Info: Only severity channel

### Test 4: Verify Alert Resolution

```bash
# Start Jenkins (if stopped)
docker start jenkins-devops-blue

# Wait for resolution (default: 5 minutes)
# Check Teams for "RESOLVED" message
```

---

## Alert Management

### Silence Alerts

**Via UI:**
```bash
# Access Alertmanager UI
http://monitoring-vm:9093

# Click alert → "Silence" button
# Set duration and reason
```

**Via CLI:**
```bash
# Silence specific alert for 2 hours
docker exec alertmanager-production amtool silence add \
  alertname="JenkinsMasterDown" \
  team="devops" \
  --duration=2h \
  --comment="Planned maintenance"

# List active silences
docker exec alertmanager-production amtool silence query

# Expire silence early
docker exec alertmanager-production amtool silence expire <SILENCE_ID>
```

### View Active Alerts

```bash
# Via amtool
docker exec alertmanager-production amtool alert query

# Via API
curl -s http://monitoring-vm:9093/api/v1/alerts | jq
```

### Alert Inhibition Rules

Configured inhibition prevents alert storms:

```yaml
# Critical suppresses warnings (same service)
- source_match:
    severity: 'critical'
  target_match:
    severity: 'warning'
  equal: ['alertname', 'service', 'instance']

# Service down suppresses all related alerts
- source_match:
    alertname: 'ServiceDown'
  target_match_re:
    alertname: '.*'
  equal: ['service', 'instance']
```

**Example:**
```
JenkinsMasterDown (critical) fires
  ↓ suppresses
JenkinsHighBuildQueue (warning)
JenkinsSlowBuilds (info)
```

---

## Troubleshooting

### Issue 1: No Alerts Received in Teams

**Symptoms:** Alertmanager shows firing alerts, but Teams receives nothing

**Diagnosis:**
```bash
# Check Alertmanager logs for webhook errors
docker logs alertmanager-production | grep -i error

# Test webhook manually
curl -H "Content-Type: application/json" \
  -d '{"text":"Test from Alertmanager"}' \
  "YOUR_TEAMS_WEBHOOK_URL"

# Verify webhook URL in config
docker exec alertmanager-production cat /etc/alertmanager/alertmanager.yml | grep webhook_url
```

**Solutions:**
1. Verify webhook URL is correct (no trailing spaces)
2. Check webhook is not expired (Teams webhooks can expire)
3. Verify network connectivity from monitoring VM to Teams API
4. Check Alertmanager container has internet access

### Issue 2: Duplicate Alerts

**Symptoms:** Same alert appears multiple times in Teams

**Diagnosis:**
```bash
# Check alert grouping configuration
docker exec alertmanager-production cat /etc/alertmanager/alertmanager.yml | grep -A 5 "route:"
```

**Solutions:**
1. Adjust `group_by` to include more labels
2. Increase `group_wait` (default: 30s)
3. Check for multiple receivers firing for same alert

### Issue 3: Alert Routing Incorrect

**Symptoms:** Alerts go to wrong Teams channel

**Diagnosis:**
```bash
# Verify alert labels
curl -s http://monitoring-vm:9093/api/v1/alerts | jq '.data[] | {labels}'

# Check routing tree
docker exec alertmanager-production amtool config routes --config.file=/etc/alertmanager/alertmanager.yml
```

**Solutions:**
1. Verify `team` label on alerts matches routing config
2. Check `continue: true` setting for overlapping routes
3. Validate Jinja2 template rendering in alertmanager.yml.j2

### Issue 4: Alerts Not Firing

**Symptoms:** Expected alerts don't trigger

**Diagnosis:**
```bash
# Check Prometheus rules
curl http://prometheus-vm:9090/api/v1/rules | jq

# Verify alert rule syntax
docker exec prometheus-production promtool check rules /etc/prometheus/rules/*.yml

# Check Prometheus targets
curl http://prometheus-vm:9090/api/v1/targets | jq
```

**Solutions:**
1. Verify metric exists in Prometheus
2. Check alert `for` duration (alert must be firing for duration)
3. Validate PromQL query syntax

### Issue 5: Teams Webhook Expired

**Symptoms:** Webhooks worked previously, now fail with 404

**Diagnosis:**
```bash
# Test webhook
curl -X POST "YOUR_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"text":"test"}' -v
# Response: 404 Not Found
```

**Solutions:**
1. Regenerate webhook in Teams (Connectors → Incoming Webhook)
2. Update vault with new webhook URL
3. Redeploy Alertmanager configuration

---

## Alert Message Format

### Critical Alert Example

```
🚨 CRITICAL ALERT - Jenkins Infrastructure

Alert: JenkinsMasterDown
Severity: CRITICAL
Team: Devops
Service: jenkins
Instance: jenkins-devops-blue:8080

Summary: Jenkins master is down
Description: Jenkins master jenkins-devops-blue has been unreachable for more than 2 minutes

Firing Alerts: 1
Time: 2025-01-15T10:30:45Z
```

### Warning Alert Example

```
⚠️ WARNING - Jenkins Infrastructure

Alert: JenkinsHighBuildQueue
Severity: WARNING
Team: Devops
Service: jenkins
Instance: jenkins-devops-blue:8080

Summary: Build queue is growing
Description: Jenkins build queue has 15 jobs waiting for more than 10 minutes

Firing Alerts: 1
```

### Resolved Alert Example

```
✅ RESOLVED - Jenkins Infrastructure

Alert: JenkinsMasterDown
Team: Devops
Service: jenkins

Summary: Jenkins master is back online
```

---

## Advanced Configuration

### Custom Alert Templates

Modify `ansible/roles/monitoring/templates/alertmanager.yml.j2` to customize message format:

```yaml
- name: 'teams-critical'
  msteams_configs:
    - webhook_url: '{{ teams_webhook_critical }}'
      send_resolved: true
      title: '🚨 CUSTOM TITLE'
      text: |
        **Custom Field:** {{ '{{' }} .CustomLabel {{ '}}' }}
        {{ '{{' }} .CommonAnnotations.custom_annotation {{ '}}' }}
```

### Add Email Notifications

Combine Teams with email for critical alerts:

```yaml
- name: 'teams-critical'
  msteams_configs:
    - webhook_url: '{{ teams_webhook_critical }}'
  email_configs:
    - to: 'oncall@company.com'
      from: 'alertmanager@company.com'
      smarthost: 'smtp.company.com:587'
```

### Webhook Proxy (Optional)

For advanced Teams card formatting, deploy a webhook proxy:

```bash
# Deploy custom proxy for MessageCard format
# See: examples/alertmanager-teams-proxy.md (future enhancement)
```

---

## Best Practices

### 1. Webhook Management
- Use dedicated channels for each severity/team
- Document webhook purposes in channel descriptions
- Rotate webhooks periodically (security)
- Store webhooks in encrypted vault only

### 2. Alert Routing
- Start with `hybrid` strategy for production
- Use `single` strategy for development/testing
- Enable `per-team` when teams are mature and independent

### 3. Alert Tuning
- Review alert frequency monthly
- Adjust thresholds based on false positives
- Use silences for planned maintenance
- Document alert response procedures

### 4. Testing
- Test webhooks before production deployment
- Create dedicated test channels
- Fire test alerts after configuration changes
- Verify alert resolution messages work

### 5. Monitoring Alertmanager
- Set up alerts for Alertmanager itself
- Monitor webhook success rates
- Track alert notification latency
- Review inhibition effectiveness

---

## Related Documentation

- [Separate VM Monitoring Deployment Guide](monitoring-separate-vm-deployment-guide.md)
- [Jenkins Job Logs with Loki Guide](jenkins-job-logs-with-loki-guide.md)
- [Monitoring Agent Architecture](monitoring-agent-architecture-implementation.md)
- [Prometheus Alert Rules](../ansible/roles/monitoring/files/prometheus/rules/)

---

## References

- [Prometheus Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [Microsoft Teams Incoming Webhooks](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook)
- [Alert Routing Tree](https://prometheus.io/docs/alerting/latest/configuration/#route)

---

**Document Version:** 1.0
**Last Updated:** 2025-01-15
**Author:** Jenkins HA Infrastructure Team
