# Containerized HAProxy Deployment Guide

This guide explains the containerized HAProxy deployment for Jenkins multi-team infrastructure with wildcard subdomain routing.

## Overview

HAProxy now runs as a Docker container instead of a native service, providing:
- **Isolation**: HAProxy runs in its own containerized environment
- **Version Control**: Pinned HAProxy versions with official images
- **Resource Management**: Memory and CPU limits for HAProxy
- **Easy Management**: Systemd integration with container lifecycle
- **Security**: Non-root container execution with proper permissions

## Architecture

```
Host System
    ↓
Docker Engine
    ↓
HAProxy Container (jenkins-haproxy)
    ↓ (network_mode: host)
Host Network Interface
    ↓
Internet (*.devops.example.com)
```

## Container Configuration

### Docker Image
- **Image**: `haproxy:2.8-alpine` (configurable)
- **Container Name**: `jenkins-haproxy`
- **Network Mode**: `host` (direct access to host networking)
- **Restart Policy**: `unless-stopped`

### Volume Mounts
```yaml
volumes:
  # HAProxy configuration
  - /etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
  - /etc/haproxy/conf.d:/usr/local/etc/haproxy/conf.d:ro
  
  # SSL certificates (combined for HAProxy)
  - /etc/haproxy/ssl/combined.pem:/usr/local/etc/haproxy/ssl/combined.pem:ro
  
  # Logs and runtime
  - /var/log/haproxy:/var/log/haproxy:rw
  - /var/lib/haproxy:/var/lib/haproxy:rw
  - haproxy_socket:/run/haproxy:rw
```

### Resource Limits
```yaml
deploy:
  resources:
    limits:
      memory: "512M"
      cpus: "0.5"
    reservations:
      memory: "256M" 
      cpus: "0.25"
```

## SSL Certificate Handling

### Combined Certificate Approach
HAProxy requires certificates in a specific format. The deployment automatically creates a combined certificate:

```bash
# Combined certificate creation
cat /etc/ssl/certs/wildcard.devops.example.com.pem > /etc/haproxy/ssl/combined.pem
cat /etc/ssl/private/wildcard.devops.example.com.key >> /etc/haproxy/ssl/combined.pem
```

### Certificate Permissions
```bash
# Proper permissions for container access
chmod 640 /etc/haproxy/ssl/combined.pem
chown root:haproxy /etc/haproxy/ssl/combined.pem
```

## Container Management

### Systemd Service
HAProxy container is managed via systemd service:

```bash
# Service management
systemctl start jenkins-haproxy.service
systemctl stop jenkins-haproxy.service
systemctl restart jenkins-haproxy.service
systemctl status jenkins-haproxy.service

# Enable auto-start
systemctl enable jenkins-haproxy.service
```

### Container Manager Script
Dedicated management script provides comprehensive container operations:

```bash
# Container management
/usr/local/bin/haproxy-container-manager.sh start
/usr/local/bin/haproxy-container-manager.sh stop
/usr/local/bin/haproxy-container-manager.sh restart
/usr/local/bin/haproxy-container-manager.sh status
/usr/local/bin/haproxy-container-manager.sh logs [lines]
/usr/local/bin/haproxy-container-manager.sh validate
/usr/local/bin/haproxy-container-manager.sh update
/usr/local/bin/haproxy-container-manager.sh cleanup
```

### Docker Compose Operations
Direct Docker Compose management:

```bash
# Navigate to HAProxy directory
cd /etc/haproxy

# Container operations
docker-compose up -d          # Start container
docker-compose down           # Stop container
docker-compose restart        # Restart container
docker-compose pull           # Update image
docker-compose logs -f        # View logs
```

## Monitoring Integration

### Container Health Checks
Built-in Docker health check:
```yaml
healthcheck:
  test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8404/stats", "||", "exit", "1"]
  interval: 30s
  timeout: 10s
  retries: 3
```

### Updated Monitoring Scripts
All monitoring scripts updated for containerized HAProxy:

1. **jenkins-ha-healthcheck.sh**: Includes container health validation
2. **jenkins-failover.sh**: Uses `docker exec` for HAProxy commands
3. **jenkins-ha-monitor.sh**: Monitors container status and resources

### HAProxy Socket Access
HAProxy admin socket accessible via container:
```bash
# Execute HAProxy commands
docker exec jenkins-haproxy sh -c "echo 'show stat' | socat stdio /run/haproxy/admin.sock"

# Enable/disable servers
docker exec jenkins-haproxy sh -c "echo 'disable server backend/server' | socat stdio /run/haproxy/admin.sock"
```

## Deployment Process

### 1. Update Inventory
Ensure Docker and containerization settings:
```yaml
# Container configuration
haproxy_docker_image: "haproxy:2.8-alpine"
haproxy_memory_limit: "512M"
haproxy_cpu_limit: "0.5"

# SSL certificate paths
ssl_enabled: true
ssl_cert_path: "/etc/ssl/certs/wildcard.devops.example.com.pem"
ssl_key_path: "/etc/ssl/private/wildcard.devops.example.com.key"
```

