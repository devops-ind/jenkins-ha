# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-grade Jenkins infrastructure with **Blue-Green Deployment**, **Multi-Team Support**, and **Enterprise Security** using Ansible for configuration management. The system deploys Jenkins masters in blue-green configuration with secure container management, HAProxy load balancing, comprehensive monitoring stack (Prometheus/Grafana), automated backup and disaster recovery systems, and Job DSL automation with enhanced security controls.

### Recent Security & Operational Enhancements
- **Container Security**: Trivy vulnerability scanning, security constraints, runtime monitoring
- **Automated Rollback**: SLI-based rollback triggers with configurable thresholds
- **Enhanced Monitoring**: 26-panel Grafana dashboards with DORA metrics and SLI tracking
- **Disaster Recovery**: Enterprise-grade automated DR with RTO/RPO compliance
- **Pre-deployment Validation**: Comprehensive system validation framework
- **Security Compliance**: Real-time security monitoring and compliance reporting
- **Architecture Simplification**: Single configuration per team with runtime blue-green differentiation (DevOps expert validated)
- **Build Optimization**: Unified Docker images for blue-green environments reducing build complexity by 55%
- **✅ Resource-Optimized Blue-Green**: Only active environment runs (50% resource reduction) with dynamic switching - **COMPLETE**: Both HAProxy and Jenkins master deployments optimized
- **✅ Dynamic SSL Generation**: Team-based wildcard SSL certificates auto-generated from `jenkins_teams` configuration
- **✅ Improved Domain Architecture**: Corrected subdomain format `{team}jenkins.domain.com` for better team isolation
- **✅ SSL Architecture Refactor**: SSL generation moved to high-availability-v2 role for better separation of concerns
- **⚡ Jenkins Container Optimization**: Active-only container deployment in jenkins-master-v2 role with intelligent environment switching
- **✅ Smart Data Sharing**: Selective data sharing between blue-green environments with plugin isolation for safe upgrades
- **🔒 HAProxy SSL Container Fix**: Resolved persistent SSL certificate mounting issues with container-safe approach, comprehensive troubleshooting system, and automated recovery
- **🪝 Comprehensive Pre-commit Hooks**: Advanced Groovy/Jenkinsfile validation with security scanning, syntax checking, and best practices enforcement
- **🔍 Enhanced Code Quality**: Multi-layer validation for 22 Groovy files and 7 Jenkinsfiles with automated CI/CD integration
- **📦 GlusterFS Replicated Storage**: Complete Ansible automation for GlusterFS 10.x with real-time replication (RPO < 5s, RTO < 30s), team-based volumes, automated health monitoring, and zero-downtime failover
- **✅ Intelligent Keepalived Failover**: Prevents cascading failures with percentage-based backend health monitoring, team quorum logic, and 30s grace period - eliminates 2-5 min downtime for healthy teams when single team fails
- **✅ Workspace Data Retention**: Automated cleanup system with 7-10 day configurable retention per team, cron-based scheduling, and monitoring - saves 30-50% disk space
- **✅ Cross-VM Individual Monitoring**: HAProxy monitors each team's Jenkins across VMs with active-passive or active-active failover strategies - enables per-team failover without affecting other teams (configurable: `haproxy_backend_failover_strategy`)
- **🔄 Hybrid GlusterFS Architecture**: **PRODUCTION-READY** - Jenkins writes to fast local Docker volumes, periodic rsync syncs to GlusterFS sync layer (`/var/jenkins/{team}/sync/{blue|green}`). GlusterFS handles automatic VM-to-VM replication. **Solves**: No concurrent write conflicts, no mount failures, no Jenkins freezes. **RPO**: 5 minutes, **RTO**: < 2 minutes. Best of both worlds: local performance + distributed replication
- **📊 Separate VM Monitoring Deployment**: Deploy Prometheus/Grafana/Loki stack to dedicated monitoring VM, separate from Jenkins infrastructure. Auto-detects deployment type from inventory, replaces all localhost references with actual IPs, configures firewall rules automatically, deploys cross-VM exporters (Node Exporter, Promtail, cAdvisor) on all VMs. Better resource isolation, independent scaling, centralized monitoring for multiple Jenkins instances
- **📝 Jenkins Job Logs with Loki**: Complete Jenkins job build log collection via Loki/Promtail. Automatically mounts all Jenkins Docker volumes (`/var/jenkins_home/jobs/*/builds/*/log`), extracts metadata (team, environment, job_name, build_number) from file paths, 30-day retention, Grafana visualization ready. Complements existing container log collection for 100% Jenkins observability
- **🔔 Microsoft Teams Alerting**: Native Alertmanager Teams integration with flexible routing strategies (single, per-team, hybrid). Severity-based channels (critical, warning, info), team-specific webhooks, intelligent alert grouping, inhibition rules to prevent alert storms. Rich formatted messages with full alert context. 130+ pre-configured alert rules covering infrastructure, Jenkins, blue-green, and logs. Vault-encrypted webhook management
- **🌐 FQDN Infrastructure Addressing**: Complete FQDN support for monitoring infrastructure with toggle-based migration. Smart addressing hierarchy (monitoring_fqdn → host_fqdn → IP fallback), DNS-based service discovery, HA/failover support, network flexibility. Backward compatible with seamless IP-to-FQDN migration. Affects all internal communication: Prometheus targets, Promtail Loki URLs, cross-VM agent addresses, health checks. Zero-downtime migration with rollback support
- **🔧 Cross-VM Monitoring Fix**: Fixed critical network communication issues between monitoring agents and servers across VMs. All agents (Node Exporter, Promtail, cAdvisor) now use `network_mode: host` for cross-VM connectivity. Prometheus target generation reordered to execute BEFORE template rendering. Template updated to include cross-VM targets with role labels. Comprehensive troubleshooting guide with health check scripts, verification procedures, and migration paths
- **♻️ Monitoring Role Refactoring v2.0**: **NEW** - Complete architectural refactoring with phase-based organization. **67% reduction in main.yml** (489→161 lines), **40% elimination of code duplication** (unified agent deployment), clear server/agent separation across 4 phases. Multi-host deployment capability (`monitoring:jenkins_masters`), single deployment path per agent, improved maintainability and testability. Follows HAProxy/Jenkins role patterns with import_tasks orchestration. Production-ready with comprehensive refactoring guide
- **🔌 GitHub & Jira Integration**: GitHub Enterprise datasource for repository metrics, PR tracking, and workflow status; Jira Cloud datasource for sprint management and issue tracking; Auto-provisioned with secure vault credential management; Pre-built 10-panel dashboard correlating code and project management data; Full JQL query support for custom Jira metrics

