# Enhanced Jenkins Log Dashboard Integration

## Overview

This guide documents the comprehensive enhancement of Grafana dashboards with Loki log integration, providing unified observability that combines metrics and logs for the Jenkins HA infrastructure.

## Features Implemented

### 1. **Comprehensive Log Panel Integration**

#### Jenkins Overview Dashboard
- **Real-time Build Logs**: Shows recent build activity with team filtering
- **Error Logs Panel**: Highlights critical issues with automatic pattern detection
- **Log Volume Statistics**: Error, Warning, and Info log counts with color-coded thresholds
- **Security Event Logs**: Authentication failures and security violations
- **HAProxy Load Balancer Logs**: Traffic routing and backend health logs

#### Jenkins Builds Dashboard  
- **Build Success/Failure Log Correlation**: Links build metrics with corresponding log entries
- **Job-Specific Build Analysis**: Tabular view of build results with log integration
- **Log-Metrics Correlation Panel**: Visualizes relationship between error logs and build failures
- **Build Duration vs Log Volume**: Correlates slow builds with error patterns

#### Jenkins Dynamic Agents Dashboard
- **Agent Provisioning Logs**: Real-time agent creation and startup logs
- **Agent Error Logs**: Container failures, launch issues, and connectivity problems
- **Container Lifecycle Logs**: Docker container start/stop/exit events
- **Agent Performance Correlation**: Links agent metrics with error log rates
- **Docker Socket & Volume Logs**: Mount and permission issues

### 2. **Team-Aware Log Filtering**

```logql
# Team-specific log queries
{job=\"jenkins\", team=\"devops\", environment=\"blue\"} |= \"BUILD\"

# Cross-team error correlation
{job=\"jenkins\", team=~\"devops|ma|ba|tw\"} |~ \"(?i)(error|exception|failed)\"

# Environment-specific filtering
{job=\"jenkins\", environment=\"blue\"} |~ \"(?i)(deploy.*fail|config.*error)\"
```

### 3. **Advanced Log-Based Alerting**

#### Critical Error Volume Alerts
- **High Error Volume**: >5 errors/second for 5 minutes
- **Critical Error Volume**: >20 errors/second for 2 minutes

#### Security Event Monitoring
- **Authentication Failures**: >2 auth failures/second
- **Security Violations**: Immediate alerts on unauthorized access

#### Agent Issues Detection
- **Provisioning Errors**: >1 agent error/second for 5 minutes
- **Connection Issues**: >3 disconnections/second for 3 minutes
- **Docker Socket Errors**: >0.5 Docker errors/second for 5 minutes

#### Team-Specific Alerts
- **Team Error Rate**: >3 errors/second per team for 10 minutes
- **Environment Issues**: Deployment failures in specific environments

### 4. **Log Correlation Features**

#### Build Failure Analysis
```promql
# Metric: Build failure rate
rate(jenkins_builds_failure_build_count[5m])

# Correlated Log Query
{job=\"jenkins\"} |~ \"(?i)(build.*failed|compilation.*error)\"
```

#### Agent Performance Analysis
```promql
# Metric: Agent launch rate
rate(jenkins_agent_launches_total[5m])

# Correlated Log Query  
{job=\"jenkins\"} |~ \"(?i)(agent.*error|launch.*fail)\"
```

#### Blue-Green Environment Correlation
```promql
# Environment disparity detection
rate(count_over_time({job=\"jenkins\", environment=\"blue\"} |~ \"(?i)(error|fail)\" [1m])[5m:]) -
rate(count_over_time({job=\"jenkins\", environment=\"green\"} |~ \"(?i)(error|fail)\" [1m])[5m:])
```

## Architecture Integration

### Loki Stack Components

#### Loki Configuration (`loki-config.yml.j2`)
```yaml
server:
  http_listen_port: 9400
  log_level: info

# Retention and compaction
limits_config:
  retention_period: 30d
  enforce_metric_name: false
  
# Analytics disabled for privacy
analytics:
  reporting_enabled: false
```

