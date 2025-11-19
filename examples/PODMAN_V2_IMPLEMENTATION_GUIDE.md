# Podman v2 Implementation Guide

This document provides a comprehensive guide to the new Podman v2 roles that have been created as modern alternatives to the existing Docker-based infrastructure.

## 🎯 Overview

The Podman v2 roles provide a complete container runtime solution with enhanced security, better systemd integration, and rootless container support. These roles are designed to be drop-in replacements for Docker-based infrastructure while providing additional enterprise features.

## 📁 New Roles Created

### 1. **podman-v2 Role**

**Location:** `ansible/roles/podman-v2/`

**Purpose:** Complete Podman container runtime setup with advanced features

**Key Features:**
- ✅ **Rootless & Rootful Support**: Both privileged and unprivileged containers
- ✅ **Pod Management**: Native Kubernetes-style pod support
- ✅ **Systemd Integration**: Quadlet support for container services
- ✅ **Docker Compatibility**: Drop-in Docker CLI replacement
- ✅ **Enhanced Security**: User namespaces, SELinux integration
- ✅ **Auto-update**: Automatic container updates via systemd
- ✅ **Modern Networking**: Netavark network backend

**Files Structure:**
```
ansible/roles/podman-v2/
├── tasks/main.yml                    # Main installation and configuration
├── defaults/main.yml                 # Comprehensive variable definitions
├── handlers/main.yml                 # Service and system handlers
└── templates/
    ├── containers.conf.j2            # Podman daemon configuration
    ├── registries.conf.j2            # Registry configuration
    ├── storage.conf.j2               # Storage backend configuration
    ├── podman-logrotate.j2           # Log rotation setup
    ├── podman-cleanup.sh.j2          # Cleanup automation script
    └── podman-service.service.j2     # Systemd service template
```

### 2. **common-v2 Role**

**Location:** `ansible/roles/common-v2/`

**Purpose:** Enhanced common system setup with Podman-specific optimizations

**Key Features:**
- ✅ **Container Runtime Agnostic**: Supports both Podman and Docker
- ✅ **Rootless User Management**: Enhanced user/group configuration
- ✅ **Container Health Monitoring**: Automated health checks and recovery
- ✅ **Registry Authentication**: Secure registry credential management
- ✅ **Enhanced Logging**: Container-aware log rotation
- ✅ **Resource Management**: Container resource limits and monitoring

**Files Structure:**
```
ansible/roles/common-v2/
├── tasks/main.yml                    # Enhanced system setup tasks
├── defaults/main.yml                 # Container-aware default variables
├── handlers/main.yml                 # Container-specific handlers
└── templates/
    ├── logrotate.j2                  # System log rotation
    ├── container-logrotate.j2        # Container log rotation
    ├── auth.json.j2                  # Registry authentication
    ├── container-health-check.sh.j2  # Health monitoring script
    └── ntp.conf.j2                   # Container-friendly NTP config
```

## 🚀 Key Advantages Over Docker

### **Architecture Benefits**

| Feature | Docker | Podman v2 |
|---------|---------|-----------|
| **Architecture** | Client-server daemon | Daemonless fork-exec |
| **Root Access** | Requires root daemon | Rootless by default |
| **Pod Support** | None (needs orchestrator) | Native pod support |
| **Systemd Integration** | Basic | Native Quadlet support |
| **Security** | Single daemon attack surface | Process-level isolation |
| **Resource Management** | Docker daemon limits | Direct systemd cgroups |

### **Security Enhancements**

1. **Rootless Containers**
   - No privileged daemon running
   - User namespace isolation
   - Reduced attack surface

2. **Enhanced SELinux Integration**
   - Better label management
   - Automatic context switching
   - Container-specific policies

3. **Process-level Security**
   - Each container runs as separate process
   - Direct kernel interaction
   - No shared daemon vulnerabilities

### **Operational Benefits**

1. **Systemd Native**
   - Containers as systemd services
   - Native logging via journald
   - Resource management via cgroups v2

2. **Pod Support**
   - Group related containers
   - Shared networking and storage
   - Kubernetes YAML compatibility

3. **Auto-update**
   - Automatic image updates
   - Rolling updates support
   - Dependency management

## 📋 Configuration Reference

### **Podman v2 Role Variables**

