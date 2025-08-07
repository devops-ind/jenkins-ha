# Monitoring Operations Runbook

## Overview

This runbook provides comprehensive procedures for monitoring operations of the Jenkins HA infrastructure, including alert handling, escalation procedures, dashboard management, and troubleshooting monitoring issues.

## Monitoring Stack Overview

### Components
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and notification
- **Node Exporter**: System metrics collection
- **Jenkins Exporter**: Application-specific metrics

### Monitoring Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Application   │───▶│   Prometheus    │───▶│     Grafana     │
│    Metrics      │    │   (Collector)   │    │  (Visualizer)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │  AlertManager   │───▶│  Notifications  │
                       │    (Alerts)     │    │ (Email/Slack)   │
                       └─────────────────┘    └─────────────────┘
```

## Alert Classification and Response

### Alert Severity Levels

| Severity | Response Time | Escalation | Description |
|----------|---------------|------------|-------------|
| **Critical** | 5 minutes | Immediate | Service down, data loss risk |
| **High** | 15 minutes | 30 minutes | Performance degradation, partial failure |
| **Medium** | 1 hour | 4 hours | Non-critical issues, capacity warnings |
| **Low** | 24 hours | Weekly review | Informational, maintenance needed |

### Critical Alert Response Procedures

#### Alert: Jenkins Master Down
**Symptoms:**
- Jenkins UI inaccessible
- Health check failures
- Agent disconnections

**Immediate Response (0-5 minutes):**
```bash
# 1. Verify alert accuracy
curl -f http://{{ jenkins_vip }}:8080/login

# 2. Check Jenkins master status
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl status jenkins-master"

# 3. Check container status
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker ps | grep jenkins-master"

# 4. Verify load balancer status
curl -f http://{{ jenkins_vip }}:8404/stats
```

**Investigation (5-15 minutes):**
```bash
# Check logs for errors
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "journalctl -u jenkins-master -n 50 --no-pager"

# Check Docker container logs
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker logs jenkins-master --tail 50"

# Check resource utilization
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "top -bn1 | head -20"

# Check disk space
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "df -h"
```

**Resolution Actions:**
```bash
# Restart Jenkins master if needed
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl restart jenkins-master"

# If container issue, restart container
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker restart jenkins-master"

# Check failover status
curl -f http://{{ jenkins_vip }}:8080/login
```

#### Alert: High Memory Usage
**Symptoms:**
- Memory usage > 85%
- Java heap space warnings
- Application slowness

**Response Procedure:**
```bash
# 1. Check current memory usage
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "free -h && ps aux --sort=-%mem | head -10"

# 2. Check Jenkins heap usage
curl -s "http://{{ jenkins_vip }}:8080/monitoring" | grep -i memory

# 3. Identify memory-consuming processes
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "ps aux --sort=-%mem | head -20"

# 4. Check for memory leaks
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "jstat -gc \$(pgrep java) 5s 3"

# 5. Clear unnecessary data if safe
# (after confirming with development team)
curl -X POST "http://{{ jenkins_vip }}:8080/script" \
  -d "script=System.gc()" \
  --user "{{ jenkins_admin_user }}:{{ jenkins_admin_password }}"
```

#### Alert: Disk Space Critical
**Symptoms:**
- Disk usage > 90%
- Build failures
- Log rotation issues

**Response Procedure:**
```bash
# 1. Identify largest directories
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "du -sh /* 2>/dev/null | sort -hr | head -10"

# 2. Check Jenkins workspace usage
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "du -sh {{ jenkins_home }}/workspace/* | sort -hr | head -10"

# 3. Clean old builds (if configured)
curl -X POST "http://{{ jenkins_vip }}:8080/script" \
  -d "script=Jenkins.instance.getAllItems(Job.class).each { job -> 
      if (job.getBuilds().size() > 10) { 
        job.getBuilds()[10..-1].each { build -> 
          build.delete() 
        } 
      } 
    }" \
  --user "{{ jenkins_admin_user }}:{{ jenkins_admin_password }}"

# 4. Clean Docker images
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker system prune -f"

# 5. Rotate logs manually if needed
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "logrotate -f /etc/logrotate.conf"
```

### High Priority Alert Response

#### Alert: Jenkins Agent Disconnected
**Response Procedure:**
```bash
# 1. Identify disconnected agents
curl -s "http://{{ jenkins_vip }}:8080/computer/api/json" | \
  jq '.computer[] | select(.offline==true) | .displayName'

# 2. Check agent host connectivity
ansible jenkins_agents -i ansible/inventories/production/hosts.yml \
  -m ping

