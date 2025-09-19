# Multi-Source Health Engine Implementation Guide

## Overview

This document describes the implementation of a comprehensive multi-source health engine for Jenkins HA zero-downtime auto-healing. The health engine integrates Prometheus metrics, Loki logs, and container health checks to provide intelligent health assessment and automated recovery capabilities.

## Architecture

### Components

1. **Health Engine Core** (`scripts/health-engine.sh`)
   - Main assessment orchestrator
   - Multi-source data collection
   - Health scoring algorithm
   - Circuit breaker implementation
   - Trend analysis engine

2. **Utility Functions** (`scripts/health-engine-utils.sh`)
   - Advanced Prometheus queries with retry logic
   - Enhanced Loki log pattern detection
   - SLI/SLO compliance checking
   - Flapping detection algorithm
   - Team environment resolution

3. **Integration Layer** (`scripts/health-engine-integration.sh`)
   - Auto-healing orchestration
   - Blue-green deployment integration
   - Jenkins restart automation
   - Notification system integration
   - Grafana annotations and Prometheus metrics

4. **Configuration System** (`config/health-engine.json`)
   - Team-specific health policies
   - Configurable thresholds and weights
   - Auto-healing strategies
   - Integration settings

## Health Assessment Algorithm

### Multi-Source Data Collection

The health engine collects data from three primary sources:

#### 1. Prometheus Metrics (Weighted: 35-50%)
```bash
# Core metrics collected per team:
- jenkins:error_rate_5m
- jenkins:response_time_p95
- jenkins:service_availability_by_team
- jenkins:deployment_success_rate_5m
- jenkins:blue_green_switch_success_rate
- Memory, CPU, and Disk utilization
- Build failure rates and queue sizes
- SSL certificate expiry status
```

#### 2. Loki Log Analysis (Weighted: 20-35%)
```bash
# Log patterns analyzed:
- Error patterns: "ERROR", "Exception", "Failed", "Timeout"
- Critical patterns: "FATAL", "OutOfMemoryError", "Service unavailable"
- Warning patterns: "WARN", "Deprecated", "Memory low"
```

#### 3. Health Check Scripts (Weighted: 30%)
```bash
# Health check execution:
- Team-specific health scripts: /opt/jenkins/scripts/health-check-{team}.sh
- Generic health checks via blue-green-healthcheck templates
- Timeout-based validation (default: 30s)
- Exit code interpretation (0=healthy, non-zero=unhealthy)
```

### Health Scoring Algorithm

The health engine uses a weighted scoring system with advanced algorithms:

#### 1. Metrics Scoring
```bash
Base Score: 100
Deductions:
- Error rate exceeding SLI target: up to -25 points
- Response time exceeding threshold: up to -20 points  
- Availability below minimum: up to -25 points (critical)
- Resource utilization violations: up to -40 points combined
```

#### 2. Log Analysis Scoring
```bash
Base Score: 100
Deductions:
- Warning logs: -1 point each
- Error logs: -3 points each
- Critical logs: -10 points each
```

#### 3. Weighted Combination
```bash
Total Score = (Metrics Score × Metrics Weight + 
               Logs Score × Logs Weight + 
               Health Score × Health Weight) / 100
```

#### 4. Tier-Based Adjustments
```bash
Production Teams: More stringent scoring (0.9-1.0 multiplier)
Testing Teams: More lenient scoring (1.0-1.1 multiplier)
```

## Team-Specific Configuration

### DevOps Team (Production-Critical)
```json
{
  "enabled": true,
  "tier": "production",
  "weights": {"prometheus_metrics": 40, "loki_logs": 30, "health_checks": 30},
  "thresholds": {
    "error_rate_max": 5.0,
    "response_time_p95_max": 2000,
    "service_availability_min": 99.0
  },
  "sli_targets": {
    "availability": 99.5,
    "error_rate": 1.0,
    "mttr_minutes": 15
  },
  "auto_healing": {
    "enabled": true,
    "actions": ["restart", "switch_environment", "scale_up"],
    "max_attempts": 3,
    "safety_checks": {"min_healthy_instances": 1}
  }
}
```

### Dev-QA Team (Quality-Focused)
```json
{
  "enabled": true,
  "tier": "production",
  "weights": {"prometheus_metrics": 45, "loki_logs": 25, "health_checks": 30},
  "thresholds": {
    "error_rate_max": 3.0,
    "test_coverage_min": 85.0,
    "security_scan_pass_rate_min": 95.0
  },
  "auto_healing": {
    "actions": ["restart", "switch_environment"],
    "max_attempts": 2
  }
}
```

