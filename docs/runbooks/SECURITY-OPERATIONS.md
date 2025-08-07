# Security Operations Runbook

## Overview

This runbook provides comprehensive security operations procedures for the Jenkins HA infrastructure, including incident response, security monitoring, certificate management, and compliance operations.

## Emergency Security Contacts

### Security Team
- **Security Lead**: security-lead@company.com / +1-555-0124 (24/7)
- **CISO**: ciso@company.com / +1-555-0125
- **Security Operations**: secops@company.com / +1-555-0126 (24/7)
- **Incident Response**: ir@company.com / +1-555-0127 (24/7)

### External Contacts
- **Law Enforcement**: +1-911 (emergencies only)
- **Cyber Insurance**: +1-555-0200
- **Legal Team**: legal@company.com / +1-555-0130

## Security Incident Response

### Incident Classification

| Severity | Description | Response Time | Escalation |
|----------|-------------|---------------|------------|
| **Critical** | Active breach, data exfiltration, ransomware | 15 minutes | CISO, CEO |
| **High** | Unauthorized access, malware detection, DoS | 30 minutes | Security Lead |
| **Medium** | Failed login attempts, policy violations | 2 hours | Security Team |
| **Low** | Suspicious activity, configuration drift | 24 hours | On-call Engineer |

### Critical Security Incident Response

**Immediate Response (0-15 minutes):**
```bash
# 1. IMMEDIATE ISOLATION
# Isolate affected systems
ansible {{ affected_hosts }} -i ansible/inventories/production/hosts.yml \
  -m shell -a "iptables -I INPUT 1 -j DROP && iptables -I OUTPUT 1 -j DROP"

# 2. DECLARE INCIDENT
./scripts/incident-response.sh declare-security-incident \
  --severity=critical \
  --type="data-breach" \
  --description="Unauthorized access detected on Jenkins infrastructure"

# 3. PRESERVE EVIDENCE
./scripts/security-forensics.sh preserve-evidence \
  --hosts="{{ affected_hosts }}" \
  --incident-id="{{ incident_id }}"

# 4. NOTIFY STAKEHOLDERS
./scripts/notify-security-incident.sh \
  --severity=critical \
  --estimated-impact="Jenkins infrastructure compromised"
```

**Investigation Phase (15-60 minutes):**
```bash
# 1. COLLECT FORENSIC DATA
./scripts/security-forensics.sh collect-logs \
  --timeframe="24h" \
  --hosts="all" \
  --incident-id="{{ incident_id }}"

# 2. ANALYZE ATTACK VECTORS
./scripts/security-analysis.sh analyze-intrusion \
  --incident-id="{{ incident_id }}" \
  --output-format="json"

# 3. ASSESS IMPACT
./scripts/security-impact.sh assess \
  --incident-id="{{ incident_id }}" \
  --check-data-integrity \
  --check-system-integrity

# 4. DETERMINE IOCs (Indicators of Compromise)
./scripts/security-analysis.sh extract-iocs \
  --incident-id="{{ incident_id }}" \
  --format="stix"
```

**Containment Phase (1-4 hours):**
```bash
# 1. IMPLEMENT ADDITIONAL BLOCKING
./scripts/security-containment.sh block-iocs \
  --ioc-file="/tmp/incident-{{ incident_id }}-iocs.json"

# 2. PATCH VULNERABILITIES
ansible-playbook ansible/security-emergency-patch.yml \
  --tags="critical-patches" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# 3. ROTATE CREDENTIALS
./scripts/security-credentials.sh rotate-all-emergency \
  --incident-id="{{ incident_id }}"

# 4. HARDEN SYSTEMS
ansible-playbook ansible/site.yml \
  --tags="security-hardening-emergency"
```

