# 🚀 Local Development with DevContainers

This guide explains how to run the Jenkins HA infrastructure locally using DevContainers for development and testing.

## 📋 Prerequisites

- Docker Desktop or Docker Engine
- VS Code with Dev Containers extension (recommended)
- Git

## 🏗️ Local Architecture

The local setup runs all services as Docker containers on `localhost` with different ports:

| Service | URL | Container Name | Default Credentials |
|---------|-----|----------------|-------------------|
| Jenkins Master | http://localhost:8080 | jenkins-master-dev | admin / admin123 |
| Grafana | http://localhost:3000 | grafana-dev | admin / admin |
| Prometheus | http://localhost:9090 | prometheus-dev | - |
| Harbor Registry | http://localhost:8082 | harbor-dev | admin / Harbor12345 |

## 🚀 Quick Start

### Option 1: Using the Deploy Script (Recommended)

```bash
# Deploy everything
./scripts/deploy-local.sh

# Deploy with verbose output
./scripts/deploy-local.sh --verbose

# Deploy only Jenkins infrastructure
./scripts/deploy-local.sh --tags jenkins,infrastructure

# Deploy without backup services
./scripts/deploy-local.sh --skip-tags backup

# Dry run to see what would be deployed
./scripts/deploy-local.sh --dry-run
```

### Option 2: Using Ansible Directly

```bash
cd ansible

# Full deployment
ansible-playbook -i inventories/local/hosts.yml deploy-local.yml

# Deploy specific components
ansible-playbook -i inventories/local/hosts.yml deploy-local.yml --tags jenkins,infrastructure

# Deploy with monitoring
ansible-playbook -i inventories/local/hosts.yml deploy-local.yml --tags jenkins,monitoring
```

### Option 3: Using the Main Site Playbook

```bash
cd ansible

# Full site deployment (adapted for local)
ansible-playbook -i inventories/local/hosts.yml site.yml
```

## 🏷️ Available Tags

Use these tags to deploy specific components:

### Core Infrastructure
- `common` - Common system setup
- `docker` - Docker configuration
- `jenkins` - Jenkins master and agents
- `infrastructure` - Complete Jenkins infrastructure

### Additional Services
- `harbor` - Harbor registry
- `monitoring` - Complete monitoring stack
- `prometheus` - Prometheus only
- `grafana` - Grafana only
- `backup` - Backup system
- `images` - Build Jenkins images
- `registry` - Registry services

### Example Tag Combinations

```bash
# Core Jenkins only
--tags common,docker,jenkins

# Jenkins with monitoring
--tags common,docker,jenkins,monitoring

# Everything except backup
--skip-tags backup

# Only monitoring stack
--tags monitoring,prometheus,grafana
```

## 🔧 Configuration

### Local Environment Variables

The local setup uses these key configurations:

```yaml
# Network Configuration
jenkins_network_name: "jenkins-dev-net"
monitoring_network_name: "monitoring-dev-net"

# Resource Limits (optimized for local development)
jenkins_master_memory: "2g"
jenkins_master_cpu_limit: "1"

# Security (relaxed for development)
enable_ssl: false
jenkins_enable_csrf: false
jenkins_admin_password: "admin123"

# Features (disabled for faster local deployment)
jenkins_ha_enabled: false
backup_enabled: false
build_jenkins_images: false
```

### Customizing Local Configuration

Edit `ansible/inventories/local/group_vars/all/main.yml` to customize:

- Resource limits
- Port assignments
- Feature enablement
- Credentials
- Network configuration

## 🐳 Container Management

### View Running Containers
```bash
docker ps
```

### View Logs
```bash
# Jenkins master logs
docker logs jenkins-master-dev

# Grafana logs  
docker logs grafana-dev

# Prometheus logs
docker logs prometheus-dev
```

### Access Container Shell
```bash
# Jenkins master container
docker exec -it jenkins-master-dev bash

# Grafana container
docker exec -it grafana-dev bash
```

### Stop All Services
```bash
# Stop all running containers
docker stop $(docker ps -q)

# Remove stopped containers
docker container prune -f

# Clean up unused resources
docker system prune -f
```

## 🔍 Troubleshooting

### Port Conflicts
If you get port binding errors, check what's using the ports:

```bash
# Check what's using port 8080
lsof -i :8080

# Or use netstat
netstat -tulpn | grep :8080
```

### Container Issues
```bash
# Restart a specific container
docker restart jenkins-master-dev

# View container resource usage
docker stats

# Inspect container configuration
docker inspect jenkins-master-dev
```

### Ansible Issues
```bash
# Test inventory
ansible-inventory -i inventories/local/hosts.yml --list

# Test connectivity
ansible -i inventories/local/hosts.yml localhost -m ping

# Syntax check
ansible-playbook -i inventories/local/hosts.yml deploy-local.yml --syntax-check
```

### Reset Everything
```bash
# Stop and remove all containers
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)

# Remove all volumes (WARNING: This deletes all data)
docker volume prune -f

# Remove networks
docker network prune -f

# Clean up everything
docker system prune -a -f
```

## 🧪 Development Workflow

### 1. Make Changes
Edit Ansible roles, playbooks, or configurations

### 2. Test Changes
```bash
# Test with dry run
./scripts/deploy-local.sh --dry-run

# Deploy specific components
./scripts/deploy-local.sh --tags jenkins
```

### 3. Validate
- Check service accessibility
- Verify logs for errors
- Test functionality

### 4. Iterate
Repeat the cycle for rapid development

## 📁 Local File Structure

```
ansible/
├── inventories/local/           # Local inventory
│   ├── hosts.yml               # Local host definitions
│   └── group_vars/all/
│       ├── main.yml           # Local configuration
│       └── vault.yml          # Local secrets (unencrypted)
├── deploy-local.yml            # Local deployment playbook
└── site.yml                   # Main site playbook

scripts/
└── deploy-local.sh            # Local deployment script

LOCAL_DEVELOPMENT.md           # This file
```

## 🛡️ Security Notes

The local development setup uses:
- **Unencrypted vault file** for convenience
- **Simple passwords** for easy access
- **Disabled SSL/CSRF** for development ease
- **Relaxed security settings** for faster iteration

**⚠️ Never use these settings in production!**

## 🎯 Next Steps

After local development:

1. Test with staging inventory (`inventories/staging/`)
2. Validate with production inventory (`inventories/production/`)
3. Enable security features
4. Configure proper secrets management
5. Set up CI/CD pipeline

## 📞 Support

For issues with local development:
1. Check the troubleshooting section above
2. Review container logs
3. Validate Ansible inventory and playbook syntax
4. Test individual components in isolation

Happy local development! 🎉