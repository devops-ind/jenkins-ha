# Jenkins HA Automated Switch Manager - Demo Guide

This document demonstrates the comprehensive automated switch manager capabilities for Jenkins HA infrastructure with zero-downtime auto-healing.

## Overview

The Automated Switch Manager provides intelligent blue-green switching based on multi-source health monitoring with comprehensive safety mechanisms and integration with existing Jenkins HA infrastructure.

## Key Features

### 🔄 **Automated Switch Logic**
- Health engine integration for intelligent decision making
- SLI threshold-based triggers (error rate >5%, latency >2000ms, availability <99.5%)
- Log-based error pattern detection
- Time-window validation to prevent flapping

### 🛡️ **Safety Mechanisms**
- Circuit breaker patterns (max 3 failures before opening)
- Rate limiting (3 switches/hour, 10/day per team)
- Flapping detection (5 switches in 30 minutes)
- Business hours awareness
- Maintenance window respect

### ⚙️ **Team-Independent Management**
- Per-team automation levels (manual, assisted, automatic)
- Team-specific thresholds and policies
- Independent blue-green switching
- Customizable safety limits

### 🔧 **Integration Features**
- HAProxy runtime API for zero-downtime switching
- Pre-switch backup using simplified backup script
- Data sync using sync-for-bluegreen-switch.sh
- Post-switch validation and rollback capability
- Comprehensive audit logging

## Quick Start

### 1. Initial Setup

```bash
# Make scripts executable
chmod +x scripts/automated-switch-manager.sh
chmod +x scripts/update-team-environment.py
chmod +x scripts/automated-switch-daemon.sh

# Create required directories
mkdir -p data logs

# Check current team configurations
scripts/update-team-environment.py show
```

### 2. Configure Team Automation Levels

```bash
# Set automation levels for each team
scripts/automated-switch-manager.sh set-automation devops automatic
scripts/automated-switch-manager.sh set-automation ma assisted
scripts/automated-switch-manager.sh set-automation ba assisted
scripts/automated-switch-manager.sh set-automation tw automatic
```

### 3. Check System Status

```bash
# Show global status
scripts/automated-switch-manager.sh status

# Check specific team status
scripts/automated-switch-manager.sh status devops
```

## Usage Examples

### Manual Switch Operations

```bash
# Execute manual switch for devops team
scripts/automated-switch-manager.sh switch devops manual_intervention

# Force switch (bypasses safety checks)
scripts/automated-switch-manager.sh switch ma emergency_fix true

# Switch with custom reason
scripts/automated-switch-manager.sh switch ba performance_issue
```

### Automated Assessment and Healing

```bash
# Assess if teams need switching
scripts/automated-switch-manager.sh assess all

# Assess specific team
scripts/automated-switch-manager.sh assess devops

# Run automated healing for all teams
scripts/automated-switch-manager.sh auto-heal

# Run automated healing for specific team
scripts/automated-switch-manager.sh auto-heal ma
```

### Maintenance Operations

```bash
# Enable maintenance mode (disables automation)
scripts/automated-switch-manager.sh maintenance devops enable

# Disable maintenance mode
scripts/automated-switch-manager.sh maintenance devops disable

# Reset circuit breaker after manual fix
scripts/automated-switch-manager.sh reset-circuit-breaker devops

# Clean up automation locks
scripts/automated-switch-manager.sh cleanup
```

## Automation Levels Explained

### 🔴 **Manual Mode**
- No automatic switches
- Manual intervention required for all switches
- Suitable for critical production teams requiring human oversight

```bash
scripts/automated-switch-manager.sh set-automation ba manual
```

### 🟡 **Assisted Mode**
- Automatic switches only with multiple strong indicators
- Requires 2+ triggers (health engine + SLI + logs)
- Suitable for production teams with moderate automation trust

```bash
scripts/automated-switch-manager.sh set-automation ma assisted
```

### 🟢 **Automatic Mode**
- Automatic switches on any strong indicator
- Single trigger sufficient (health engine OR SLI OR logs)
- Suitable for dev/test teams or highly trusted production

