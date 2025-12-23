# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Production-grade Jenkins HA infrastructure with **Blue-Green Deployment**, **Multi-Team Support**, and **Enterprise Security** using Ansible. Features Jenkins masters in blue-green configuration, HAProxy load balancing, Prometheus/Grafana monitoring, automated backup/DR, and Job DSL automation with security controls.

### Quick Reference

```bash
# Common variables (use throughout)
PROD_INV="ansible/inventories/production/hosts.yml"
SITE_YML="ansible/site.yml"
AP="ansible-playbook -i $PROD_INV $SITE_YML"

# Service Access URLs
# Grafana: http://<monitoring-vm-ip>:9300 (admin/admin123)
# Prometheus: http://<monitoring-vm-ip>:9090
# Loki: http://<monitoring-vm-ip>:9400
# HAProxy Stats: http://<vm-ip>:8404/stats (admin/admin123)
# Alertmanager: http://<monitoring-vm-ip>:9093
```

### Recent Enhancements
- Container Security: Trivy scanning, security constraints, runtime monitoring
- Automated Rollback: SLI-based triggers with configurable thresholds
- Enhanced Monitoring: 26-panel Grafana dashboards with DORA metrics
- Resource-Optimized Blue-Green: Only active environment runs (50% reduction)
- Dynamic SSL Generation: Team-based wildcard certificates
- Smart Data Sharing: Selective blue-green sharing with plugin isolation
- Pre-commit Hooks: Groovy/Jenkinsfile validation with 25+ security patterns
- GlusterFS: Hybrid architecture (RPO 5min, RTO <2min) with replicated storage
- Intelligent Keepalived: Prevents cascading failures with team quorum logic
- Workspace Retention: Auto-cleanup (7-10 days, saves 30-50% disk)
- Cross-VM Monitoring: Per-team Jenkins monitoring across VMs
- Separate VM Deployment: Monitoring on dedicated VM with auto-detection
- Jenkins Job Logs: Complete log collection via Loki with metadata extraction
- Teams Alerting: Native integration with 130+ alert rules
- FQDN Addressing: DNS-based service discovery with IP fallback
- Monitoring Modernization: File-based Prometheus SD, Grafonnet dashboards
- GitHub & Jira Integration: Enterprise datasources for Grafana
- File-Based JCasC: Hot-reload with zero-downtime config updates
- Option 2 Multi-VM: 3-VM hybrid architecture (Jenkins Blue + Green + Monitoring)

## Key Commands

### Core Deployment
```bash
make deploy-production        # Deploy to production
make deploy-local            # Deploy to local dev
make build-images            # Build and push Docker images
make backup                  # Run backup procedures
make monitor                 # Setup monitoring stack

# Full infrastructure deployment
$AP

# Deploy specific components
$AP --tags jenkins,deploy
$AP --tags monitoring
$AP --tags backup
$AP --tags glusterfs
```

### Infrastructure Jobs
```bash
# Access via Jenkins UI: Infrastructure/Infrastructure-Deployment
# Parameters: COMPONENT, TARGET_VM, DEPLOY_TEAMS, TARGET_ENVIRONMENT, etc.
# See docs/infrastructure-deployment-plan.md for details

# Emergency rollback: Infrastructure/Infrastructure-Rollback
# Manual validation
bash scripts/jenkins-deployment-validator.sh --teams all --vm jenkins_hosts_01
```

### Blue-Green Operations
```bash
# Access via Jenkins UI: Infrastructure/Blue-Green-Switch
# Parameters: SWITCH_SCOPE, TEAMS_TO_SWITCH, SWITCH_STRATEGY, etc.
# Sequential: 15-20 min, Parallel: 8-12 min, Rollback: <30 sec
# See docs/blue-green-switch-job-plan.md for workflow
```

