# Production Deployment Runbook

## Overview

This runbook provides step-by-step procedures for deploying the Jenkins HA infrastructure to production environments. Follow these procedures exactly to ensure a successful, secure deployment.

## Prerequisites Checklist

### Infrastructure Requirements
- [ ] All target hosts are provisioned and accessible via SSH
- [ ] Control node has Ansible 2.14+ installed
- [ ] Python 3.9+ with required packages (pip install -r requirements.txt)
- [ ] Network connectivity between all components
- [ ] DNS resolution configured (or IP-based inventory)
- [ ] NTP synchronization across all nodes

### Access Requirements
- [ ] SSH key-based authentication configured
- [ ] Sudo/root access on all target hosts
- [ ] Vault password file available
- [ ] SSL certificates ready (if using custom certs)

### Environment Validation
```bash
# Verify Ansible connectivity
ansible all -i ansible/inventories/production/hosts.yml -m ping

# Check vault password file
ls -la environments/vault-passwords/.vault_pass_production

# Validate inventory syntax
ansible-inventory -i ansible/inventories/production/hosts.yml --list
```

## Pre-Deployment Phase

### 1. Environment Preparation

```bash
# Navigate to project directory
cd /path/to/jenkins-ha

# Activate Python virtual environment
source ansible-env/bin/activate

# Verify Ansible collections
ansible-galaxy collection list | grep -E "(community.docker|community.general|ansible.posix)"
```

### 2. Configuration Validation

```bash
# Syntax check for all playbooks
ansible-playbook ansible/site.yml --syntax-check

# Check inventory configuration
ansible-inventory -i ansible/inventories/production/hosts.yml --graph

# Validate vault files
ansible-vault view ansible/inventories/production/group_vars/all/vault.yml \
  --vault-password-file=environments/vault-passwords/.vault_pass_production
```

### 3. Network and Security Validation

```bash
# Test SSH connectivity to all hosts
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "hostname && date"

# Check firewall status
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl status firewalld || systemctl status ufw"

# Verify shared storage accessibility (if using NFS)
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "showmount -e {{ nfs_server }}"
```

## Deployment Phase

### Phase 1: Infrastructure Bootstrap (30-45 minutes)

```bash
# Deploy common infrastructure components
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags "bootstrap,common,security" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Verify bootstrap completion
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker --version && systemctl is-active docker"
```

**Expected Outcomes:**
- Docker/Podman installed and running
- Basic security hardening applied
- Firewall rules configured
- User accounts and SSH keys configured

### Phase 2: Shared Storage Setup (15-20 minutes)

```bash
# Deploy shared storage configuration
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags "shared-storage" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Verify shared storage mounts
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "df -h | grep jenkins_home"
```

**Expected Outcomes:**
- NFS/GlusterFS client configured
- Jenkins home directory mounted
- Proper permissions set on shared directories

### Phase 3: Harbor Registry Deployment (20-30 minutes)

```bash
# Deploy Harbor registry
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags "harbor" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Verify Harbor accessibility
curl -k https://{{ harbor_hostname }}/api/v2.0/systeminfo
```

**Expected Outcomes:**
- Harbor registry running and accessible
- SSL certificates configured
- Authentication configured (LDAP/local)
- Default projects created

### Phase 4: Jenkins Image Building (20-30 minutes)

```bash
# Build custom Jenkins images
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags "jenkins-images" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Verify images built and pushed
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker images | grep jenkins-ha"
```

**Expected Outcomes:**
- Custom Jenkins master and agent images built
- Images pushed to Harbor registry
- Vulnerability scans completed

### Phase 5: Load Balancer Configuration (15-20 minutes)

```bash
# Deploy load balancer components
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags "load-balancer,high-availability" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Verify VIP configuration
ansible load_balancers -i ansible/inventories/production/hosts.yml \
  -m shell -a "ip addr show | grep {{ jenkins_vip }}"
```

**Expected Outcomes:**
- HAProxy configured and running
- Keepalived managing VIP
- Health checks configured

### Phase 6: Jenkins Masters Deployment (45-60 minutes)

```bash
# Deploy Jenkins masters (serial deployment for HA)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags "jenkins" \
  --limit "jenkins_masters" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Verify Jenkins master accessibility
curl -I http://{{ jenkins_vip }}:8080/login
```

**Expected Outcomes:**
- Jenkins masters deployed and running
- JCasC configuration applied
- Admin user created
- Security realm configured

### Phase 7: Jenkins Agents Deployment (30-45 minutes)

```bash
# Deploy Jenkins agents
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags "jenkins" \
  --limit "jenkins_agents" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Verify agent connectivity
# Check Jenkins UI: Manage Jenkins -> Manage Nodes
```

**Expected Outcomes:**
- Jenkins agents deployed and registered
- Agent containers running
- Build capacity available

### Phase 8: Monitoring Stack (30-40 minutes)

```bash
# Deploy monitoring infrastructure
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags "monitoring" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Verify monitoring stack
curl -I http://{{ grafana_hostname }}:3000
curl -I http://{{ prometheus_hostname }}:9090
```

**Expected Outcomes:**
- Prometheus collecting metrics
- Grafana dashboards available
- AlertManager configured
- Custom Jenkins metrics flowing