#### **Core Configuration**
```yaml
# Basic Podman setup
podman_enabled: true
podman_runtime: "crun"
podman_network_backend: "netavark"
podman_storage_driver: "overlay"

# User management
podman_enable_rootless: true
podman_users:
  - "vscode"
  - "jenkins"
  - "monitoring"

# Docker compatibility
podman_docker_compatibility: true
podman_compose_enabled: true
```

#### **Network Configuration**
```yaml
# Networks (more flexible than Docker)
podman_networks:
  - name: jenkins-network
    driver: bridge
    subnet: "172.20.0.0/16"
    gateway: "172.20.0.1"
    internal: false
    disable_dns: false
```

#### **Registry Configuration**
```yaml
# Registry mirrors and authentication
podman_registry_mirrors: []
podman_unqualified_search_registries:
  - "registry.fedoraproject.org"
  - "registry.access.redhat.com"
  - "docker.io"
  - "quay.io"
```

#### **Security Settings**
```yaml
# Security features
podman_enable_selinux: true
podman_enable_secrets: true
podman_pod_security_context:
  run_as_user: 1000
  run_as_group: 1000
  fs_group: 1000
```

### **Common v2 Role Variables**

#### **Container Runtime Selection**
```yaml
# Choose container runtime
common_container_runtime: "podman"  # or "docker"

# Rootless configuration
common_enable_rootless_containers: true
common_monitoring_subuid_start: 200000
common_monitoring_subuid_size: 65536
```

#### **Registry Authentication**
```yaml
# Secure registry authentication
common_registry_auth:
  docker.io:
    username: "{{ vault_docker_username }}"
    password: "{{ vault_docker_password }}"
  private-registry.company.com:
    auth: "{{ vault_private_registry_auth }}"
```

#### **Health Monitoring**
```yaml
# Container health monitoring
common_container_health_check_enabled: true
common_health_check_containers:
  - prometheus-production
  - grafana-production
  - alertmanager-production
```

## 🧪 Testing Guide

### **Testing the New Roles**

1. **Run Test Playbook:**
   ```bash
   # Test on local environment
   ansible-playbook -i ansible/inventories/local/hosts.yml test-podman-v2-roles.yml
   
   # Test on production (dry run first)
   ansible-playbook -i ansible/inventories/production/hosts.yml test-podman-v2-roles.yml --check
   ```

2. **Verify Installation:**
   ```bash
   # Check Podman version
   podman --version
   
   # Test rootless functionality
   podman run --rm hello-world
   
   # Check system info
   podman system info
   ```

3. **Test Container Operations:**
   ```bash
   # Test pod creation
   podman pod create --name test-pod
   
   # Test network functionality
   podman network ls
   
   # Test volume management
   podman volume ls
   ```

### **Migration Testing**

1. **Side-by-side Testing:**
   ```bash
   # Keep Docker running, install Podman alongside
   ansible-playbook test-podman-v2-roles.yml --extra-vars "podman_docker_compatibility=false"
   ```

2. **Workload Migration:**
   ```bash
   # Test existing Docker Compose files with Podman
   podman-compose -f docker-compose.yml up --dry-run
   ```

3. **Performance Comparison:**
   ```bash
   # Benchmark container startup times
   time podman run --rm alpine echo "test"
   time docker run --rm alpine echo "test"
   ```

## 🔄 Integration Options

### **Option 1: Gradual Migration**

Add conditional logic to existing playbooks:
```yaml
- name: Setup container runtime
  include_role:
    name: "{{ 'podman-v2' if use_podman else 'docker' }}"
  vars:
    use_podman: "{{ deployment_mode == 'production' }}"
```

### **Option 2: Environment-based Selection**

Configure different environments to use different runtimes:
```yaml
# In local inventory
common_container_runtime: "docker"

# In production inventory
common_container_runtime: "podman"
```

### **Option 3: Complete Replacement**

Replace roles in `site.yml`:
```yaml
# Before
- common
- docker

# After
- common-v2
- podman-v2
```

## 📊 Feature Comparison Matrix

| Feature | Docker Role | Podman v2 Role | Benefit |
|---------|------------|----------------|---------|
| **Container Runtime** | Docker daemon | Podman daemonless | Better security, no SPOF |
| **Rootless Support** | Limited | Native | Enhanced security |
| **Pod Management** | None | Native | Kubernetes compatibility |
| **Systemd Integration** | Basic | Quadlet | Better service management |
| **Auto-updates** | Manual | Built-in | Automated maintenance |
| **Resource Limits** | Docker daemon | systemd cgroups | Better resource control |
| **Logging** | Docker logs | journald | Integrated system logs |
| **Networking** | Bridge/overlay | Netavark/CNI | Modern network stack |
| **Image Building** | Docker build | Buildah | Rootless image builds |
| **Security Scanning** | Third-party | Built-in | Integrated security |