# 3. Check agent container status
ansible jenkins_agents -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker ps | grep jenkins-agent"

# 4. Check agent logs
ansible jenkins_agents -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker logs jenkins-agent --tail 50"

# 5. Restart agent if needed
ansible jenkins_agents -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker restart jenkins-agent"
```

#### Alert: Harbor Registry Issues
**Response Procedure:**
```bash
# 1. Check Harbor service status
ansible harbor -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker-compose -f /opt/harbor/docker-compose.yml ps"

# 2. Test Harbor API connectivity
curl -f https://{{ harbor_hostname }}/api/v2.0/systeminfo

# 3. Check Harbor logs
ansible harbor -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker-compose -f /opt/harbor/docker-compose.yml logs --tail 50"

# 4. Test image pull/push
docker pull harbor.company.com/jenkins/agent:test
docker tag harbor.company.com/jenkins/agent:test harbor.company.com/jenkins/agent:test-$(date +%s)
docker push harbor.company.com/jenkins/agent:test-$(date +%s)
```

## Grafana Dashboard Management

### Key Dashboards

#### Jenkins HA Overview Dashboard
**Purpose**: High-level view of Jenkins infrastructure health
**Key Metrics**:
- Jenkins master availability
- Active build count
- Agent availability
- Queue length
- System resource usage

**Access**: http://{{ grafana_hostname }}:3000/d/jenkins-ha-overview

#### Infrastructure Monitoring Dashboard
**Purpose**: System-level monitoring of all infrastructure components
**Key Metrics**:
- CPU, Memory, Disk usage
- Network traffic
- Container status
- Service availability

**Access**: http://{{ grafana_hostname }}:3000/d/infrastructure-overview

#### Security Monitoring Dashboard
**Purpose**: Security events and intrusion detection
**Key Metrics**:
- Failed login attempts
- Suspicious network activity
- Certificate expiration
- Security scan results

**Access**: http://{{ grafana_hostname }}:3000/d/security-monitoring

### Dashboard Maintenance

**Weekly Dashboard Review:**
```bash
# Check dashboard performance
curl -s "http://{{ grafana_hostname }}:3000/api/health" | jq .

# Update dashboard variables
./scripts/grafana-maintenance.sh update-variables

# Verify dashboard functionality
./scripts/grafana-maintenance.sh test-dashboards

# Generate dashboard usage report
./scripts/grafana-maintenance.sh usage-report
```

**Dashboard Backup:**
```bash
# Export all dashboards
./scripts/grafana-backup.sh export-all

# Import dashboard from backup
./scripts/grafana-backup.sh import --dashboard=jenkins-ha-overview

# Verify dashboard integrity
./scripts/grafana-backup.sh verify
```

## Prometheus Configuration Management

### Prometheus Targets

**Target Health Check:**
```bash
# Check target status
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.health != "up") | .labels'

# Verify scrape duration
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/query?query=up" | \
  jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'

# Check for scrape errors
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.lastError != "") | {instance: .labels.instance, error: .lastError}'
```

**Prometheus Configuration Update:**
```bash
# Reload Prometheus configuration
curl -X POST "http://{{ prometheus_hostname }}:9090/-/reload"

# Verify configuration syntax
ansible prometheus -i ansible/inventories/production/hosts.yml \
  -m shell -a "promtool check config /etc/prometheus/prometheus.yml"

# Check rule syntax
ansible prometheus -i ansible/inventories/production/hosts.yml \
  -m shell -a "promtool check rules /etc/prometheus/rules/*.yml"
```

### Alert Rule Management

**Alert Rule Testing:**
```bash
# Test specific alert rule
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/query?query=ALERTS" | \
  jq '.data.result[] | select(.metric.alertname=="JenkinsMasterDown")'

# Check alert rule syntax
promtool check rules /path/to/alert/rules.yml

# Test alert with sample data
promtool test rules test-alerts.yml
```

**Alert Rule Deployment:**
```bash
# Deploy new alert rules
ansible-playbook ansible/site.yml --tags prometheus-rules

# Reload Prometheus rules
curl -X POST "http://{{ prometheus_hostname }}:9090/-/reload"

# Verify rule loading
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/rules" | \
  jq '.data.groups[].rules[] | select(.type=="alerting") | .name'
```

## AlertManager Operations

### Notification Management

**Test Notifications:**
```bash
# Send test alert
curl -X POST "http://{{ alertmanager_hostname }}:9093/api/v1/alerts" \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning",
      "instance": "test-instance"
    },
    "annotations": {
      "summary": "Test alert for notification verification"
    }
  }]'