## Key Commands

### Core Deployment Commands
```bash
# Deploy to production environment
make deploy-production

# Deploy to local development environment  
make deploy-local

# Build and push Docker images
make build-images

# Run backup procedures
make backup

# Setup monitoring stack
make monitor
```

### Direct Ansible Commands
```bash
# Full infrastructure deployment
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

# Deploy specific components with tags
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags jenkins,deploy
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags monitoring
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags backup
```

### Testing and Validation
```bash
# Test inventory configuration
python tests/inventory_test.py ansible/inventories/production/hosts.yml

# Test playbook syntax
ansible-playbook tests/playbook-syntax.yml --syntax-check

# Validate Ansible playbook syntax
ansible-playbook ansible/site.yml --syntax-check

# Run comprehensive pre-deployment validation
ansible-playbook ansible/site.yml --tags validation -e validation_mode=strict

# Security compliance scan
/usr/local/bin/jenkins-security-scan.sh --all

# SSL certificate validation (NEW)
ansible-playbook ansible/site.yml --tags ssl --check

# Test SSL certificate generation for teams (NEW)
ansible-playbook ansible/site.yml --tags ssl,wildcard --limit local

# HAProxy SSL deployment with troubleshooting (NEW)
./scripts/deploy-haproxy-ssl.sh

# HAProxy SSL troubleshooting and recovery (NEW)
ansible-playbook ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml --extra-vars "troubleshoot_mode=fix"

# GlusterFS deployment and testing (NEW)
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags glusterfs
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags glusterfs,mount  # With server-side mounting
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/playbooks/test-glusterfs.yml
```

### Pre-commit Hooks and Code Quality (NEW)
```bash
# Setup development environment with pre-commit hooks
make dev-setup
./scripts/pre-commit-setup.sh

# Activate development environment
source ./activate-dev-env.sh

# Run all validation tests
make test-full

# Groovy and Jenkins validation
make test-groovy              # Full Groovy syntax validation (requires Groovy SDK)
make test-groovy-basic        # Basic Groovy validation (no Groovy SDK required)
make test-jenkinsfiles        # Validate all Jenkinsfiles structure
make test-dsl                 # Enhanced DSL validation with security
make test-jenkins-security    # Security pattern scanning

# Pre-commit hook management
make pre-commit-install       # Install pre-commit hooks
make pre-commit-run          # Run pre-commit on all files
make pre-commit-update       # Update hooks to latest versions
make pre-commit-clean        # Clean pre-commit cache

# Enhanced DSL syntax validator
./scripts/dsl-syntax-validator.sh --dsl-path jenkins-dsl/ --security-check --complexity-check
./scripts/dsl-syntax-validator.sh --dsl-path pipelines/ --security-check --output-format json

# Manual validation runs (useful for debugging)
pre-commit run groovy-syntax --all-files
pre-commit run jenkinsfile-validation --all-files  
pre-commit run jenkins-security-scan --all-files
```

### GlusterFS Replicated Storage Commands (NEW)
```bash
# Deploy GlusterFS server cluster
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags glusterfs

# Mount GlusterFS volumes on clients
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags storage

# Run comprehensive GlusterFS tests
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/test-glusterfs.yml

# Run specific test categories
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/test-glusterfs.yml --tags service,peers,volumes,replication

# Manual health check
sudo /usr/local/bin/gluster-health-check.sh

# View health logs
sudo tail -f /var/log/gluster-health.log

# Generate Prometheus metrics
sudo /usr/local/bin/gluster-metrics-exporter.sh

# View Prometheus metrics
cat /var/lib/node_exporter/textfile_collector/gluster.prom

# Migrate from local/NFS to GlusterFS (with backup and rollback)
sudo ./scripts/migrate-to-glusterfs.sh --dry-run     # Preview migration
sudo ./scripts/migrate-to-glusterfs.sh                # Full migration
sudo ./scripts/migrate-to-glusterfs.sh --team devops  # Migrate specific team

# Manual GlusterFS operations
sudo gluster peer status                              # Check cluster peers
sudo gluster volume list                              # List all volumes
sudo gluster volume status                            # Check volume status
sudo gluster volume info jenkins-devops-data          # Volume details
sudo gluster volume heal jenkins-devops-data info     # Check self-heal status
sudo gluster volume heal jenkins-devops-data info split-brain  # Check split-brain

# Check mounts (server-side and client-side)
df -h | grep glusterfs
mount | grep glusterfs
findmnt -t fuse.glusterfs                          # Show all GlusterFS mounts

# Verify team-specific mounts
ls -la /var/jenkins/*/data                         # List team mount points
cat /var/jenkins/devops/data/.glusterfs-mount-test # Test file access

# Check mount ownership
stat /var/jenkins/devops/data                      # Check permissions and ownership
```

### Intelligent Keepalived Failover Commands (NEW)
```bash
# Deploy intelligent keepalived health check
ansible-playbook ansible/site.yml --tags high-availability,keepalived

# Monitor backend health (per-team status)
tail -f /var/log/keepalived-backend-health.log

# Expected output:
# 2025-01-07 10:15:00 Overall: 3/4 (75%) | Teams: devops:UP(1/1) ma:UP(1/1) ba:DOWN(0/1) tw:UP(1/1)
# INFO: Backend health 75% below threshold but 3 teams healthy - NO FAILOVER (prevents cascading failure)

# Monitor keepalived decisions
tail -f /var/log/keepalived-haproxy-check.log

# Test intelligent failover (simulate single team failure)
docker stop jenkins-ba-blue  # Should NOT trigger failover (only 1 team down)

# Verify VIP remains on current master
ip addr show | grep 192.168.1.100
```