#### Promtail Configuration (`promtail-config.yml.j2`)
```yaml
scrape_configs:
  # Jenkins container logs with team extraction
  - job_name: jenkins-containers
    static_configs:
      - targets: [localhost]
        labels:
          job: jenkins
          source: container
    pipeline_stages:
      - json:
          expressions:
            output: log
            stream: stream
            timestamp: time
      # Extract team from container name
      - template:
          source: team
          template: |
            {{- if contains .container_name \"jenkins-devops\" -}}devops
            {{- else if contains .container_name \"jenkins-ma\" -}}ma  
            {{- else if contains .container_name \"jenkins-ba\" -}}ba
            {{- else if contains .container_name \"jenkins-tw\" -}}tw
            {{- else -}}unknown{{- end }}
```

### Grafana Integration

#### Loki Datasource (`loki.yml.j2`)
```yaml
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://localhost:9400
    isDefault: false
    jsonData:
      maxLines: 1000
      derivedFields:
        # Extract container ID for correlation
        - name: "Container ID"
          matcherRegex: "container_id=([a-f0-9]+)"
          url: "/explore?left=[\"now-1h\",\"now\",\"Loki\",{\"expr\":\"{container_id=\\\"${__value.raw}\\\"}\"}]"
        # Team dashboard links
        - name: "Team Dashboard"
          matcherRegex: "team=([a-zA-Z0-9_-]+)"
          url: "/d/jenkins-overview-${__value.raw}/jenkins-overview-${__value.raw}-team"
```

### Dashboard Panel Examples

#### Log Panel with Team Filtering
```json
{
  \"id\": 5,
  \"title\": \"Jenkins Build Logs - Recent Activity\",
  \"type\": \"logs\",
  \"datasource\": \"Loki\",
  \"targets\": [
    {
      \"expr\": \"{job=\\\"jenkins\\\", team=\\\"{{ dashboard_team }}\\\", environment=\\\"{{ team_environment }}\\\"} |= \\\"BUILD\\\"\",
      \"refId\": \"A\"
    }
  ],
  \"options\": {
    \"showTime\": true,
    \"showLabels\": true,
    \"wrapLogMessage\": true,
    \"enableLogDetails\": true,
    \"sortOrder\": \"Descending\"
  }
}
```

#### Log-Metric Correlation Panel
```json
{
  \"id\": 6,
  \"title\": \"Build Log Volume vs Failure Rate Correlation\",
  \"type\": \"timeseries\",
  \"targets\": [
    {
      \"expr\": \"rate(jenkins_builds_failure_build_count[5m])\",
      \"legendFormat\": \"Build Failure Rate\",
      \"refId\": \"A\"
    },
    {
      \"expr\": \"rate(count_over_time({job=\\\"jenkins\\\"} |~ \\\"(?i)(error|exception|failed)\\\" [1m])[5m:])\",
      \"legendFormat\": \"Error Log Rate\",
      \"refId\": \"B\",
      \"datasource\": \"Loki\"
    }
  ]
}
```

## Deployment Instructions

### 1. **Enable Loki Stack**
```yaml
# In monitoring role defaults
loki_enabled: true
promtail_enabled: true
loki_retention: \"30d\"
```

### 2. **Deploy Enhanced Dashboards**
```bash
# Deploy monitoring stack with log integration
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags monitoring

# Test enhanced dashboards
ansible-playbook -i ansible/inventories/local/hosts.yml test-enhanced-log-dashboards.yml
```

### 3. **Configure Team-Specific Dashboards**
```yaml
# Enable team-specific dashboard generation
dashboard_deployment:
  generate_team_specific: true
  team_folder_organization: true
  keep_global_dashboards: true
```

## Usage Guide

### 1. **Accessing Enhanced Dashboards**

#### Global Dashboards
- **Jenkins Overview**: http://localhost:9300/d/jenkins-overview/
- **Jenkins Builds**: http://localhost:9300/d/jenkins-builds/  
- **Jenkins Dynamic Agents**: http://localhost:9300/d/jenkins-dynamic-agents/

#### Team-Specific Dashboards
- **DevOps Team**: http://localhost:9300/d/jenkins-overview-devops/
- **MA Team**: http://localhost:9300/d/jenkins-overview-ma/
- **BA Team**: http://localhost:9300/d/jenkins-overview-ba/
- **TW Team**: http://localhost:9300/d/jenkins-overview-tw/

### 2. **Log Query Examples**

