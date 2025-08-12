# Jenkins HA Security Guide

## Overview

This document provides comprehensive security guidance for the Jenkins High Availability infrastructure. The system implements enterprise-grade security controls including container security, vulnerability scanning, compliance validation, and automated security monitoring.

**Security Enhancements Implemented:**
- **Container Security**: Trivy vulnerability scanning, security constraints, runtime monitoring
- **Automated Rollback**: SLI-based rollback triggers with security validation
- **Enhanced Monitoring**: Real-time security monitoring with compliance reporting
- **Job DSL Security**: Secure execution replacing vulnerable dynamic-ansible-executor.groovy
- **Credential Management**: Automated secure credential generation and vault integration

## Table of Contents

- [Current Security Implementation](#current-security-implementation)
- [Security Architecture](#security-architecture)
- [Container Security](#container-security)
- [Job DSL Security](#job-dsl-security)
- [Credential Management](#credential-management)
- [Network Security](#network-security)
- [Compliance & Auditing](#compliance--auditing)
- [Security Testing](#security-testing)
- [Security Maintenance](#security-maintenance)
- [Emergency Security Operations](#emergency-security-operations)
- [Incident Response](#incident-response)

## Current Security Implementation

### Implemented Security Controls

#### Container Security Framework
- **Trivy Scanner Integration**: Automated vulnerability scanning (v0.48.3)
- **Security Constraints**: Non-root execution, non-privileged, read-only filesystem
- **Runtime Monitoring**: Real-time security monitoring with `/usr/local/bin/jenkins-security-monitor.sh`
- **Compliance Validation**: Automated security compliance checking

#### Secure Job DSL Execution
- **Removed Vulnerable Code**: Eliminated `dynamic-ansible-executor.groovy` (critical security vulnerability)
- **Secure Replacement**: Implemented `secure-ansible-executor.groovy` with sandboxing
- **Approval Workflows**: Required security team approval for production execution
- **Audit Logging**: Complete audit trail of all Job DSL changes

#### Enhanced Credential Management
- **Automated Generation**: Secure credential generation with `scripts/generate-credentials.sh`
- **Vault Integration**: All credentials stored in encrypted Ansible Vault
- **Rotation Support**: Automated credential rotation capabilities
- **Access Controls**: Role-based access to credential stores

#### Security Monitoring & Alerting
- **Real-time Monitoring**: Continuous security monitoring and alerting
- **SLI Integration**: Security metrics integrated with SLI monitoring
- **Automated Response**: Automated containment on security violations
- **Compliance Reporting**: Automated security compliance validation and reporting

### Security File Locations

```bash
# Security Scripts
/usr/local/bin/jenkins-security-scan.sh          # Trivy vulnerability scanning
/usr/local/bin/jenkins-security-monitor.sh       # Runtime security monitoring
/usr/local/bin/jenkins-secure-run.sh            # Secure container execution

# Security Configuration
/etc/jenkins/security-policies/                  # Security policy configurations
/var/log/jenkins/security/                       # Security audit logs
ansible/roles/jenkins-master/tasks/security-scanning.yml  # Security tasks

# Credential Management
scripts/generate-credentials.sh                  # Secure credential generation
ansible/inventories/*/group_vars/all/vault.yml  # Encrypted credential storage
```

## Security Architecture

### Defense in Depth

The security implementation follows a layered defense strategy:

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Layers                         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Perimeter Security                     │    │
│  │  - Firewall Rules                                   │    │
│  │  - VPN Access                                       │    │
│  │  - DDoS Protection                                  │    │
│  └─────────────────┬───────────────────────────────────┘    │
│                    │                                        │
│  ┌─────────────────▼───────────────────────────────────┐    │
│  │              Network Security                       │    │
│  │  - SSL/TLS Encryption                              │    │
│  │  - Network Segmentation                            │    │
│  │  - Container Network Isolation                     │    │
│  └─────────────────┬───────────────────────────────────┘    │
│                    │                                        │
│  ┌─────────────────▼───────────────────────────────────┐    │
│  │            Application Security                     │    │
│  │  - Jenkins Security Configuration                  │    │
│  │  - RBAC and Authentication                         │    │
│  │  - Plugin Security Management                      │    │
│  └─────────────────┬───────────────────────────────────┘    │
│                    │                                        │
│  ┌─────────────────▼───────────────────────────────────┐    │
│  │            Container Security                       │    │
│  │  - Image Vulnerability Scanning                    │    │
│  │  - Runtime Security Policies                       │    │
│  │  - Resource Limits and Isolation                   │    │
│  └─────────────────┬───────────────────────────────────┘    │
│                    │                                        │
│  ┌─────────────────▼───────────────────────────────────┐    │
│  │              Host Security                          │    │
│  │  - System Hardening                                │    │
│  │  - Intrusion Detection (AIDE, RKHunter)           │    │
│  │  - Access Controls and Audit Logging               │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Security Components

#### Core Security Tools
- **Fail2ban**: Intrusion prevention and IP blocking
- **AIDE**: Advanced Intrusion Detection Environment
- **RKHunter**: Rootkit detection and system integrity
- **OpenSSL**: Certificate and encryption management
- **UFW/Firewalld**: Host-based firewall management
- **Auditd**: System call auditing and logging

## System Hardening

### Automated Security Hardening

The security role implements comprehensive system hardening:

#### Kernel and System Parameters
```sysctl
# Network security
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Kernel hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
```

#### File Permissions and Ownership
```bash
# System files
/etc/passwd: 644 root:root
/etc/shadow: 640 root:shadow
/etc/group: 644 root:root
/etc/gshadow: 640 root:shadow
/etc/ssh/sshd_config: 600 root:root

# Jenkins files
/opt/jenkins: 755 jenkins:jenkins
/shared/jenkins: 755 jenkins:jenkins
/var/log/jenkins: 750 jenkins:jenkins
```

### SSH Hardening

#### SSH Configuration
```ssh
# /etc/ssh/sshd_config
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers jenkins ubuntu admin
```

#### SSH Security Features
- **Key-based Authentication**: Only public key authentication allowed
- **Root Login Disabled**: No direct root access via SSH
- **Connection Limits**: Maximum authentication attempts and timeouts
- **User Restrictions**: Specific user allowlists

## Network Security

### Firewall Configuration

#### Required Ports and Services
```yaml
# Production firewall rules
security_allowed_ports:
  - "22"    # SSH (restricted to management networks)
  - "80"    # HTTP (redirects to HTTPS)
  - "443"   # HTTPS (Jenkins web interface)
  - "8080"  # Jenkins primary master
  - "8081"  # Jenkins secondary master
  - "50000" # Jenkins agent communication primary
  - "50001" # Jenkins agent communication secondary
  - "8404"  # HAProxy statistics (restricted)
  - "9090"  # Prometheus (internal only)
  - "3000"  # Grafana (internal only)
  - "2049"  # NFS (storage network only)
```

#### Network Segmentation
```bash
# Management Network: 10.0.1.0/24
# Jenkins Masters: 10.0.2.0/24
# Jenkins Agents: 10.0.3.0/24
# Shared Storage: 10.0.4.0/24
# Harbor Registry: 10.0.5.0/24
# Monitoring: 10.0.6.0/24
```

### SSL/TLS Configuration

#### Certificate Management
```bash
# Generate self-signed certificate for testing
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/jenkins.key \
  -out /etc/ssl/certs/jenkins.crt \
  -subj "/C=US/ST=State/L=City/O=Company/CN=jenkins.company.com"

# Production: Use Let's Encrypt or corporate CA
certbot certonly --standalone -d jenkins.company.com
```

#### HAProxy SSL Configuration
```haproxy
# SSL/TLS security headers
frontend jenkins_frontend
    bind *:443 ssl crt /etc/ssl/certs/jenkins.pem no-sslv3 no-tls-tickets
    rspadd Strict-Transport-Security:\ max-age=31536000;\ includeSubDomains;\ preload
    rspadd X-Frame-Options:\ DENY
    rspadd X-Content-Type-Options:\ nosniff
    rspadd X-XSS-Protection:\ 1;\ mode=block
    rspadd Referrer-Policy:\ strict-origin-when-cross-origin
```

## Access Control and Authentication

### Jenkins Security Configuration

#### Matrix-Based Security
```groovy
// Jenkins security configuration
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()

// Configure security realm
def ldapRealm = new LDAPSecurityRealm(
    "ldap://company.com:389",
    "dc=company,dc=com",
    null, null, null, null,
    null, null, null, false, false, null, null
)
instance.setSecurityRealm(ldapRealm)

// Configure authorization strategy
def strategy = new ProjectMatrixAuthorizationStrategy()
strategy.add(Jenkins.ADMINISTER, "admin")
strategy.add(Jenkins.READ, "authenticated")
strategy.add(Item.BUILD, "developers")
strategy.add(Item.READ, "developers")

instance.setAuthorizationStrategy(strategy)
instance.save()
```

#### Role-Based Access Control (RBAC)
```yaml
# Jenkins roles and permissions
jenkins_security_roles:
  - name: "administrators"
    permissions:
      - "hudson.model.Hudson.Administer"
      - "hudson.model.Hudson.Read"
      - "hudson.model.Hudson.RunScripts"
    users:
      - "admin"
      - "jenkins-admin"

  - name: "developers"
    permissions:
      - "hudson.model.Hudson.Read"
      - "hudson.model.Item.Build"
      - "hudson.model.Item.Read"
      - "hudson.model.Item.Workspace"
    users:
      - "dev-team"

  - name: "viewers"
    permissions:
      - "hudson.model.Hudson.Read"
      - "hudson.model.Item.Read"
    users:
      - "qa-team"
      - "management"
```

### Credential Management

#### Jenkins Credentials Store
```groovy
// Secure credential management
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.plugins.credentials.domains.*

def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

// Add SSH key for agents
def sshKey = new BasicSSHUserPrivateKey(
    CredentialsScope.GLOBAL,
    "jenkins-agent-key",
    "jenkins",
    new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(privateKey),
    "",
    "SSH key for Jenkins agents"
)
store.addCredentials(Domain.global(), sshKey)

// Add API tokens
def apiToken = new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    "harbor-api-token",
    "Harbor registry API token",
    Secret.fromString(apiTokenValue)
)
store.addCredentials(Domain.global(), apiToken)
```

## Container Security

### Image Security

#### Vulnerability Scanning with Trivy
```bash
# Automated image scanning in Harbor
trivy image harbor.company.com/jenkins/jenkins-master:latest
trivy image harbor.company.com/jenkins/jenkins-agent-dind:latest
trivy image harbor.company.com/jenkins/jenkins-agent-maven:latest
```

#### Security Scanning Results
```yaml
# Example security scan configuration
harbor_security_scanning:
  enabled: true
  scan_all_policy: true
  vulnerability_allowlist:
    - "CVE-2023-12345"  # Approved exceptions
  severity_threshold: "High"
  auto_scan_on_push: true
```

### Container Runtime Security

#### Docker Security Configuration
```json
{
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "icc": false,
  "userns-remap": "default",
  "log-driver": "journald",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

#### Container Resource Limits
```yaml
# Resource constraints for security
jenkins_master_resources:
  memory: "4g"
  memory_swap: "4g"
  cpu: "2.0"
  pids_limit: 1000

jenkins_agent_resources:
  memory: "2g"
  memory_swap: "2g"
  cpu: "1.0"
  pids_limit: 500
```

### Runtime Security Policies

#### AppArmor/SELinux Policies
```bash
# AppArmor profile for Jenkins containers
/usr/bin/docker-default flags=(attach_disconnected,mediate_deleted) {
  network,
  capability,
  file,
  umount,
  deny @{PROC}/* w,
  deny /sys/[^f]** wklx,
  deny /sys/f[^s]** wklx,
  deny /sys/fs/[^c]** wklx,
  deny /sys/fs/c[^g]** wklx,
  deny /sys/fs/cg[^r]** wklx,
  deny /sys/firmware/** rwklx,
  deny /sys/devices/virtual/powercap/** rwklx,
}
```

## Intrusion Detection and Prevention

### Fail2ban Configuration

#### Automated Intrusion Prevention
```ini
# /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[jenkins]
enabled = true
port = 8080,8081
filter = jenkins
logpath = /opt/jenkins/logs/jenkins.log
maxretry = 5
findtime = 300
bantime = 1800

[haproxy-http-auth]
enabled = true
port = http,https
filter = haproxy-http-auth
logpath = /var/log/haproxy.log
maxretry = 5
```

#### Custom Filters
```python
# /etc/fail2ban/filter.d/jenkins.conf
[Definition]
failregex = ^.* Failed login attempt for user .* from <HOST>.*$
            ^.* Authentication failed for .* from <HOST>.*$
            ^.* Invalid user .* from <HOST>.*$

ignoreregex = ^.* Authentication successful for .*$
```

### Advanced Threat Detection

#### Security Event Monitoring
```bash
#!/bin/bash
# /usr/local/bin/security-monitor.sh

LOG_FILE="/var/log/security-events.log"
ALERT_THRESHOLD=5

# Monitor failed login attempts
failed_logins=$(grep "Failed login" /opt/jenkins/logs/jenkins.log | wc -l)
if [ $failed_logins -gt $ALERT_THRESHOLD ]; then
    echo "$(date): High number of failed logins detected: $failed_logins" >> $LOG_FILE
    # Send alert
fi

# Monitor privilege escalation attempts
if grep -q "sudo.*FAILED" /var/log/auth.log; then
    echo "$(date): Privilege escalation attempt detected" >> $LOG_FILE
fi

# Monitor unusual network connections
netstat -ant | grep ESTABLISHED | awk '{print $5}' | grep -v ":22\|:80\|:443\|:8080" > /tmp/connections.tmp
if [ -s /tmp/connections.tmp ]; then
    echo "$(date): Unusual network connections detected" >> $LOG_FILE
fi
```

## File Integrity Monitoring

### AIDE Configuration

#### System File Monitoring
```bash
# /etc/aide/aide.conf
database=file:/var/lib/aide/aide.db
database_out=file:/var/lib/aide/aide.db.new
gzip_dbout=yes

# Monitor critical system files
/etc p+i+n+u+g+s+b+m+c+md5+sha1
/bin p+i+n+u+g+s+b+m+c+md5+sha1
/sbin p+i+n+u+g+s+b+m+c+md5+sha1
/usr/bin p+i+n+u+g+s+b+m+c+md5+sha1
/usr/sbin p+i+n+u+g+s+b+m+c+md5+sha1

# Monitor Jenkins configurations
/opt/jenkins/config.xml p+i+n+u+g+s+b+m+c+md5+sha1
/shared/jenkins/config.xml p+i+n+u+g+s+b+m+c+md5+sha1
/shared/jenkins/credentials.xml p+i+n+u+g+s+b+m+c+md5+sha1
```

#### Automated Integrity Checks
```bash
#!/bin/bash
# /usr/local/bin/aide-check.sh

# Initialize AIDE database
aide --init

# Run daily checks
aide --check

# Process results
if [ $? -eq 0 ]; then
    echo "$(date): AIDE check passed - no changes detected"
else
    echo "$(date): AIDE check failed - file system changes detected"
    aide --check | mail -s "AIDE Alert: File System Changes Detected" security@company.com
fi
```

### RKHunter (Rootkit Detection)

#### Rootkit Scanning Configuration
```bash
# /etc/rkhunter.conf
UPDATE_MIRRORS=1
MIRRORS_MODE=0
WEB_CMD=""
DISABLE_TESTS="suspscan hidden_procs deleted_files packet_cap_apps"
ALLOW_SSH_ROOT_USER=no
ALLOW_SSH_PROT_V1=0
SCRIPTWHITELIST="/usr/bin/egrep"
SCRIPTWHITELIST="/usr/bin/fgrep"
SCRIPTWHITELIST="/usr/bin/which"
ALLOWHIDDENDIR="/etc/.java"
ALLOWHIDDENDIR="/dev/.static"
ALLOWHIDDENDIR="/dev/.udev"
```

#### Automated Scanning
```bash
#!/bin/bash
# /usr/local/bin/rkhunter-scan.sh

# Update signatures
rkhunter --update

# Run scan
rkhunter --check --skip-keypress --report-warnings-only

# Log results
if [ $? -eq 0 ]; then
    echo "$(date): RKHunter scan completed - no threats detected" >> /var/log/rkhunter-scan.log
else
    echo "$(date): RKHunter scan completed - potential threats detected" >> /var/log/rkhunter-scan.log
    rkhunter --check --report-warnings-only | mail -s "RKHunter Alert: Potential Threats Detected" security@company.com
fi
```

## Security Monitoring and Alerting

### Log Aggregation and Analysis

#### Centralized Logging Configuration
```yaml
# Elasticsearch/Logstash configuration for security logs
logstash_inputs:
  - name: "jenkins-logs"
    type: "file"
    path: "/opt/jenkins/logs/*.log"
    tags: ["jenkins", "application"]
  
  - name: "security-logs"
    type: "file"
    path: "/var/log/auth.log"
    tags: ["security", "authentication"]
  
  - name: "fail2ban-logs"
    type: "file"
    path: "/var/log/fail2ban.log"
    tags: ["security", "intrusion-prevention"]
```

#### Security Event Correlation
```bash
# Security event correlation script
#!/bin/bash
# /usr/local/bin/security-correlate.sh

SECURITY_LOG="/var/log/security-events.log"
CORRELATION_THRESHOLD=3

# Check for multiple failed logins from same IP
suspicious_ips=$(grep "Failed login" /opt/jenkins/logs/jenkins.log | \
                awk '{print $NF}' | sort | uniq -c | \
                awk -v threshold=$CORRELATION_THRESHOLD '$1 > threshold {print $2}')

for ip in $suspicious_ips; do
    echo "$(date): Suspicious activity from IP: $ip" >> $SECURITY_LOG
    # Add to fail2ban if not already banned
    fail2ban-client set jenkins banip $ip
done
```

### Real-time Monitoring

#### Security Metrics Collection
```yaml
# Prometheus security metrics
security_metrics:
  - name: "failed_login_attempts"
    query: 'increase(jenkins_login_failures_total[5m])'
    threshold: 10
    
  - name: "privilege_escalation_attempts"
    query: 'increase(sudo_failures_total[5m])'
    threshold: 3
    
  - name: "file_integrity_violations"
    query: 'aide_violations_total'
    threshold: 1
```

## Vulnerability Management

### Automated Scanning

#### System Vulnerability Assessment
```bash
#!/bin/bash
# /usr/local/bin/vulnerability-scan.sh

# Update vulnerability database
apt-get update && apt-get upgrade -y

# Run OpenVAS/Nessus scan
if command -v openvas-scanner &> /dev/null; then
    openvas-scanner --target localhost --format XML --output /tmp/vuln-scan.xml
fi

# Scan container images
docker images --format "table {{.Repository}}:{{.Tag}}" | grep -v REPOSITORY | while read image; do
    trivy image $image --format json --output /tmp/trivy-$image.json
done

# Generate security report
python3 /usr/local/bin/generate-security-report.py
```

#### Patch Management
```yaml
# Automated patch management
security_patching:
  enabled: true
  schedule: "0 2 * * 0"  # Weekly on Sunday at 2 AM
  auto_reboot: false
  excluded_packages:
    - "jenkins"  # Manual testing required
  notification_email: "security@company.com"
```

### Container Image Security

#### Harbor Registry Security Policies
```yaml
# Harbor security policies
harbor_policies:
  vulnerability_scanning:
    enabled: true
    severity_threshold: "High"
    scan_on_push: true
    
  content_trust:
    enabled: true
    notary_url: "https://notary.harbor.company.com"
    
  image_signing:
    enabled: true
    required_signers:
      - "security-team"
      - "release-manager"
```

## Compliance and Auditing

### Audit Logging

#### System Audit Configuration
```bash
# /etc/audit/rules.d/audit.rules
# Monitor file access
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k identity

# Monitor Jenkins files
-w /opt/jenkins/config.xml -p wa -k jenkins-config
-w /shared/jenkins/credentials.xml -p wa -k jenkins-credentials
-w /shared/jenkins/secrets/ -p wa -k jenkins-secrets

# Monitor privilege escalation
-a always,exit -F arch=b64 -S execve -k privilege-escalation
-a always,exit -F arch=b32 -S execve -k privilege-escalation

# Monitor network connections
-a always,exit -F arch=b64 -S socket -k network-connections
-a always,exit -F arch=b32 -S socket -k network-connections
```

#### Compliance Reporting
```python
#!/usr/bin/env python3
# /usr/local/bin/compliance-report.py

import json
import datetime
from pathlib import Path

def generate_compliance_report():
    report = {
        "timestamp": datetime.datetime.now().isoformat(),
        "compliance_checks": {
            "ssh_hardening": check_ssh_config(),
            "file_permissions": check_file_permissions(),
            "user_accounts": check_user_accounts(),
            "firewall_rules": check_firewall_rules(),
            "container_security": check_container_security()
        }
    }
    
    with open("/var/log/compliance-report.json", "w") as f:
        json.dump(report, f, indent=2)
    
    return report

def check_ssh_config():
    """Check SSH configuration compliance"""
    config_file = Path("/etc/ssh/sshd_config")
    if not config_file.exists():
        return {"status": "fail", "reason": "SSH config file not found"}
    
    content = config_file.read_text()
    checks = {
        "PermitRootLogin no": "PermitRootLogin no" in content,
        "PasswordAuthentication no": "PasswordAuthentication no" in content,
        "Protocol 2": "Protocol 2" in content
    }
    
    return {
        "status": "pass" if all(checks.values()) else "fail",
        "details": checks
    }

if __name__ == "__main__":
    report = generate_compliance_report()
    print(json.dumps(report, indent=2))
```

### Security Auditing

#### Regular Security Assessments
```bash
#!/bin/bash
# /usr/local/bin/security-audit.sh

AUDIT_LOG="/var/log/security-audit.log"
DATE=$(date)

echo "=== Security Audit Report - $DATE ===" >> $AUDIT_LOG

# Check for unauthorized users
echo "Checking for unauthorized users..." >> $AUDIT_LOG
awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd >> $AUDIT_LOG

# Check for files with weak permissions
echo "Checking for files with weak permissions..." >> $AUDIT_LOG
find /etc -type f -perm -002 -exec ls -l {} \; >> $AUDIT_LOG

# Check for running services
echo "Checking for running services..." >> $AUDIT_LOG
systemctl list-units --type=service --state=running >> $AUDIT_LOG

# Check for open ports
echo "Checking for open network ports..." >> $AUDIT_LOG
netstat -tuln >> $AUDIT_LOG

# Check Jenkins security configuration
echo "Checking Jenkins security configuration..." >> $AUDIT_LOG
curl -s -u admin:password http://localhost:8080/api/json | jq '.useSecurity' >> $AUDIT_LOG

echo "=== Audit Complete ===" >> $AUDIT_LOG
```

## Incident Response

### Security Incident Procedures

#### Incident Classification
- **Critical**: Root compromise, data breach, service disruption
- **High**: Privilege escalation, malware detection, failed security controls
- **Medium**: Policy violations, suspicious activity, configuration drift
- **Low**: Failed login attempts, minor security alerts

#### Response Workflow
```bash
#!/bin/bash
# /usr/local/bin/incident-response.sh

INCIDENT_TYPE=$1
SEVERITY=$2
DESCRIPTION="$3"

case $SEVERITY in
    "critical")
        # Immediate containment
        echo "CRITICAL INCIDENT: Implementing emergency containment"
        # Isolate affected systems
        iptables -P INPUT DROP
        iptables -P OUTPUT DROP
        # Stop all services except SSH
        systemctl stop jenkins-master-*
        systemctl stop haproxy
        ;;
    "high")
        # Enhanced monitoring and alerts
        echo "HIGH SEVERITY: Implementing enhanced monitoring"
        # Increase log verbosity
        # Alert security team
        ;;
    "medium"|"low")
        # Standard response
        echo "STANDARD RESPONSE: Logging and monitoring"
        ;;
esac

# Log incident
echo "$(date): $SEVERITY incident - $DESCRIPTION" >> /var/log/security-incidents.log

# Send notifications
mail -s "Security Incident: $SEVERITY" security@company.com < /var/log/security-incidents.log
```

### Forensic Data Collection

#### Evidence Preservation
```bash
#!/bin/bash
# /usr/local/bin/forensic-collect.sh

INCIDENT_ID=$1
EVIDENCE_DIR="/var/forensics/$INCIDENT_ID"

mkdir -p $EVIDENCE_DIR

# Collect system information
uname -a > $EVIDENCE_DIR/system_info.txt
date > $EVIDENCE_DIR/timestamp.txt
ps aux > $EVIDENCE_DIR/processes.txt
netstat -tuln > $EVIDENCE_DIR/network_connections.txt
mount > $EVIDENCE_DIR/mounted_filesystems.txt

# Collect logs
cp /var/log/auth.log $EVIDENCE_DIR/
cp /var/log/syslog $EVIDENCE_DIR/
cp /opt/jenkins/logs/*.log $EVIDENCE_DIR/
cp /var/log/fail2ban.log $EVIDENCE_DIR/

# Collect container information
docker ps -a > $EVIDENCE_DIR/containers.txt
docker images > $EVIDENCE_DIR/images.txt

# Create checksums
find $EVIDENCE_DIR -type f -exec md5sum {} \; > $EVIDENCE_DIR/checksums.md5

# Archive evidence
tar -czf /var/forensics/incident_${INCIDENT_ID}_$(date +%Y%m%d_%H%M%S).tar.gz -C /var/forensics $INCIDENT_ID
```

## Security Maintenance

### Regular Security Tasks

#### Daily Tasks
```bash
#!/bin/bash
# /usr/local/bin/daily-security-tasks.sh

# Check for security updates
apt list --upgradable | grep -i security

# Review fail2ban logs
tail -n 100 /var/log/fail2ban.log | grep "Ban\|Unban"

# Check file integrity
aide --check --quiet

# Monitor resource usage
df -h | awk '$5 > 85 {print "Disk usage warning: " $0}'
free -m | awk 'NR==2 {if ($3/$2*100 > 80) print "Memory usage warning: " $3/$2*100"%"}'
```

#### Weekly Tasks
```bash
#!/bin/bash
# /usr/local/bin/weekly-security-tasks.sh

# Update security tools
rkhunter --update
aide --update
fail2ban-client reload

# Security scan
rkhunter --check --skip-keypress --report-warnings-only
lynis audit system

# Vulnerability assessment
if command -v trivy &> /dev/null; then
    docker images --format "{{.Repository}}:{{.Tag}}" | xargs -I {} trivy image {}
fi

# Generate security report
python3 /usr/local/bin/generate-security-report.py
```

#### Monthly Tasks
```bash
#!/bin/bash
# /usr/local/bin/monthly-security-tasks.sh

# Comprehensive security audit
/usr/local/bin/security-audit.sh

# Certificate expiry check
openssl x509 -in /etc/ssl/certs/jenkins.crt -text -noout | grep "Not After"

# User access review
awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | \
    while read user; do
        echo "User: $user, Last login: $(lastlog -u $user | tail -1)"
    done

# Configuration compliance check
python3 /usr/local/bin/compliance-report.py
```

### Security Configuration Management

#### Continuous Compliance Monitoring
```yaml
# Ansible playbook for security compliance
- name: Security compliance check
  hosts: all
  tasks:
    - name: Verify SSH configuration
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: "{{ item.regexp }}"
        line: "{{ item.line }}"
        state: present
      loop:
        - { regexp: "^PermitRootLogin", line: "PermitRootLogin no" }
        - { regexp: "^PasswordAuthentication", line: "PasswordAuthentication no" }
      register: ssh_changes
      
    - name: Restart SSH if configuration changed
      service:
        name: ssh
        state: restarted
      when: ssh_changes.changed
      
    - name: Verify file permissions
      file:
        path: "{{ item.path }}"
        mode: "{{ item.mode }}"
        owner: "{{ item.owner }}"
        group: "{{ item.group }}"
      loop:
        - { path: "/etc/passwd", mode: "0644", owner: "root", group: "root" }
        - { path: "/etc/shadow", mode: "0640", owner: "root", group: "shadow" }
```

### Best Practices

#### Security Checklist
1. **Regular Updates**: Keep all systems and software up to date
2. **Access Control**: Implement least privilege principle
3. **Monitoring**: Continuous security monitoring and alerting
4. **Backups**: Regular backup of security configurations and logs
5. **Incident Response**: Maintain and test incident response procedures
6. **Training**: Regular security awareness training for team members
7. **Documentation**: Keep security documentation up to date
8. **Testing**: Regular security testing and vulnerability assessments

#### Security Metrics
- Mean Time to Detection (MTTD): < 5 minutes
- Mean Time to Response (MTTR): < 30 minutes
- Security Update Compliance: > 95%
- Failed Login Attempt Rate: < 1%
- Critical Vulnerability Resolution: < 24 hours

## Emergency Security Operations

### Emergency Security Contacts

#### Security Team
- **Security Lead**: security-lead@company.com / +1-555-0124 (24/7)
- **CISO**: ciso@company.com / +1-555-0125
- **Security Operations**: secops@company.com / +1-555-0126 (24/7)
- **Incident Response**: ir@company.com / +1-555-0127 (24/7)

#### External Contacts
- **Law Enforcement**: +1-911 (emergencies only)
- **Cyber Insurance**: +1-555-0200
- **Legal Team**: legal@company.com / +1-555-0130

## Incident Response

### Incident Classification

| Severity | Description | Response Time | Escalation |
|----------|-------------|---------------|------------|
| **Critical** | Active breach, data exfiltration, ransomware | 15 minutes | CISO, CEO |
| **High** | Unauthorized access, malware detection, DoS | 30 minutes | Security Lead |
| **Medium** | Failed login attempts, policy violations | 2 hours | Security Team |
| **Low** | Suspicious activity, configuration drift | 24 hours | On-call Engineer |

### Emergency Response Procedures

#### 1. Immediate Actions (0-15 minutes)
- Assess and classify the incident severity
- Notify appropriate security team members
- Isolate affected systems if necessary
- Begin evidence collection

#### 2. Containment Phase (15-30 minutes)
- Implement containment measures
- Stop ongoing attack or breach
- Preserve system state for forensics
- Coordinate with stakeholders

#### 3. Investigation Phase (30+ minutes)
- Conduct detailed forensic analysis
- Determine attack vectors and impact
- Document findings and timeline
- Coordinate recovery efforts

#### 4. Recovery Phase
- Restore systems from known good backups
- Implement additional security measures
- Verify system integrity
- Resume normal operations

#### 5. Post-Incident Review
- Conduct lessons learned session
- Update security procedures
- Implement preventive measures
- Report to leadership and authorities

### Emergency Security Commands

```bash
# Emergency system isolation
ansible all -i ansible/inventories/production/hosts.yml -m service -a "name=jenkins-master state=stopped"

# Security scan all systems
ansible-playbook ansible/site.yml --tags security -e emergency_scan=true

# Lock down access
ansible all -i ansible/inventories/production/hosts.yml -m iptables -a "chain=INPUT jump=DROP"

# Generate security report
/usr/local/bin/jenkins-security-scan.sh --emergency-report
```
