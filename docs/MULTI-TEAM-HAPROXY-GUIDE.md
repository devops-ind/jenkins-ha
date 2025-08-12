# Multi-Team HAProxy Configuration Guide

This guide explains how to configure HAProxy for multi-team Jenkins infrastructure with wildcard subdomain routing using `*.devops.example.com`.

## Overview

The multi-team HAProxy setup provides:
- **Wildcard subdomain routing** for team-specific Jenkins instances
- **SSL/TLS termination** with wildcard certificates
- **Blue-green deployment support** for each team
- **Health monitoring** and automatic failover
- **Team isolation** with dedicated backends
- **Centralized statistics** and monitoring

## Architecture

```
Internet
    ↓
HAProxy Load Balancer (*.devops.example.com)
    ↓
┌─────────────────────────────────────────────────────┐
│                 Team Routing                        │
├─────────────────────────────────────────────────────┤
│ jenkins.devops.example.com  → Jenkins Team (8080)  │
│ dev.devops.example.com      → Dev Team (8081)      │
│ staging.devops.example.com  → Staging Team (8082)  │
│ prod.devops.example.com     → Prod Team (8083)     │
│ platform.devops.example.com → Platform Team (8084) │
└─────────────────────────────────────────────────────┘
    ↓
Jenkins Masters (Blue-Green per Team)
    ↓
┌──────────────┐  ┌──────────────┐
│ Blue Env     │  │ Green Env    │
│ Port 8080    │  │ Port 8180    │
│ (Active)     │  │ (Standby)    │
└──────────────┘  └──────────────┘
```

## Configuration Components

### 1. Inventory Configuration

**File**: `ansible/inventories/production/hosts.yml`

```yaml
all:
  vars:
    # Domain configuration
    jenkins_domain: "devops.example.com"
    jenkins_wildcard_domain: "*.devops.example.com"
    
    # SSL configuration
    ssl_enabled: true
    ssl_cert_path: "/etc/ssl/certs/wildcard.devops.example.com.pem"
    ssl_key_path: "/etc/ssl/private/wildcard.devops.example.com.key"
    
    # Team configuration
    jenkins_teams:
      - team_name: "jenkins"
        ports: { web: 8080, jnlp: 50000 }
        blue_green_enabled: true
        active_environment: "blue"
        
      - team_name: "dev"
        ports: { web: 8081, jnlp: 50001 }
        blue_green_enabled: true
        active_environment: "blue"
        
      - team_name: "staging"
        ports: { web: 8082, jnlp: 50002 }
        blue_green_enabled: true
        active_environment: "green"
        
      - team_name: "prod"
        ports: { web: 8083, jnlp: 50003 }
        blue_green_enabled: true
        active_environment: "blue"
```

### 2. HAProxy Configuration

**Generated File**: `/etc/haproxy/haproxy.cfg`

Key features:
- **Frontend routing** based on Host header matching
- **Backend pools** for each team with blue-green support
- **SSL termination** with wildcard certificate
- **Health checks** with team-specific endpoints
- **Statistics interface** for monitoring

### 3. Team-Specific Backends

Each team gets:
- Dedicated backend pool (`jenkins_backend_teamname`)
- Blue-green server configuration
- Custom health check paths
- Team-specific HTTP headers
- Configurable timeouts and limits

## Deployment Process

### 1. SSL Certificate Setup

First, obtain a wildcard SSL certificate for `*.devops.example.com`:

```bash
# Using Let's Encrypt (example)
certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini \
  -d "*.devops.example.com" \
  -d "devops.example.com"

# Combine certificate and private key for HAProxy
cat /etc/letsencrypt/live/devops.example.com/fullchain.pem \
    /etc/letsencrypt/live/devops.example.com/privkey.pem \
    > /etc/ssl/certs/wildcard.devops.example.com.pem
```

### 2. Deploy HAProxy Configuration

```bash
# Deploy to load balancer hosts
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags "ha,loadbalancer" \
  --limit load_balancers

# Verify configuration
ansible load_balancers -i inventories/production/hosts.yml \
  -m shell -a "haproxy -f /etc/haproxy/haproxy.cfg -c"
```

### 3. Deploy Jenkins Masters

```bash
# Deploy Jenkins masters for all teams
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags "jenkins,deploy" \
  --limit jenkins_masters
```