```bash
scripts/automated-switch-manager.sh set-automation tw automatic
```

## Health Monitoring Integration

### SLI Threshold Monitoring

The system monitors key SLIs from Prometheus:

```bash
# Error rate monitoring
rate(jenkins_http_requests_total{team="devops",status=~"5.."}[5m]) / rate(jenkins_http_requests_total{team="devops"}[5m]) * 100

# Response time monitoring  
histogram_quantile(0.95, rate(jenkins_http_request_duration_seconds_bucket{team="devops"}[5m])) * 1000

# Availability monitoring
avg_over_time(up{team="devops"}[5m]) * 100
```

### Log Pattern Detection

Critical log patterns from Loki:
- `FATAL`, `OutOfMemoryError`
- `Service unavailable`, `502 Bad Gateway`
- `SSL certificate expired`
- `Security breach`, `Unauthorized access`

### Health Engine Integration

```bash
# Health engine provides intelligent decisions
scripts/health-engine.sh assess devops json

# Automated switch manager uses health decisions
scripts/automated-switch-manager.sh assess devops
```

## Safety Demonstrations

### Circuit Breaker Pattern

```bash
# Simulate multiple failures to trigger circuit breaker
for i in {1..4}; do
    scripts/automated-switch-manager.sh switch test-team failure_simulation true
    sleep 60
done

# Check circuit breaker status
scripts/automated-switch-manager.sh status test-team

# Reset after manual fix
scripts/automated-switch-manager.sh reset-circuit-breaker test-team
```

### Rate Limiting

```bash
# Attempt multiple switches to trigger rate limiting
for i in {1..5}; do
    scripts/automated-switch-manager.sh switch devops rate_test_$i
    sleep 10
done

# Check rate limit status
scripts/automated-switch-manager.sh status devops
```

### Flapping Detection

```bash
# Simulate rapid switching to trigger flapping detection
for i in {1..6}; do
    scripts/automated-switch-manager.sh switch tw flapping_test_$i true
    sleep 180  # 3 minutes between switches
done

# Check flapping status
scripts/automated-switch-manager.sh status tw
```

## Daemon Mode for Continuous Monitoring

### Start Daemon

```bash
# Start background daemon for continuous monitoring
scripts/automated-switch-daemon.sh start

# Check daemon status
scripts/automated-switch-daemon.sh status

# View daemon logs
scripts/automated-switch-daemon.sh logs 100
```

### Systemd Integration

```bash
# Install systemd service
sudo cp config/jenkins-automated-switch.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable jenkins-automated-switch

# Start service
sudo systemctl start jenkins-automated-switch

# Check service status
sudo systemctl status jenkins-automated-switch

# View service logs
journalctl -u jenkins-automated-switch -f
```

## Configuration Examples

### Team-Specific Configuration

Edit `config/automated-switch-config.json`:

```json
{
  "team_configurations": {
    "devops": {
      "automation_level": "automatic",
      "custom_limits": {
        "max_switches_per_hour": 3,
        "max_switches_per_day": 8,
        "business_hours_only": false
      },
      "switch_triggers": {
        "health_engine_decision": true,
        "sli_threshold_violations": true,
        "log_pattern_detection": true
      },
      "approval_gates": {
        "production_hours_approval": false,
        "after_hours_approval": false
      }
    }
  }
}
```

### Health Engine Configuration

Update `config/health-engine.json`:

```json
{
  "teams": {
    "devops": {
      "thresholds": {
        "error_rate_max": 5.0,
        "response_time_p95_max": 2000,
        "service_availability_min": 99.0
      },
      "auto_healing": {
        "enabled": true,
        "actions": ["restart", "switch_environment"],
        "safety_checks": {
          "max_restarts_per_hour": 3,
          "business_hours_only": false
        }
      }
    }
  }
}
```

## Monitoring and Observability

### Grafana Dashboards

The system creates annotations in Grafana for:
- Switch started/completed/failed events
- Circuit breaker state changes
- Rate limit violations
- Flapping detection

### Prometheus Metrics