### Microsoft Teams Alerting Commands (NEW)
```bash
# Deploy Alertmanager with Teams integration
ansible-playbook ansible/site.yml --tags monitoring,alertmanager

# Verify Alertmanager configuration
docker exec alertmanager-production amtool check-config /etc/alertmanager/alertmanager.yml

# View Alertmanager configuration
docker exec alertmanager-production amtool config show

# Check active alerts
docker exec alertmanager-production amtool alert query

# Fire test alert (via Prometheus)
curl -X POST http://prometheus-vm:9090/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [{
      "labels": {
        "alertname": "TestAlert",
        "severity": "warning",
        "team": "devops"
      },
      "annotations": {
        "summary": "Test alert for Teams integration"
      }
    }]
  }'

# Silence alert for 2 hours
docker exec alertmanager-production amtool silence add \
  alertname="JenkinsMasterDown" team="devops" \
  --duration=2h --comment="Planned maintenance"

# List active silences
docker exec alertmanager-production amtool silence query

# Expire silence early
docker exec alertmanager-production amtool silence expire <SILENCE_ID>

# View Alertmanager logs
docker logs alertmanager-production -f | grep -i teams

# Check alert routing tree
docker exec alertmanager-production amtool config routes

# Test Teams webhook manually
curl -H "Content-Type: application/json" \
  -d '{"text":"Test from Alertmanager"}' \
  "https://company.webhook.office.com/webhookb2/YOUR_WEBHOOK_URL"

# Access Alertmanager UI
# http://monitoring-vm-ip:9093
```

### Workspace Data Retention Commands (NEW)
```bash
# Deploy workspace retention system
ansible-playbook ansible/site.yml --tags glusterfs,retention

# Manual workspace cleanup (dry-run)
/usr/local/bin/glusterfs-workspace-cleanup.sh devops 10 --dry-run

# Actual cleanup
/usr/local/bin/glusterfs-workspace-cleanup.sh devops 10

# Generate workspace retention report for all teams
/usr/local/bin/glusterfs-workspace-report.sh

# Monitor cleanup execution status
/usr/local/bin/glusterfs-workspace-monitor.sh

# View cleanup logs
tail -f /var/log/glusterfs-retention/devops-cleanup.log

# Check cron jobs
crontab -l | grep glusterfs-workspace-cleanup
```

### Hybrid GlusterFS Sync Commands (NEW)
```bash
# Deploy GlusterFS sync scripts and cron jobs
ansible-playbook ansible/site.yml --tags jenkins,gluster,sync

# Manual sync to GlusterFS (force sync for specific team)
/usr/local/bin/jenkins-sync-to-gluster-devops.sh

# Blue-green switch with GlusterFS sync integration
./scripts/blue-green-switch-with-gluster.sh devops green

# Failover from failed VM using GlusterFS
./scripts/jenkins-failover-from-gluster.sh devops blue vm1 vm2

# Recover Jenkins data from GlusterFS
/usr/local/bin/jenkins-recover-from-gluster-devops.sh devops blue

# View sync logs
tail -f /var/log/jenkins-glusterfs-sync-devops.log

# Check sync cron jobs
crontab -l | grep jenkins-sync-to-gluster

# View sync documentation
cat examples/hybrid-glusterfs-architecture-guide.md
```

### Cross-VM Individual Jenkins Monitoring Commands (NEW)
```bash
# Configure failover strategy (choose one)
# ansible/roles/high-availability-v2/defaults/main.yml
haproxy_backend_failover_strategy: "active-passive"  # Recommended for HA
# haproxy_backend_failover_strategy: "active-active"   # Load balancing
# haproxy_backend_failover_strategy: "local-only"      # No cross-VM failover

# Deploy cross-VM backend configuration
ansible-playbook ansible/site.yml --tags high-availability,haproxy

# Verify HAProxy configuration includes both VMs
ansible jenkins_masters -m command -a "docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg"

# Check HAProxy backend status
curl -u admin:admin123 http://192.168.1.100:8404/stats

# Or view in browser:
# http://192.168.1.100:8404/stats

# Test individual team failover
# 1. Stop team Jenkins on VM1
docker stop jenkins-ba-blue

# 2. Wait for health checks (15-20 seconds)
sleep 20

# 3. Verify team failed over to VM2 (other teams still on VM1)
curl -f http://192.168.1.100/bajenkins.example.com/login

# 4. Check HAProxy stats for backend status
curl -s -u admin:admin123 http://192.168.1.100:8404/stats | grep jenkins_backend_ba

# 5. Verify VIP did not move (NO cascading failure)
ip addr show | grep 192.168.1.100

# Monitor HAProxy backend health
docker logs -f jenkins-haproxy --tail 100 | grep backend

# View per-team backend status
echo "show stat" | socat stdio /run/haproxy/admin.sock | grep jenkins_backend

# Force backend state change (if needed)
echo "set server jenkins_backend_devops/devops-vm1 state ready" | socat stdio /run/haproxy/admin.sock
```

### Hybrid GlusterFS Architecture (Docker Volumes + GlusterFS Sync Layer)
```bash
# Deploy GlusterFS infrastructure with /sync directories
ansible-playbook ansible/site.yml --tags glusterfs

# Deploy sync scripts and cron jobs
ansible-playbook ansible/site.yml --tags jenkins,gluster,sync

# Verify sync directory structure
ls -la /var/jenkins/devops/sync/blue/
ls -la /var/jenkins/devops/sync/green/

# Manual sync to GlusterFS (force)
/usr/local/bin/jenkins-sync-to-gluster-devops.sh

# Check sync status
tail -f /var/log/jenkins-gluster-sync-devops.log

# Monitor sync lag across all teams
/usr/local/bin/jenkins-sync-monitor.sh

# Blue-green switch with GlusterFS sync
./scripts/blue-green-switch-with-gluster.sh devops green

# Failover from failed VM using GlusterFS
./scripts/jenkins-failover-from-gluster.sh devops blue vm1 vm2

# Recover Jenkins from GlusterFS
/usr/local/bin/jenkins-recover-from-gluster-devops.sh devops blue

# Check GlusterFS volume status
gluster volume info jenkins-devops-data
gluster volume status jenkins-devops-data

# Monitor replication health
gluster volume heal jenkins-devops-data info
```