**Recovery Phase (4-24 hours):**
```bash
# 1. CLEAN SYSTEM RESTORATION
./scripts/disaster-recovery.sh security-clean-restore \
  --backup-date="pre-incident" \
  --verify-integrity

# 2. ENHANCED MONITORING
./scripts/security-monitoring.sh enable-enhanced \
  --duration="72h" \
  --incident-id="{{ incident_id }}"

# 3. CONTROLLED SYSTEM RESTART
./scripts/security-recovery.sh controlled-restart \
  --verify-at-each-step \
  --incident-id="{{ incident_id }}"
```

### High Priority Security Incident Response

**Detection and Initial Response:**
```bash
# 1. VERIFY THREAT
./scripts/security-verification.sh verify-threat \
  --alert-id="{{ alert_id }}" \
  --confidence-threshold=0.8

# 2. CONTAIN IF VERIFIED
if [ $threat_verified = true ]; then
  ./scripts/security-containment.sh isolate-affected \
    --hosts="{{ suspicious_hosts }}" \
    --preserve-evidence
fi

# 3. INVESTIGATE SCOPE
./scripts/security-investigation.sh scope-analysis \
  --initial-host="{{ affected_host }}" \
  --timeframe="12h"
```

### Security Monitoring and Detection

**Real-time Security Monitoring:**
```bash
# Monitor security events (runs continuously)
./scripts/security-monitoring.sh real-time \
  --config="/etc/security-monitoring/config.yml"

# Check security dashboard
curl -s "http://{{ grafana_hostname }}:3000/api/dashboards/uid/security-overview" \
  -H "Authorization: Bearer {{ grafana_api_key }}"

# Verify SIEM connectivity
./scripts/security-monitoring.sh test-siem-connectivity
```

**Failed Login Analysis:**
```bash
# Analyze failed login patterns
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "journalctl -u ssh --since='1 hour ago' | grep 'Failed password'"

# Check Jenkins authentication failures
curl -s "http://{{ jenkins_vip }}:8080/log/all" | grep -i "authentication failed"

# Block suspicious IPs
./scripts/security-blocking.sh analyze-and-block \
  --threshold=10 \
  --timeframe="1h"
```

**Vulnerability Scanning:**
```bash
# Daily vulnerability scan
./scripts/security-scanning.sh vulnerability-scan \
  --target="jenkins-infrastructure" \
  --type="authenticated"

# Container vulnerability scanning
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy image jenkins-ha:latest"

# Network security scan
nmap -sS -O {{ jenkins_network_range }}
```

## Certificate Management

### SSL Certificate Lifecycle

**Certificate Monitoring:**
```bash
# Check certificate expiration (automated daily)
./scripts/ssl-management.sh check-expiration \
  --warning-days=30 \
  --critical-days=7

# Manual certificate check
openssl x509 -in /etc/ssl/certs/jenkins.crt -text -noout | grep -A 2 "Validity"

# Certificate chain validation
openssl verify -CAfile /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/jenkins.crt
```