Key metrics exported:
- `jenkins_automated_switch_total{team, result}`
- `jenkins_automated_switch_duration_seconds{team}`
- `jenkins_circuit_breaker_status{team}`
- `jenkins_automation_rate_limit{team, period}`

### Audit Logging

Comprehensive logging includes:
- Switch decisions and execution
- Safety mechanism triggers
- Health assessment results
- Configuration changes

```bash
# View recent audit logs
tail -f logs/automated-switch-audit.log

# Search for specific team events
grep "devops" logs/automated-switch-audit.log | tail -20

# Check for circuit breaker events
grep "circuit_breaker" logs/automated-switch-audit.log
```

## Troubleshooting

### Common Issues

1. **Switch Blocked by Circuit Breaker**
```bash
# Check circuit breaker status
scripts/automated-switch-manager.sh status devops

# Reset if issue is resolved
scripts/automated-switch-manager.sh reset-circuit-breaker devops
```

2. **Rate Limit Exceeded**
```bash
# Check current rate limits
scripts/automated-switch-manager.sh status devops

# Wait for rate limit window to reset (hourly/daily)
```

3. **Health Engine Not Responding**
```bash
# Check health engine availability
scripts/health-engine.sh assess devops

# Verify Prometheus/Loki connectivity
curl -s http://localhost:9090/api/v1/query?query=up
curl -s http://localhost:3100/ready
```

4. **HAProxy Integration Issues**
```bash
# Check HAProxy container status
docker ps | grep haproxy

# Verify HAProxy stats API
curl -s http://localhost:8404/stats

# Test manual backend switching
docker exec haproxy-loadbalancer socat - /var/run/haproxy/admin.sock
```

### Debug Mode

```bash
# Enable debug logging
DEBUG=true scripts/automated-switch-manager.sh assess devops

# View detailed logs
tail -f logs/automated-switch.log
```

## Best Practices

### 1. **Gradual Rollout**
- Start with test teams in automatic mode
- Move production teams from manual → assisted → automatic
- Monitor for 1-2 weeks at each level

### 2. **Safety Configuration**
- Conservative rate limits initially
- Longer stabilization periods for critical teams
- Business hours restrictions for sensitive systems

### 3. **Monitoring Setup**
- Configure Slack/PagerDuty notifications
- Set up Grafana alerts on automation failures
- Regular review of switch history and patterns

### 4. **Regular Maintenance**
- Weekly review of circuit breaker events
- Monthly analysis of flapping incidents
- Quarterly tuning of thresholds and limits

## Production Deployment Checklist

- [ ] Configure team automation levels appropriately
- [ ] Set up notification channels (Slack/PagerDuty)
- [ ] Configure Grafana dashboards and alerts
- [ ] Test manual switches for each team
- [ ] Verify health engine integration
- [ ] Test rollback procedures
- [ ] Document team-specific procedures
- [ ] Train operations team on troubleshooting
- [ ] Set up log aggregation and monitoring
- [ ] Configure backup and disaster recovery

## Advanced Usage

### Custom Health Checks

Extend health checking with custom scripts:

```bash
# Custom health check script
cat > scripts/custom-health-check.sh << 'EOF'
#!/bin/bash
team="$1"
# Custom health logic here
# Return 0 for healthy, 1 for switch needed
EOF

# Integrate with switch manager
scripts/automated-switch-manager.sh assess devops
```

### Integration with CI/CD

```yaml
# Jenkins pipeline integration
pipeline {
    agent any
    stages {
        stage('Deploy') {
            steps {
                script {
                    // Trigger switch after deployment
                    sh 'scripts/automated-switch-manager.sh switch devops deployment_completed'
                }
            }
        }
    }
}
```

### Webhook Integration

```bash
# Webhook endpoint for external triggers
curl -X POST http://jenkins-automation:8080/webhook/switch \
  -H "Content-Type: application/json" \
  -d '{"team": "devops", "reason": "external_monitoring_alert"}'
```

This comprehensive automated switch manager provides production-ready zero-downtime blue-green switching with intelligent health monitoring and robust safety mechanisms.