#### Build Investigation
```logql
# All build failures for a specific team
{job=\"jenkins\", team=\"devops\"} |~ \"(?i)(build.*failed|build.*error)\"

# Build timeouts across all teams
{job=\"jenkins\"} |~ \"(?i)(timeout|build.*timeout)\" | line_format \"{{.timestamp}} [{{.team}}] {{.output}}\"

# Successful builds with duration info
{job=\"jenkins\"} |~ \"(?i)(build.*success|build.*completed)\" |~ \"duration\"
```

#### Agent Troubleshooting
```logql
# Agent provisioning failures
{job=\"jenkins\"} |~ \"(?i)(agent.*error|agent.*fail|launch.*fail)\"

# Docker socket issues
{job=\"jenkins\"} |~ \"(?i)(docker.*error|socket.*error|container.*fail)\"

# Agent connection issues
{job=\"jenkins\"} |~ \"(?i)(agent.*disconnect|connection.*lost)\"
```

#### Security Monitoring
```logql
# Authentication failures
{job=\"jenkins\"} |~ \"(?i)(login.*failed|authentication.*failed)\"

# Security violations
{job=\"jenkins\"} |~ \"(?i)(unauthorized|forbidden|security.*violation)\"

# HAProxy security events
{job=\"haproxy\"} |~ \"(?i)(4[0-9][0-9]|5[0-9][0-9])\" |~ \"(?i)(auth|security)\"
```

### 3. **Alert Investigation Workflow**

#### When Log-Based Alerts Fire
1. **Check Dashboard**: Navigate to relevant team dashboard
2. **Correlate Metrics**: Compare log volume with build/agent metrics  
3. **Drill Down**: Use log panel filters to isolate issues
4. **Context**: Use derived fields to jump to related logs
5. **Resolution**: Follow runbook procedures

#### Alert Types and Responses
- **High Error Volume**: Check infrastructure health + recent deployments
- **Security Events**: Investigate authentication patterns + source IPs
- **Agent Issues**: Check Docker daemon + network connectivity
- **Build Failures**: Review code changes + infrastructure changes

## Maintenance and Operations

### 1. **Log Retention Management**
```yaml
# Loki retention configuration
loki_retention: \"30d\"
loki_compactor_retention_enabled: true
loki_max_chunk_age: \"1h\"
```

### 2. **Performance Optimization**
```yaml
# Promtail performance tuning
promtail_positions_file: \"/promtail/data/positions.yaml\"

# Loki query optimization
limits_config:
  max_cache_freshness_per_query: 10m
  split_queries_by_interval: 15m
```

### 3. **Monitoring the Monitors**
- **Loki Health**: http://localhost:9400/ready
- **Promtail Metrics**: http://localhost:9401/metrics
- **Log Ingestion Rate**: Monitor via Prometheus metrics

## Troubleshooting

### Common Issues

#### Log Panels Not Showing Data
1. Check Loki datasource configuration
2. Verify Promtail is collecting logs
3. Validate log queries syntax
4. Check team/environment label extraction

#### Missing Team-Specific Filtering
1. Verify container naming conventions
2. Check Promtail pipeline configuration
3. Validate team label extraction regex
4. Ensure dashboard team variables are set

#### Performance Issues
1. Optimize LogQL queries (add filters early)
2. Reduce time ranges for heavy queries
3. Check Loki resource allocation
4. Monitor ingestion rate vs query load

### Log Query Debugging
```bash
# Test Loki connectivity
curl http://localhost:9400/ready

# Check available labels
curl -G http://localhost:9400/loki/api/v1/labels

# Test specific query
curl -G http://localhost:9400/loki/api/v1/query_range \\
  --data-urlencode 'query={job=\"jenkins\"}' \\
  --data-urlencode 'start=2024-01-01T00:00:00Z' \\
  --data-urlencode 'end=2024-01-01T01:00:00Z'
```

## Benefits Achieved

### 1. **Unified Observability**
- Single pane of glass for metrics and logs
- Correlated troubleshooting workflows
- Reduced mean time to resolution (MTTR)

### 2. **Team Efficiency**
- Team-specific filtered views
- Context-aware log exploration
- Automated error pattern detection

### 3. **Proactive Monitoring**
- Log-based alerting for early issue detection
- Pattern recognition for recurring problems
- Security event monitoring and alerting

### 4. **Operational Excellence**
- Comprehensive audit trail
- Performance correlation analysis
- Infrastructure optimization insights

This enhanced log integration provides a production-ready observability solution that scales with your Jenkins infrastructure while maintaining team isolation and security.