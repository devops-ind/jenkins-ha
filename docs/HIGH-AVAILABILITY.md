# HIGH AVAILABILITY

## Overview

This document describes the High Availability configuration for Jenkins infrastructure, including load balancing, failover mechanisms, and cluster management. The HA setup ensures continuous service availability with minimal downtime and automatic recovery capabilities.

## Table of Contents

- [HA Architecture](#ha-architecture)
- [Load Balancer Configuration](#load-balancer-configuration)
- [Jenkins Master Clustering](#jenkins-master-clustering)
- [Shared Storage HA](#shared-storage-ha)
- [Failover Procedures](#failover-procedures)
- [Monitoring and Health Checks](#monitoring-and-health-checks)
- [Maintenance Procedures](#maintenance-procedures)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)

## HA Architecture

### Design Principles

The Jenkins HA infrastructure is designed with the following principles:

- **Active-Passive Configuration**: One active Jenkins master with standby masters ready for failover
- **Shared State**: All masters share the same Jenkins home directory via distributed storage
- **Load Balancing**: HAProxy distributes traffic and provides health monitoring
- **Automatic Failover**: Keepalived manages Virtual IP (VIP) for seamless failover
- **Container Isolation**: Each Jenkins master runs in isolated containers with systemd management

### Components Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    HA Architecture                         │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
│  │   Client    │    │   Client    │    │   Client    │      │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘      │
│         │                  │                  │             │
│         └──────────────────┼──────────────────┘             │
│                            │                                │
│                    ┌───────▼────────┐                       │
│                    │  Virtual IP    │                       │
│                    │  (10.0.1.10)   │                       │
│                    └───────┬────────┘                       │
│                            │                                │
│            ┌───────────────▼────────────────┐               │
│            │         HAProxy LB             │               │
│            │   - Health Checks              │               │
│            │   - Session Persistence        │               │
│            │   - SSL Termination            │               │
│            │   - Stats Dashboard            │               │
│            └───────────────┬────────────────┘               │
│                            │                                │
│     ┌──────────────────────┼──────────────────────┐         │
│     │                      │                      │         │
│ ┌───▼─────┐        ┌───────▼────┐        ┌────────▼───┐     │
│ │Master-1 │        │ Master-2   │        │ Master-N   │     │
│ │(Active) │        │(Standby)   │        │(Standby)   │     │
│ │Port:8080│        │Port:8081   │        │Port:808N   │     │
│ └───┬─────┘        └───────┬────┘        └────────┬───┘     │
│     │                      │                      │         │
│     └──────────────────────┼──────────────────────┘         │
│                            │                                │
│                   ┌────────▼─────────┐                      │
│                   │  Shared Storage  │                      │
│                   │   (NFS/GlusterFS)│                      │
│                   │ - Jenkins Home   │                      │
│                   │ - Configurations │                      │
│                   │ - Build Data     │                      │
│                   └──────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

### HA Modes

#### Active-Passive (Default)
- **Primary Master**: Handles all requests and executes builds
- **Secondary Masters**: Standby mode, monitoring shared storage for changes
- **Failover**: Automatic promotion of secondary to primary on failure
- **Benefits**: Simple configuration, data consistency, resource efficiency

#### Active-Active (Advanced)
- **Multiple Active Masters**: Load distributed across multiple masters
- **Session Affinity**: Users stick to the same master for session consistency
- **Build Distribution**: Builds can execute on any available master
- **Benefits**: Better performance, load distribution

## Load Balancer Configuration

### HAProxy Setup

The HA role automatically configures HAProxy with the following features:

#### Configuration Overview
```haproxy
global
    daemon
    log 127.0.0.1:514 local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    
defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    option httplog
    
frontend jenkins_frontend
    bind *:80
    bind *:443 ssl crt /etc/ssl/certs/jenkins.pem
    redirect scheme https if !{ ssl_fc }
    default_backend jenkins_masters
    
backend jenkins_masters
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200
    cookie JSESSIONID prefix indirect nocache
    
    server jenkins-master-1 10.0.2.10:8080 check inter 5s fall 3 rise 2 cookie master1
    server jenkins-master-2 10.0.2.11:8081 check inter 5s fall 3 rise 2 cookie master2 backup
    
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
```

#### Key Features
- **Health Checks**: Regular health monitoring every 5 seconds
- **Session Persistence**: Cookie-based session stickiness
- **SSL Termination**: HTTPS handling at load balancer level
- **Statistics Dashboard**: Real-time monitoring on port 8404
- **Graceful Failover**: Automatic detection and traffic redirection

### Keepalived VIP Management

#### Virtual IP Configuration
```bash
# Keepalived master configuration
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass changeme
    }
    virtual_ipaddress {
        10.0.1.10/24
    }
    track_script {
        chk_haproxy
    }
}

# Health check script
vrrp_script chk_haproxy {
    script "/usr/local/bin/check_haproxy.sh"
    interval 2
    weight -2
    fall 3
    rise 2
}
```

#### Failover Process
1. **Detection**: Health check script detects HAProxy failure
2. **Priority Adjustment**: Failed node priority reduced
3. **VIP Migration**: Backup node takes over VIP
4. **Gratuitous ARP**: Network updated with new MAC address
5. **Traffic Redirection**: Clients connect to new active node

## Jenkins Master Clustering

### Container-Based Masters

Each Jenkins master runs in an isolated container with systemd management:

#### Master Container Configuration
```yaml
# Container specifications per master
jenkins-master-1:
  ports:
    - "8080:8080"
    - "50000:50000"
  volumes:
    - "jenkins-home-1:/opt/jenkins"
    - "jenkins-shared:/shared/jenkins"
    - "/var/run/docker.sock:/var/run/docker.sock"
  environment:
    - JAVA_OPTS=-Djenkins.install.runSetupWizard=false
    - JENKINS_OPTS=--httpPort=8080
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8080/login"]
    interval: 30s
    timeout: 10s
    retries: 3
```

#### Systemd Service Integration
```ini
[Unit]
Description=Jenkins Master 1 Container
Requires=docker.service
After=docker.service network.target

[Service]
Type=forking
ExecStartPre=-/usr/bin/docker stop jenkins-master-1
ExecStartPre=-/usr/bin/docker rm jenkins-master-1
ExecStart=/usr/bin/docker run --name jenkins-master-1 [container-options]
ExecStop=/usr/bin/docker stop jenkins-master-1
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
```

### Configuration Synchronization

#### Shared Jenkins Home
- **Location**: `/shared/jenkins` (mounted on all masters)
- **Contents**: 
  - Configuration files (config.xml, credentials, etc.)
  - Installed plugins and updates
  - Job definitions and history
  - User accounts and permissions
  - System logs and audit trails

#### Configuration as Code (JCasC)
```yaml
# jenkins.yaml - JCasC configuration
jenkins:
  mode: NORMAL
  numExecutors: 0
  primaryView:
    all:
      name: "All Jobs"
  views:
  - all:
      name: "All Jobs"
  - buildMonitor:
      includeRegex: ".*"
      name: "Build Monitor"
      
security:
  globalJobDslSecurityConfiguration:
    useScriptSecurity: false
  scriptApproval:
    approvedSignatures:
    - "staticMethod org.codehaus.groovy.runtime.DefaultGroovyMethods leftShift java.lang.Object java.lang.Object"
```

## Shared Storage HA

### NFS High Availability

#### NFS Server Configuration
```bash
# NFS exports configuration
/export/jenkins *(rw,sync,no_subtree_check,no_root_squash)

# NFS server clustering with Pacemaker/Corosync
pcs cluster setup nfs-cluster nfs-node1 nfs-node2
pcs cluster start --all
pcs resource create nfs-server systemd:nfs-server
pcs resource create nfs-ip IPaddr2 ip=10.0.4.100
pcs constraint colocation add nfs-ip with nfs-server
```

#### Client Mount Options
```bash
# Optimized mount options for Jenkins
10.0.4.100:/export/jenkins /shared/jenkins nfs4 \
  rw,hard,intr,rsize=32768,wsize=32768,vers=4.1,timeo=600 0 0
```

### GlusterFS Distributed Storage

#### Volume Configuration
```bash
# Create distributed replicated volume
gluster volume create jenkins-vol replica 3 \
  gluster-node1:/data/jenkins \
  gluster-node2:/data/jenkins \
  gluster-node3:/data/jenkins

# Optimize for Jenkins workload
gluster volume set jenkins-vol performance.cache-size 256MB
gluster volume set jenkins-vol performance.write-behind-window-size 4MB
gluster volume set jenkins-vol performance.read-ahead on
```

## Failover Procedures

### Automatic Failover

#### Detection and Response
1. **Health Check Failure**: HAProxy detects Jenkins master failure
2. **Service Isolation**: Failed master removed from load balancer pool
3. **Traffic Redirection**: New requests routed to healthy masters
4. **Container Restart**: Systemd attempts to restart failed containers
5. **VIP Failover**: If primary node fails, keepalived migrates VIP

#### Failover Timeline
- **Detection**: 5-15 seconds (based on health check interval)
- **Traffic Redirection**: < 5 seconds
- **Service Recovery**: 30-60 seconds (container restart)
- **Total Downtime**: < 2 minutes (typical)

### Manual Failover

#### Planned Maintenance
```bash
# 1. Put master in maintenance mode
curl -X POST "http://jenkins-master-1:8080/quietDown" -u admin:password

# 2. Wait for running builds to complete
curl -s "http://jenkins-master-1:8080/api/json" | jq '.jobs[].lastBuild.building'

# 3. Remove from load balancer
sudo systemctl stop jenkins-master-1

# 4. Perform maintenance
# ... maintenance tasks ...

# 5. Restart and verify
sudo systemctl start jenkins-master-1
curl -I http://jenkins-master-1:8080/login
```

#### Emergency Failover
```bash
# Force immediate failover
sudo systemctl stop keepalived  # On current master
sudo systemctl stop jenkins-master-1

# Verify VIP migration
ip addr show | grep 10.0.1.10

# Check new active master
curl -I http://10.0.1.10:8080/login
```

## Monitoring and Health Checks

### Health Check Scripts

#### Jenkins Master Health Check
```bash
#!/bin/bash
# /usr/local/bin/jenkins-ha-healthcheck.sh

JENKINS_URL="http://localhost:8080"
HEALTH_ENDPOINT="${JENKINS_URL}/login"
MAX_RETRIES=3
RETRY_DELAY=5

for i in $(seq 1 $MAX_RETRIES); do
    if curl -f -s --max-time 10 "$HEALTH_ENDPOINT" > /dev/null 2>&1; then
        echo "Jenkins health check passed"
        exit 0
    fi
    echo "Jenkins health check failed (attempt $i/$MAX_RETRIES)"
    sleep $RETRY_DELAY
done

echo "Jenkins health check failed after $MAX_RETRIES attempts"
exit 1
```

#### Comprehensive Monitoring
```bash
#!/bin/bash
# /usr/local/bin/jenkins-ha-monitor.sh

LOG_FILE="/var/log/jenkins-ha-monitor.log"
ALERT_EMAIL="admin@company.com"

check_jenkins_master() {
    local master_url=$1
    local master_name=$2
    
    if curl -f -s --max-time 10 "$master_url/api/json" > /dev/null; then
        echo "$(date): $master_name is healthy" >> $LOG_FILE
        return 0
    else
        echo "$(date): $master_name is unhealthy" >> $LOG_FILE
        return 1
    fi
}

check_shared_storage() {
    if [ -w "/shared/jenkins" ]; then
        echo "$(date): Shared storage is accessible" >> $LOG_FILE
        return 0
    else
        echo "$(date): Shared storage is not accessible" >> $LOG_FILE
        return 1
    fi
}

check_load_balancer() {
    if curl -f -s --max-time 5 "http://localhost:8404/stats" > /dev/null; then
        echo "$(date): Load balancer is healthy" >> $LOG_FILE
        return 0
    else
        echo "$(date): Load balancer is unhealthy" >> $LOG_FILE
        return 1
    fi
}

# Main monitoring loop
check_jenkins_master "http://jenkins-master-1:8080" "Jenkins Master 1"
check_jenkins_master "http://jenkins-master-2:8081" "Jenkins Master 2"
check_shared_storage
check_load_balancer
```

### Prometheus Metrics

#### Jenkins Metrics
```yaml
# Jenkins Prometheus plugin configuration
jenkins:
  metrics:
    prometheus:
      enabled: true
      path: /prometheus
      
# Custom metrics collected:
# - jenkins_node_builds_count
# - jenkins_queue_size
# - jenkins_health_check_score
# - jenkins_plugins_active_count
# - jenkins_job_duration_seconds
```

#### HAProxy Metrics
```bash
# HAProxy Prometheus exporter
docker run -d \
  --name haproxy-exporter \
  -p 9101:9101 \
  prom/haproxy-exporter \
  --haproxy.scrape-uri="http://localhost:8404/stats;csv"
```

## Maintenance Procedures

### Rolling Updates

#### Jenkins Version Updates
```bash
# Update Jenkins masters one by one
for master in jenkins-master-1 jenkins-master-2; do
    echo "Updating $master..."
    
    # Put in maintenance mode
    curl -X POST "http://$master:8080/quietDown" -u admin:password
    
    # Wait for builds to complete
    sleep 60
    
    # Stop service
    sudo systemctl stop $master
    
    # Update container image
    ansible-playbook -i ansible/inventories/production/hosts.yml \
      ansible/site.yml \
      --tags jenkins-images \
      --limit $(hostname)
    
    # Start service
    sudo systemctl start $master
    
    # Verify health
    while ! curl -f http://localhost:8080/login; do
        echo "Waiting for $master to start..."
        sleep 10
    done
    
    # Remove maintenance mode
    curl -X POST "http://$master:8080/cancelQuietDown" -u admin:password
    
    echo "$master updated successfully"
done
```

### Configuration Updates

#### JCasC Configuration Reload
```bash
# Update configuration without restart
curl -X POST "http://jenkins-master-1:8080/configuration-as-code/reload" \
  -u admin:password

# Verify configuration
curl -s "http://jenkins-master-1:8080/configuration-as-code/checkNewSource" \
  -u admin:password
```

### Backup Procedures

#### Automated Backup Integration
```bash
# Backup before maintenance
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/backup-restore.yml \
  --tags backup \
  -e backup_type=maintenance \
  -e backup_retention=7
```

## Troubleshooting

### Common HA Issues

#### Split-Brain Scenarios
**Symptom**: Multiple masters active simultaneously
```bash
# Check VIP ownership
ip addr show | grep 10.0.1.10

# Check keepalived status on all nodes
ansible jenkins_masters -m shell -a "systemctl status keepalived"

# Force VIP to specific node
sudo systemctl stop keepalived  # On all nodes except desired master
sudo systemctl start keepalived  # On desired master
```

#### Session Persistence Issues
**Symptom**: Users getting logged out frequently
```bash
# Check HAProxy session configuration
curl -s http://localhost:8404/stats | grep JSESSIONID

# Verify cookie settings in Jenkins
curl -I http://10.0.1.10:8080/login

# Clear browser cookies and test
# Check for time synchronization issues
ansible jenkins_masters -m shell -a "timedatectl status"
```

#### Shared Storage Problems
**Symptom**: Configuration inconsistencies between masters
```bash
# Check mount status
ansible jenkins_masters -m shell -a "mount | grep jenkins"

# Verify file permissions
ansible jenkins_masters -m shell -a "ls -la /shared/jenkins"

# Test write access
ansible jenkins_masters -m shell -a "touch /shared/jenkins/test && rm /shared/jenkins/test"

# Check NFS/GlusterFS logs
tail -f /var/log/nfs.log
gluster volume status jenkins-vol
```

### Performance Issues

#### Load Balancer Optimization
```bash
# Monitor connection distribution
watch -n 5 'curl -s http://localhost:8404/stats | grep jenkins-master'

# Adjust load balancing algorithm
# Edit /etc/haproxy/haproxy.cfg
balance leastconn  # Change from roundrobin

# Reload configuration
sudo systemctl reload haproxy
```

#### Master Resource Optimization
```bash
# Monitor container resources
docker stats jenkins-master-1

# Adjust JVM settings
docker exec jenkins-master-1 jinfo -flags 1

# Update container resource limits
docker update --memory=4g jenkins-master-1
```

## Performance Tuning

### Optimal Configuration

#### HAProxy Tuning
```haproxy
global
    maxconn 4096
    nbproc 2
    spread-checks 5
    
defaults
    maxconn 2048
    timeout http-request 10s
    timeout queue 30s
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    
backend jenkins_masters
    balance leastconn
    option httpchk GET /api/json
    http-check expect status 200
    default-server check inter 10s fastinter 2s downinter 5s rise 2 fall 3
```

#### Jenkins JVM Tuning
```bash
# Recommended JVM settings for HA masters
JAVA_OPTS="
-Xmx4g
-Xms2g
-XX:+UseG1GC
-XX:+UseStringDeduplication
-XX:+DisableExplicitGC
-XX:+UnlockExperimentalVMOptions
-XX:+UseCGroupMemoryLimitForHeap
-Djava.awt.headless=true
-Dhudson.DNSMultiCast.disabled=true
-Djenkins.install.runSetupWizard=false
"
```

### Capacity Planning

#### Scaling Guidelines
- **2 Masters**: Up to 500 jobs, 50 concurrent builds
- **3 Masters**: Up to 1000 jobs, 100 concurrent builds  
- **4+ Masters**: Enterprise scale, custom sizing required

#### Resource Monitoring
```bash
# Monitor key metrics
curl -s http://jenkins-master-1:8080/prometheus | grep -E "(jenkins_queue_size|jenkins_builds_duration)"

# Alert thresholds
# - Queue size > 10 items
# - Average build duration > 30 minutes
# - Memory usage > 80%
# - Disk usage > 85%
```

### Best Practices

1. **Regular Health Checks**: Monitor all components continuously
2. **Graceful Shutdowns**: Always use maintenance mode for planned outages
3. **Configuration Backups**: Backup before any configuration changes
4. **Load Testing**: Regular testing of failover scenarios
5. **Documentation**: Keep runbooks updated with current procedures
6. **Monitoring**: Comprehensive monitoring with alerting
7. **Security**: Regular security updates and vulnerability scanning