### 2. Deploy Container Infrastructure
```bash
# Deploy containerized HAProxy
ansible-playbook -i inventories/production/hosts.yml site.yml \
  --tags "ha,container,loadbalancer" \
  --limit load_balancers
```

### 3. Verify Container Deployment
```bash
# Check container status
/usr/local/bin/haproxy-container-manager.sh status

# Validate configuration
/usr/local/bin/haproxy-container-manager.sh validate

# View logs
/usr/local/bin/haproxy-container-manager.sh logs
```

### 4. Test Multi-Team Routing
```bash
# Test team endpoints
curl -k https://jenkins.devops.example.com/login
curl -k https://dev.devops.example.com/login
curl -k https://staging.devops.example.com/login
curl -k https://prod.devops.example.com/login

# Check HAProxy stats
curl http://haproxy-server:8404/stats
```

## Troubleshooting

### Container Issues

**Container not starting:**
```bash
# Check Docker service
systemctl status docker

# Check container logs
docker logs jenkins-haproxy

# Validate Docker Compose
cd /etc/haproxy && docker-compose config
```

**Configuration errors:**
```bash
# Validate HAProxy config
docker exec jenkins-haproxy haproxy -f /usr/local/etc/haproxy/haproxy.cfg -c

# Check file permissions
ls -la /etc/haproxy/ssl/combined.pem
```

**SSL certificate issues:**
```bash
# Verify certificate format
openssl x509 -in /etc/haproxy/ssl/combined.pem -text -noout

# Check certificate permissions
ls -la /etc/haproxy/ssl/
```

### Network Issues

**Port conflicts:**
```bash
# Check port usage
netstat -tulpn | grep ':80\|:443\|:8404'

# Container network inspection
docker network ls
docker inspect jenkins-haproxy
```

**DNS resolution:**
```bash
# Test subdomain resolution
nslookup dev.devops.example.com
nslookup jenkins.devops.example.com

# Test routing
curl -H "Host: dev.devops.example.com" http://haproxy-ip/login
```

### Performance Monitoring

**Resource usage:**
```bash
# Container resource stats
docker stats jenkins-haproxy

# System resource usage
htop
iotop
```

**HAProxy statistics:**
```bash
# Real-time stats
watch -n 2 'curl -s http://localhost:8404/stats;csv | column -t -s,'

# Backend status
docker exec jenkins-haproxy sh -c "echo 'show stat' | socat stdio /run/haproxy/admin.sock"
```

## Security Considerations

### Container Security
- **Non-root execution**: Container runs as haproxy user
- **Read-only configuration**: Config files mounted read-only
- **Resource limits**: Memory and CPU constraints prevent resource exhaustion
- **Minimal image**: Alpine-based image reduces attack surface

### SSL/TLS Security
- **Wildcard certificate**: Single certificate for all team subdomains
- **Modern TLS**: TLS 1.2+ with strong cipher suites
- **Security headers**: HTTP security headers configured
- **Certificate rotation**: Automated certificate renewal support

### Network Security
- **Host networking**: Direct access to host network (required for VIP)
- **Firewall integration**: UFW/firewalld rules for HTTP/HTTPS
- **Stats access**: HAProxy statistics interface protection

## Performance Optimization

### Container Tuning
```yaml
# Optimized resource allocation
haproxy_memory_limit: "1G"      # For high-traffic environments
haproxy_cpu_limit: "1.0"        # Multiple CPU cores
haproxy_memory_reservation: "512M"
```

### HAProxy Configuration
```haproxy
global
    maxconn 8192                 # Increase for high load
    nbproc auto                  # Multi-process mode
    
defaults
    timeout connect 5s           # Connection timeout
    timeout client 300s          # Client timeout
    timeout server 300s          # Server timeout
```

## Benefits of Containerization

### ✅ **Advantages**
- **Isolation**: HAProxy isolated from host system
- **Consistency**: Same image across environments
- **Resource Control**: Memory/CPU limits and monitoring
- **Easy Updates**: Container image updates without system packages
- **Rollback**: Easy rollback to previous image versions
- **Monitoring**: Built-in health checks and logging

### ⚠️ **Considerations**
- **Network Mode**: Host networking required for VIP functionality
- **Volume Mounts**: Configuration and certificates must be properly mounted
- **Docker Dependency**: Requires Docker service to be running
- **Complexity**: Additional layer compared to native installation

## Migration from Native HAProxy

If migrating from native HAProxy installation:

1. **Backup current configuration**: `cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.native`
2. **Stop native service**: `systemctl stop haproxy && systemctl disable haproxy`
3. **Deploy container**: Run Ansible playbook with container tags
4. **Verify functionality**: Test all team endpoints
5. **Update monitoring**: Ensure monitoring scripts work with container

The containerized deployment maintains all existing functionality while providing improved isolation, resource management, and operational flexibility.