### Monitoring Stack Deployment Commands (NEW)

#### Separate VM Monitoring Deployment
```bash
# Deploy monitoring stack to separate VM (auto-detects deployment type from inventory)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring --limit monitoring

# Deploy with firewall configuration
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,firewall --limit monitoring

# Deploy cross-VM exporters to Jenkins VMs
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,cross-vm --limit jenkins_masters

# Full deployment (monitoring VM + Jenkins VM exporters)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Verify deployment type detection
ansible monitoring -m debug -a "var=monitoring_deployment_type"
```

#### Monitoring Stack Access
```bash
# Access Grafana (separate VM)
http://<monitoring-vm-ip>:9300
# Default login: admin/admin123

# Access Prometheus
http://<monitoring-vm-ip>:9090

# Access Loki
http://<monitoring-vm-ip>:9400

# Check Prometheus targets
http://<monitoring-vm-ip>:9090/targets

# Check Prometheus metrics
curl http://<monitoring-vm-ip>:9090/api/v1/targets
```

#### Jenkins Job Logs with Loki
```bash
# Query available log labels
curl http://<monitoring-vm-ip>:9400/loki/api/v1/labels

# Query Jenkins job logs for specific team
curl -G http://<monitoring-vm-ip>:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins-job-logs", team="devops"}' \
  --data-urlencode 'limit=100'

# Query logs for specific job
curl -G http://<monitoring-vm-ip>:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins-job-logs", job_name="my-pipeline"}' \
  --data-urlencode 'limit=100'

# Query logs for specific build
curl -G http://<monitoring-vm-ip>:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins-job-logs", job_name="my-pipeline", build_number="42"}' \
  --data-urlencode 'limit=1000'

# View in Grafana Explore
# http://<monitoring-vm-ip>:9300/explore
# Select Loki datasource and use LogQL:
# {job="jenkins-job-logs", team="devops"}
# {job="jenkins-job-logs"} |= "ERROR"
# {job="jenkins-job-logs"} |~ "(?i)(error|exception|failed)"
```

#### Monitoring Verification
```bash
# Verify Promtail on Monitoring VM
docker exec promtail-monitoring-production ls -la /var/log/

# Verify Promtail on Jenkins VMs (has access to Jenkins volumes)
docker exec promtail-jenkins-vm1-production ls -la /jenkins-logs/
docker exec promtail-jenkins-vm2-production ls -la /jenkins-logs/

# Check Node Exporter on Jenkins VMs
curl http://<jenkins-vm-ip>:9100/metrics

# Check Promtail status on Jenkins VMs
docker logs promtail-jenkins-vm1-production
curl http://<jenkins-vm-ip>:9401/ready

# Check Loki ingestion on Monitoring VM
curl http://<monitoring-vm-ip>:9400/ready

# Verify firewall rules (RHEL/CentOS)
sudo firewall-cmd --list-all

# Verify firewall rules (Debian/Ubuntu)
sudo ufw status verbose
```

#### Monitoring Health Checks
```bash
# Run monitoring health check script
/opt/monitoring/scripts/monitoring-health.sh

# Check Prometheus health
curl http://<monitoring-vm-ip>:9090/-/healthy

# Check Grafana health
curl http://<monitoring-vm-ip>:9300/api/health

# Check Loki health
curl http://<monitoring-vm-ip>:9400/ready

# View monitoring logs (on Monitoring VM)
docker logs prometheus-production
docker logs grafana-production
docker logs loki-production
docker logs promtail-monitoring-production

# View Promtail logs (on Jenkins VMs)
docker logs promtail-jenkins-vm1-production
docker logs promtail-jenkins-vm2-production
```

#### Monitoring Agent Management (NEW)
```bash
# Deploy cAdvisor on Jenkins VMs for container metrics
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,cross-vm,cadvisor

# Deploy agent health monitoring
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,cross-vm,agent-health

# Check agent health from Jenkins VMs
ssh jenkins-vm1 '/usr/local/bin/monitoring/agent-health-check.sh'
ssh jenkins-vm2 '/usr/local/bin/monitoring/agent-health-check.sh'

# View agent health logs
ssh jenkins-vm1 'tail -f /var/log/monitoring-agents/health-check.log'

# Check agent health timer status
ssh jenkins-vm1 'systemctl status monitoring-agent-health.timer'
ssh jenkins-vm1 'systemctl list-timers | grep monitoring'

# Manually trigger health check
ssh jenkins-vm1 'systemctl start monitoring-agent-health.service'

# Check cAdvisor metrics from Jenkins VMs
curl http://jenkins-vm1:9200/metrics
curl http://jenkins-vm2:9200/metrics

# Query container metrics in Prometheus
# CPU usage per container
container_cpu_usage_seconds_total{job="cadvisor"}

# Memory usage per container
container_memory_usage_bytes{job="cadvisor"}

# Network traffic per container
container_network_receive_bytes_total{job="cadvisor"}
```