### 4. Verify Team Access

```bash
# Test each team endpoint
curl -k https://jenkins.devops.example.com/login
curl -k https://dev.devops.example.com/login
curl -k https://staging.devops.example.com/login
curl -k https://prod.devops.example.com/login
```

## Subdomain Routing Logic

### Frontend Routing Rules

```haproxy
# Team-based routing using subdomain matching
use_backend jenkins_backend_jenkins if { hdr_beg(host) -i jenkins.devops.example.com }
use_backend jenkins_backend_dev if { hdr_beg(host) -i dev.devops.example.com }
use_backend jenkins_backend_staging if { hdr_beg(host) -i staging.devops.example.com }
use_backend jenkins_backend_prod if { hdr_beg(host) -i prod.devops.example.com }

# Default backend for other subdomains
default_backend jenkins_backend_default
```

### Backend Configuration

Each team backend includes:

```haproxy
backend jenkins_backend_dev
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200
    
    # Blue environment servers
    server dev-jenkins-master-01-blue 192.168.5.10:8081 check
    server dev-jenkins-master-02-blue 192.168.5.11:8081 check
    
    # Green environment servers (backup)
    server dev-jenkins-master-01-green 192.168.5.10:8181 check backup
    server dev-jenkins-master-02-green 192.168.5.11:8181 check backup
    
    # Team-specific headers
    http-response set-header X-Jenkins-Team dev
    http-response set-header X-Jenkins-Environment blue
```

## Blue-Green Deployment

### Switching Environments

Each team can independently switch between blue and green environments:

```bash
# Switch dev team to green environment
ansible-playbook -i inventories/production/hosts.yml \
  scripts/blue-green-switch.yml \
  -e "team_name=dev" \
  -e "target_environment=green"
```

### Automatic Failover

The monitoring system can automatically trigger failover:

```bash
# Manual failover for specific team
/usr/local/bin/jenkins-failover.sh dev auto

# Emergency failover (disable unhealthy servers)
/usr/local/bin/jenkins-failover.sh dev emergency

# Check current status
/usr/local/bin/jenkins-failover.sh dev status
```

## Monitoring and Health Checks

### HAProxy Statistics

Access real-time statistics:
- URL: `http://haproxy-server:8404/stats`
- Shows backend status, active connections, health checks
- Displays blue-green environment status per team

### Health Check Scripts

**Comprehensive Health Check**:
```bash
/usr/local/bin/jenkins-ha-healthcheck.sh
```

**Continuous Monitoring**:
```bash
/usr/local/bin/jenkins-ha-monitor.sh
```

### Monitoring Metrics

Key metrics tracked:
- **Response times** per team/environment
- **Active connections** and queue depth
- **Health check success rates**
- **Blue-green environment status**
- **SSL certificate expiration**

## Team Configuration Options

### Per-Team Settings

```yaml
jenkins_teams:
  - team_name: "prod"
    description: "Production team with strict SLA"
    ports: { web: 8083, jnlp: 50003 }
    blue_green_enabled: true
    active_environment: "blue"
    
    # Custom settings
    session_persistence: true      # Enable sticky sessions
    health_check_path: "/login"    # Custom health check
    timeout_connect: "10s"         # Longer connect timeout
    timeout_server: "600s"         # Longer server timeout
    
    # Resource limits
    max_connections: 200           # Higher connection limit
    
    # Alert thresholds
    alert_response_time: "5s"      # Alert if response > 5s
    alert_failure_rate: 0.1        # Alert if >10% failures
```

### Team-Specific Features

- **Session Persistence**: Sticky sessions for teams that need them
- **Custom Timeouts**: Different timeout values per team
- **Health Check Paths**: Team-specific health check endpoints
- **Resource Limits**: Per-team connection and rate limits
- **Alert Thresholds**: Custom alerting per team requirements

## SSL/TLS Configuration

### Wildcard Certificate Management

**Certificate Locations**:
```bash
# Combined certificate + private key for HAProxy
/etc/ssl/certs/wildcard.devops.example.com.pem

# Separate files (if needed)
/etc/ssl/certs/wildcard.devops.example.com.crt
/etc/ssl/private/wildcard.devops.example.com.key
/etc/ssl/certs/ca-chain.pem
```