### Testing & Validation
```bash
python tests/inventory_test.py $PROD_INV
$AP --syntax-check
$AP --tags validation -e validation_mode=strict
/usr/local/bin/jenkins-security-scan.sh --all
$AP --tags monitoring,targets,validation
$AP --tags ssl --check
ansible-playbook -i $PROD_INV ansible/playbooks/test-glusterfs.yml
```

### JCasC Hot-Reload (New Playbook)
```bash
# Dry-run for single team
ansible-playbook -i $PROD_INV ansible/playbooks/jcasc-hot-reload.yml \
  -e "jcasc_teams_input=devops" \
  -e "jcasc_environments_input=both" \
  --check

# Update all teams (both blue/green)
ansible-playbook -i $PROD_INV ansible/playbooks/jcasc-hot-reload.yml \
  -e "jcasc_teams_input=all" \
  -e "jcasc_environments_input=both"

# Update specific teams
ansible-playbook -i $PROD_INV ansible/playbooks/jcasc-hot-reload.yml \
  -e "jcasc_teams_input=devops,ma"

# Manual rollback
cp /var/jenkins/devops/backups/current.yaml.{latest} \
   /var/jenkins/devops/configs/current.yaml
curl -X POST -u admin:TOKEN http://localhost:8080/configuration-as-code/reload

# View audit log
tail -f /var/log/jenkins/jcasc-updates.log

# Check config state
cat /var/jenkins/devops/config-state.json | jq .

# See docs/jcasc-hot-reload-guide.md for details
```

### Option 2 Multi-VM Architecture
```bash
# 3 VMs: Jenkins Blue + Jenkins Green + Monitoring
# Migration: 60-90 minutes total (4 phases)

# Full migration
ansible-playbook -i $PROD_INV ansible/playbooks/migrate-to-option2-multi-vm.yml

# Specific phases
... --tags phase1  # Monitoring (10-15 min)
... --tags phase2  # GlusterFS (15-20 min)
... --tags phase3  # HAProxy (5-10 min)
... --tags phase4  # Jenkins (40-60 min)

# Validation
... --tags validation --check
... --tags final-validation

# Component deployments
$AP --tags monitoring --limit monitoring
$AP --tags glusterfs --limit glusterfs_servers
$AP --tags high-availability --limit load_balancers
$AP --tags jenkins --limit jenkins_masters

# Verify
curl -u admin:admin123 http://<vm-ip>:8404/stats
ansible glusterfs_servers -m command -a "gluster peer status"
curl http://<monitoring-vm>:9090/api/v1/targets | jq
```

### Pre-commit & Code Quality
```bash
make dev-setup
source ./activate-dev-env.sh
make test-full

# Validation
make test-groovy              # Full Groovy validation
make test-groovy-basic        # Basic validation
make test-jenkinsfiles        # Jenkinsfile structure
make test-dsl                 # DSL with security
make test-jenkins-security    # Security patterns

# Pre-commit management
make pre-commit-install
make pre-commit-run
make pre-commit-update

# Enhanced DSL validator
./scripts/dsl-syntax-validator.sh --dsl-path jenkins-dsl/ --security-check --complexity-check
```