#### Monitoring FQDN Configuration (NEW)
```bash
# Configure FQDN-based infrastructure addressing for monitoring

# Step 1: Add FQDN variables to inventory
# Edit ansible/inventories/production/hosts.yml
jenkins_masters:
  hosts:
    centos9-vm:
      ansible_host: 192.168.188.142  # Keep for SSH
      host_fqdn: centos9-vm.internal.local        # Infrastructure FQDN
      monitoring_fqdn: monitoring.internal.local  # Monitoring server FQDN

# Step 2: Setup DNS (choose one method)
# Option A: Production DNS
# Add A records: centos9-vm.internal.local → 192.168.188.142

# Option B: /etc/hosts (all VMs)
sudo tee -a /etc/hosts <<EOF
192.168.188.142 centos9-vm.internal.local monitoring.internal.local
EOF

# Step 3: Test DNS resolution
dig +short centos9-vm.internal.local
ping -c 2 monitoring.internal.local

# Step 4: Deploy with FQDN mode enabled (default)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Deploy with IP mode (for migration/rollback)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring -e "monitoring_use_fqdn=false"

# Verify FQDN configuration
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep targets:
# Should show: centos9-vm.internal.local:8080 (FQDN mode)
# Or: 192.168.188.142:8080 (IP mode)

# Check Promtail Loki URL
docker exec promtail-jenkins-vm1-production cat /etc/promtail/promtail-config.yml | grep url:
# Should show: http://monitoring.internal.local:9400/loki/api/v1/push

# Verify Prometheus targets using FQDNs
curl http://monitoring.internal.local:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# Rollback to IP-based addressing
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring -e "monitoring_use_fqdn=false"
```

#### Cross-VM Monitoring Troubleshooting (NEW)
```bash
# Troubleshoot cross-VM agent communication issues
# Comprehensive guide: examples/cross-vm-monitoring-troubleshooting-guide.md

# Verify agent containers use host network (required for cross-VM)
ansible jenkins_masters -m shell -a "docker inspect node-exporter-production | jq '.[0].HostConfig.NetworkMode'"
# Expected: "host" (NOT "monitoring-net")

# Test agent connectivity from monitoring VM
curl -s http://centos9-vm.internal.local:9100/metrics | head -n 20  # Node Exporter
curl -s http://centos9-vm.internal.local:9200/metrics | grep cadvisor  # cAdvisor
curl -s http://centos9-vm.internal.local:9080/ready  # Promtail

# Check Prometheus configuration includes cross-VM targets
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep -A 10 "Cross-VM"
# Should show Jenkins VM targets with role: 'jenkins-vm' labels

# Verify Prometheus target health
curl -s http://monitoring.internal.local:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.role=="jenkins-vm") | {job: .job, health: .health, instance: .labels.instance}'
# Expected: health: "up" for all cross-VM targets

# Check Promtail sending logs to Loki
docker logs promtail-jenkins-vm1-production 2>&1 | grep "Successfully sent batch"

# Verify Loki receiving logs from Jenkins VMs
curl -s "http://monitoring.internal.local:9400/loki/api/v1/label/hostname/values" | jq

# Run comprehensive health check
cat > /tmp/cross-vm-health-check.sh <<'EOF'
#!/bin/bash
set -e
MONITORING_VM="monitoring.internal.local"
JENKINS_VM="centos9-vm.internal.local"

echo "Cross-VM Monitoring Health Check"
echo "=================================="

# Check agent containers
echo -e "\n[1/5] Agent containers on Jenkins VM:"
ssh ${JENKINS_VM} "docker ps --filter 'name=node-exporter\|promtail\|cadvisor' --format '{{.Names}} - {{.Status}}'"

# Test endpoints
echo -e "\n[2/5] Agent endpoints:"
curl -sf http://${JENKINS_VM}:9100/metrics > /dev/null && echo "✓ Node Exporter" || echo "✗ Node Exporter FAILED"
curl -sf http://${JENKINS_VM}:9200/metrics > /dev/null && echo "✓ cAdvisor" || echo "✗ cAdvisor FAILED"
curl -sf http://${JENKINS_VM}:9080/ready > /dev/null && echo "✓ Promtail" || echo "✗ Promtail FAILED"

# Check Prometheus config
echo -e "\n[3/5] Prometheus configuration:"
ssh ${MONITORING_VM} "docker exec prometheus-production cat /etc/prometheus/prometheus.yml" | \
  grep -q "${JENKINS_VM}:9100" && echo "✓ Node Exporter target configured" || echo "✗ MISSING"

# Check target health
echo -e "\n[4/5] Target health:"
curl -sf http://${MONITORING_VM}:9090/api/v1/targets | \
  jq -r '.data.activeTargets[] | select(.labels.role=="jenkins-vm") | "\(.job): \(.health)"'

# Check data flow
echo -e "\n[5/5] Metrics available:"
QUERY_RESULT=$(curl -sf "http://${MONITORING_VM}:9090/api/v1/query?query=node_uname_info{role=\"jenkins-vm\"}" | \
  jq -r '.data.result | length')
echo "Jenkins VM metrics in Prometheus: ${QUERY_RESULT} series"

echo -e "\n=================================="
echo "Health check complete"
EOF
chmod +x /tmp/cross-vm-health-check.sh
/tmp/cross-vm-health-check.sh

# Common fixes:
# 1. Network mode issues → Redeploy: ansible-playbook ansible/site.yml --tags monitoring
# 2. DNS issues → Check /etc/hosts or DNS A records
# 3. Firewall → Open ports 9100, 9200, 9080, 9400 between VMs
# 4. Missing targets → Verify cross-VM tasks run BEFORE Prometheus deployment
```

### Environment Setup
```bash
# Install Python dependencies
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r collections/requirements.yml

# Generate secure credentials
scripts/generate-credentials.sh production

# Setup vault passwords (interactive)
ansible-vault create ansible/inventories/production/group_vars/all/vault.yml

# Automated HA setup (production)
scripts/ha-setup.sh production full

# Disaster recovery validation
scripts/disaster-recovery.sh production --validate
```

### Grafana Plugin Management Commands (NEW)

#### Install & Verify Plugins

```bash
# Deploy Grafana with GitHub and Jira plugins
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Verify plugins are installed
docker exec grafana-production grafana-cli plugin ls

# Expected output:
# grafana-github-datasource @ 1.3.9 (grafana-plugin)
# grafana-jira-datasource @ 1.x.x (grafana-plugin)

# Check Grafana logs for plugin loading
docker logs grafana-production | grep -i plugin

# Verify datasources provisioned
curl -u admin:password http://localhost:9300/api/datasources | jq '.[] | {name, type, uid}'
```

