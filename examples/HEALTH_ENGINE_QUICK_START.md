# Health Engine Quick Start Guide

## Overview

This guide provides step-by-step instructions to get the Jenkins HA Multi-Source Health Engine up and running quickly.

## Prerequisites

### Required Tools
```bash
# Install required tools on your system
sudo apt-get update
sudo apt-get install -y jq curl bc docker.io

# Or on macOS
brew install jq curl bc
```

### System Requirements
- Linux/macOS environment
- Docker or systemd for container management
- Network access to Prometheus, Loki, and Grafana
- Sufficient disk space for logs (recommended: 1GB)

## Quick Setup

### 1. Validate Installation
```bash
# Run the validation script to check setup
./scripts/validate-health-engine.sh
```

### 2. Configure Monitoring URLs (if different from defaults)
```bash
# Edit the configuration file
vim config/health-engine.json

# Update these URLs if needed:
{
  "global": {
    "prometheus_url": "http://your-prometheus:9090",
    "loki_url": "http://your-loki:3100", 
    "grafana_url": "http://your-grafana:9300"
  }
}
```

### 3. Test Basic Functionality
```bash
# Test configuration loading
./scripts/health-engine.sh config

# Validate monitoring connectivity  
./scripts/health-engine.sh validate

# Run a basic health assessment
./scripts/health-engine.sh assess devops json
```

### 4. Set Up Team-Specific Health Checks (Optional)
```bash
# Create team-specific health check scripts
sudo mkdir -p /opt/jenkins/scripts

# Example for devops team
sudo tee /opt/jenkins/scripts/health-check-devops.sh << 'EOF'
#!/bin/bash
# DevOps team specific health check
set -euo pipefail

TEAM="devops"
CHECK_TYPE="${1:-basic}"

case "$CHECK_TYPE" in
    "basic")
        # Basic connectivity check
        curl -s --max-time 10 "http://devopsjenkins.local.dev:8080/api/json" >/dev/null
        ;;
    "full")
        # Comprehensive health check
        curl -s --max-time 10 "http://devopsjenkins.local.dev:8080/api/json" >/dev/null
        curl -s --max-time 10 "http://devopsjenkins.local.dev:8080/manage/system-info" >/dev/null
        ;;
    *)
        echo "Unknown check type: $CHECK_TYPE"
        exit 1
        ;;
esac

echo "Health check passed for team $TEAM"
exit 0
EOF

sudo chmod +x /opt/jenkins/scripts/health-check-devops.sh
```

## Usage Examples

### Basic Operations
```bash
# Run health assessment for all teams
./scripts/health-engine.sh assess

# Run assessment for specific teams
./scripts/health-engine.sh assess devops,dev-qa

# Get human-readable output
./scripts/health-engine.sh assess all text

# Get Prometheus metrics format
./scripts/health-engine.sh assess all prometheus
```

### Advanced Operations
```bash
# Start continuous monitoring (5-minute intervals)
./scripts/health-engine.sh monitor 300

# Check circuit breaker status
./scripts/health-engine.sh circuit-breaker

# View trend analysis for a team
./scripts/health-engine.sh trends devops

# Manual auto-healing trigger
./scripts/health-engine.sh auto-heal devops
```

### Integration Commands
```bash
# Run assessment with automatic healing
./scripts/health-engine-integration.sh assess_and_heal

# Manual blue-green switch
./scripts/health-engine-integration.sh blue_green_switch devops health_triggered

# Manual Jenkins restart
./scripts/health-engine-integration.sh restart dev-qa graceful

# Test notification system
./scripts/health-engine-integration.sh test_notifications devops

# Clean up automation locks
./scripts/health-engine-integration.sh cleanup_locks
```

## Configuration Customization

### Team-Specific Thresholds
```json
{
  "teams": {
    "your-team": {
      "enabled": true,
      "tier": "production",
      "weights": {
        "prometheus_metrics": 40,
        "loki_logs": 30,
        "health_checks": 30
      },
      "thresholds": {
        "error_rate_max": 5.0,
        "response_time_p95_max": 2000,
        "service_availability_min": 99.0
      },
      "auto_healing": {
        "enabled": true,
        "actions": ["restart", "switch_environment"],
        "max_attempts": 3
      }
    }
  }
}
```

### Notification Setup
```json
{
  "integration_settings": {
    "external_tools": {
      "slack": {
        "enabled": true,
        "webhook_url": "https://hooks.slack.com/your-webhook",
        "channel_mapping": {
          "devops": "#devops-alerts",
          "dev-qa": "#dev-qa-alerts"
        }
      },
      "pagerduty": {
        "enabled": true,
        "integration_key": "your-pagerduty-key"
      }
    }
  }
}
```

## Monitoring Setup

### Prometheus Rules
Add these recording rules to your Prometheus configuration:
```yaml
groups:
  - name: health_engine
    rules:
      - record: jenkins_health_engine_team_status
        expr: jenkins_health_engine_score
        labels:
          service: "health_engine"
      
      - record: jenkins_health_engine_sli_compliance
        expr: |
          (
            jenkins_health_engine_score > 85
          ) * 100
```