### GlusterFS Operations
```bash
# Deploy server cluster
$AP --tags glusterfs

# Mount volumes
$AP --tags storage

# Comprehensive tests
ansible-playbook -i $PROD_INV ansible/playbooks/test-glusterfs.yml --tags service,peers,volumes,replication

# Health & metrics
sudo /usr/local/bin/gluster-health-check.sh
sudo tail -f /var/log/gluster-health.log
sudo /usr/local/bin/gluster-metrics-exporter.sh
cat /var/lib/node_exporter/textfile_collector/gluster.prom

# Migration
sudo ./scripts/migrate-to-glusterfs.sh --dry-run
sudo ./scripts/migrate-to-glusterfs.sh
sudo ./scripts/migrate-to-glusterfs.sh --team devops

# Manual operations
sudo gluster peer status
sudo gluster volume list
sudo gluster volume status
sudo gluster volume info jenkins-devops-data
sudo gluster volume heal jenkins-devops-data info

# Verify mounts
df -h | grep glusterfs
findmnt -t fuse.glusterfs
ls -la /var/jenkins/*/data

# Hybrid sync (Docker volumes + GlusterFS)
$AP --tags jenkins,gluster,sync
/usr/local/bin/jenkins-sync-to-gluster-devops.sh
tail -f /var/log/jenkins-glusterfs-sync-devops.log
./scripts/blue-green-switch-with-gluster.sh devops green
./scripts/jenkins-failover-from-gluster.sh devops blue vm1 vm2
/usr/local/bin/jenkins-recover-from-gluster-devops.sh devops blue

# Workspace retention
$AP --tags glusterfs,retention
/usr/local/bin/glusterfs-workspace-cleanup.sh devops 10 --dry-run
/usr/local/bin/glusterfs-workspace-cleanup.sh devops 10
/usr/local/bin/glusterfs-workspace-report.sh
tail -f /var/log/glusterfs-retention/devops-cleanup.log
```

### Monitoring Operations

#### Deployment
```bash
# Separate VM monitoring (auto-detects from inventory)
$AP --tags monitoring --limit monitoring
$AP --tags monitoring,firewall --limit monitoring

# Cross-VM exporters
$AP --tags monitoring,cross-vm --limit jenkins_masters

# Full deployment
$AP --tags monitoring

# Verify
ansible monitoring -m debug -a "var=monitoring_deployment_type"
```

#### Health Checks & Verification
```bash
# Run health check
/opt/monitoring/scripts/monitoring-health.sh

# Check services
curl http://<monitoring-vm>:9090/-/healthy    # Prometheus
curl http://<monitoring-vm>:9300/api/health   # Grafana
curl http://<monitoring-vm>:9400/ready        # Loki

# View logs
docker logs prometheus-production
docker logs grafana-production
docker logs loki-production
docker logs promtail-monitoring-production

# Jenkins VMs
docker logs promtail-jenkins-vm1-production
curl http://<jenkins-vm>:9100/metrics         # Node Exporter
curl http://<jenkins-vm>:9200/metrics         # cAdvisor
curl http://<jenkins-vm>:9401/ready           # Promtail

# Agent health
ssh jenkins-vm1 '/usr/local/bin/monitoring/agent-health-check.sh'
ssh jenkins-vm1 'tail -f /var/log/monitoring-agents/health-check.log'
ssh jenkins-vm1 'systemctl status monitoring-agent-health.timer'
```

#### Jenkins Job Logs with Loki
```bash
# Query log labels
curl http://<monitoring-vm>:9400/loki/api/v1/labels

# Query team logs
curl -G http://<monitoring-vm>:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins-job-logs", team="devops"}' \
  --data-urlencode 'limit=100'

# Query specific job/build
curl -G http://<monitoring-vm>:9400/loki/api/v1/query_range \
  --data-urlencode 'query={job="jenkins-job-logs", job_name="my-pipeline", build_number="42"}' \
  --data-urlencode 'limit=1000'

# Grafana Explore
# http://<monitoring-vm>:9300/explore
# {job="jenkins-job-logs", team="devops"}
# {job="jenkins-job-logs"} |= "ERROR"
```

#### FQDN Configuration
```bash
# Add to inventory: host_fqdn, monitoring_fqdn
# Setup DNS or /etc/hosts
sudo tee -a /etc/hosts <<EOF
192.168.188.142 centos9-vm.internal.local monitoring.internal.local
EOF

# Test resolution
dig +short centos9-vm.internal.local
ping -c 2 monitoring.internal.local

# Deploy with FQDN (default)
$AP --tags monitoring

# Deploy with IP mode
$AP --tags monitoring -e "monitoring_use_fqdn=false"

# Verify
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep targets:
docker exec promtail-jenkins-vm1-production cat /etc/promtail/promtail-config.yml | grep url:
curl http://monitoring.internal.local:9090/api/v1/targets | jq
```

