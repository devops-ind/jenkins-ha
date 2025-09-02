# HAProxy SSL Certificate Deployment Solution

## Problem Analysis

The HAProxy container was experiencing persistent restart issues with SSL certificate mounting due to several fundamental problems:

### Root Causes Identified

1. **Symlink Resolution in Containers**: Docker cannot properly mount symlinks across the host-container boundary
2. **File System Timing Issues**: SSL certificates might not be fully generated when the container starts
3. **Container Security Context**: Permission mismatches between host and container file systems  
4. **Mount Path Inconsistencies**: Container expected specific paths but mounts were failing
5. **Container Restart Loops**: Failed SSL access caused continuous container restarts

## Comprehensive Solution Implementation

### 1. Enhanced SSL Certificate Generation

**File**: `ansible/roles/high-availability-v2/tasks/ssl-certificates.yml`

**Key Improvements**:
- **Robust Bundle Creation**: Eliminates symlinks, uses direct file copies
- **Timing Safety**: Waits for certificate files to be ready before proceeding
- **Integrity Verification**: Comprehensive SSL certificate validation
- **Container-Safe Approach**: Direct file copies instead of symlinks

```yaml
# Container-Safe SSL Bundle Generation
- name: Create HAProxy SSL certificate bundle (cert + key)
  shell: |
    set -euo pipefail
    # Wait for certificate files to be ready
    for i in {1..30}; do
      if [[ -f "$CERT_FILE" && -f "$KEY_FILE" && -s "$CERT_FILE" && -s "$KEY_FILE" ]]; then
        break
      fi
      sleep 2
    done
    
    # Create bundle with proper concatenation
    cat "$CERT_FILE" "$KEY_FILE" > "$BUNDLE_FILE"
    # Create direct copy (not symlink) for container compatibility
    cp "$BUNDLE_FILE" "$COMBINED_FILE"
```

### 2. Improved Container Mounting Strategy

**File**: `ansible/roles/high-availability-v2/tasks/haproxy.yml`

**Key Changes**:
- **Directory Mounting**: Mount entire SSL directory instead of individual files
- **Pre-deployment Verification**: Comprehensive SSL certificate validation before container start
- **Enhanced Container Management**: Graceful container cleanup and restart logic

```yaml
# Mount entire SSL directory for better compatibility
_haproxy_volumes: >-
  {%- if ssl_enabled | default(false) -%}
    {%- set _ = base_volumes.append("/etc/haproxy/ssl:/usr/local/etc/haproxy/ssl:ro") -%}
  {%- endif -%}
```

### 3. Pre-deployment Validation Framework

**Key Features**:
- **SSL File Existence Check**: Verify all required files exist and are accessible
- **Certificate Integrity Testing**: Validate SSL certificates before deployment
- **Container Readiness Verification**: Ensure container is healthy before proceeding

```yaml
- name: Verify SSL certificate files exist and are accessible
  stat:
    path: "{{ item }}"
  register: ssl_files_check
  loop:
    - "/etc/haproxy/ssl/combined.pem"
    - "/etc/haproxy/ssl/wildcard-{{ jenkins_domain }}-haproxy.pem"
```

### 4. Comprehensive Troubleshooting System

**File**: `troubleshoot-haproxy-ssl.yml`

**Capabilities**:
- **Multi-mode Operation**: Diagnose, Fix, and Recover modes
- **Comprehensive Diagnostics**: Docker, SSL, HAProxy, and configuration analysis
- **Automatic Fixes**: Permission corrections, certificate recreation, container cleanup
- **Full Recovery**: Complete SSL regeneration and HAProxy redeployment

**Usage**:
```bash
# Diagnose issues
ansible-playbook -i ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml

# Attempt automatic fixes
ansible-playbook -i ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml --extra-vars "troubleshoot_mode=fix"

# Full recovery
ansible-playbook -i ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml --extra-vars "troubleshoot_mode=recover"
```

### 5. Automated Deployment Script

**File**: `scripts/deploy-haproxy-ssl.sh`

**Features**:
- **Phase-based Deployment**: SSL generation → Configuration → Container deployment → Verification
- **Automatic Recovery**: Built-in troubleshooting and retry logic
- **Dry Run Support**: Test deployment process without execution
- **Comprehensive Logging**: Detailed progress tracking and error reporting

**Usage**:
```bash
# Basic deployment
./scripts/deploy-haproxy-ssl.sh

# Dry run
./scripts/deploy-haproxy-ssl.sh --dry-run

# Production deployment
./scripts/deploy-haproxy-ssl.sh -i production -e prod

# Troubleshooting
./scripts/deploy-haproxy-ssl.sh --troubleshoot
```

## Deployment Process

### Step-by-Step Resolution

1. **SSL Certificate Generation**
   ```bash
   ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags ssl --extra-vars "ssl_enabled=true"
   ```

