# Jenkins Job Logs with Grafana Loki

## Overview

Complete guide for collecting, storing, and visualizing Jenkins job build logs using Grafana Loki and Promtail.

## Current Log Collection Status

### ✅ Already Collected (Default)

| Log Source | Path | Labels | Status |
|-----------|------|--------|--------|
| **Jenkins Container Logs** | `/var/lib/docker/containers/*/*-json.log` | job=jenkins, team, environment | ✅ Working |
| **HAProxy Logs** | `/var/log/haproxy/*.log` | job=haproxy, backend | ✅ Working |
| **System Logs** | `/var/log/messages` | job=system | ✅ Working |
| **Auth Logs** | `/var/log/secure` | job=auth | ✅ Working |

### ✅ Newly Added

| Log Source | Path | Labels | Status |
|-----------|------|--------|--------|
| **Jenkins Job Logs** | `/jenkins-logs/*/*/jobs/*/builds/*/log` | job=jenkins-job-logs, team, environment, job_name, build_number | ✅ Implemented |

## Architecture

### Before (Container Logs Only)
```
Jenkins Container
├── stdout/stderr → Docker logs → Promtail → Loki
└── Job logs (in volume) → ❌ NOT COLLECTED
```

### After (Complete Log Collection)
```
Jenkins Container
├── stdout/stderr → Docker logs → Promtail → Loki  ✅
└── Job logs (in volume) → Volume mount → Promtail → Loki  ✅
```

## Implementation

### Automatic Deployment

Job log collection is **automatically configured** when deploying monitoring stack:

```bash
# Deploy monitoring with job log collection
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Volume mounts and scrape configs are added automatically
```

### What Gets Deployed

#### 1. Promtail Volume Mounts (Automatic)

Promtail container automatically mounts all Jenkins Docker volumes:

```yaml
volumes:
  # Per-team volume mounts (auto-generated from jenkins_teams_config)
  - "jenkins-devops-blue-home:/jenkins-logs/devops/blue:ro"
  - "jenkins-devops-green-home:/jenkins-logs/devops/green:ro"
  - "jenkins-ma-blue-home:/jenkins-logs/ma/blue:ro"
  - "jenkins-ma-green-home:/jenkins-logs/ma/green:ro"
  # ... all teams automatically included
```

#### 2. Promtail Scrape Configuration (Automatic)

Job log scrape config automatically added to `promtail-config.yml`:

```yaml
scrape_configs:
  - job_name: jenkins-job-logs
    static_configs:
      - targets: [localhost]
        labels:
          job: jenkins-job-logs
          source: build-logs
          __path__: "/jenkins-logs/*/*/jobs/*/builds/*/log"
    pipeline_stages:
      # Extract team, environment, job_name, build_number from path
      - regex:
          expression: '/jenkins-logs/(?P<team>[^/]+)/(?P<environment>[^/]+)/jobs/(?P<job_name>[^/]+)/builds/(?P<build_number>[^/]+)/log'
      - labels:
          team:
          environment:
          job_name:
          build_number:
```

## Verification

### 1. Check Volume Mounts

```bash
# Verify Promtail on Jenkins VMs has access to Jenkins volumes
# Note: Container name includes hostname (e.g., promtail-jenkins-vm1-production)
docker exec promtail-jenkins-vm1-production ls -la /jenkins-logs/

# Expected output:
# drwxr-xr-x  devops/
# drwxr-xr-x  ma/
# drwxr-xr-x  ba/
# drwxr-xr-x  tw/

# Check specific team logs
docker exec promtail-jenkins-vm1-production ls -la /jenkins-logs/devops/blue/jobs/

# Should show Jenkins job directories
```

### 2. Query Job Logs from Loki

```bash
# Get available labels
curl http://localhost:9400/loki/api/v1/labels

# Should include: team, environment, job_name, build_number

# Query logs for specific team
curl -G http://localhost:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins-job-logs", team="devops"}' \
  --data-urlencode 'limit=100'

# Query logs for specific job
curl -G http://localhost:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins-job-logs", job_name="my-pipeline"}' \
  --data-urlencode 'limit=100'

# Query logs for specific build
curl -G http://localhost:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins-job-logs", job_name="my-pipeline", build_number="42"}' \
  --data-urlencode 'limit=1000'
```

### 3. View in Grafana Explore