#### Grafana Plugins (GitHub & Jira)
```bash
# Deploy with plugins
$AP --tags monitoring

# Verify
docker exec grafana-production grafana-cli plugin ls
curl -u admin:password http://localhost:9300/api/datasources | jq

# Test datasources
curl -u admin:password http://localhost:9300/api/datasources/uid/github-enterprise/health
curl -u admin:password http://localhost:9300/api/datasources/uid/jira-cloud/health

# Update plugins
docker exec grafana-production grafana-cli plugin update grafana-github-datasource
docker restart grafana-production

# Troubleshoot
docker inspect grafana-production | grep -A 20 '"Env"'
docker exec grafana-production printenv | grep GF_INSTALL_PLUGINS
docker logs grafana-production | grep -i plugin
cat examples/github-jira-datasource-integration.md
```

#### Modernization (File-SD & Grafonnet)
```bash
# Phase 1: File-based Service Discovery
$AP --tags monitoring,phase1-file-sd -e "prometheus_file_sd_enabled=true"

# Verify
ls -la /opt/monitoring/prometheus/targets.d/
python3 -m json.tool /opt/monitoring/prometheus/targets.d/jenkins-devops.json
curl http://localhost:9090/api/v1/targets | jq
docker exec prometheus-production cat /etc/prometheus/prometheus.yml | grep -A 5 "file_sd_configs"

# Phase 2: Grafonnet Dashboards
$AP --tags monitoring,phase2-dashboards,grafonnet -e "grafonnet_enabled=true"
$AP --tags monitoring,phase4-dashboards,setup-grafonnet
$AP --tags monitoring,phase4-dashboards,generate
$AP --tags monitoring,phase4-dashboards,test

# View structure
ls -la /opt/grafonnet/
ls -la /opt/monitoring/grafana/dashboards/generated/

# Verify
python3 -m json.tool /opt/monitoring/grafana/dashboards/generated/infrastructure-health.json
curl -u admin:password http://localhost:9300/api/dashboards/uid/infrastructure-health-modern | jq

# Manual compilation
cd /opt/grafonnet
jsonnet -J vendor infrastructure-health.jsonnet -o infrastructure-health.json
jb install  # Update dependencies
```

#### Dashboard Management (Simple JSON)
```bash
# Simple JSON dashboard deployment (Phase 5.6 - Simplified Alternative)
# No complex templating, minimal variables, static JSON files

# Enable simple JSON dashboards in defaults/main.yml:
# grafana_json_enabled: true
# dashboard_deployment_method: "file"  # or "api"

# Initial deployment (file-based, requires Grafana restart)
$AP --tags monitoring,phase5.6,dashboards,deploy

# Quick updates via API (no restart, 30 seconds)
ansible-playbook -i $PROD_INV playbooks/update-dashboards.yml

# Or use tags for API deployment
$AP --tags monitoring,phase5.6,dashboards,update -e "dashboard_deployment_method=api"

# Dashboard files location
ls -la ansible/roles/monitoring/files/dashboards/json/

# Add new dashboard
# 1. Create JSON file: ansible/roles/monitoring/files/dashboards/json/my-dashboard.json
# 2. Add to list in defaults/main.yml:
#    grafana_json_dashboards:
#      - jenkins-overview.json
#      - infrastructure-health.json
#      - jenkins-builds.json
#      - my-dashboard.json  # NEW
# 3. Deploy:
ansible-playbook -i $PROD_INV playbooks/update-dashboards.yml

# Export existing dashboard from Grafana
curl -u admin:password "http://localhost:9300/api/dashboards/uid/DASHBOARD_UID" | \
  jq '.dashboard | del(.id, .uid, .version)' > my-dashboard.json

# Benefits:
# - 0-3 variables (vs 30-50+ in Jinja2)
# - Static JSON files (no templating)
# - Fast updates (30 sec via API)
# - Simple maintenance (10 lines vs 150+)
# - Use Grafana $team variable instead of team-specific dashboards
```