2. **HAProxy Configuration**
   ```bash
   ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags configuration --extra-vars "ssl_enabled=true"
   ```

3. **Container Deployment**
   ```bash
   ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags haproxy,deploy --extra-vars "ssl_enabled=true"
   ```

4. **Verification**
   ```bash
   ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags verify
   ```

### Alternative: Automated Deployment

```bash
# All-in-one deployment with automatic recovery
./scripts/deploy-haproxy-ssl.sh

# Or use the troubleshooting playbook
ansible-playbook -i ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml --extra-vars "troubleshoot_mode=recover"
```

## Verification and Testing

### Container Status Check
```bash
docker ps | grep jenkins-haproxy
docker logs jenkins-haproxy
```

### SSL Certificate Verification
```bash
# Host system
openssl x509 -in /etc/haproxy/ssl/combined.pem -noout -text

# Inside container
docker exec jenkins-haproxy openssl x509 -in /usr/local/etc/haproxy/ssl/combined.pem -noout -text
```

### Endpoint Testing
```bash
# HTTPS endpoint
curl -k https://localhost/

# HAProxy stats
curl http://localhost:8404/stats

# SSL connection test
openssl s_client -connect localhost:443 -servername localhost
```

## Configuration Parameters

### SSL Configuration
```yaml
ssl_enabled: true
jenkins_domain: "192.168.188.142"
jenkins_wildcard_domain: "*.192.168.188.142"
ssl_certificate_path: "/etc/haproxy/ssl/combined.pem"
```

### HAProxy Configuration
```yaml
haproxy_container_runtime: "docker"
haproxy_frontend_port: 80  # HTTP (redirects to HTTPS)
haproxy_stats_port: 8404
ssl_certificate_path: "/usr/local/etc/haproxy/ssl/combined.pem"  # Container path
```

## Architecture Benefits

### Container Security
- **Non-privileged Operation**: Attempts standard deployment first
- **Minimal Permissions**: Only necessary capabilities granted
- **Read-only Mounts**: SSL certificates mounted read-only

### High Availability
- **Graceful Degradation**: Fallback to privileged mode if needed
- **Health Checks**: Container health monitoring
- **Automatic Recovery**: Built-in troubleshooting and retry logic

### Operational Excellence
- **Comprehensive Logging**: Detailed deployment tracking
- **Automated Verification**: Multi-layer validation
- **Documentation**: Self-documenting configuration and processes

## Troubleshooting Guide

### Common Issues and Solutions

1. **Container Restarts with SSL Error**
   - **Solution**: Run troubleshooting playbook with `fix` mode
   - **Command**: `ansible-playbook troubleshoot-haproxy-ssl.yml --extra-vars "troubleshoot_mode=fix"`

2. **Certificate Not Found**
   - **Solution**: Regenerate SSL certificates
   - **Command**: `ansible-playbook ansible/site.yml --tags ssl --extra-vars "ssl_enabled=true"`

3. **Permission Denied**
   - **Solution**: Fix permissions and ownership
   - **Command**: Run troubleshooting with automatic fixes

4. **Configuration Errors**
   - **Solution**: Validate and regenerate configuration
   - **Command**: `ansible-playbook ansible/site.yml --tags configuration`

### Diagnostic Commands

```bash
# Quick container check
docker ps | grep haproxy && echo "Container running" || echo "Container not running"

# SSL certificate validation
openssl x509 -in /etc/haproxy/ssl/combined.pem -noout -dates

# HAProxy configuration test
docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Comprehensive diagnostics
ansible-playbook -i ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml
```

## Performance Optimizations

### Container Resource Limits
```yaml
memory: "512m"
cpus: "1.0"
```

### SSL Performance
- **TLS 1.2+ Only**: Modern SSL/TLS protocols
- **Optimized Ciphers**: Strong encryption with performance balance
- **Certificate Caching**: Efficient certificate management

### Monitoring Integration
- **Health Checks**: Container and application health monitoring
- **Stats Interface**: Real-time performance metrics
- **Logging**: Structured logging for troubleshooting

## Security Considerations

### Certificate Management
- **Secure Permissions**: 600 for private keys, 644 for certificates
- **Proper Ownership**: root:haproxy ownership
- **Regular Rotation**: Automated certificate renewal capability

### Container Security
- **Capability Dropping**: Minimal required capabilities
- **Non-root Execution**: HAProxy runs as non-root user
- **Read-only Filesystems**: Where possible

### Network Security
- **TLS Termination**: Secure SSL/TLS handling
- **HTTP to HTTPS Redirect**: Automatic secure connection enforcement
- **Security Headers**: XSS protection, content type validation

This comprehensive solution addresses all the original SSL certificate mounting issues and provides a robust, production-ready HAProxy deployment with SSL termination.