#### GitHub Enterprise Datasource Configuration

```bash
# Test GitHub Enterprise API connectivity
curl -H "Authorization: token {{ vault_github_enterprise_token }}" \
  https://{{ vault_github_enterprise_url }}/api/v3/user/repos | jq '.[] | {name, full_name, default_branch}' | head -n 10

# Verify GitHub datasource in Grafana
curl -u admin:password http://localhost:9300/api/datasources/uid/github-enterprise | jq '.{name, type, access, jsonData}'

# Test GitHub datasource query
curl -u admin:password http://localhost:9300/api/datasources/uid/github-enterprise/health
```

#### Jira Cloud Datasource Configuration

```bash
# Test Jira Cloud API connectivity
curl -u {{ vault_jira_cloud_email }}:{{ vault_jira_cloud_token }} \
  https://{{ vault_jira_cloud_url }}/rest/api/3/myself | jq '{displayName, emailAddress, accountType}'

# Verify Jira datasource in Grafana
curl -u admin:password http://localhost:9300/api/datasources/uid/jira-cloud | jq '.{name, type, access, jsonData}'

# Test Jira datasource query
curl -u admin:password http://localhost:9300/api/datasources/uid/jira-cloud/health

# Query Jira issues via API (test JQL)
curl -u {{ vault_jira_cloud_email }}:{{ vault_jira_cloud_token }} \
  "https://{{ vault_jira_cloud_url }}/rest/api/3/search?jql=project%20in%20(DEVOPS)%20AND%20status%20%3D%20Done&maxResults=5" | jq '.issues[] | {key, summary, status}'
```

#### Dashboard Access

```bash
# Access GitHub & Jira Metrics dashboard
# http://localhost:9300/d/github-jira-metrics/github-jira-metrics

# Verify dashboard loaded (API check)
curl -u admin:password http://localhost:9300/api/dashboards/uid/github-jira-metrics | jq '.dashboard | {title, panels: (.panels | length), refresh}'
```

#### Plugin Updates

```bash
# Update plugins to latest versions
# Option 1: Via environment variable (requires container restart)
# Edit GF_INSTALL_PLUGINS in ansible/roles/monitoring/tasks/phase3-servers/grafana.yml
# Change to: "grafana-github-datasource@latest,grafana-jira-datasource@latest"

# Then redeploy
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Option 2: Manual update via CLI
docker exec grafana-production grafana-cli plugin update grafana-github-datasource
docker exec grafana-production grafana-cli plugin update grafana-jira-datasource
docker restart grafana-production

# Option 3: Specific version update
docker exec grafana-production grafana-cli plugin install grafana-github-datasource 1.3.9
docker restart grafana-production
```

#### Troubleshooting Plugins

```bash
# View all Grafana container configuration
docker inspect grafana-production | grep -A 20 '"Env"'

# Check if GF_INSTALL_PLUGINS environment variable is set
docker exec grafana-production printenv | grep GF_INSTALL_PLUGINS

# View plugin installation logs (during container startup)
docker logs grafana-production | head -n 100

# Check plugin directory
docker exec grafana-production ls -la /var/lib/grafana/plugins/

# Check plugin configuration
docker exec grafana-production cat /etc/grafana/provisioning/plugins/plugins.yml

# Check datasource provisioning status
docker exec grafana-production cat /etc/grafana/provisioning/datasources/github-datasource.yml
docker exec grafana-production cat /etc/grafana/provisioning/datasources/jira-datasource.yml

# View Grafana database logs (plugin records)
docker exec grafana-production tail -f /var/log/grafana/grafana.log | grep -i plugin

# Force Grafana to reload provisioned datasources
docker restart grafana-production
```

#### Documentation

```bash
# View comprehensive plugin integration guide
cat examples/github-jira-datasource-integration.md

# View vault credentials (requires vault password)
ansible-vault view ansible/inventories/production/group_vars/all/vault.yml | grep -E 'github_enterprise|jira_cloud'
```

---

## Architecture Overview

### Core Infrastructure Components
- **🔄 Resource-Optimized Blue-Green Jenkins Masters**: Multiple team environments with zero-downtime deployments and automated rollback. **OPTIMIZED**: Only active environment runs (50% resource reduction), single configuration per team with runtime environment differentiation
- **🌐 Dynamic HAProxy Load Balancer**: Advanced traffic routing with health checks, SLI monitoring, and API management. **ENHANCED**: Supports dynamic team discovery, corrected subdomain format (`{team}jenkins.domain.com`), and blue-green switching
- **🔒 Dynamic SSL Certificate Management**: Wildcard SSL certificates auto-generated based on `jenkins_teams` configuration. **NEW**: Team-aware certificate generation with automatic subdomain inclusion
- **🔧 Secure Dynamic Jenkins Agents**: Container-based agents (maven, python, nodejs, dind) with security constraints and vulnerability scanning
- **📋 Job DSL Automation**: Code-driven job creation with security sandboxing and approval workflows. **IMPROVED**: Production-safe DSL with no auto-execution startup failures
- **📊 Comprehensive Monitoring Stack**: Prometheus metrics, enhanced Grafana dashboards with 26 panels, DORA metrics, and SLI tracking
- **💾 Enterprise Backup & DR**: Automated backup with RTO/RPO compliance and automated disaster recovery procedures
- **📦 Hybrid GlusterFS Architecture**: **PRODUCTION-READY** Jenkins writes to local Docker volumes (`jenkins-{team}-{env}-home`) for fast performance. Periodic rsync (every 5 min) syncs to GlusterFS (`/var/jenkins/{team}/sync/{env}`) which handles automatic VM-to-VM replication. **Solves all issues**: No concurrent writes (Jenkins never touches GlusterFS), no mount failures, no freezes. **RPO**: 5 minutes (configurable to 1 min), **RTO**: < 2 minutes. Automatic failover via GlusterFS recovery
- **🛡️ Security Infrastructure**: Container security monitoring, vulnerability scanning, compliance validation, and audit logging
- **🪝 Pre-commit Validation Framework**: Comprehensive code quality enforcement with Groovy/Jenkinsfile validation, security scanning, and automated CI/CD integration