### Test Workbench Team (Development)
```json
{
  "enabled": true,
  "tier": "testing",
  "weights": {"prometheus_metrics": 35, "loki_logs": 35, "health_checks": 30},
  "thresholds": {
    "error_rate_max": 8.0,
    "service_availability_min": 98.0
  },
  "auto_healing": {
    "actions": ["restart", "switch_environment"],
    "max_attempts": 4,
    "safety_checks": {"max_restarts_per_hour": 5}
  }
}
```

## Advanced Features

### 1. Circuit Breaker Pattern
```bash
# Circuit breaker states:
- CLOSED: Normal operation
- OPEN: Failures exceed threshold, assessments bypassed
- HALF-OPEN: Testing recovery after timeout

# Configuration:
circuit_breaker_threshold: 3        # failures before opening
circuit_breaker_timeout: 300        # seconds before half-open
```

### 2. Flapping Detection
```bash
# Prevents oscillating between states:
threshold_changes: 3                 # state changes to detect flapping
time_window: "10m"                  # window for change detection
stabilization_period: "5m"         # suppression period
```

### 3. Trend Analysis
```bash
# Analyzes health score trends:
- Improving: Score trending upward
- Degrading: Score trending downward  
- Stable: No significant trend
- Confidence levels: 50-90%
```

### 4. SLI/SLO Compliance Monitoring
```bash
# Per-team SLI targets:
- Availability SLI: 99.5% uptime
- Error Rate SLI: <1% error rate
- Response Time SLI: <1500ms P95
- MTTR SLI: <15 minutes recovery
```

## Auto-Healing Capabilities

### Escalation Framework
```bash
Level 1: Graceful restart (Jenkins API)
Level 2: Container restart (systemd/docker)
Level 3: Blue-green environment switch
Level 4: Manual intervention notification
```

### Safety Mechanisms
```bash
- Rate limiting: Max restarts per hour per team
- Business hours enforcement (optional)
- Circuit breaker integration
- Flapping suppression
- Minimum healthy instances requirement
```

### Blue-Green Integration
```bash
# Automatic environment switching:
1. Detect critical health issues
2. Validate target environment health
3. Execute traffic switch via HAProxy
4. Monitor switch success
5. Rollback on failure
```

## Integration Points

### Prometheus Integration
```bash
# Custom metrics exported:
jenkins_health_engine_score{team,status,tier,environment}
jenkins_health_engine_assessment_timestamp{team}
jenkins_health_engine_circuit_breaker_status{team}
jenkins_health_engine_trend_confidence{team,trend}
```

### Grafana Integration
```bash
# Dashboard annotations:
- Auto-healing events
- Circuit breaker state changes
- Health status transitions
- Manual interventions
```

### Notification Systems
```bash
# Supported channels:
- Slack (team-specific channels)
- PagerDuty (critical events)
- Email (configurable recipients)
- Grafana annotations
```

### Jenkins API Integration
```bash
# Automated actions:
- Graceful restarts (/safeRestart)
- System information collection (/systemInfo)
- Build queue management
- Plugin status monitoring
```

## Usage Examples

### Basic Health Assessment
```bash
# Assess all teams
./scripts/health-engine.sh assess

# Assess specific teams  
./scripts/health-engine.sh assess devops,dev-qa

# Assessment with text output
./scripts/health-engine.sh assess all text
```

### Advanced Operations
```bash
# Continuous monitoring (5-minute intervals)
./scripts/health-engine.sh monitor 300

# Manual auto-healing trigger
./scripts/health-engine.sh auto-heal devops

# Circuit breaker status
./scripts/health-engine.sh circuit-breaker all

# Trend analysis
./scripts/health-engine.sh trends devops
```

### Integration Operations
```bash
# Assessment with auto-healing
./scripts/health-engine-integration.sh assess_and_heal

# Manual blue-green switch
./scripts/health-engine-integration.sh blue_green_switch devops health_triggered

# Manual restart
./scripts/health-engine-integration.sh restart dev-qa graceful manual_intervention

# Test notifications
./scripts/health-engine-integration.sh test_notifications devops
```

## Monitoring and Observability

