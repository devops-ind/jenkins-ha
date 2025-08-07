# Disaster Recovery Runbook

## Overview

This runbook provides comprehensive disaster recovery (DR) procedures for the Jenkins HA infrastructure. Use these procedures to recover from various failure scenarios and ensure business continuity.

## Emergency Contact Information

### Immediate Response Team
- **Infrastructure Lead**: +1-555-0123 (24/7)
- **Security Lead**: +1-555-0124 (24/7)
- **DevOps Manager**: +1-555-0125
- **Emergency Escalation**: +1-555-0911

### Communication Channels
- **Incident Channel**: #incident-response (Slack)
- **Status Page**: https://status.company.com
- **Emergency Email**: emergency@company.com

## Disaster Scenarios and Response

### Scenario 1: Single Jenkins Master Failure

**Detection:**
- Keepalived failover alerts
- Jenkins master health check failures
- Load balancer backend failures

**Response Time:** < 5 minutes (automatic failover)

**Recovery Procedure:**
```bash
# 1. Verify automatic failover occurred
curl -f http://{{ jenkins_vip }}:8080/login

# 2. Check which master is active
ansible load_balancers -i ansible/inventories/production/hosts.yml \
  -m shell -a "cat /var/log/keepalived.log | tail -20"

# 3. Investigate failed master
ansible jenkins_masters[0] -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl status jenkins-master"

# 4. Restart failed master if needed
ansible jenkins_masters[0] -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl restart jenkins-master"

# 5. Verify both masters are healthy
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker ps | grep jenkins-master"
```

**Validation:**
- [ ] Jenkins accessible via VIP
- [ ] Both masters showing healthy in monitoring
- [ ] Build jobs can be executed
- [ ] No data loss confirmed

### Scenario 2: Complete Jenkins Master Cluster Failure

**Detection:**
- Total loss of Jenkins UI access
- All master health checks failing
- Critical alerts from monitoring

**Response Time:** < 30 minutes

**Recovery Procedure:**
```bash
# 1. Execute automated DR script
cd /path/to/jenkins-ha
./scripts/disaster-recovery.sh full-restore

# 2. If automated restore fails, manual procedure:

# 2a. Stop all Jenkins services
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl stop jenkins-master"

# 2b. Restore from latest backup
./scripts/backup.sh restore-latest

# 2c. Verify shared storage integrity
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "ls -la /opt/jenkins_home/"

# 2d. Start Jenkins masters (primary first)
ansible jenkins_masters[0] -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl start jenkins-master"

# Wait 2 minutes for primary to fully start
sleep 120

# 2e. Start secondary masters
ansible jenkins_masters[1:] -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl start jenkins-master"

# 2f. Verify cluster formation
curl -f http://{{ jenkins_vip }}:8080/login
```

**Validation:**
- [ ] Jenkins UI accessible
- [ ] All builds/jobs restored
- [ ] Agent connectivity restored
- [ ] User authentication working
- [ ] Plugin functionality verified

### Scenario 3: Shared Storage Failure

**Detection:**
- Jenkins masters unable to start
- File system mount errors
- Backup failures

**Response Time:** < 60 minutes

**Recovery Procedure:**
```bash
# 1. Assess storage failure scope
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "df -h | grep jenkins_home"

# 2. If NFS server failed, restart NFS services
ansible nfs_servers -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl restart nfs-server"

# 3. If storage corruption, restore from backup
# 3a. Stop all Jenkins services
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl stop jenkins-master"

# 3b. Unmount corrupted storage
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "umount /opt/jenkins_home"

# 3c. Restore shared storage from backup
./scripts/backup.sh restore-shared-storage

# 3d. Remount storage
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "mount -a"

# 3e. Restart Jenkins services
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl start jenkins-master"
```

**Validation:**
- [ ] Shared storage mounted successfully
- [ ] Jenkins data integrity verified
- [ ] All Jenkins instances accessible
- [ ] Build history preserved