### Deployment Flow (ansible/site.yml)
1. **Pre-deployment Validation**: Comprehensive system validation framework with connectivity, security, and resource checks
2. **GlusterFS Setup** (if enabled): GlusterFS server installation, cluster formation, replicated volume creation with performance tuning
3. **Bootstrap Infrastructure**: Common setup, Docker, shared storage mounting, security hardening with container security constraints
4. **Secure Jenkins Image Building**: Custom Jenkins images with vulnerability scanning and security validation
5. **Blue-Green Jenkins Deployment**: Deploy blue/green environments with enhanced pre-switch validation and automated rollback triggers
6. **HAProxy Load Balancer Setup**: Configure traffic routing, health checks, and SLI monitoring integration
7. **Job DSL Seed Job Creation**: Secure automated job creation with approval workflows (removed vulnerable dynamic-ansible-executor.groovy)
8. **Enhanced Monitoring and Backup Setup**: Comprehensive Grafana dashboards, SLI tracking, and enterprise backup procedures
9. **Security Scanning & Compliance**: Container vulnerability scanning, security constraint validation, and compliance reporting
10. **Post-Deployment Verification**: Multi-layer health checks, security validation, and comprehensive deployment summary

### Key Ansible Roles
- `glusterfs-server`: **NEW** Complete GlusterFS 10.x automation with server installation, trusted storage pool formation, replicated volume creation (replica=2), performance tuning, health monitoring, and Prometheus metrics export
- `shared-storage`: **ENHANCED** Multi-backend storage (local/NFS/GlusterFS) with team-based volume mounting, automatic failover configuration, and smart data sharing integration
- `jenkins-master-v2`: **OPTIMIZED** Unified Jenkins deployment with single configuration per team, **resource-optimized blue-green deployment** (active-only containers), production-safe DSL architecture, 55% code reduction (4 files vs 13 files), and **SEPARATED DATA OPERATIONS** with dedicated backup daemons and Ansible-native sync
- `high-availability-v2`: **ENHANCED** Advanced HA configuration with perfect jenkins-master-v2 compatibility, dynamic team discovery, resource-optimized blue-green deployment, and **NEW** dynamic SSL certificate generation based on `jenkins_teams`
- `monitoring`: Enhanced Prometheus/Grafana stack with GitHub/Jira datasources, 26+ panel dashboards, DORA metrics, SLI tracking, and automated alerting
- `security`: **REFACTORED** System hardening and compliance validation (SSL generation moved to high-availability-v2 for better separation of concerns)
- `common`: System bootstrap with pre-deployment validation framework


### Environment Configuration
- **Production**: `environments/production.env` and `ansible/inventories/production/`
- **Local**: `environments/local.env` and `ansible/inventories/local/` with `deployment_mode: local`
- **Vault Variables**: Encrypted in `ansible/inventories/*/group_vars/all/vault.yml`

### Pipeline Definitions
Jenkins pipelines are pre-configured in `pipelines/` directory with enhanced security and safety:
- `Jenkinsfile.infrastructure-update`: Infrastructure updates with **automated rollback triggers**, SLI monitoring, and approval gates
- `Jenkinsfile.backup`: Automated backup procedures with validation and reporting
- `Jenkinsfile.disaster-recovery`: Comprehensive disaster recovery with RTO/RPO compliance testing
- `Jenkinsfile.monitoring`: Enhanced monitoring setup with SLI configuration and alerting
- `Jenkinsfile.security-scan`: **Trivy vulnerability scanning** with compliance reporting
- `Jenkinsfile.image-builder`: Secure image building with vulnerability scanning and security validation
- `Jenkinsfile.health-check`: Multi-layer health monitoring with blue-green validation and security checks

### Job DSL Scripts
Job definitions are organized in `jenkins-dsl/` directory with enhanced security:
- `jenkins-dsl/folders.groovy`: Folder structure creation
- `jenkins-dsl/views.groovy`: View and dashboard definitions
- `jenkins-dsl/infrastructure/secure-ansible-executor.groovy`: **Secure Ansible execution** with sandboxing and approval workflows (replaces removed dynamic-ansible-executor.groovy)
- `jenkins-dsl/infrastructure/*.groovy`: Infrastructure pipeline jobs with security validation
- `jenkins-dsl/applications/*.groovy`: Sample application jobs with security best practices

**Security Note**: The vulnerable `dynamic-ansible-executor.groovy` has been removed and replaced with secure execution patterns.

### Inventory Structure
Required inventory groups for proper deployment:
- `jenkins_masters`: Blue-green Jenkins master nodes (supports multiple teams)
- `monitoring`: Prometheus/Grafana monitoring stack
- `load_balancers`: HAProxy load balancer nodes
- `shared_storage`: NFS/GlusterFS storage nodes

**Note**: No static agents - all agents are dynamic containers provisioned on-demand

### Script Utilities
- `scripts/deploy.sh`: Environment-aware deployment wrapper with validation
- `scripts/backup.sh`: Manual backup execution with integrity validation
- `scripts/disaster-recovery.sh`: **Enterprise-grade automated disaster recovery** with RTO/RPO compliance (508 lines)
- `scripts/ha-setup.sh`: **Comprehensive HA infrastructure setup automation** with multiple deployment modes (559 lines)
- `scripts/blue-green-switch.sh`: Blue-green environment switching with enhanced pre-switch validation
- `scripts/blue-green-healthcheck.sh`: Multi-layer health validation for environments
- `scripts/monitor.sh`: Monitoring stack management with SLI configuration
- `scripts/generate-credentials.sh`: **Secure credential generation** and rotation
- `/usr/local/bin/jenkins-security-scan.sh`: **Trivy vulnerability scanning** automation
- `/usr/local/bin/jenkins-security-monitor.sh`: **Real-time security monitoring** with compliance validation