**Certificate Renewal (Let's Encrypt):**
```bash
# Automated renewal (runs via cron)
ansible-playbook ansible/site.yml \
  --tags="ssl-certificate-renewal" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Manual renewal
./scripts/ssl-management.sh renew-certificates \
  --domain="jenkins.company.com" \
  --challenge="http-01"

# Emergency certificate renewal
./scripts/ssl-management.sh emergency-renewal \
  --domain="jenkins.company.com" \
  --bypass-rate-limits
```

**Certificate Rotation:**
```bash
# Rotate all certificates
./scripts/ssl-management.sh rotate-all \
  --generate-new-csr \
  --update-services

# Verify certificate deployment
./scripts/ssl-management.sh verify-deployment \
  --test-https-connectivity \
  --validate-chain
```

### Certificate Emergency Procedures

**Certificate Compromise:**
```bash
# 1. IMMEDIATE REVOCATION
./scripts/ssl-management.sh revoke-certificate \
  --certificate="/etc/ssl/certs/jenkins.crt" \
  --reason="key-compromise"

# 2. GENERATE NEW CERTIFICATES
./scripts/ssl-management.sh generate-emergency-cert \
  --domain="jenkins.company.com" \
  --validity-days=90

# 3. DEPLOY NEW CERTIFICATES
ansible-playbook ansible/site.yml \
  --tags="ssl-emergency-deployment"

# 4. VERIFY NEW DEPLOYMENT
./scripts/ssl-management.sh verify-emergency-deployment
```

## Access Control Management

### User Access Management

**User Provisioning:**
```bash
# Add new user with proper RBAC
./scripts/user-management.sh add-user \
  --username="john.doe" \
  --email="john.doe@company.com" \
  --role="developer" \
  --groups="development,ci-cd"

# Grant temporary privileged access
./scripts/user-management.sh grant-temporary-access \
  --username="john.doe" \
  --role="admin" \
  --duration="4h" \
  --justification="emergency deployment"
```

**User Deprovisioning:**
```bash
# Remove user access (immediate)
./scripts/user-management.sh remove-user \
  --username="departed.employee" \
  --revoke-certificates \
  --disable-accounts

# Disable user temporarily
./scripts/user-management.sh disable-user \
  --username="suspended.user" \
  --duration="30d"
```

**Access Review:**
```bash
# Monthly access review
./scripts/user-management.sh access-review \
  --format="csv" \
  --include-last-login \
  --include-permissions

# Identify inactive accounts
./scripts/user-management.sh find-inactive \
  --threshold="90d" \
  --action="report"
```

### Service Account Management

**Service Account Security:**
```bash
# Rotate service account credentials
./scripts/service-accounts.sh rotate-credentials \
  --account="jenkins-backup" \
  --update-vault

# Audit service account usage
./scripts/service-accounts.sh audit-usage \
  --timeframe="30d" \
  --format="json"

# Review service account permissions
./scripts/service-accounts.sh permission-review \
  --principle-of-least-privilege
```

## Compliance and Auditing

### Security Compliance Checks

**CIS Benchmark Compliance:**
```bash
# Run CIS benchmark scan
./scripts/compliance.sh cis-benchmark \
  --profile="level-2" \
  --format="json" \
  --output="/tmp/cis-report.json"

# Remediate CIS findings
ansible-playbook ansible/compliance-remediation.yml \
  --tags="cis-remediation"
```

**NIST Framework Compliance:**
```bash
# NIST compliance assessment
./scripts/compliance.sh nist-assessment \
  --framework="800-53" \
  --controls="AC,AU,SC,SI"

# Generate compliance report
./scripts/compliance.sh generate-report \
  --framework="nist" \
  --format="pdf" \
  --recipient="compliance@company.com"
```

### Security Auditing

**Access Audit:**
```bash
# User access audit
./scripts/security-audit.sh access-audit \
  --timeframe="30d" \
  --include-failed-attempts \
  --export-format="csv"

# Privileged access audit
./scripts/security-audit.sh privileged-access-audit \
  --role="admin" \
  --include-service-accounts
```

**Configuration Audit:**
```bash
# Security configuration audit
ansible-playbook ansible/security-audit.yml \
  --tags="configuration-audit" \
  --check

# File integrity audit
./scripts/security-audit.sh file-integrity \
  --critical-files \
  --generate-baseline
```

**Network Security Audit:**
```bash
# Network segmentation audit
./scripts/security-audit.sh network-segmentation \
  --test-isolation \
  --verify-firewall-rules

# Port security audit
nmap -sS -O {{ jenkins_network_range }} > /tmp/network-audit.txt
./scripts/security-audit.sh analyze-port-scan \
  --input="/tmp/network-audit.txt"
```

## Security Hardening

### System Hardening

**Automated Hardening:**
```bash
# Apply security hardening
ansible-playbook ansible/site.yml \
  --tags="security-hardening" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Verify hardening implementation
./scripts/security-verification.sh verify-hardening \
  --cis-compliance \
  --security-controls
```

**Container Security Hardening:**
```bash
# Harden Docker daemon
ansible docker_hosts -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl edit docker --full"

# Container runtime security
./scripts/container-security.sh harden-runtime \
  --enable-userns \
  --enable-seccomp \
  --enable-apparmor
```

### Network Security

**Firewall Management:**
```bash
# Update firewall rules
ansible-playbook ansible/firewall.yml \
  --tags="firewall-update"

# Verify firewall configuration
./scripts/network-security.sh verify-firewall \
  --test-connectivity \
  --validate-rules

# Emergency firewall lockdown
./scripts/network-security.sh emergency-lockdown \
  --preserve-ssh \
  --incident-id="{{ incident_id }}"
```

**Network Monitoring:**
```bash
# Enable network monitoring
./scripts/network-security.sh enable-monitoring \
  --capture-suspicious \
  --alert-threshold="high"

# Analyze network traffic
./scripts/network-security.sh traffic-analysis \
  --timeframe="1h" \
  --detect-anomalies
```

## Backup Security

### Backup Encryption

**Encrypt Existing Backups:**
```bash
# Encrypt backup repository
./scripts/backup-security.sh encrypt-repository \
  --repository="/backup/jenkins" \
  --encryption="aes-256"

# Verify backup encryption
./scripts/backup-security.sh verify-encryption \
  --repository="/backup/jenkins" \
  --test-restore
```

**Backup Access Control:**
```bash
# Restrict backup access
./scripts/backup-security.sh restrict-access \
  --repository="/backup/jenkins" \
  --allowed-users="backup,admin"

# Audit backup access
./scripts/backup-security.sh audit-access \
  --timeframe="30d" \
  --repository="all"
```

## Security Training and Awareness

### Security Awareness

**Phishing Simulation:**
```bash
# Run phishing awareness test
./scripts/security-training.sh phishing-simulation \
  --target-group="jenkins-admins" \
  --template="jenkins-update"

# Security training reminder
./scripts/security-training.sh send-reminder \
  --topic="password-security" \
  --target="all-users"
```

### Incident Response Training

**Tabletop Exercises:**
```bash
# Schedule security incident simulation
./scripts/security-training.sh schedule-tabletop \
  --scenario="ransomware-attack" \
  --participants="ops-team,security-team"

# Conduct red team exercise
./scripts/security-training.sh red-team-exercise \
  --scope="jenkins-infrastructure" \
  --duration="4h"
```

## Security Metrics and Reporting

### Security Metrics Collection

**Key Security Metrics:**
```bash
# Collect security metrics
./scripts/security-metrics.sh collect \
  --metrics="failed-logins,vulnerabilities,incidents" \
  --timeframe="30d"

# Generate security dashboard
./scripts/security-metrics.sh update-dashboard \
  --dashboard="security-overview" \
  --auto-refresh="5m"
```

**Security Reporting:**
```bash
# Monthly security report
./scripts/security-reporting.sh monthly-report \
  --include-metrics \
  --include-incidents \
  --recipient="ciso@company.com"

# Executive security summary
./scripts/security-reporting.sh executive-summary \
  --format="pptx" \
  --highlight-trends
```

## Emergency Procedures

### Security Emergency Contacts
- **After Hours Security**: +1-555-0124
- **Emergency Response**: +1-555-0911
- **Cyber Insurance**: policy-cyber@company.com

### Security Emergency Checklist
- [ ] Incident declared and stakeholders notified
- [ ] Affected systems isolated
- [ ] Evidence preserved
- [ ] Forensic analysis initiated
- [ ] Legal team notified (if required)
- [ ] Regulatory reporting (if required)
- [ ] Customer notification (if required)
- [ ] Recovery plan activated
- [ ] Post-incident review scheduled

---

**Document Version:** 2.0
**Last Updated:** {{ ansible_date_time.date }}
**Next Review:** Quarterly
**Owner:** Security Team
**Emergency Contact:** +1-555-0124