### Grafana Dashboard
Create a dashboard with these panels:
1. Health Score Grid (by team)
2. Health Trends (time series)
3. Auto-healing Events (annotations)
4. Circuit Breaker Status
5. SLI Compliance Percentage

### Alert Rules
```yaml
groups:
  - name: health_engine_alerts
    rules:
      - alert: HealthEngineTeamCritical
        expr: jenkins_health_engine_score < 50
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Team {{ $labels.team }} health is critical"
          
      - alert: HealthEngineCircuitBreakerOpen
        expr: jenkins_health_engine_circuit_breaker_status == 1
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Circuit breaker open for team {{ $labels.team }}"
```

## Troubleshooting

### Common Issues

#### 1. "jq: command not found"
```bash
# Install jq
sudo apt-get install jq  # Ubuntu/Debian
brew install jq          # macOS
```

#### 2. "Configuration file invalid JSON"
```bash
# Validate JSON syntax
jq '.' config/health-engine.json

# Fix common JSON issues:
# - Missing commas between objects
# - Trailing commas
# - Unescaped quotes in strings
```

#### 3. "Cannot connect to Prometheus"
```bash
# Check Prometheus status
curl http://localhost:9090/-/healthy

# Verify configuration URLs
./scripts/health-engine.sh config | jq '.global'

# Update URLs in config/health-engine.json if needed
```

#### 4. "Health check script not found"
```bash
# Check if team-specific script exists
ls -la /opt/jenkins/scripts/health-check-*.sh

# Create directory if missing
sudo mkdir -p /opt/jenkins/scripts

# Use generic health check template instead
```

#### 5. "Auto-healing not working"
```bash
# Check auto-healing configuration
./scripts/health-engine.sh config | jq '.teams.devops.auto_healing'

# Verify circuit breaker status
./scripts/health-engine.sh circuit-breaker devops

# Check automation locks
ls -la /tmp/jenkins-health-automation/

# Clean up stuck locks
./scripts/health-engine-integration.sh cleanup_locks
```

### Debug Mode
```bash
# Enable debug logging
DEBUG=true ./scripts/health-engine.sh assess devops

# Check log files
tail -f logs/health-engine.log
tail -f logs/health-automation.log
```

### Log Analysis
```bash
# View recent health assessments
./scripts/health-engine.sh trends devops

# Check Prometheus metrics
cat logs/health-engine-metrics.prom

# View state file
jq '.' logs/health-engine-state.json
```

## Performance Tuning

### For Large Deployments
```json
{
  "performance": {
    "max_concurrent_assessments": 10,
    "assessment_timeout": "10m",
    "cache_duration": "2m",
    "batch_processing": true
  },
  "global": {
    "evaluation_window": "10m",
    "trend_analysis_window": "1h"
  }
}
```

### For High-Frequency Monitoring
```bash
# Increase monitoring frequency
./scripts/health-engine.sh monitor 60  # Every minute

# Use shorter evaluation windows
{
  "global": {
    "evaluation_window": "2m",
    "circuit_breaker_timeout": 120
  }
}
```

## Production Deployment

### Systemd Service Setup
```bash
# Create systemd service file
sudo tee /etc/systemd/system/jenkins-health-engine.service << 'EOF'
[Unit]
Description=Jenkins Health Engine Monitor
After=network.target

[Service]
Type=simple
User=jenkins
WorkingDirectory=/opt/jenkins-ha
ExecStart=/opt/jenkins-ha/scripts/health-engine.sh monitor 300
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable jenkins-health-engine
sudo systemctl start jenkins-health-engine
```

### Log Rotation
```bash
# Configure log rotation
sudo tee /etc/logrotate.d/jenkins-health-engine << 'EOF'
/opt/jenkins-ha/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 jenkins jenkins
}
EOF
```

### Backup Configuration
```bash
# Include in backup scripts
tar -czf health-engine-config-$(date +%Y%m%d).tar.gz \
    config/health-engine.json \
    logs/health-engine-state.json \
    scripts/health-engine*.sh
```

## Security Considerations

### File Permissions
```bash
# Set secure permissions
chmod 750 scripts/health-engine*.sh
chmod 640 config/health-engine.json
chmod 640 logs/*.log

# Restrict state file access
chmod 600 logs/health-engine-state.json
```

### API Security
```bash
# Use environment variables for sensitive data
export JENKINS_API_TOKEN="your-token"
export GRAFANA_API_TOKEN="your-token"
export SLACK_WEBHOOK_URL="your-webhook"

# Or use dedicated credential files
echo "your-token" > /etc/jenkins/api-token
chmod 600 /etc/jenkins/api-token
```

### Network Security
- Restrict network access to monitoring systems
- Use HTTPS for external API calls
- Implement API rate limiting
- Monitor for unusual access patterns

## Support

### Getting Help
1. Check validation output: `./scripts/validate-health-engine.sh`
2. Review log files in `logs/` directory
3. Test individual components manually
4. Check configuration syntax with `jq`

### Reporting Issues
Include this information when reporting issues:
- Validation script output
- Configuration file (sanitized)
- Relevant log entries
- System environment details
- Error messages and stack traces

This health engine provides robust monitoring and auto-healing capabilities for your Jenkins HA infrastructure. Regular monitoring and tuning will ensure optimal performance and reliability.