```bash
# Access Grafana
http://localhost:9300/explore

# Select Loki datasource

# Query examples:
{job="jenkins-job-logs"}                                    # All job logs
{job="jenkins-job-logs", team="devops"}                     # Team-specific
{job="jenkins-job-logs", job_name="build-api"}              # Job-specific
{job="jenkins-job-logs", build_number="123"}                # Build-specific
{job="jenkins-job-logs"} |= "ERROR"                         # Filter errors
{job="jenkins-job-logs"} |~ "(?i)(error|fail|exception)"    # Regex filter
```

## LogQL Query Examples

### Basic Queries

```logql
# All job logs
{job="jenkins-job-logs"}

# Specific team
{job="jenkins-job-logs", team="devops"}

# Specific job
{job="jenkins-job-logs", job_name="deploy-production"}

# Specific build
{job="jenkins-job-logs", job_name="deploy-production", build_number="456"}

# Blue environment only
{job="jenkins-job-logs", environment="blue"}
```

### Filtered Queries

```logql
# Show only errors
{job="jenkins-job-logs"} |= "ERROR"

# Show failures
{job="jenkins-job-logs"} |~ "(?i)(fail|failed|failure)"

# Show exceptions
{job="jenkins-job-logs"} |~ "(?i)(exception|error)"

# Show build results
{job="jenkins-job-logs"} |= "BUILD SUCCESSFUL"
{job="jenkins-job-logs"} |= "BUILD FAILED"

# Exclude noise
{job="jenkins-job-logs"} != "DEBUG"
```

### Aggregation Queries

```logql
# Count logs per team
sum by (team) (count_over_time({job="jenkins-job-logs"}[1h]))

# Count errors per job
sum by (job_name) (count_over_time({job="jenkins-job-logs"} |= "ERROR" [1h]))

# Build failure rate
sum by (job_name) (count_over_time({job="jenkins-job-logs"} |= "BUILD FAILED" [1h])) /
sum by (job_name) (count_over_time({job="jenkins-job-logs"} |= "BUILD" [1h]))

# Logs per minute
rate({job="jenkins-job-logs"}[5m])
```

## Grafana Dashboard Integration

### Add Job Logs Panel to Existing Dashboards

1. **Navigate to Dashboard**: Jenkins Builds or Jenkins Overview
2. **Add Panel**: Click "Add panel" → "Add new panel"
3. **Select Datasource**: Loki
4. **Enter Query**:
   ```logql
   {job="jenkins-job-logs", team="$team", job_name="$job"}
   ```
5. **Configure Variables**:
   - `$team` - Team filter
   - `$job` - Job name filter
6. **Panel Settings**:
   - Visualization: Logs
   - Options: Show time, Show labels
7. **Save Dashboard**

### Example Panel Queries

```logql
# Build logs panel (filtered by variables)
{job="jenkins-job-logs", team="$team", job_name="$job", build_number="$build"}

# Error logs panel
{job="jenkins-job-logs", team="$team"} |~ "(?i)(error|exception|fail)"

# Build timeline panel
sum by (job_name) (count_over_time({job="jenkins-job-logs", team="$team"}[5m]))
```

## Use Cases

### 1. Debug Failed Build

```bash
# Find failed build
{job="jenkins-job-logs", job_name="api-deployment"} |= "BUILD FAILED"

# View full build log
{job="jenkins-job-logs", job_name="api-deployment", build_number="789"}

# Find error in logs
{job="jenkins-job-logs", job_name="api-deployment", build_number="789"} |~ "(?i)error"
```

### 2. Monitor Deployment Pipelines

```logql
# Track deployments
{job="jenkins-job-logs", job_name=~"deploy-.*"} |= "Deploying to"

# Count deployments per environment
sum by (job_name) (
  count_over_time({job="jenkins-job-logs", job_name=~"deploy-.*"}[24h])
)

# Failed deployments alert
sum by (job_name) (
  count_over_time({job="jenkins-job-logs", job_name=~"deploy-.*"} |= "FAILED" [1h])
) > 0
```

### 3. Performance Analysis

```logql
# Build duration (extract from logs)
{job="jenkins-job-logs"} |~ "Build took .* seconds"

# Test execution times
{job="jenkins-job-logs"} |~ "Tests completed in .* ms"

# Slow builds (>5 minutes)
{job="jenkins-job-logs"} |~ "Build took [5-9]|[0-9]{2,} minutes"
```