### Keepalived & HAProxy
```bash
# Deploy intelligent keepalived
$AP --tags high-availability,keepalived

# Monitor
tail -f /var/log/keepalived-backend-health.log
tail -f /var/log/keepalived-haproxy-check.log

# Test failover
docker stop jenkins-ba-blue
ip addr show | grep 192.168.1.100

# Cross-VM monitoring
# Set haproxy_backend_failover_strategy in ansible/roles/high-availability-v2/defaults/main.yml
# Options: active-passive (HA), active-active (load balancing), local-only (no cross-VM)
$AP --tags high-availability,haproxy
curl -u admin:admin123 http://192.168.1.100:8404/stats
docker logs -f jenkins-haproxy --tail 100 | grep backend
```

### Microsoft Teams Alerting
```bash
# Deploy with Teams integration
$AP --tags monitoring,alertmanager

# Manage alerts
docker exec alertmanager-production amtool check-config /etc/alertmanager/alertmanager.yml
docker exec alertmanager-production amtool config show
docker exec alertmanager-production amtool alert query

# Silence alerts
docker exec alertmanager-production amtool silence add \
  alertname="JenkinsMasterDown" team="devops" \
  --duration=2h --comment="Planned maintenance"

# View silences
docker exec alertmanager-production amtool silence query
docker exec alertmanager-production amtool silence expire <SILENCE_ID>

# Test webhook
curl -H "Content-Type: application/json" \
  -d '{"text":"Test from Alertmanager"}' \
  "https://company.webhook.office.com/webhookb2/YOUR_WEBHOOK_URL"

# Logs & routing
docker logs alertmanager-production -f | grep -i teams
docker exec alertmanager-production amtool config routes
```

### Environment Setup
```bash
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml
scripts/generate-credentials.sh production
ansible-vault create ansible/inventories/production/group_vars/all/vault.yml
scripts/ha-setup.sh production full
scripts/disaster-recovery.sh production --validate
```

## Architecture Overview

### Core Components
- **Blue-Green Jenkins**: Multi-team with zero-downtime deployments, active-only (50% resource reduction)
- **HAProxy**: Dynamic routing, health checks, SLI monitoring, team discovery
- **Dynamic SSL**: Team-based wildcard certificates auto-generated from jenkins_teams
- **Dynamic Agents**: Container-based (maven, python, nodejs, dind) on-demand
- **Job DSL**: Code-driven with security sandboxing, production-safe
- **Monitoring**: Prometheus/Grafana/Loki/Alertmanager, 26-panel dashboards, DORA metrics
- **Backup & DR**: Enterprise-grade (RTO 15min, RPO 5min), automated procedures
- **Hybrid GlusterFS**: Local Docker volumes + periodic rsync + VM-to-VM replication (RPO 5min, RTO <2min)
- **Security**: Trivy scanning, constraints, compliance validation, pre-commit hooks (25+ patterns)

### Deployment Flow
1. Pre-deployment validation
2. GlusterFS setup (if enabled)
3. Bootstrap infrastructure
4. Jenkins image building (with scanning)
5. Blue-green deployment
6. HAProxy setup
7. Job DSL seed creation
8. Monitoring & backup setup
9. Security scanning
10. Post-deployment verification

### Key Ansible Roles
- `glusterfs-server`: GlusterFS 10.x automation with replication, health monitoring
- `shared-storage`: Multi-backend (local/NFS/GlusterFS) with team volumes
- `jenkins-master-v2`: Unified deployment, active-only containers, 55% code reduction
- `high-availability-v2`: HA config, dynamic SSL, blue-green support
- `monitoring`: Prometheus/Grafana stack, phase-based (67% reduction), GitHub/Jira integration
- `security`: Trivy scanning, hardening, compliance validation
- `common`: System bootstrap, pre-deployment validation

