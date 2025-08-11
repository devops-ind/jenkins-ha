# Jenkins HA Operations Guide

## Overview

This document provides comprehensive operational guidance for managing the Jenkins High Availability infrastructure. It covers day-to-day operations, troubleshooting, maintenance procedures, and the enhanced operational scripts.

## Table of Contents

- [Operational Scripts](#operational-scripts)
- [Deployment Operations](#deployment-operations)
- [Disaster Recovery](#disaster-recovery)
- [Blue-Green Operations](#blue-green-operations)
- [Security Operations](#security-operations)
- [Monitoring Operations](#monitoring-operations)
- [Maintenance Procedures](#maintenance-procedures)
- [Troubleshooting Guide](#troubleshooting-guide)

## Operational Scripts

### Enhanced Automation Scripts

#### HA Setup Script (`scripts/ha-setup.sh`)
Comprehensive Jenkins HA infrastructure setup automation with 559 lines of enterprise-grade functionality.

**Features:**
- Multi-mode deployment (full, masters-only, monitoring-only, validate-only)
- Comprehensive validation framework
- Production confirmation prompts
- Detailed reporting and logging
- Error handling and rollback capabilities

**Usage:**
```bash
# Full production setup
scripts/ha-setup.sh production full

# Staging masters only
scripts/ha-setup.sh staging masters-only

# Validation only (dry run)
scripts/ha-setup.sh production validate-only

# Local monitoring setup
scripts/ha-setup.sh local monitoring-only
```

**Command Line Options:**
```bash
scripts/ha-setup.sh [environment] [setup_mode]

Options:
  --help                Show help message
  --dry-run            Show execution plan without running
  --verbose            Enable verbose output
  --skip-validation    Skip environment validation (not recommended)

Examples:
  scripts/ha-setup.sh production full              # Full production setup
  scripts/ha-setup.sh staging masters-only         # Staging with Jenkins masters only
  scripts/ha-setup.sh production validate-only     # Validate environment only
  scripts/ha-setup.sh local monitoring-only        # Local monitoring setup
```

#### Disaster Recovery Script (`scripts/disaster-recovery.sh`)
Enterprise-grade automated disaster recovery with RTO/RPO compliance (508 lines).

**Features:**
- RTO/RPO compliance tracking (15-minute RTO, 5-minute RPO targets)
- Automated backup validation and integrity checking
- Infrastructure failover with health validation
- DNS management and service orchestration
- Comprehensive recovery reporting

**Usage:**
```bash
# Execute production disaster recovery
scripts/disaster-recovery.sh production secondary 15 5

# Validate DR prerequisites
scripts/disaster-recovery.sh production --validate

# Simulate DR process
scripts/disaster-recovery.sh production --simulate
```

**Parameters:**
- `environment`: Target environment (production, staging)
- `dr_site`: DR site identifier (secondary, dr-west, etc.)
- `rto_minutes`: Recovery Time Objective in minutes (default: 15)
- `rpo_minutes`: Recovery Point Objective in minutes (default: 5)

#### Enhanced Security Scripts

##### Security Scanning (`/usr/local/bin/jenkins-security-scan.sh`)
Comprehensive vulnerability scanning with Trivy integration.

```bash
# Full security scan
/usr/local/bin/jenkins-security-scan.sh --all

# Scan specific image
/usr/local/bin/jenkins-security-scan.sh jenkins:latest

# Generate compliance report
/usr/local/bin/jenkins-security-scan.sh --compliance

# Scheduled scan (for cron)
/usr/local/bin/jenkins-security-scan.sh --scheduled
```

##### Security Monitoring (`/usr/local/bin/jenkins-security-monitor.sh`)
Real-time security monitoring and compliance validation.

```bash
# Full monitoring cycle
/usr/local/bin/jenkins-security-monitor.sh monitor

# Vulnerability scan only
/usr/local/bin/jenkins-security-monitor.sh scan

# Security compliance check
/usr/local/bin/jenkins-security-monitor.sh compliance

# Resource monitoring only
/usr/local/bin/jenkins-security-monitor.sh resources
```

##### Secure Container Execution (`/usr/local/bin/jenkins-secure-run.sh`)
Secure container execution with enterprise security constraints.

```bash
# Run container with security constraints
/usr/local/bin/jenkins-secure-run.sh jenkins/master:latest

# Debug mode
/usr/local/bin/jenkins-secure-run.sh --debug jenkins/master:latest

# Validate security configuration
/usr/local/bin/jenkins-secure-run.sh --validate
```

#### Credential Management (`scripts/generate-credentials.sh`)
Automated secure credential generation and management.

```bash
# Generate all credentials for environment
scripts/generate-credentials.sh production

# Generate specific credential type
scripts/generate-credentials.sh production --type jenkins-admin

# Rotate existing credentials
scripts/generate-credentials.sh production --rotate

# Validate credential strength
scripts/generate-credentials.sh production --validate
```

## Deployment Operations

### Standard Deployment Workflow

#### 1. Pre-deployment Validation
```bash
# Validate environment configuration
ansible-playbook ansible/site.yml --tags validation -e validation_mode=strict

# Check infrastructure readiness
scripts/ha-setup.sh production validate-only

# Security compliance check
/usr/local/bin/jenkins-security-scan.sh --compliance
```

#### 2. Deployment Execution
```bash
# Full production deployment
make deploy-production

# Or use enhanced HA setup script
scripts/ha-setup.sh production full

# Monitor deployment progress
tail -f /var/log/jenkins/ha-setup-*.log
```

#### 3. Post-deployment Validation
```bash
# Health check
ansible-playbook ansible/playbooks/health-check.yml -i ansible/inventories/production/hosts.yml

# Blue-green validation
ansible-playbook ansible/playbooks/blue-green-operations.yml -e blue_green_operation=status

# Security validation
/usr/local/bin/jenkins-security-monitor.sh compliance
```

### Enhanced Infrastructure Update Pipeline

The infrastructure update pipeline now includes automated rollback triggers and SLI monitoring:

#### Key Features
- **SLI-based Rollback**: Automatic rollback on performance degradation
- **Approval Gates**: Required approvals for production changes
- **Health Monitoring**: Continuous monitoring during deployments
- **Circuit Breaker**: Automatic deployment halting on failures

#### Pipeline Stages
1. **Pre-deployment Validation**: System readiness and security checks
2. **Staging Deployment**: Deploy to staging environment first
3. **Automated Testing**: Run comprehensive test suites
4. **Production Approval**: Required approval for production deployment
5. **Production Deployment**: Gradual rollout with monitoring
6. **SLI Monitoring**: Real-time SLI threshold monitoring
7. **Automated Rollback Assessment**: Trigger rollback if SLI thresholds exceeded
8. **Post-deployment Validation**: Comprehensive health and security checks

## Disaster Recovery

### Automated Disaster Recovery Process

#### Recovery Workflow
1. **Backup Validation**: Find and validate backup within RPO window
2. **Service Shutdown**: Graceful shutdown of existing services
3. **Infrastructure Failover**: Deploy DR site infrastructure
4. **Data Restoration**: Restore Jenkins data from validated backup
5. **Service Startup**: Start services in correct dependency order
6. **DNS Failover**: Update DNS to point to DR site
7. **Health Validation**: Comprehensive recovery validation
8. **Compliance Reporting**: Generate RTO/RPO compliance report

#### RTO/RPO Monitoring
- **RTO Target**: 15 minutes (configurable)
- **RPO Target**: 5 minutes (configurable)
- **Automated Reporting**: Real-time compliance tracking
- **Alerting**: Notifications on SLA violations

#### DR Testing
```bash
# Test DR prerequisites
scripts/disaster-recovery.sh production --validate

# Simulate full DR process
scripts/disaster-recovery.sh production --simulate

# Execute non-destructive DR test
scripts/disaster-recovery.sh staging secondary 30 10
```

## Blue-Green Operations

### Enhanced Blue-Green Deployment

#### Pre-switch Validation
The blue-green deployment now includes comprehensive pre-switch validation:

- **Health Checks**: Validate target environment health
- **Performance Testing**: Load testing and performance validation
- **Security Scanning**: Security compliance validation
- **Data Consistency**: Database and configuration consistency checks
- **Integration Testing**: External service integration validation

#### Blue-Green Commands
```bash
# Check current blue-green status
ansible-playbook ansible/playbooks/blue-green-operations.yml -e blue_green_operation=status

# Switch to green environment
ansible-playbook ansible/playbooks/blue-green-operations.yml -e blue_green_operation=switch -e target_color=green

# Rollback to blue environment
ansible-playbook ansible/playbooks/blue-green-operations.yml -e blue_green_operation=rollback

# Enhanced health check
scripts/blue-green-healthcheck.sh production
```

#### Automated Rollback Triggers
- **Error Rate Threshold**: > 5% error rate triggers rollback
- **Response Time Threshold**: > 2000ms average response time
- **Resource Usage**: > 90% CPU or memory utilization
- **Health Check Failures**: > 3 consecutive health check failures

## Security Operations

### Daily Security Operations

#### Security Monitoring Dashboard
Access the comprehensive security monitoring:
- **Grafana Security Dashboard**: http://monitoring:3000/d/security
- **Security Alerts**: tail -f /var/log/jenkins/security/alerts.log
- **Compliance Status**: /usr/local/bin/jenkins-security-monitor.sh compliance

#### Daily Security Tasks
```bash
# Run daily security scan
/usr/local/bin/jenkins-security-scan.sh --scheduled

# Check security alerts
tail -n 100 /var/log/jenkins/security/alerts.log

# Validate security compliance
/usr/local/bin/jenkins-security-monitor.sh compliance

# Review failed login attempts
grep "Failed login" /var/log/jenkins/security/audit.log | tail -20
```

### Security Incident Response

#### Automated Response Triggers
The security monitoring system includes automated response capabilities:

```bash
# Security violation detected - automatic response
if security_violation_detected; then
    # Stop affected container
    container_runtime stop $container
    
    # Generate incident report
    generate_incident_report $container $violation_type
    
    # Alert security team
    logger -t "jenkins-security" -p "user.crit" "SECURITY INCIDENT: $violation_type"
fi
```

#### Manual Incident Response
```bash
# Isolate compromised system
iptables -P INPUT DROP
systemctl stop jenkins-master-*

# Collect forensic evidence
/usr/local/bin/forensic-collect.sh INCIDENT_ID

# Generate incident report
/usr/local/bin/incident-response.sh critical "Security breach detected"
```

## Monitoring Operations

### Enhanced Grafana Dashboards

#### Comprehensive Monitoring
The monitoring stack now includes a comprehensive 26-panel Grafana dashboard:

**Dashboard Panels:**
- **SLI Metrics**: Error rate, response time, availability
- **DORA Metrics**: Deployment frequency, lead time, MTTR, change failure rate  
- **Blue-Green Status**: Environment health and switch status
- **Security Metrics**: Vulnerability counts, compliance status
- **Container Resources**: CPU, memory, disk usage per container
- **Jenkins Metrics**: Job success rates, queue depth, agent utilization

#### Accessing Monitoring
```bash
# Grafana Dashboard
http://monitoring:3000/d/jenkins-comprehensive

# Prometheus Metrics
http://monitoring:9090/graph

# Direct metric queries
curl "http://monitoring:9090/api/v1/query?query=jenkins:error_rate_5m"
```

### SLI/SLO Monitoring

#### Service Level Indicators (SLIs)
- **Availability**: 99.9% uptime target
- **Error Rate**: < 0.1% error rate target  
- **Response Time**: < 500ms 95th percentile target
- **Deployment Success**: > 95% success rate target

#### Automated Alerting Rules
```yaml
# Prometheus alerting rules
groups:
  - name: jenkins_sli_alerts
    rules:
      - alert: HighErrorRate
        expr: jenkins:error_rate_5m > 0.05
        for: 5m
        annotations:
          summary: "High error rate detected: {{ $value }}"
          
      - alert: HighResponseTime  
        expr: jenkins:response_time_95p > 2000
        for: 5m
        annotations:
          summary: "High response time: {{ $value }}ms"
```

## Maintenance Procedures

### Scheduled Maintenance

#### Daily Maintenance
```bash
# Automated via cron
0 2 * * * /usr/local/bin/jenkins-security-scan.sh --scheduled
0 3 * * * /usr/local/bin/backup.sh --automated
0 4 * * * /usr/local/bin/cleanup-old-logs.sh
```

#### Weekly Maintenance
```bash
# System updates (with approval)
ansible-playbook ansible/playbooks/system-update.yml

# Security compliance audit
/usr/local/bin/security-audit.sh

# Performance optimization
/usr/local/bin/performance-tune.sh
```

#### Monthly Maintenance
```bash
# Full infrastructure health check
scripts/ha-setup.sh production validate-only --verbose

# Disaster recovery testing
scripts/disaster-recovery.sh staging --simulate

# Security penetration testing
/usr/local/bin/security-pentest.sh

# Capacity planning review
/usr/local/bin/capacity-analysis.sh
```

### Certificate Management

#### SSL/TLS Certificate Operations
```bash
# Check certificate expiry
openssl x509 -in /etc/ssl/certs/jenkins.crt -text -noout | grep "Not After"

# Renew Let's Encrypt certificates
certbot renew --dry-run

# Update HAProxy certificate bundle
cat /etc/letsencrypt/live/jenkins.company.com/{fullchain,privkey}.pem > /etc/ssl/certs/jenkins.pem
systemctl reload haproxy
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Deployment Issues

**Issue**: Deployment fails with validation errors
```bash
# Solution: Run detailed validation
scripts/ha-setup.sh production validate-only --verbose

# Check specific validation failures
ansible-playbook ansible/site.yml --tags validation -e validation_mode=warn
```

**Issue**: Container security constraints causing failures
```bash
# Solution: Check security constraints
/usr/local/bin/jenkins-secure-run.sh --validate

# Review security logs
tail -f /var/log/jenkins/security/container.log
```

#### Security Issues

**Issue**: High number of security alerts
```bash
# Solution: Review security monitoring
/usr/local/bin/jenkins-security-monitor.sh compliance

# Check specific violations
grep "CRITICAL\|WARNING" /var/log/jenkins/security/alerts.log
```

**Issue**: Vulnerability scan failures
```bash
# Solution: Update Trivy database
trivy image --download-db-only

# Re-run security scan
/usr/local/bin/jenkins-security-scan.sh --all
```

#### Blue-Green Issues

**Issue**: Blue-green switch fails validation
```bash
# Solution: Check pre-switch validation
ansible-playbook ansible/playbooks/blue-green-operations.yml -e blue_green_operation=validate -e target_color=green

# Review health check logs
tail -f /var/log/jenkins/blue-green-health.log
```

#### Disaster Recovery Issues

**Issue**: DR backup not found within RPO window
```bash
# Solution: Check backup status
ls -la /backup/jenkins/jenkins-backup-*.tar.gz

# Extend RPO window temporarily
scripts/disaster-recovery.sh production secondary 15 30
```

### Log File Locations

#### Application Logs
```bash
/var/log/jenkins/ha-setup-*.log          # HA setup logs
/var/log/jenkins/disaster-recovery-*.log # DR execution logs
/opt/jenkins/logs/jenkins.log            # Jenkins application logs
```

#### Security Logs
```bash
/var/log/jenkins/security/alerts.log     # Security alerts
/var/log/jenkins/security/audit.log      # Security audit log
/var/log/jenkins/security/container.log  # Container security log
/var/log/jenkins/security/scan-results/  # Vulnerability scan results
```

#### System Logs
```bash
/var/log/syslog                          # System logs
/var/log/auth.log                        # Authentication logs
/var/log/haproxy.log                     # Load balancer logs
```

### Performance Monitoring

#### Key Performance Metrics
```bash
# Jenkins performance
curl -s "http://monitoring:9090/api/v1/query?query=jenkins_job_duration_seconds"

# System resources
curl -s "http://monitoring:9090/api/v1/query?query=node_memory_MemAvailable_bytes"

# Container metrics
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

#### Performance Tuning
```bash
# JVM tuning for Jenkins masters
export JAVA_OPTS="-Xms2g -Xmx4g -XX:+UseG1GC -XX:MaxGCPauseMillis=100"

# Container resource optimization
docker update --memory=4g --cpus=2.0 jenkins-master-blue

# Database performance tuning
postgresql-tune /etc/postgresql/13/main/postgresql.conf
```

### Emergency Procedures

#### Emergency Contacts
- **Security Team**: security@company.com
- **DevOps Team**: devops@company.com  
- **On-call Engineer**: +1-555-JENKINS

#### Emergency Response
```bash
# Emergency shutdown
systemctl stop jenkins-master-*
systemctl stop haproxy

# Emergency recovery
scripts/disaster-recovery.sh production secondary --emergency

# Emergency security isolation
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
```

---

For additional operational support or to report operational issues, contact the DevOps team or create an operational ticket.