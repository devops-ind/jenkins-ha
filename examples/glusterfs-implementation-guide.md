# GlusterFS Implementation Guide - Ansible Automation

Complete guide for implementing GlusterFS replicated storage in the Jenkins HA infrastructure using Ansible automation.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Configuration](#configuration)
6. [Deployment](#deployment)
7. [Testing and Validation](#testing-and-validation)
8. [Migration from Local/NFS](#migration-from-localnfs)
9. [Monitoring and Maintenance](#monitoring-and-maintenance)
10. [Troubleshooting](#troubleshooting)

---

## Overview

This guide automates the complete GlusterFS setup described in [docs/gluster-fs.md](../docs/gluster-fs.md) using Ansible, providing:

✅ **Real-Time Replication**: < 5 second RPO (Recovery Point Objective)
✅ **Zero Data Loss**: Write confirmed only after both VMs have data
✅ **Automatic Failover**: VM2 has all data if VM1 fails (< 30s RTO)
✅ **Self-Healing**: Automatic sync when failed VM recovers
✅ **Team-Based Volumes**: Separate replicated volumes per team
✅ **Automated Deployment**: Complete infrastructure-as-code

### What Gets Automated

- GlusterFS 10.x server installation (RHEL/Ubuntu)
- Firewall configuration (ports 24007-24008, 49152-49251)
- Brick directory creation for each team
- Trusted storage pool formation (peer probing)
- Replicated volume creation (replica=2)
- Volume performance optimization
- Health monitoring and Prometheus metrics
- Client mounting with automatic failover

---

## Architecture

### Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Jenkins HA Infrastructure                          │
│                                                                         │
│  ┌──────────────────────┐              ┌──────────────────────┐        │
│  │ VM1 (Primary)        │              │ VM2 (Secondary)      │        │
│  │ 192.168.188.142     │              │ 192.168.188.143      │        │
│  │                      │              │                      │        │
│  │ ┌─────────────────┐ │              │ ┌─────────────────┐ │        │
│  │ │ Jenkins Masters │ │              │ │ Jenkins Masters │ │        │
│  │ │ - DevOps        │ │              │ │ - DevOps        │ │        │
│  │ │ - Dev           │ │              │ │ - Dev           │ │        │
│  │ │ - QA            │ │              │ │ - QA            │ │        │
│  │ └─────────┬───────┘ │              │ └─────────┬───────┘ │        │
│  │           │ Mounts  │              │           │ Mounts  │        │
│  │           ▼         │              │           ▼         │        │
│  │ /var/jenkins/*/data │              │ /var/jenkins/*/data │        │
│  │    (GlusterFS)      │              │    (GlusterFS)      │        │
│  └──────────┬──────────┘              └──────────┬──────────┘        │
│             │                                    │                    │
└─────────────┼────────────────────────────────────┼────────────────────┘
              │                                    │
┌─────────────▼────────────────────────────────────▼────────────────────┐
│                      GlusterFS Cluster Layer                           │
│  ┌──────────────────────┐              ┌──────────────────────┐        │
│  │ VM1 GlusterFS Server │◄────────────►│ VM2 GlusterFS Server │        │
│  │                      │  Peer Probe  │                      │        │
│  │ Volumes (Replica=2): │              │ Volumes (Replica=2): │        │
│  │ - jenkins-devops-data│              │ - jenkins-devops-data│        │
│  │ - jenkins-dev-data   │              │ - jenkins-dev-data   │        │
│  │ - jenkins-qa-data    │              │ - jenkins-qa-data    │        │
│  │                      │              │                      │        │
│  │ Bricks:              │              │ Bricks:              │        │
│  │ /data/glusterfs/     │              │ /data/glusterfs/     │        │
│  │ - jenkins-devops-brick│             │ - jenkins-devops-brick│       │
│  │ - jenkins-dev-brick  │              │ - jenkins-dev-brick  │        │
│  │ - jenkins-qa-brick   │              │ - jenkins-qa-brick   │        │
│  └──────────────────────┘              └──────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

**Write Operation** (Write on VM1, replicate to VM2):
```
1. Jenkins writes /var/jenkins/devops/data/jobs/my-job/config.xml
2. GlusterFS client intercepts write (FUSE layer)
3. GlusterFS sends to BOTH bricks (VM1 + VM2) - Replica 2
4. Both bricks acknowledge write
5. GlusterFS confirms to Jenkins
6. Time: < 5 seconds
```

**Failover Scenario** (VM1 fails, VM2 continues):
```
1. VM1 crashes (hardware/network failure)
2. Jenkins on VM2 continues reading from local brick
3. NO DATA LOSS - VM2 has complete replica
4. When VM1 recovers, self-heal syncs missing data
5. RPO: 0 seconds, RTO: < 30 seconds
```

---

## Prerequisites

### System Requirements

**Both VM1 and VM2:**
- OS: RHEL/CentOS 7/8/9 or Ubuntu 20.04/22.04
- RAM: Minimum 4GB (8GB recommended)
- CPU: 2+ cores
- Disk: Separate partition/disk for GlusterFS bricks (100GB+ per team)
- Network: 1Gbps minimum (10Gbps recommended)

**Recommended Disk Layout:**
```
/dev/sda1   → / (OS and applications)
/dev/sdb1   → /data/glusterfs (GlusterFS bricks - dedicated disk)
```

**Network Configuration:**
```
VM1: 192.168.188.142 (Primary)
VM2: 192.168.188.143 (Secondary)
Required Ports:
  - 24007-24008/tcp (GlusterFS daemon)
  - 49152-49251/tcp (GlusterFS bricks)
  - ICMP (ping for health checks)
```

### Software Requirements

- Ansible 2.9+
- Python 3.6+
- SSH access to both VMs
- sudo/root privileges

---

## Quick Start

### 1. Update Inventory

Edit `ansible/inventories/production/hosts.yml`:

```yaml
glusterfs_servers:
  hosts:
    centos9-vm:
      ansible_host: 192.168.188.142
    centos9-vm2:
      ansible_host: 192.168.188.143
```

### 2. Configure Storage Type

Edit `ansible/inventories/production/group_vars/all/main.yml`:

```yaml
shared_storage_enabled: true
shared_storage_type: "glusterfs"  # Change from "local" or "nfs"
```

### 3. Deploy GlusterFS

```bash
# Deploy GlusterFS server infrastructure
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags glusterfs

# Mount GlusterFS volumes on clients
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags storage

# Deploy Jenkins with GlusterFS storage
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins
```

### 4. Validate Deployment

```bash
# Run comprehensive tests
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/test-glusterfs.yml
```

---

## Configuration

### GlusterFS Server Configuration

File: `ansible/inventories/production/group_vars/glusterfs_servers.yml`

```yaml
# Cluster configuration
glusterfs_cluster_nodes:
  - 192.168.188.142
  - 192.168.188.143

glusterfs_primary_node: "centos9-vm"
glusterfs_replica_count: 2

# Brick storage
glusterfs_brick_base_path: "/data/glusterfs"

# Team-based volumes (auto-created from jenkins_teams)
glusterfs_create_team_volumes: true
glusterfs_team_volume_prefix: "jenkins"
glusterfs_team_volume_suffix: "data"

# Performance tuning
glusterfs_performance_options:
  performance.cache-size: "512MB"
  performance.write-behind-window-size: "4MB"
  performance.io-thread-count: "32"
  network.ping-timeout: "10"
  network.remote-dio: "enable"

# Self-healing
glusterfs_self_heal_options:
  cluster.self-heal-daemon: "on"
  cluster.metadata-self-heal: "on"
  cluster.data-self-heal: "on"

# Monitoring
glusterfs_monitoring_enabled: true
glusterfs_metrics_enabled: true
```

### Volume Naming Convention

Volumes are automatically created based on `jenkins_teams`:

```
Team Name: devops
Volume Name: jenkins-devops-data
Brick Path: /data/glusterfs/jenkins-devops-brick
Mount Path: /var/jenkins/devops/data
```

---

## Deployment

### Full Infrastructure Deployment

```bash
# Complete deployment (GlusterFS + Jenkins + Monitoring)
make deploy-production

# Or using Ansible directly
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml
```

### GlusterFS-Only Deployment

```bash
# Deploy only GlusterFS server
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags glusterfs

# Deploy only storage mounting
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags storage
```

### Deployment Order

The playbook automatically handles deployment order:

1. **Pre-deployment Validation** (system requirements)
2. **GlusterFS Server Setup** (both nodes in parallel)
   - Install packages
   - Configure firewall
   - Create brick directories
   - Form trusted storage pool (peer probe)
   - Create and configure volumes
3. **Bootstrap Infrastructure** (common, docker, security)
4. **Shared Storage Mounting** (mount GlusterFS volumes)
5. **Jenkins Deployment** (with GlusterFS volumes)
6. **Monitoring Setup** (Prometheus/Grafana)

---

## Testing and Validation

### Automated Test Suite

```bash
# Run all GlusterFS tests
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/test-glusterfs.yml

# Run specific test categories
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/test-glusterfs.yml --tags service,peers,volumes

# Skip cleanup (keep test files for inspection)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/test-glusterfs.yml -e cleanup_test_files=false
```

### Test Coverage

The test playbook includes 8 comprehensive tests:

1. **Service Status**: Verify glusterd is running
2. **Peer Connectivity**: Check trusted storage pool
3. **Volume Status**: Verify all volumes are started
4. **Mount Points**: Validate GlusterFS mounts
5. **Basic Replication**: Write on VM1, read on VM2
6. **Bidirectional Sync**: Write from both VMs
7. **Split-Brain Check**: Detect and report conflicts
8. **Performance Test**: 100-file replication test

### Manual Validation

```bash
# Check service status
sudo systemctl status glusterd

# Check peer status
sudo gluster peer status

# Check volume status
sudo gluster volume status

# Check volume info
sudo gluster volume info jenkins-devops-data

# Check mounts
df -h | grep glusterfs

# Check for split-brain
sudo gluster volume heal jenkins-devops-data info split-brain

# Check heal queue
sudo gluster volume heal jenkins-devops-data info
```

---

## Migration from Local/NFS

### Automated Migration

Use the migration script for safe migration:

```bash
# Preview migration (dry-run)
sudo ./scripts/migrate-to-glusterfs.sh --dry-run

# Migrate all teams
sudo ./scripts/migrate-to-glusterfs.sh

# Migrate specific team
sudo ./scripts/migrate-to-glusterfs.sh --team devops

# Use custom backup path
sudo ./scripts/migrate-to-glusterfs.sh --backup-path /backup/jenkins
```

### Migration Process

The script performs:

1. **Pre-migration backup** (compressed tar.gz)
2. **GlusterFS setup** (via Ansible)
3. **Stop Jenkins containers**
4. **Data migration** (rsync with progress)
5. **Ownership fix** (jenkins:jenkins)
6. **Start Jenkins** (with GlusterFS)
7. **Validation** (mount points, data integrity)
8. **Rollback script generation** (in case of issues)

### Rollback

If migration fails, use the auto-generated rollback script:

```bash
# Located in backup directory
sudo /opt/jenkins-migration-backup/rollback_YYYYMMDD_HHMMSS.sh
```

---

## Monitoring and Maintenance

### Health Monitoring

**Automated Health Checks:**
```bash
# Manual health check
sudo /usr/local/bin/gluster-health-check.sh

# View health log
sudo tail -f /var/log/gluster-health.log

# Health checks run automatically every 5 minutes via cron
```

**Health Check Output:**
```
=== GlusterFS Health Check ===
1. Service Status:
   ✅ GlusterFS service: Running

2. Peer Status:
   ✅ Connected peers: 1

3. Volume Status:
   Volume: jenkins-devops-data
      ✅ Status: Started
      ✅ Split-brain: None
      ✅ Heal queue: Empty
```

### Prometheus Metrics

**Metrics Collection:**
```bash
# Manual metrics generation
sudo /usr/local/bin/gluster-metrics-exporter.sh

# View metrics
cat /var/lib/node_exporter/textfile_collector/gluster.prom

# Metrics update automatically every 2 minutes
```

**Available Metrics:**
- `glusterfs_service_up`: Service status (1=up, 0=down)
- `glusterfs_peer_count`: Number of connected peers
- `glusterfs_volume_status`: Volume status per volume
- `glusterfs_volume_split_brain_count`: Split-brain files
- `glusterfs_volume_heal_pending`: Pending heal entries
- `glusterfs_brick_disk_used_bytes`: Brick disk usage
- `glusterfs_brick_disk_total_bytes`: Brick disk capacity

### Grafana Dashboard

Create dashboard with queries:
```promql
# Service uptime
glusterfs_service_up{node="centos9-vm"}

# Peer connectivity
glusterfs_peer_count{node="centos9-vm"}

# Volume health
glusterfs_volume_status{volume="jenkins-devops-data"}

# Disk usage percentage
(glusterfs_brick_disk_used_bytes / glusterfs_brick_disk_total_bytes) * 100
```

### Maintenance Tasks

**Daily:**
```bash
sudo /usr/local/bin/gluster-health-check.sh
```

**Weekly:**
```bash
# Check self-heal status
for vol in $(gluster volume list); do
  gluster volume heal $vol info
done

# Check disk usage
df -h | grep glusterfs
```

**Monthly:**
```bash
# Performance review
du -sh /data/glusterfs/jenkins-*-brick

# Review logs
journalctl -u glusterd --since "30 days ago"
```

---

## Troubleshooting

### Issue 1: Peer Not Connected

**Symptom:**
```bash
$ gluster peer status
State: Peer Rejected
```

**Solution:**
```bash
# Check glusterd service
sudo systemctl status glusterd

# Check network connectivity
ping 192.168.188.143

# Re-probe peer
sudo gluster peer probe 192.168.188.143

# Check firewall
sudo firewall-cmd --list-all
sudo ufw status
```

### Issue 2: Volume Won't Mount

**Symptom:**
```
mount: wrong fs type, bad option, bad superblock
```

**Solution:**
```bash
# Check volume is started
sudo gluster volume status jenkins-devops-data

# Check FUSE client
rpm -qa | grep glusterfs-fuse    # RHEL
dpkg -l | grep glusterfs-fuse    # Ubuntu

# Check mount logs
sudo tail -f /var/log/glusterfs/*.log

# Try manual mount
sudo mount -t glusterfs localhost:/jenkins-devops-data /var/jenkins/devops/data
```

### Issue 3: Split-Brain Detected

**Symptom:**
```bash
$ gluster volume heal jenkins-devops-data info split-brain
Number of entries: 5
```

**Solution:**
```bash
# Resolve using latest modification time
sudo gluster volume heal jenkins-devops-data split-brain latest-mtime

# Verify resolution
sudo gluster volume heal jenkins-devops-data info split-brain
```

### Issue 4: Slow Replication

**Symptom:** Files take > 10 seconds to replicate

**Solution:**
```bash
# Check network latency
ping -c 10 192.168.188.143

# Optimize performance
sudo gluster volume set jenkins-devops-data performance.cache-size 512MB
sudo gluster volume set jenkins-devops-data performance.write-behind on

# Check disk I/O
iostat -x 1 10
```

### Issue 5: Deployment Fails

**Check Ansible logs:**
```bash
# Increase verbosity
ansible-playbook ansible/site.yml --tags glusterfs -vvv

# Check specific role
ansible-playbook ansible/site.yml --tags glusterfs --start-at-task="Create volumes"

# Verify inventory
ansible-inventory -i ansible/inventories/production/hosts.yml --graph
```

---

## Success Criteria

### Validation Checklist

After deployment, verify:

- [ ] GlusterFS service running on both VMs
- [ ] Peer status shows "Connected"
- [ ] All volumes showing "Started"
- [ ] Volumes mounted on both VMs
- [ ] Test file replicates in < 5 seconds
- [ ] Bidirectional sync works
- [ ] Jenkins data replicates correctly
- [ ] Failover test successful
- [ ] Self-heal works after VM recovery
- [ ] No split-brain issues
- [ ] Health checks passing
- [ ] Prometheus metrics collecting

### Performance Targets

✅ **RPO**: < 5 seconds (real-time replication)
✅ **RTO**: < 30 seconds (automatic failover)
✅ **Data Consistency**: 99.99% (GlusterFS guarantees)
✅ **Availability**: 99.99% (no single point of failure)

---

## References

- [Original Manual Setup Guide](../docs/gluster-fs.md)
- [GlusterFS Documentation](https://docs.gluster.org/)
- [Ansible Role: glusterfs-server](../ansible/roles/glusterfs-server/)
- [Ansible Role: shared-storage](../ansible/roles/shared-storage/)
- [Test Playbook](../ansible/playbooks/test-glusterfs.yml)
- [Migration Script](../scripts/migrate-to-glusterfs.sh)

---

## Support

For issues or questions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review health check logs: `/var/log/gluster-health.log`
3. Run test suite: `ansible-playbook ansible/playbooks/test-glusterfs.yml`
4. Check GlusterFS logs: `/var/log/glusterfs/`

---

**Last Updated**: 2025-01-05
**Version**: 1.0.0