## Important Notes

### Blue-Green Deployment Considerations  
- **🚀 COMPLETE RESOURCE-OPTIMIZED ARCHITECTURE**: Only active environment runs (50% resource reduction) - **IMPLEMENTED** in both HAProxy and Jenkins master deployments
- **🔄 Active-Only Deployment**: 
  - **HAProxy**: Routes traffic only to active environment backends
  - **Jenkins Masters**: Deploy only active environment containers, inactive containers stopped
  - **Instant Switching**: Ready for zero-downtime environment switching via configuration update
- **⚡ End-to-End Dynamic Environment Switching**: 
  - **HAProxy**: Routes traffic based on `team.active_environment` setting
  - **Jenkins**: Deploys containers based on `team.active_environment` setting
  - **Unified Management**: Single inventory variable controls entire stack
- **🎯 Team-Independent Switching**: Each team can independently switch their blue/green environments without affecting other teams
- **☁️ Dynamic Agent Provisioning**: All agents are dynamic containers provisioned on-demand (no static agent management)
- **🏗️ Consistent Artifacts**: Same Docker images for both environments, differences only at infrastructure and routing level
- **📊 Enhanced Monitoring**: Blue-green status integrated into monitoring dashboards with automated rollback triggers
- **💾 Volume Preservation**: Both blue and green volumes maintained for instant environment switching

### Security and Secrets Management
- **🔐 Enhanced Vault Security**: All sensitive data stored in encrypted Ansible Vault files with automated credential generation
- **🛡️ Container Security**: Trivy vulnerability scanning, security constraints (non-root, non-privileged, read-only filesystem)
- **👁️ Runtime Security Monitoring**: Real-time container security monitoring with automated alerting
- **🔑 Jenkins Security**: Admin credentials encrypted and rotated through Ansible with secure Job DSL execution
- **📜 Dynamic SSL/TLS Management**: **NEW** Wildcard SSL certificates auto-generated based on `jenkins_teams` configuration, managed in `high-availability-v2` role for better architecture
- **✅ Compliance Validation**: Automated security compliance reporting and validation
- **📝 Audit Logging**: Comprehensive security audit logging with centralized collection
- **🚪 Access Controls**: Enhanced RBAC with team-based isolation and security policies
- **🌐 Team-Aware SSL**: SSL certificates automatically include all team subdomains in format `{team}jenkins.{domain}`
- **🪝 Pre-commit Security Validation**: **NEW** Multi-layer security scanning for Groovy/Jenkins code with 25+ security patterns including:
  - **Critical Risk Detection**: System.exit(), Runtime.getRuntime(), ProcessBuilder usage
  - **Code Injection Prevention**: GroovyShell, evaluate(), ScriptEngine pattern detection
  - **Credential Exposure Prevention**: Hardcoded password, token, API key detection
  - **Shell Injection Protection**: Variable expansion in shell command validation
  - **File System Security**: Path traversal, dangerous rm -rf operation detection
  - **Jenkins-Specific Security**: Instance manipulation, master node execution prevention
  - **Privilege Escalation Prevention**: sudo usage, permission modification detection

### Monitoring and Alerting
- **Enhanced Prometheus Rules**: Advanced SLI/SLO monitoring rules in `monitoring/prometheus/rules/jenkins.yml`
- **Comprehensive Grafana Dashboards**: 26-panel dashboard with DORA metrics, SLI tracking, deployment success rates, and blue-green status
- **Multi-layer Health Checks**: Jenkins health checks integrated with monitoring stack and automated rollback triggers
- **Blue-green Environment Monitoring**: Enhanced health monitoring with pre-switch validation and rollback automation
- **HAProxy Advanced Monitoring**: Statistics, health checks, and SLI integration for load balancer monitoring
- **Per-team Security Metrics**: Team-specific dashboards with security compliance and vulnerability tracking
- **Container Security Monitoring**: Real-time security monitoring with resource usage, compliance, and vulnerability alerts
- **Automated Rollback Integration**: SLI threshold monitoring with automatic rollback triggers on performance degradation

### Backup and Recovery
- **Enterprise Backup System**: Automated backup schedules with integrity validation and configurable retention policies
- **Automated Disaster Recovery**: Comprehensive DR procedures with RTO/RPO compliance (15-minute RTO, 5-minute RPO targets)
- **Team Configuration Backup**: Jenkins team configurations and secure Job DSL scripts backed up to encrypted shared storage
- **Blue-green Environment DR**: Enhanced backup and restore procedures with validation and rollback capabilities
- **Database Backup**: Monitoring and registry data backup with point-in-time recovery
- **Version Controlled Recovery**: Job DSL scripts and infrastructure code version controlled with automated recovery workflows
- **DR Site Management**: Automated failover to secondary sites with DNS management and service orchestration
- **Compliance Reporting**: RTO/RPO compliance tracking with automated reporting and alerting

### Development and Code Quality
- **Comprehensive Pre-commit Framework**: **NEW** Advanced code quality enforcement with automated validation pipeline including:
  - **Groovy Validation**: Syntax checking for all 22 Groovy files with Groovy compiler integration and fallback validation
  - **Jenkinsfile Validation**: Structure validation for all 7 Jenkinsfiles with pipeline best practices enforcement
  - **Security Scanning**: Multi-pattern security analysis with 25+ risk detection patterns
  - **Best Practices Enforcement**: Automated checking for naming conventions, documentation, and code organization
  - **GitHub Actions Integration**: Automated PR validation, comprehensive CI/CD testing, and release tagging workflows
  - **Development Environment**: Automated setup with virtual environment, tool installation, and hook configuration
  - **Multiple Output Formats**: Text and JSON reporting for human and machine consumption
  - **Complexity Analysis**: Code complexity monitoring with configurable thresholds and reporting
- always update documentation for the work in repository.
- use code-searcher for all the code scanning
- never use Unicode emoji symbols or images in the code, like these ❌
- always use bash-executor for running any bash commands