### Environment Configuration
- **Production**: `environments/production.env` and `ansible/inventories/production/`
- **Local**: `environments/local.env` and `ansible/inventories/local/`
- **Vault**: Encrypted in `ansible/inventories/*/group_vars/all/vault.yml`

### Pipeline Definitions
Located in `pipelines/` with enhanced security:
- `Jenkinsfile.infrastructure-update`: Automated rollback, SLI monitoring
- `Jenkinsfile.backup`: Validation and reporting
- `Jenkinsfile.disaster-recovery`: RTO/RPO compliance
- `Jenkinsfile.monitoring`: SLI configuration
- `Jenkinsfile.security-scan`: Trivy scanning
- `Jenkinsfile.image-builder`: Vulnerability scanning
- `Jenkinsfile.health-check`: Multi-layer validation

### Job DSL Scripts
Located in `jenkins-dsl/` with security:
- `folders.groovy`: Folder structure
- `views.groovy`: View definitions
- `infrastructure/secure-ansible-executor.groovy`: Secure execution with sandboxing
- `infrastructure/*.groovy`: Infrastructure pipelines
- `applications/*.groovy`: Sample applications

### Inventory Groups
- `jenkins_masters`: Blue-green master nodes
- `monitoring`: Prometheus/Grafana stack
- `load_balancers`: HAProxy nodes
- `shared_storage`: NFS/GlusterFS nodes
- `glusterfs_servers`: GlusterFS cluster

### Script Utilities
- `scripts/deploy.sh`: Deployment wrapper
- `scripts/disaster-recovery.sh`: Automated DR (508 lines)
- `scripts/ha-setup.sh`: HA automation (559 lines)
- `scripts/blue-green-switch.sh`: Environment switching
- `scripts/monitor.sh`: Monitoring management
- `/usr/local/bin/jenkins-security-scan.sh`: Trivy automation
- `/usr/local/bin/jenkins-security-monitor.sh`: Real-time monitoring

## Important Notes

### Blue-Green Deployment
- Active-only deployment (50% resource reduction)
- HAProxy routes to active environment only
- Jenkins deploys active containers only
- Team-independent switching
- Zero-downtime switching via HAProxy Runtime API
- Enhanced monitoring with rollback automation
- Volume preservation for instant switching

### Security & Secrets
- Vault-encrypted credentials with rotation
- Trivy vulnerability scanning
- Container security constraints (non-root, non-privileged, read-only)
- Runtime monitoring with alerting
- Dynamic SSL/TLS with team-aware certificates
- RBAC with team isolation
- Pre-commit security validation (25+ patterns):
  - Critical risk detection (System.exit, Runtime, ProcessBuilder)
  - Code injection prevention (GroovyShell, evaluate)
  - Credential exposure prevention
  - Shell injection protection
  - File system security (path traversal)
  - Jenkins-specific security
  - Privilege escalation prevention

### Monitoring & Alerting
- Enhanced Prometheus rules (SLI/SLO)
- 26-panel Grafana dashboards (DORA metrics)
- Active environment monitoring only (no false alerts)
- HAProxy statistics and health
- Per-team security metrics
- Container security monitoring
- Automated rollback integration
- 130+ pre-configured alert rules
- Microsoft Teams integration

### Backup & Recovery
- Enterprise backup system (automated schedules)
- DR procedures (RTO 15min, RPO 5min)
- Team config backup (encrypted shared storage)
- Blue-green DR with validation
- Database backup (point-in-time recovery)
- Version controlled recovery
- DR site management (automated failover)
- RTO/RPO compliance tracking

### Development & Code Quality
- Pre-commit framework with validation pipeline
- Groovy validation (22 files, compiler integration)
- Jenkinsfile validation (7 files, best practices)
- Security scanning (25+ patterns)
- Best practices enforcement
- GitHub Actions integration
- Development environment automation
- Complexity analysis with reporting
- Always update documentation in repository
- Use code-searcher for code scanning
- Never use Unicode emoji symbols in code
- Always use bash-executor for bash commands