### Key Metrics to Monitor
```bash
# Health Engine Performance:
- Assessment duration per team
- Circuit breaker activation frequency
- Auto-healing success rates
- Trend analysis accuracy

# Team Health Indicators:
- Overall health scores over time
- SLI compliance percentages
- Error pattern frequencies
- Recovery time distributions
```

### Grafana Dashboard Panels
```bash
1. Overall Health Status Grid (by team)
2. Health Score Trends (time series)
3. SLI Compliance Heatmap
4. Auto-healing Event Timeline
5. Circuit Breaker Status Indicators
6. Error Pattern Analysis
7. Response Time Distributions
8. Resource Utilization Trends
```

### Alerting Rules
```bash
# Health Engine Alerts:
- Health score drops below critical threshold
- Circuit breaker opens for any team
- Auto-healing fails multiple times
- Assessment timeouts or failures

# Team-specific Alerts:
- SLI violations (availability, error rate, response time)
- Critical log patterns detected
- Resource utilization exceeds limits
- SSL certificate expiring soon
```

## Implementation Best Practices

### 1. Configuration Management
```bash
- Use version-controlled configuration files
- Implement configuration validation
- Support environment-specific overrides
- Document all threshold rationale
```

### 2. Testing Strategy
```bash
- Unit tests for scoring algorithms
- Integration tests with mock data sources
- Chaos engineering for auto-healing validation
- Regular DR testing with health engine
```

### 3. Security Considerations
```bash
- Secure credential management for API access
- Rate limiting for external API calls
- Audit logging for all auto-healing actions
- Role-based access for manual overrides
```

### 4. Performance Optimization
```bash
- Parallel assessment execution
- Caching for frequently accessed metrics
- Connection pooling for external services
- Configurable timeout values
```

## Troubleshooting Guide

### Common Issues

#### Health Engine Not Starting
```bash
# Check configuration file validity
jq '.' config/health-engine.json

# Verify script permissions
ls -la scripts/health-engine*.sh

# Check dependency availability
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:3100/ready
```

#### Prometheus Connectivity Issues
```bash
# Test metric queries manually
curl "http://localhost:9090/api/v1/query?query=up"

# Check Prometheus targets
curl "http://localhost:9090/api/v1/targets"

# Verify network connectivity
ping prometheus-host
```

#### Auto-healing Not Triggering
```bash
# Check team configuration
./scripts/health-engine.sh config | jq '.teams.devops.auto_healing'

# Verify circuit breaker status
./scripts/health-engine.sh circuit-breaker devops

# Check recent healing attempts
./scripts/health-engine.sh trends devops
```

#### Blue-Green Switch Failures
```bash
# Manual health check validation
./scripts/blue-green-healthcheck.sh devops health

# HAProxy backend status
curl "http://localhost:8404/stats"

# Container status verification
docker ps --filter "name=jenkins-devops"
```

### Log Analysis
```bash
# Health engine logs
tail -f logs/health-engine.log

# Automation logs  
tail -f logs/health-automation.log

# Prometheus metrics
cat logs/health-engine-metrics.prom
```

## Future Enhancements

### Planned Features
1. **Machine Learning Integration**
   - Anomaly detection for health patterns
   - Predictive failure analysis
   - Adaptive threshold adjustment

2. **Advanced Auto-scaling**
   - Dynamic resource allocation
   - Container orchestration integration
   - Cost-optimized scaling strategies

3. **Enhanced Analytics**
   - Team performance benchmarking
   - Historical trend analysis
   - Capacity planning insights

4. **Extended Integration**
   - Kubernetes health checks
   - Cloud provider APIs
   - Service mesh monitoring

### Configuration Evolution
```bash
# Future configuration structure:
{
  "ml_features": {
    "anomaly_detection": true,
    "predictive_analysis": true,
    "adaptive_thresholds": true
  },
  "auto_scaling": {
    "enabled": true,
    "min_instances": 1,
    "max_instances": 5,
    "scale_metrics": ["cpu", "memory", "queue_size"]
  }
}
```

## Conclusion

The multi-source health engine provides a robust foundation for Jenkins HA zero-downtime operations. Its integration of multiple data sources, intelligent scoring algorithms, and automated recovery capabilities ensure high service availability while minimizing manual intervention requirements.

The system's modular design allows for easy extension and customization, making it suitable for diverse team requirements and operational patterns. Regular monitoring and tuning of the health policies ensure optimal performance and reliability.

For support and further customization, refer to the configuration files and utility scripts provided in the implementation.