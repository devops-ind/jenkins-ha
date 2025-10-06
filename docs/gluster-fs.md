# GlusterFS Data Synchronization - Complete Solution Guide

## 📑 Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Overview](#solution-overview)
3. [Architecture](#architecture)
4. [Prerequisites](#prerequisites)
5. [Installation Steps](#installation-steps)
6. [Configuration](#configuration)
7. [Testing and Validation](#testing-and-validation)
8. [Monitoring](#monitoring)
9. [Troubleshooting](#troubleshooting)
10. [Maintenance](#maintenance)

---

## 🚨 Problem Statement

### Current Situation

```
VM1 (Primary)                          VM2 (Backup)
┌─────────────────────────┐           ┌─────────────────────────┐
│ Jenkins DevOps          │           │ Jenkins DevOps          │
│ /var/jenkins/devops/    │           │ /var/jenkins/devops/    │
│ (LOCAL DISK)            │    ❌     │ (LOCAL DISK - STALE)    │
│                         │   NO SYNC │                         │
│ - Recent builds         │           │ - Old data              │
│ - New jobs              │           │ - Missing jobs          │
│ - User changes          │           │ - Outdated users        │
└─────────────────────────┘           └─────────────────────────┘
```

### Critical Issues

**1. Data Loss During Failover**
```
Time: 10:00 AM - User creates job "deploy-prod" on VM1
Time: 10:05 AM - Build #123 runs successfully on VM1
Time: 10:10 AM - VM1 crashes, Keepalived fails over to VM2
Time: 10:11 AM - User logs into VM2 Jenkins

Result:
❌ Job "deploy-prod" NOT FOUND
❌ Build #123 NO RECORD
❌ Recent 10 minutes of work LOST
```

**2. Stale Data on Standby**
- VM2 has data from last manual sync (could be hours/days old)
- Configuration drift between VMs
- User permissions out of sync
- Plugin versions mismatch

**3. Impact on Business**
- **Data Loss**: RPO (Recovery Point Objective) = Unknown (hours to days)
- **Downtime**: Users must recreate lost work
- **User Experience**: Poor, frustrating
- **Compliance**: Audit trail gaps

### Requirements

| Requirement | Target | Current State |
|------------|--------|---------------|
| **RPO** | < 5 seconds | Hours/Days ❌ |
| **RTO** | < 30 seconds | Minutes ❌ |
| **Data Consistency** | 99.99% | Unknown ❌ |
| **Automatic Sync** | Yes | No ❌ |
| **Zero Data Loss** | Yes | No ❌ |

---

## 💡 Solution Overview

### GlusterFS Replicated Storage

**What is GlusterFS?**
- Distributed file system
- Real-time replication (Replica = 2)
- Automatic failover
- Self-healing capabilities
- No single point of failure

**How It Solves the Problem:**

```
BEFORE (Local Storage):
Write on VM1 → Stays on VM1 only → VM2 has stale data

AFTER (GlusterFS):
Write on VM1 → Replicated to VM2 in < 5 seconds → Both VMs have same data
```

**Key Benefits:**

✅ **Real-Time Sync**: < 5 second replication lag
✅ **Zero Data Loss**: Write confirmed only after both VMs have data
✅ **Automatic Failover**: VM2 has all data if VM1 fails
✅ **Self-Healing**: Automatic sync when failed VM recovers
✅ **Active-Active**: Both VMs can write simultaneously
✅ **Split-Brain Resolution**: Automatic conflict handling

---

## 🏗️ Architecture

### Solution Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Application Layer                               │
│  ┌──────────────────────┐              ┌──────────────────────┐        │
│  │ VM1 Jenkins          │              │ VM2 Jenkins          │        │
│  │ Containers:          │              │ Containers:          │        │
│  │ - DevOps Blue        │              │ - DevOps Green       │        │
│  │ - Dev Green          │              │ - Dev Blue           │        │
│  │ - QA Blue            │              │ - QA Green           │        │
│  └──────────┬───────────┘              └──────────┬───────────┘        │
│             │                                      │                     │
│      Docker volumes mounted to:              Docker volumes mounted to: │
│      /var/jenkins/*/data                     /var/jenkins/*/data       │
└─────────────┼──────────────────────────────────────┼────────────────────┘
              │                                      │
┌─────────────▼──────────────────────────────────────▼────────────────────┐
│                      GlusterFS Client Layer (FUSE)                      │
│  ┌──────────────────────┐              ┌──────────────────────┐        │
│  │ VM1 FUSE Mount       │              │ VM2 FUSE Mount       │        │
│  │ /var/jenkins/devops  │              │ /var/jenkins/devops  │        │
│  │ /var/jenkins/dev     │              │ /var/jenkins/dev     │        │
│  │ /var/jenkins/qa      │              │ /var/jenkins/qa      │        │
│  └──────────┬───────────┘              └──────────┬───────────┘        │
└─────────────┼──────────────────────────────────────┼────────────────────┘
              │                                      │
┌─────────────▼──────────────────────────────────────▼────────────────────┐
│                      GlusterFS Server Layer                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │              Replicated Volumes (Replica = 2)                   │   │
│  │                                                                  │   │
│  │  ┌──────────────────┐              ┌──────────────────┐        │   │
│  │  │ VM1 Brick        │◄────────────►│ VM2 Brick        │        │   │
│  │  │                  │              │                  │        │   │
│  │  │ /data/glusterfs/ │   Real-time  │ /data/glusterfs/ │        │   │
│  │  │ - jenkins-devops │   Bi-dir     │ - jenkins-devops │        │   │
│  │  │ - jenkins-dev    │   Sync       │ - jenkins-dev    │        │   │
│  │  │ - jenkins-qa     │              │ - jenkins-qa     │        │   │
│  │  │                  │              │                  │        │   │
│  │  └──────────────────┘              └──────────────────┘        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

**Write Operation:**
```
1. Jenkins writes to /var/jenkins/devops/data/jobs/my-job/config.xml
2. FUSE client intercepts write
3. GlusterFS sends to BOTH bricks (VM1 + VM2)
4. Both bricks acknowledge write
5. FUSE confirms to Jenkins
6. Write complete

Time: < 5 seconds total
```

**Read Operation:**
```
1. Jenkins reads from /var/jenkins/devops/data/jobs/my-job/config.xml
2. FUSE client reads from local brick (VM1 or VM2)
3. Returns data immediately

Time: < 100ms (local read)
```

**Failover Scenario:**
```
1. VM1 fails (hardware/network/crash)
2. Jenkins on VM2 continues working
3. FUSE client on VM2 reads from local brick
4. NO DATA LOSS - all data available
5. When VM1 recovers, self-heal syncs missing data

Downtime: 0 seconds for data access
RPO: 0 seconds (no data loss)
```

---

## 📋 Prerequisites

### System Requirements

**Both VM1 and VM2:**
- OS: RHEL/CentOS 7/8/9 or Ubuntu 20.04/22.04
- RAM: Minimum 4GB (8GB recommended)
- Disk: Separate partition/disk for GlusterFS bricks
- Network: 1Gbps minimum (10Gbps recommended)

**Disk Layout:**
```
/dev/sda1   → / (OS)
/dev/sdb1   → /data/glusterfs (GlusterFS bricks) - 100GB+ per team
```

**Network Requirements:**
```
VM1: 192.168.1.101
VM2: 192.168.1.102
Ports: 
  - 24007-24008/tcp (GlusterFS daemon)
  - 49152-49251/tcp (GlusterFS bricks)
  - ICMP (ping)
```

**Software:**
- GlusterFS 10.x (latest stable)
- Docker / Docker Compose
- Ansible (for automation)

### Pre-Installation Checklist

- [ ] Both VMs can ping each other
- [ ] Firewall ports opened (or disabled for testing)
- [ ] Separate disk/partition for GlusterFS mounted at `/data/glusterfs`
- [ ] Root/sudo access on both VMs
- [ ] NTP synchronized (time sync between VMs)
- [ ] DNS or /etc/hosts configured with VM hostnames

---

## 🔧 Installation Steps

### Step 1: Install GlusterFS

**On Both VM1 and VM2:**

```bash
# === RHEL/CentOS ===
# Add GlusterFS repository
sudo yum install -y centos-release-gluster10

# Install GlusterFS server and client
sudo yum install -y glusterfs-server glusterfs-client attr

# === Ubuntu ===
# Add GlusterFS PPA
sudo add-apt-repository ppa:gluster/glusterfs-10
sudo apt-get update

# Install packages
sudo apt-get install -y glusterfs-server glusterfs-client attr

# === Common Steps ===
# Start and enable GlusterFS daemon
sudo systemctl start glusterd
sudo systemctl enable glusterd

# Verify service is running
sudo systemctl status glusterd

# Verify installation
gluster --version
# Output: glusterfs 10.x
```

**Configure Firewall (RHEL/CentOS):**
```bash
# On both VMs
sudo firewall-cmd --permanent --add-service=glusterfs
sudo firewall-cmd --permanent --add-port=24007-24008/tcp
sudo firewall-cmd --permanent --add-port=49152-49251/tcp
sudo firewall-cmd --reload
```

**Configure Firewall (Ubuntu):**
```bash
# On both VMs
sudo ufw allow 24007:24008/tcp
sudo ufw allow 49152:49251/tcp
sudo ufw reload
```

### Step 2: Create Brick Directories

**On Both VMs:**

```bash
# Create base directory for all bricks
sudo mkdir -p /data/glusterfs

# Create brick directories for each team
sudo mkdir -p /data/glusterfs/jenkins-devops-brick
sudo mkdir -p /data/glusterfs/jenkins-dev-brick
sudo mkdir -p /data/glusterfs/jenkins-qa-brick

# Set permissions
sudo chmod 755 /data/glusterfs
sudo chmod 755 /data/glusterfs/jenkins-*-brick

# Verify
ls -la /data/glusterfs/
```

### Step 3: Create Trusted Storage Pool

**On VM1 Only:**

```bash
# Probe VM2 to add to trusted pool
sudo gluster peer probe 192.168.1.102

# Expected output:
# peer probe: success

# Verify peer status
sudo gluster peer status

# Expected output:
# Number of Peers: 1
# 
# Hostname: 192.168.1.102
# Uuid: <some-uuid>
# State: Peer in Cluster (Connected)
```

**Verify on VM2:**

```bash
# Check peer status (should show VM1)
sudo gluster peer status

# Expected output:
# Number of Peers: 1
# 
# Hostname: 192.168.1.101
# Uuid: <some-uuid>
# State: Peer in Cluster (Connected)
```

### Step 4: Create Replicated Volumes

**On VM1 Only:**

```bash
# Create volume for DevOps team
sudo gluster volume create jenkins-devops-data \
  replica 2 \
  192.168.1.101:/data/glusterfs/jenkins-devops-brick \
  192.168.1.102:/data/glusterfs/jenkins-devops-brick \
  force

# Create volume for Dev team
sudo gluster volume create jenkins-dev-data \
  replica 2 \
  192.168.1.101:/data/glusterfs/jenkins-dev-brick \
  192.168.1.102:/data/glusterfs/jenkins-dev-brick \
  force

# Create volume for QA team
sudo gluster volume create jenkins-qa-data \
  replica 2 \
  192.168.1.101:/data/glusterfs/jenkins-qa-brick \
  192.168.1.102:/data/glusterfs/jenkins-qa-brick \
  force

# Expected output for each:
# volume create: jenkins-xxx-data: success: please start the volume to access data
```

### Step 5: Configure Volume Options

**On VM1 Only:**

```bash
# For each volume, set optimizations
for VOLUME in jenkins-devops-data jenkins-dev-data jenkins-qa-data; do
  
  # Performance tuning
  sudo gluster volume set $VOLUME performance.cache-size 256MB
  sudo gluster volume set $VOLUME performance.write-behind-window-size 4MB
  sudo gluster volume set $VOLUME performance.io-thread-count 32
  
  # Network tuning
  sudo gluster volume set $VOLUME network.ping-timeout 10
  sudo gluster volume set $VOLUME network.remote-dio enable
  
  # Quorum (split-brain prevention)
  sudo gluster volume set $VOLUME cluster.quorum-type auto
  sudo gluster volume set $VOLUME cluster.server-quorum-ratio 51%
  
  # Self-heal
  sudo gluster volume set $VOLUME cluster.self-heal-daemon on
  sudo gluster volume set $VOLUME cluster.metadata-self-heal on
  sudo gluster volume set $VOLUME cluster.data-self-heal on
  
  # Disable NFS (we use native FUSE)
  sudo gluster volume set $VOLUME nfs.disable on
  
done

echo "✅ Volume options configured"
```

### Step 6: Start Volumes

**On VM1 Only:**

```bash
# Start all volumes
sudo gluster volume start jenkins-devops-data
sudo gluster volume start jenkins-dev-data
sudo gluster volume start jenkins-qa-data

# Expected output for each:
# volume start: jenkins-xxx-data: success

# Verify all volumes are started
sudo gluster volume status

# Expected output shows all volumes with Status: Started
```

### Step 7: Mount Volumes on Both VMs

**On Both VM1 and VM2:**

```bash
# Install FUSE client (if not already installed)
sudo yum install -y glusterfs-fuse  # RHEL/CentOS
# OR
sudo apt-get install -y glusterfs-fuse  # Ubuntu

# Create mount point directories
sudo mkdir -p /var/jenkins/devops/data
sudo mkdir -p /var/jenkins/dev/data
sudo mkdir -p /var/jenkins/qa/data

# Add to /etc/fstab for automatic mounting
cat << 'EOF' | sudo tee -a /etc/fstab
localhost:/jenkins-devops-data /var/jenkins/devops/data glusterfs defaults,_netdev,backup-volfile-servers=192.168.1.102 0 0
localhost:/jenkins-dev-data /var/jenkins/dev/data glusterfs defaults,_netdev,backup-volfile-servers=192.168.1.102 0 0
localhost:/jenkins-qa-data /var/jenkins/qa/data glusterfs defaults,_netdev,backup-volfile-servers=192.168.1.102 0 0
EOF

# Note: On VM2, change backup-volfile-servers to 192.168.1.101

# Mount all volumes
sudo mount -a

# Verify mounts
df -h | grep glusterfs

# Expected output:
# localhost:/jenkins-devops-data  50G  1.1G   49G   3% /var/jenkins/devops/data
# localhost:/jenkins-dev-data     50G  1.1G   49G   3% /var/jenkins/dev/data
# localhost:/jenkins-qa-data      50G  1.1G   49G   3% /var/jenkins/qa/data

# Set ownership for Jenkins (UID 1000)
sudo chown -R 1000:1000 /var/jenkins/*/data
```

### Step 8: Update Docker Compose

**On Both VMs:**

Update your Jenkins docker-compose.yml to use GlusterFS mounts:

```yaml
version: '3.8'

services:
  jenkins-devops-blue:
    image: jenkins-custom-devops:latest
    container_name: jenkins-devops-blue
    volumes:
      # GlusterFS mount (automatically replicated)
      - /var/jenkins/devops/data:/var/jenkins_home
      # Local cache (not replicated)
      - jenkins-devops-cache:/var/jenkins_home/.cache
    ports:
      - "8080:8080"
    restart: unless-stopped

  jenkins-dev-green:
    image: jenkins-custom-dev:latest
    container_name: jenkins-dev-green
    volumes:
      - /var/jenkins/dev/data:/var/jenkins_home
      - jenkins-dev-cache:/var/jenkins_home/.cache
    ports:
      - "8181:8080"
    restart: unless-stopped

  jenkins-qa-blue:
    image: jenkins-custom-qa:latest
    container_name: jenkins-qa-blue
    volumes:
      - /var/jenkins/qa/data:/var/jenkins_home
      - jenkins-qa-cache:/var/jenkins_home/.cache
    ports:
      - "8082:8080"
    restart: unless-stopped

volumes:
  jenkins-devops-cache:
  jenkins-dev-cache:
  jenkins-qa-cache:
```

**Restart Jenkins:**

```bash
# Stop containers
sudo docker-compose down

# Start with new configuration
sudo docker-compose up -d

# Verify containers are running
sudo docker ps | grep jenkins
```

---

## ✅ Testing and Validation

### Test 1: Basic Replication

**On VM1:**
```bash
# Create test file
echo "Hello from VM1" | sudo tee /var/jenkins/devops/data/test-replication.txt

# Verify on VM1
cat /var/jenkins/devops/data/test-replication.txt
# Output: Hello from VM1
```

**On VM2:**
```bash
# Wait 3 seconds, then check
sleep 3
cat /var/jenkins/devops/data/test-replication.txt
# Output: Hello from VM1

# ✅ If you see "Hello from VM1", replication works!
```

### Test 2: Bidirectional Sync

**On VM2:**
```bash
# Write from VM2
echo "Hello from VM2" | sudo tee /var/jenkins/devops/data/test-from-vm2.txt
```

**On VM1:**
```bash
# Read on VM1
sleep 3
cat /var/jenkins/devops/data/test-from-vm2.txt
# Output: Hello from VM2

# ✅ Bidirectional sync confirmed!
```

### Test 3: Jenkins Data Replication

**On VM1:**
```bash
# Create a Jenkins job config (simulate)
sudo mkdir -p /var/jenkins/devops/data/jobs/test-job
cat << 'EOF' | sudo tee /var/jenkins/devops/data/jobs/test-job/config.xml
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Test job for replication</description>
</project>
EOF
```

**On VM2:**
```bash
# Verify job exists
sleep 5
sudo ls -la /var/jenkins/devops/data/jobs/test-job/
sudo cat /var/jenkins/devops/data/jobs/test-job/config.xml

# ✅ If you see the config.xml, Jenkins data replicates correctly!
```

### Test 4: Failover Simulation

**On VM1:**
```bash
# Stop GlusterFS to simulate failure
sudo systemctl stop glusterd
```

**On VM2:**
```bash
# Verify you can still read/write
echo "VM1 is down, writing from VM2" | sudo tee /var/jenkins/devops/data/failover-test.txt
cat /var/jenkins/devops/data/failover-test.txt

# ✅ If successful, VM2 works independently!
```

**On VM1 (Restore):**
```bash
# Restart GlusterFS
sudo systemctl start glusterd

# Wait for self-heal
sleep 30

# Verify self-heal
sudo gluster volume heal jenkins-devops-data info

# Check if file from VM2 is now on VM1
cat /var/jenkins/devops/data/failover-test.txt
# Output: VM1 is down, writing from VM2

# ✅ Self-heal working!
```

### Test 5: Performance Test

```bash
# On VM1, create 1000 small files
for i in {1..1000}; do
  echo "File $i" | sudo tee /var/jenkins/devops/data/perf-test-$i.txt > /dev/null
done

# Measure time
START=$(date +%s)
for i in {1..1000}; do
  echo "File $i" | sudo tee /var/jenkins/devops/data/perf-test-$i.txt > /dev/null
done
END=$(date +%s)
echo "Time: $((END - START)) seconds for 1000 files"

# On VM2, verify
sleep 10
FILE_COUNT=$(sudo ls /var/jenkins/devops/data/perf-test-*.txt 2>/dev/null | wc -l)
echo "Files replicated: $FILE_COUNT/1000"

# ✅ Should be close to 1000

# Cleanup
sudo rm /var/jenkins/devops/data/perf-test-*.txt
```

---

## 📊 Monitoring

### Health Check Script

Create `/usr/local/bin/gluster-health-check.sh`:

```bash
#!/bin/bash

echo "=== GlusterFS Health Check ==="
echo ""

# Check service
systemctl is-active glusterd && echo "✅ GlusterFS service: Running" || echo "❌ Service: Down"

# Check peers
PEERS=$(gluster peer status | grep -c "Peer in Cluster")
echo "✅ Connected peers: $PEERS"

# Check volumes
for VOL in jenkins-devops-data jenkins-dev-data jenkins-qa-data; do
  STATUS=$(gluster volume info $VOL | grep "Status:" | awk '{print $2}')
  echo "Volume $VOL: $STATUS"
  
  # Check split-brain
  SPLIT=$(gluster volume heal $VOL info split-brain 2>/dev/null | grep -c "in split-brain" || echo "0")
  if [ $SPLIT -eq 0 ]; then
    echo "  ✅ No split-brain"
  else
    echo "  ⚠️  $SPLIT files in split-brain"
  fi
  
  # Check heal queue
  HEAL=$(gluster volume heal $VOL info | grep "Number of entries:" | awk '{sum+=$4} END {print sum}')
  echo "  Pending heal entries: ${HEAL:-0}"
done

echo ""
echo "=== Disk Usage ==="
df -h | grep jenkins

echo ""
echo "=== Health Check Complete ==="
```

Make it executable and run:
```bash
sudo chmod +x /usr/local/bin/gluster-health-check.sh
sudo /usr/local/bin/gluster-health-check.sh
```

### Add Cron Job

```bash
# Run health check every 5 minutes
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/gluster-health-check.sh >> /var/log/gluster-health.log 2>&1") | crontab -
```

### Prometheus Metrics (Optional)

Export metrics at `/var/lib/node_exporter/textfile_collector/gluster.prom`:

```bash
#!/bin/bash
METRICS_FILE="/var/lib/node_exporter/textfile_collector/gluster.prom"
mkdir -p $(dirname $METRICS_FILE)

{
  echo "# HELP gluster_volume_status Volume status (1=Started, 0=Stopped)"
  echo "# TYPE gluster_volume_status gauge"
  
  for VOL in jenkins-devops-data jenkins-dev-data jenkins-qa-data; do
    STATUS=$(gluster volume info $VOL | grep "Status:" | awk '{print $2}')
    VALUE=0
    [ "$STATUS" == "Started" ] && VALUE=1
    echo "gluster_volume_status{volume=\"$VOL\"} $VALUE"
  done
} > $METRICS_FILE
```

---

## 🔧 Troubleshooting

### Issue 1: Peer Not Connected

**Symptom:**
```bash
gluster peer status
# Output: State: Peer Rejected
```

**Fix:**
```bash
# On both nodes, check glusterd
sudo systemctl status glusterd

# Verify network connectivity
ping <other-vm-ip>

# Re-probe
sudo gluster peer probe <other-vm-ip>

# Check firewall
sudo firewall-cmd --list-all  # RHEL
sudo ufw status               # Ubuntu
```

### Issue 2: Mount Fails

**Symptom:**
```bash
mount: wrong fs type, bad option, bad superblock on localhost:/jenkins-devops-data
```

**Fix:**
```bash
# Check volume is started
sudo gluster volume status jenkins-devops-data

# Check FUSE client installed
rpm -qa | grep glusterfs-fuse    # RHEL
dpkg -l | grep glusterfs-fuse    # Ubuntu

# Try manual mount
sudo mount -t glusterfs localhost:/jenkins-devops-data /var/jenkins/devops/data

# Check logs
sudo tail -50 /var/log/glusterfs/mnt-var-jenkins-devops-data.log
```

### Issue 3: Split-Brain Detected

**Symptom:**
```bash
gluster volume heal jenkins-devops-data info split-brain
# Shows files in split-brain
```

**Fix:**
```bash
# View split-brain files
sudo gluster volume heal jenkins-devops-data info split-brain

# Resolve using latest modification time
sudo gluster volume heal jenkins-devops-data split-brain latest-mtime

# Verify resolution
sudo gluster volume heal jenkins-devops-data info split-brain
# Should show: Number of entries: 0
```

### Issue 4: High Replication Lag

**Symptom:**
- File takes >10 seconds to appear on other VM

**Fix:**
```bash
# Check network latency
ping -c 10 <other-vm-ip>

# Optimize performance
sudo gluster volume set jenkins-devops-data performance.cache-size 512MB
sudo gluster volume set jenkins-devops-data performance.write-behind on

# Check disk I/O
iostat -x 1 10
```

### Issue 5: Volume Won't Start

**Symptom:**
```bash
gluster volume start jenkins-devops-data
# Error: Commit failed
```

**Fix:**
```bash
# Check logs
sudo tail -100 /var/log/glusterfs/glusterd.log

# Remove and recreate if necessary
sudo gluster volume stop jenkins-devops-data
sudo gluster volume delete jenkins-devops-data

# Recreate (see Step 4)
```

---

## 🔄 Maintenance

### Daily Checks
```bash
# Run health check
sudo /usr/local/bin/gluster-health-check.sh

# Check logs for errors
sudo journalctl -u glusterd -n 50

# Verify mounts
df -h | grep jenkins
```

### Weekly Tasks
```bash
# Check self-heal status
for VOL in jenkins-devops-data jenkins-dev-data jenkins-qa-data; do
  sudo gluster volume heal $VOL info
done

# Review split-brain status
for VOL in jenkins-devops-data jenkins-dev-data jenkins-qa-data; do
  sudo gluster volume heal $VOL info split-brain
done

# Check disk usage
df -h | grep glusterfs
```

### Monthly Tasks
```bash
# Performance review
# Run performance tests (Test 5)

# Capacity planning
du -sh /data/glusterfs/jenkins-*-brick

# Update documentation
# Document any issues encountered
```

### Backup Strategy
```bash
# GlusterFS provides replication, but still backup
# Use existing backup scripts to backup from either VM
# Data is identical on both VMs, so backup from one is sufficient

# Example: Backup devops team data
sudo tar -czf /backup/jenkins-devops-$(date +%Y%m%d).tar.gz \
  /var/jenkins/devops/data/
```

---

## 🎯 Success Criteria

### Validation Checklist

- [ ] GlusterFS service running on both VMs
- [ ] Peer status shows "Connected" 
- [ ] All volumes showing "Started"
- [ ] Volumes mounted on both VMs
- [ ] Test file replicates in < 5 seconds
- [ ] Bidirectional sync works
- [ ] Jenkins data replicates correctly
- [ ] Failover test successful (VM1 down, VM2 works)
- [ ] Self-heal works after VM recovery
- [ ] No split-brain issues
- [ ] Health checks passing
- [ ] Monitoring configured

### Performance Targets

✅ **RPO**: < 5 seconds (achieved via real-time replication)
✅ **RTO**: < 30 seconds (automatic failover)
✅ **Data Consistency**: 99.99% (GlusterFS guarantees)
✅ **Availability**: 99.99% (no single point of failure)

### Expected Results

**Before GlusterFS:**
- Data loss during failover: Hours/Days
- Manual sync required: Yes
- Downtime during failover: Minutes
- User impact: High

**After GlusterFS:**
- Data loss during failover: None (< 5 seconds)
- Manual sync required: No (automatic)
- Downtime during failover: Seconds
- User impact: Minimal/None