# Check alert status
curl -s "http://{{ alertmanager_hostname }}:9093/api/v1/alerts" | \
  jq '.data[] | {alertname: .labels.alertname, status: .status.state}'
```

**Silence Management:**
```bash
# Create silence for maintenance
curl -X POST "http://{{ alertmanager_hostname }}:9093/api/v1/silences" \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {
        "name": "instance",
        "value": "jenkins-master-01",
        "isRegex": false
      }
    ],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)'",
    "createdBy": "ops-team",
    "comment": "Scheduled maintenance"
  }'

# List active silences
curl -s "http://{{ alertmanager_hostname }}:9093/api/v1/silences" | \
  jq '.data[] | {id: .id, matchers: .matchers, comment: .comment}'

# Remove silence
curl -X DELETE "http://{{ alertmanager_hostname }}:9093/api/v1/silence/{{ silence_id }}"
```

### Escalation Procedures

#### Level 1 - On-Call Engineer (0-30 minutes)
- Acknowledge alert within 5 minutes
- Perform initial troubleshooting
- Attempt automated remediation
- Document actions in incident log

#### Level 2 - Senior Engineer (30-60 minutes)
- Review Level 1 actions
- Perform advanced troubleshooting
- Coordinate with other teams if needed
- Decide on escalation to Level 3

#### Level 3 - Infrastructure Manager (60+ minutes)
- Review overall incident response
- Coordinate external resources
- Make decisions on service degradation
- Communicate with stakeholders

**Escalation Script:**
```bash
# Automatic escalation trigger
./scripts/alert-escalation.sh \
  --alert-id="{{ alert_id }}" \
  --level=2 \
  --reason="No response within 30 minutes"

# Manual escalation
./scripts/alert-escalation.sh \
  --alert-id="{{ alert_id }}" \
  --level=3 \
  --reason="Complex issue requiring manager involvement"
```

## Monitoring Data Management

### Metrics Retention

**Prometheus Data Management:**
```bash
# Check Prometheus storage usage
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/status/tsdb" | \
  jq '.data.seriesCountByMetricName | to_entries | sort_by(.value) | reverse | .[0:10]'

# Check retention policy
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/status/flags" | \
  jq '.data["storage.tsdb.retention.time"]'

# Clean old data if needed
curl -X POST "http://{{ prometheus_hostname }}:9090/api/v1/admin/tsdb/clean_tombstones"
```

**Grafana Data Management:**
```bash
# Check Grafana database size
ansible grafana -i ansible/inventories/production/hosts.yml \
  -m shell -a "du -sh /var/lib/grafana/grafana.db"

# Export/backup dashboards
./scripts/grafana-backup.sh export-all --output=/backup/grafana/$(date +%Y%m%d)

# Clean old annotations
./scripts/grafana-maintenance.sh clean-annotations --older-than=30d
```

### Log Management

**Centralized Log Collection:**
```bash
# Check log aggregation status
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl status rsyslog"

# Verify log forwarding
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "logger 'Test log message' && tail -f /var/log/messages | grep 'Test log message'"

# Check log storage usage
ansible monitoring -i ansible/inventories/production/hosts.yml \
  -m shell -a "du -sh /var/log/aggregated/*"
```

**Log Rotation:**
```bash
# Manual log rotation
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "logrotate -f /etc/logrotate.conf"

# Check rotation status
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "cat /var/lib/logrotate/status"
```

## Performance Monitoring

### Jenkins Performance Metrics

**Build Performance:**
```bash
# Check average build times
curl -s "http://{{ jenkins_vip }}:8080/api/json?tree=jobs[name,lastBuild[duration]]" | \
  jq '.jobs[] | {name: .name, duration: .lastBuild.duration}'

# Monitor queue length
curl -s "http://{{ jenkins_vip }}:8080/queue/api/json" | \
  jq '.items | length'

# Check agent utilization
curl -s "http://{{ jenkins_vip }}:8080/computer/api/json" | \
  jq '.computer[] | {name: .displayName, busy: .executors[].currentExecutable != null}'
```

**System Performance:**
```bash
# CPU usage monitoring
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1"

# Memory usage monitoring
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "free | awk 'NR==2{printf \"%.2f%%\", \$3*100/\$2}'"

# Disk I/O monitoring
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "iostat -x 1 3 | tail -n +4"
```

## Troubleshooting Common Issues

### Prometheus Issues

**Issue: Metrics Not Being Scraped**
```bash
# Check target configuration
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.health != "up")'