### Scenario 4: Complete Infrastructure Failure

**Detection:**
- Multiple datacenter/region failure
- Complete loss of primary site
- Network infrastructure failure

**Response Time:** < 4 hours (RTO requirement)

**Recovery Procedure:**
```bash
# 1. Activate DR site infrastructure
# Deploy to DR environment
ansible-playbook -i ansible/inventories/dr/hosts.yml \
  ansible/site.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_dr

# 2. Restore from offsite backups
./scripts/disaster-recovery.sh activate-dr-site

# 3. Update DNS to point to DR site
# Update DNS records to point to DR VIP
# TTL should be 300 seconds for quick failover

# 4. Verify full functionality in DR site
curl -f http://{{ dr_jenkins_vip }}:8080/login

# 5. Notify stakeholders of DR activation
./scripts/notify-dr-activation.sh
```

**Validation:**
- [ ] DR site fully operational
- [ ] DNS failover completed
- [ ] User access restored
- [ ] Critical builds functioning
- [ ] Data loss < RPO (4 hours)

### Scenario 5: Security Incident/Compromise

**Detection:**
- Security alerts from monitoring
- Unauthorized access detected
- Malware/intrusion indicators

**Response Time:** < 15 minutes

**Response Procedure:**
```bash
# 1. Immediate isolation
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "iptables -A INPUT -j DROP && iptables -A OUTPUT -j DROP"

# 2. Preserve evidence
./scripts/incident-response.sh preserve-evidence

# 3. Execute security incident DR
./scripts/disaster-recovery.sh security-incident

# 4. Restore from known-good backup (pre-incident)
./scripts/backup.sh restore-point-in-time --date="2024-01-01 12:00:00"

# 5. Security validation and hardening
ansible-playbook ansible/site.yml --tags security-hardening

# 6. Network re-isolation and controlled restart
# Restore network access gradually after security verification
```

**Validation:**
- [ ] Incident contained and isolated
- [ ] Evidence preserved for investigation
- [ ] Clean environment restored
- [ ] Security controls verified
- [ ] Incident documented

## Backup Verification and Restoration

### Daily Backup Verification
```bash
# Automated verification (runs daily via cron)
./scripts/backup.sh verify-daily

# Manual verification
./scripts/backup.sh verify --date=$(date -d "yesterday" +%Y-%m-%d)
```

### Restoration Testing
```bash
# Monthly DR test (automated)
./scripts/disaster-recovery.sh test-restore-monthly

# Quarterly full DR drill
./scripts/disaster-recovery.sh full-dr-drill
```

### Point-in-Time Recovery
```bash
# Restore to specific timestamp
./scripts/backup.sh restore-point-in-time \
  --date="2024-01-15 14:30:00" \
  --location="/backup/archive/2024-01-15"

# Verify restoration
./scripts/backup.sh verify-restoration --timestamp="2024-01-15 14:30:00"
```

## Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)

### Service Level Objectives

| Failure Scenario | RTO Target | RPO Target | Actual Performance |
|------------------|------------|------------|-------------------|
| Single Master Failure | 5 minutes | 0 minutes | 2 minutes |
| Cluster Failure | 30 minutes | 15 minutes | 25 minutes |
| Storage Failure | 60 minutes | 1 hour | 45 minutes |
| Site Failure | 4 hours | 4 hours | 3.5 hours |
| Security Incident | 2 hours | 1 hour | 1.5 hours |

### Monitoring and Alerting

```bash
# RTO/RPO monitoring queries (Prometheus)
# Alert if restore time exceeds RTO
rate(jenkins_recovery_duration_seconds[5m]) > {{ rto_threshold }}

# Alert if data loss exceeds RPO
jenkins_backup_age_seconds > {{ rpo_threshold }}
```

## Communication Procedures