**Security Settings**:
```haproxy
# Modern TLS configuration
ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256
ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

# Security headers
http-response set-header X-Content-Type-Options nosniff
http-response set-header X-Frame-Options DENY
http-response set-header X-XSS-Protection "1; mode=block"
```

### Certificate Renewal

**Automated Renewal** (using systemd timer):
```bash
# /etc/systemd/system/cert-renewal.service
[Unit]
Description=SSL Certificate Renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/renew-wildcard-cert.sh
User=root

# /etc/systemd/system/cert-renewal.timer
[Unit]
Description=Run cert renewal monthly
Requires=cert-renewal.service

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
```

## Troubleshooting

### Common Issues

**1. Subdomain not routing correctly**
```bash
# Check HAProxy configuration
haproxy -f /etc/haproxy/haproxy.cfg -c

# Verify DNS resolution
nslookup dev.devops.example.com

# Check frontend routing
curl -H "Host: dev.devops.example.com" http://haproxy-ip/login
```

**2. SSL certificate issues**
```bash
# Verify certificate
openssl x509 -in /etc/ssl/certs/wildcard.devops.example.com.pem -text -noout

# Test SSL connection
openssl s_client -connect dev.devops.example.com:443 -servername dev.devops.example.com
```

**3. Backend servers not responding**
```bash
# Check backend status
echo "show stat" | socat stdio /run/haproxy/admin.sock | grep jenkins_backend_dev

# Test direct connection to Jenkins
curl -I http://jenkins-master-ip:8081/login
```

**4. Blue-green switch not working**
```bash
# Check current backend configuration
echo "show stat" | socat stdio /run/haproxy/admin.sock

# Manually switch environments
echo "enable server jenkins_backend_dev/dev-server-green" | socat stdio /run/haproxy/admin.sock
echo "disable server jenkins_backend_dev/dev-server-blue" | socat stdio /run/haproxy/admin.sock
```

### Debug Commands

```bash
# HAProxy configuration test
haproxy -f /etc/haproxy/haproxy.cfg -c

# Show current backends and servers
echo "show stat" | socat stdio /run/haproxy/admin.sock

# Show current sessions
echo "show sess" | socat stdio /run/haproxy/admin.sock

# Enable/disable servers
echo "disable server backend/server" | socat stdio /run/haproxy/admin.sock
echo "enable server backend/server" | socat stdio /run/haproxy/admin.sock

# Set server to maintenance mode
echo "set server backend/server state maint" | socat stdio /run/haproxy/admin.sock
```

## Performance Tuning

### HAProxy Optimization

```haproxy
global
    # Increase connection limits
    maxconn 8192
    
    # Enable CPU affinity
    nbproc 2
    cpu-map 1 0
    cpu-map 2 1

defaults
    # Optimize timeouts
    timeout connect 5s
    timeout client 300s
    timeout server 300s
    timeout http-keep-alive 10s
    
    # Connection reuse
    option http-server-close
    option forwardfor
```

### Team-Specific Tuning

```yaml
# High-traffic production team
jenkins_teams:
  - team_name: "prod"
    max_connections: 500
    timeout_server: "600s"
    session_persistence: true
    
# Development team (lower limits)
  - team_name: "dev"
    max_connections: 100
    timeout_server: "300s"
    session_persistence: false
```

## Security Considerations

### Network Security

- **SSL/TLS encryption** for all team communications
- **Security headers** to prevent common attacks
- **IP restrictions** if needed per team
- **Rate limiting** to prevent abuse

### Access Control

- **Team isolation** through separate backends
- **Credential separation** per team environment
- **Audit logging** of all configuration changes
- **Role-based access** to HAProxy statistics

### Compliance

- **PCI DSS**: SSL termination and secure headers
- **SOX**: Audit trails and change management
- **GDPR**: Data protection through encryption
- **SOC 2**: Monitoring and logging requirements

## Conclusion

The multi-team HAProxy configuration provides:

✅ **Team Isolation**: Each team has dedicated infrastructure  
✅ **Scalability**: Easy to add new teams and environments  
✅ **High Availability**: Blue-green deployments per team  
✅ **Security**: SSL termination and security headers  
✅ **Monitoring**: Comprehensive health checks and stats  
✅ **Automation**: Automated failover and recovery  

This setup scales from small teams to large enterprises while maintaining security, performance, and operational simplicity.