# Verify network connectivity
ansible prometheus -i ansible/inventories/production/hosts.yml \
  -m shell -a "curl -f http://{{ target_host }}:{{ target_port }}/metrics"

# Check Prometheus logs
ansible prometheus -i ansible/inventories/production/hosts.yml \
  -m shell -a "journalctl -u prometheus -n 50"
```

**Issue: High Prometheus Memory Usage**
```bash
# Check series count
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/label/__name__/values" | \
  jq '.data | length'

# Identify high cardinality metrics
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/status/tsdb" | \
  jq '.data.seriesCountByMetricName | to_entries | sort_by(.value) | reverse | .[0:10]'

# Reduce retention period if needed
# Edit prometheus.yml: --storage.tsdb.retention.time=15d
```

### Grafana Issues

**Issue: Dashboard Not Loading**
```bash
# Check Grafana service status
ansible grafana -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl status grafana-server"

# Check Grafana logs
ansible grafana -i ansible/inventories/production/hosts.yml \
  -m shell -a "journalctl -u grafana-server -n 50"

# Test data source connectivity
curl -s "http://{{ grafana_hostname }}:3000/api/datasources/proxy/1/api/v1/query?query=up" \
  -H "Authorization: Bearer {{ grafana_api_key }}"
```

**Issue: Alert Not Firing**
```bash
# Check alert rule evaluation
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/rules" | \
  jq '.data.groups[].rules[] | select(.name=="AlertName") | .evaluationTime'

# Test alert query manually
curl -s "http://{{ prometheus_hostname }}:9090/api/v1/query?query={{ alert_query }}"

# Check AlertManager configuration
curl -s "http://{{ alertmanager_hostname }}:9093/api/v1/status" | jq .
```

## Monitoring Automation

### Automated Health Checks

**Script: Daily Health Check (`scripts/monitoring-health-check.sh`)**
```bash
#!/bin/bash
# Daily monitoring infrastructure health check

echo "=== Monitoring Health Check - $(date) ==="

# Prometheus health
prometheus_status=$(curl -s -o /dev/null -w "%{http_code}" http://{{ prometheus_hostname }}:9090/-/healthy)
echo "Prometheus Health: $prometheus_status"

# Grafana health
grafana_status=$(curl -s http://{{ grafana_hostname }}:3000/api/health | jq -r .database)
echo "Grafana Health: $grafana_status"

# AlertManager health
alertmanager_status=$(curl -s -o /dev/null -w "%{http_code}" http://{{ alertmanager_hostname }}:9093/-/healthy)
echo "AlertManager Health: $alertmanager_status"

# Target health summary
unhealthy_targets=$(curl -s "http://{{ prometheus_hostname }}:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.health != "up") | .labels.instance' | wc -l)
echo "Unhealthy Targets: $unhealthy_targets"

# Alert summary
active_alerts=$(curl -s "http://{{ alertmanager_hostname }}:9093/api/v1/alerts?active=true" | \
  jq '.data | length')
echo "Active Alerts: $active_alerts"

if [ $prometheus_status -eq 200 ] && [ "$grafana_status" = "ok" ] && [ $alertmanager_status -eq 200 ] && [ $unhealthy_targets -eq 0 ]; then
    echo "Status: HEALTHY"
    exit 0
else
    echo "Status: UNHEALTHY - Investigation Required"
    exit 1
fi
```

### Automated Remediation

**Script: Auto-Restart Unhealthy Services (`scripts/auto-remediation.sh`)**
```bash
#!/bin/bash
# Automated remediation for common monitoring issues

# Check and restart unhealthy containers
check_and_restart_container() {
    local service=$1
    local host=$2
    
    status=$(ansible $host -i ansible/inventories/production/hosts.yml \
      -m shell -a "docker ps --filter name=$service --filter health=unhealthy --quiet" | wc -l)
    
    if [ $status -gt 0 ]; then
        echo "Restarting unhealthy $service container on $host"
        ansible $host -i ansible/inventories/production/hosts.yml \
          -m shell -a "docker restart $service"
        
        # Wait and verify
        sleep 30
        ansible $host -i ansible/inventories/production/hosts.yml \
          -m shell -a "docker ps --filter name=$service --filter health=healthy --quiet"
    fi
}

# Auto-restart services
check_and_restart_container "prometheus" "prometheus"
check_and_restart_container "grafana" "grafana"
check_and_restart_container "alertmanager" "alertmanager"
```

---

**Document Version:** 1.0
**Last Updated:** {{ ansible_date_time.date }}
**Next Review:** Monthly
**Owner:** Monitoring Team / SRE Team
**Emergency Contact:** +1-555-0126