## 🛡️ Security Considerations

### **Enhanced Security Features**

1. **No Root Daemon**
   - Eliminates privileged daemon attack vector
   - Reduces system-wide compromise risk
   - Better principle of least privilege

2. **User Namespace Isolation**
   - Container root != host root
   - Automatic UID/GID mapping
   - Process isolation boundaries

3. **SELinux Integration**
   - Automatic label assignment
   - Container-specific contexts
   - Enhanced mandatory access controls

4. **Secrets Management**
   - Native secrets support
   - Encrypted storage
   - Runtime secret injection

### **Security Best Practices**

```yaml
# Recommended security configuration
podman_daemon_options:
  seccomp_profile: "/usr/share/containers/seccomp.json"
  apparmor_profile: "containers-default"
  
podman_pod_security_context:
  run_as_user: 1000
  run_as_group: 1000
  
common_container_security_options:
  - "--security-opt=no-new-privileges"
  - "--cap-drop=ALL"
  - "--cap-add=CHOWN,SETUID,SETGID"
```

## 🔧 Troubleshooting Guide

### **Common Issues and Solutions**

1. **Rootless Setup Issues**
   ```bash
   # Check subuid/subgid configuration
   cat /etc/subuid /etc/subgid
   
   # Reset user namespace
   podman system reset
   podman system migrate
   ```

2. **Network Connectivity**
   ```bash
   # Check network backend
   podman system info | grep -A5 "network"
   
   # Recreate networks
   podman network prune
   ansible-playbook test-podman-v2-roles.yml --tags=podman
   ```

3. **Storage Issues**
   ```bash
   # Check storage configuration
   podman system df
   
   # Clean up storage
   podman system prune -af --volumes
   ```

## 📈 Performance Optimization

### **Recommended Optimizations**

1. **Storage Configuration**
   ```yaml
   podman_storage_driver: "overlay"
   podman_tune_storage: true
   ```

2. **Network Optimization**
   ```yaml
   podman_network_backend: "netavark"
   podman_tune_network: true
   ```

3. **Resource Limits**
   ```yaml
   podman_default_limits:
     memory: "2G"
     cpu_quota: "100%"
     pids_limit: 1024
   ```

## 🎯 Production Readiness Checklist

### **Pre-deployment Validation**

- [ ] ✅ Test roles work on target OS (RHEL/CentOS/Ubuntu)
- [ ] ✅ Rootless containers function correctly
- [ ] ✅ Existing workloads compatible with Podman
- [ ] ✅ Network connectivity verified
- [ ] ✅ Storage performance acceptable
- [ ] ✅ Monitoring integration working
- [ ] ✅ Backup procedures updated
- [ ] ✅ Security scanning configured
- [ ] ✅ Log aggregation functional
- [ ] ✅ Auto-update tested

### **Deployment Steps**

1. **Test Environment**
   ```bash
   ansible-playbook -i test-inventory test-podman-v2-roles.yml
   ```

2. **Staging Environment**
   ```bash
   ansible-playbook -i staging-inventory test-podman-v2-roles.yml
   ```

3. **Production Deployment**
   ```bash
   # Update site.yml to use new roles
   ansible-playbook -i production-inventory site.yml --tags=podman
   ```

## 🎉 Conclusion

The Podman v2 roles provide a modern, secure, and feature-rich alternative to Docker-based container infrastructure. With enhanced security through rootless containers, better systemd integration, and native pod support, these roles are ready for production deployment.

**Key Benefits:**
- 🛡️ **Enhanced Security**: Rootless containers, no privileged daemon
- 🔧 **Better Integration**: Native systemd, journald logging
- 🚀 **Modern Features**: Pods, auto-updates, advanced networking
- 🔄 **Compatibility**: Docker CLI compatibility, easy migration
- 📊 **Enterprise Ready**: Comprehensive monitoring, logging, cleanup

The roles are designed to be drop-in replacements for existing Docker infrastructure while providing significant operational and security improvements. Start with the test playbook, validate in your environment, and migrate when ready for the benefits of modern container runtime technology.