### 4. Security Monitoring

```logql
# Authentication events
{job="jenkins-job-logs"} |~ "(?i)(login|auth|credential)"

# Permission denied
{job="jenkins-job-logs"} |~ "(?i)(permission denied|access denied|unauthorized)"

# Credential usage
{job="jenkins-job-logs"} |~ "(?i)(password|token|secret|api_key)"
```

## Retention and Storage

### Current Configuration

```yaml
# Loki retention: 30 days
loki_retention: "720h"

# Promtail positions file (tracks read progress)
promtail_positions_file: "/promtail/positions.yaml"
```

### Disk Usage Estimates

**Per team** (assuming 100 builds/day, 10KB avg log size):
- Daily: 100 builds × 10KB = 1MB/day
- Monthly: 1MB × 30 = 30MB/month

**For 4 teams**:
- Monthly: 120MB
- With compression: ~40MB

**Total Loki storage** (all log sources):
- Job logs: 40MB/month
- Container logs: 500MB/month
- System logs: 200MB/month
- **Total**: ~750MB/month (~25GB for 30 days)

### Adjust Retention

```yaml
# In ansible/roles/monitoring/defaults/main.yml
loki_retention: "1440h"  # 60 days
loki_retention: "2160h"  # 90 days
```

## Troubleshooting

### Issue: No job logs in Loki

**Check volume mounts** (on Jenkins VMs):
```bash
# Replace jenkins-vm1 with actual hostname
docker inspect promtail-jenkins-vm1-production | jq '.[].Mounts[] | select(.Destination | startswith("/jenkins-logs"))'
```

**Check Promtail logs** (on Jenkins VMs):
```bash
docker logs promtail-jenkins-vm1-production | grep "jenkins-job-logs"
docker logs promtail-jenkins-vm2-production | grep "jenkins-job-logs"
```

**Check file permissions**:
```bash
docker exec promtail-jenkins-vm1-production ls -la /jenkins-logs/devops/blue/jobs/
```

### Issue: Logs not updating

**Check Promtail positions** (on Jenkins VMs):
```bash
docker exec promtail-jenkins-vm1-production cat /promtail/positions.yaml
```

**Force re-read** (delete positions file):
```bash
docker exec promtail-jenkins-vm1-production rm /promtail/positions.yaml
docker restart promtail-jenkins-vm1-production
```

### Issue: High Loki disk usage

**Check actual usage**:
```bash
du -sh /opt/monitoring/loki/data/
```

**Reduce retention**:
```yaml
loki_retention: "360h"  # 15 days instead of 30
```

**Enable compression** (already enabled by default)

## Performance Optimization

### 1. Index Configuration

Loki uses label-based indexing. Keep label cardinality low:

✅ **Good labels**:
- team (4 values)
- environment (2 values: blue/green)
- job_name (~50 values)

❌ **Avoid high-cardinality labels**:
- build_number (thousands of values)
- timestamp
- user_id

### 2. Query Optimization

```logql
# ✅ Efficient (uses indexed labels)
{job="jenkins-job-logs", team="devops", job_name="api-build"}

# ❌ Inefficient (scans all logs)
{job="jenkins-job-logs"} |= "some random string"

# ✅ Better (narrow with labels first)
{job="jenkins-job-logs", team="devops"} |= "some random string"
```

### 3. Time Range Limits

Always specify time range for queries:

```logql
# ✅ Limited time range
{job="jenkins-job-logs"}[1h]

# ❌ Unbounded (scans all data)
{job="jenkins-job-logs"}
```

## Related Documentation

- `monitoring-separate-vm-deployment-guide.md` - Separate VM setup
- `ENHANCED_LOG_DASHBOARD_INTEGRATION.md` - Dashboard examples
- `CLAUDE.md` - Quick reference commands

## Summary

✅ **What You Get**:
- Complete Jenkins job log collection
- Automatic Docker volume mounting
- Team/job/build label extraction
- 30-day log retention
- Grafana visualization ready
- LogQL query support

✅ **Zero Configuration**:
- Automatically detects all teams from `jenkins_teams_config`
- Mounts all blue/green volumes
- Extracts metadata from file paths
- No manual configuration needed

✅ **Production Ready**:
- Read-only volume mounts (safe)
- Position tracking (no duplicate logs)
- Compression enabled
- Configurable retention
- Low overhead (~50MB RAM for Promtail)