### Phase 9: Backup Configuration (15-20 minutes)

```bash
# Configure backup system
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags "backup" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Test backup functionality
./scripts/backup.sh test
```

**Expected Outcomes:**
- Backup schedules configured
- Backup storage accessible
- Test backup successful

## Post-Deployment Validation

### 1. Functional Testing

```bash
# Jenkins accessibility test
curl -f http://{{ jenkins_vip }}:8080/login

# Load balancer stats
curl -f http://{{ jenkins_vip }}:8404/stats

# SSL certificate validation
openssl s_client -connect {{ jenkins_hostname }}:443 -servername {{ jenkins_hostname }}

# Container health check
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "docker ps --filter health=unhealthy"
```

### 2. High Availability Testing

```bash
# Test VIP failover
ansible jenkins_masters[0] -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl stop keepalived"

# Verify VIP migration
ping {{ jenkins_vip }}

# Test Jenkins master failover
ansible jenkins_masters[0] -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl stop jenkins-master"

# Verify Jenkins accessibility continues
curl -f http://{{ jenkins_vip }}:8080/login
```

### 3. Security Validation

```bash
# Verify security hardening
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl is-active fail2ban"

# Check SSL configuration
nmap --script ssl-enum-ciphers -p 443 {{ jenkins_hostname }}

# Verify file integrity monitoring
ansible all -i ansible/inventories/production/hosts.yml \
  -m shell -a "aide --check"
```

### 4. Monitoring Validation

```bash
# Check Prometheus targets
curl -s http://{{ prometheus_hostname }}:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'

# Verify Grafana dashboards
curl -f http://{{ grafana_hostname }}:3000/api/health

# Test alerting
# Trigger a test alert and verify notification delivery
```

### 5. Backup Validation

```bash
# Run full backup test
./scripts/backup.sh full

# Verify backup integrity
./scripts/backup.sh verify

# Test restore procedure (in staging environment)
./scripts/disaster-recovery.sh test-restore
```

## Common Deployment Issues

### Issue: SSH Connection Failures
**Symptoms:** `UNREACHABLE` errors during Ansible execution
**Resolution:**
```bash
# Verify SSH connectivity
ssh -i ~/.ssh/ansible_key user@target-host

# Check SSH agent
ssh-add -l

# Verify inventory configuration
ansible-inventory -i ansible/inventories/production/hosts.yml --list
```

### Issue: Docker Service Failures
**Symptoms:** Containers fail to start
**Resolution:**
```bash
# Check Docker daemon status
ansible all -i ansible/inventories/production/hosts.yml -m shell -a "systemctl status docker"

# Check Docker logs
ansible all -i ansible/inventories/production/hosts.yml -m shell -a "journalctl -u docker --no-pager -l"

# Restart Docker service
ansible all -i ansible/inventories/production/hosts.yml -m shell -a "systemctl restart docker"
```

### Issue: Shared Storage Mount Failures
**Symptoms:** Jenkins masters cannot access shared storage
**Resolution:**
```bash
# Verify NFS server accessibility
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "showmount -e {{ nfs_server }}"

# Check mount status
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "mount | grep jenkins_home"

# Remount if necessary
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "umount /opt/jenkins_home && mount -a"
```

### Issue: SSL Certificate Problems
**Symptoms:** HTTPS access fails
**Resolution:**
```bash
# Check certificate validity
openssl x509 -in /path/to/certificate.crt -text -noout

# Verify certificate chain
openssl verify -CAfile /path/to/ca.crt /path/to/certificate.crt

# Regenerate certificates if needed
ansible-playbook ansible/site.yml --tags ssl-certificates
```

## Rollback Procedures

### Emergency Rollback
If deployment fails and requires immediate rollback:

```bash
# Stop all Jenkins services
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m shell -a "systemctl stop jenkins-master"

# Restore from backup
./scripts/disaster-recovery.sh restore-latest

# Verify rollback success
curl -f http://{{ jenkins_vip }}:8080/login
```

### Partial Rollback
For component-specific rollbacks:

```bash
# Rollback specific component
ansible-playbook ansible/rollback.yml \
  --tags "component-name" \
  --extra-vars "rollback_version=previous"
```

## Post-Deployment Checklist

- [ ] All services running and healthy
- [ ] Jenkins accessible via VIP
- [ ] Load balancer functioning correctly
- [ ] SSL certificates valid and properly configured
- [ ] Monitoring systems collecting data
- [ ] Alerting rules active and tested
- [ ] Backup systems operational
- [ ] Security hardening verified
- [ ] Documentation updated
- [ ] Team notification sent
- [ ] Post-deployment review scheduled

## Maintenance Windows

### Recommended Maintenance Schedule
- **Daily**: Automated health checks and backup verification
- **Weekly**: Security updates and certificate renewal checks
- **Monthly**: Full backup testing and disaster recovery drills
- **Quarterly**: Security audits and performance optimization

### Emergency Contact Information
- **Infrastructure Team**: infra@company.com
- **Security Team**: security@company.com
- **24/7 Support**: +1-555-0123

---

**Last Updated:** {{ ansible_date_time.date }}
**Version:** 1.0
**Reviewed By:** Infrastructure Team