### Incident Declaration
```bash
# Declare incident (automated)
./scripts/incident-response.sh declare --severity=critical \
  --description="Jenkins infrastructure failure" \
  --impact="Build pipeline unavailable"

# Manual incident declaration
curl -X POST https://status.company.com/api/incidents \
  -H "Authorization: Bearer $STATUS_API_TOKEN" \
  -d '{"name":"Jenkins Infrastructure Failure","status":"investigating"}'
```

### Stakeholder Notification
```bash
# Automated notifications
./scripts/notify-stakeholders.sh \
  --type=outage \
  --severity=critical \
  --eta="30 minutes"

# Manual notification templates
cat templates/incident-notification-email.txt
cat templates/status-page-update.txt
```

### Recovery Status Updates
```bash
# Update status during recovery
./scripts/update-incident-status.sh \
  --status="in-progress" \
  --message="Initiating disaster recovery procedures" \
  --eta="25 minutes remaining"
```

## Post-Incident Procedures

### Post-Incident Review (PIR)
1. **Incident Timeline Documentation**
   - Document exact failure timeline
   - Record all recovery actions taken
   - Note any deviations from runbook

2. **Root Cause Analysis**
   - Technical root cause identification
   - Contributing factors analysis
   - Process and procedural gaps

3. **Improvement Actions**
   - Technical improvements needed
   - Process enhancements
   - Monitoring and alerting improvements
   - Training requirements

### Recovery Validation
```bash
# Full system validation post-recovery
./scripts/post-recovery-validation.sh

# Performance baseline restoration
./scripts/performance-validation.sh

# Security posture verification
./scripts/security-validation.sh
```

### Documentation Updates
- Update runbooks with lessons learned
- Modify recovery procedures if needed
- Update contact information
- Revise RTO/RPO targets if necessary

## DR Infrastructure Management

### DR Site Maintenance
```bash
# Monthly DR infrastructure update
ansible-playbook -i ansible/inventories/dr/hosts.yml \
  ansible/maintenance.yml \
  --tags dr-update

# Quarterly DR site refresh
./scripts/dr-site-refresh.sh
```

### Backup Infrastructure
```bash
# Backup system health check
./scripts/backup.sh health-check

# Backup storage capacity monitoring
./scripts/backup.sh capacity-report

# Backup retention policy enforcement
./scripts/backup.sh enforce-retention
```

## Testing and Validation Schedule

### Monthly Testing
- [ ] Automated backup restoration test
- [ ] Single master failover test
- [ ] Monitoring and alerting verification
- [ ] DR site connectivity test

### Quarterly Testing
- [ ] Full disaster recovery drill
- [ ] Complete infrastructure restoration
- [ ] Cross-team communication exercise
- [ ] RTO/RPO measurement validation

### Annual Testing
- [ ] Complete site failover test
- [ ] Security incident response drill
- [ ] Full PIR and procedure review
- [ ] DR documentation audit

## Troubleshooting Common DR Issues

### Issue: Backup Restoration Fails
```bash
# Check backup integrity
./scripts/backup.sh check-integrity --backup-id=$BACKUP_ID

# Verify backup storage accessibility
./scripts/backup.sh test-connectivity

# Alternative restore method
./scripts/backup.sh restore-alternative --method=rsync
```

### Issue: Network Connectivity Problems
```bash
# Network diagnostics
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "ping -c 4 {{ jenkins_vip }}"

# DNS resolution check
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "nslookup {{ jenkins_hostname }}"

# Firewall verification
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "iptables -L | grep -E '8080|443|22'"
```

### Issue: Authentication Failures Post-Recovery
```bash
# Verify LDAP connectivity
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "ldapsearch -x -H {{ ldap_server }}"

# Check vault secrets
ansible-vault view ansible/inventories/production/group_vars/all/vault.yml

# Reset admin credentials if needed
./scripts/reset-admin-credentials.sh
```

---

**Document Version:** 2.0
**Last Updated:** {{ ansible_date_time.date }}
**Next Review:** Quarterly
**Owner:** Infrastructure Team
**Emergency Contact:** +1-555-0123