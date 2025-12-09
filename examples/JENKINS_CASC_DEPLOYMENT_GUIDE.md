# Jenkins CASC Configuration Fix - Deployment Guide

## Overview

This guide provides step-by-step instructions to deploy the fixed Jenkins Configuration-as-Code (CASC) implementation and validate that the setup wizard issue has been resolved.

## Pre-Deployment Checklist

### 1. Environment Verification
```bash
# Verify Docker is running
docker --version
docker info

# Check available resources
df -h
free -h

# Verify Ansible installation
ansible --version
```

### 2. Configuration Validation
```bash
# Validate Ansible syntax
cd /Users/jitinchawla/Data/projects/jenkins-ha
ansible-playbook ansible/site.yml --syntax-check

# Check inventory configuration
ansible-inventory -i ansible/inventories/local/hosts.yml --list
```

## Deployment Steps

### Step 1: Clean Up Existing Containers (If Any)
```bash
# Stop and remove existing Jenkins containers
docker stop $(docker ps -q --filter "name=jenkins-") 2>/dev/null || true
docker rm $(docker ps -aq --filter "name=jenkins-") 2>/dev/null || true

# Remove existing custom images (optional - forces rebuild)
docker rmi $(docker images -q jenkins-custom-*) 2>/dev/null || true

# Clean up orphaned volumes (be careful with this)
# docker volume prune -f
```

### Step 2: Deploy Jenkins Infrastructure
```bash
# Deploy complete infrastructure with fixed CASC configuration
make deploy-local

# Or use direct Ansible command
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags jenkins,deploy

# Deploy only Jenkins components (faster iteration)
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags jenkins-master-v2
```

### Step 3: Monitor Deployment Progress
```bash
# Monitor container startup
watch docker ps --filter "name=jenkins-"

# Check container logs in real-time
docker logs -f jenkins-devops-green  # Or active container name

# Monitor image building (in another terminal)
docker images | grep jenkins-custom
```

## Validation and Testing

### Step 1: Automated CASC Validation
```bash
# Run comprehensive CASC validation script
./scripts/validate-jenkins-casc.sh devops

# Validate dev-qa team if deployed
./scripts/validate-jenkins-casc.sh dev-qa

# Verbose validation output
VERBOSE=true ./scripts/validate-jenkins-casc.sh devops
```

### Step 2: Manual Verification Steps

#### 2.1 Container Health Check
```bash
# Verify containers are running
docker ps --filter "name=jenkins-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check container resource usage
docker stats --no-stream $(docker ps -q --filter "name=jenkins-")
```

#### 2.2 CASC Configuration Files
```bash
# Verify CASC configuration files in containers
docker exec jenkins-devops-green find /usr/share/jenkins/ref/casc_configs -name "*.yaml"

# Check file contents
docker exec jenkins-devops-green cat /usr/share/jenkins/ref/casc_configs/jenkins.yaml | head -20
```

#### 2.3 Environment Variables
```bash
# Verify CASC environment variables
docker exec jenkins-devops-green env | grep -E "CASC|JAVA_OPTS|JENKINS_OPTS"

# Check team-specific environment variables  
docker exec jenkins-devops-green env | grep JENKINS_TEAM
```

#### 2.4 Plugin Installation
```bash
# Verify CASC plugin is installed
docker exec jenkins-devops-green ls /var/jenkins_home/plugins/ | grep configuration-as-code

# Check plugin versions
docker exec jenkins-devops-green cat /var/jenkins_home/plugins/configuration-as-code.jpi.pinned 2>/dev/null || echo "Plugin version file not found"
```

### Step 3: Web Interface Testing

#### 3.1 Access Jenkins Web Interface
```bash
# Get container port mapping
docker port jenkins-devops-green

# Test basic connectivity
curl -I http://localhost:8189/

# Test login page (should not show setup wizard)
curl -s http://localhost:8189/login | grep -i "unlock\|setup\|wizard" && echo "❌ Setup wizard detected" || echo "✅ No setup wizard"
```

#### 3.2 Browser Testing
1. Open browser and navigate to: `http://localhost:8189` (for dev-qa green environment)
2. Verify you see the Jenkins dashboard, NOT the setup wizard
3. Check system message shows team information
4. Verify login works with admin credentials

#### 3.3 API Testing
```bash
# Test Jenkins API (should return JSON, not setup wizard)
curl -s http://localhost:8189/api/json | jq '.mode' 2>/dev/null || echo "API not accessible"

# Test with authentication if configured
curl -u admin:admin123 -s http://localhost:8189/api/json | jq '.mode' 2>/dev/null || echo "Authenticated API test failed"
```

## Troubleshooting Common Issues

### Issue 1: Setup Wizard Still Appears

**Diagnosis Steps:**
```bash
# Check CASC configuration loading in logs
docker logs jenkins-devops-green 2>&1 | grep -i "configuration.*code\|casc"

# Verify CASC_JENKINS_CONFIG environment variable
docker exec jenkins-devops-green printenv CASC_JENKINS_CONFIG

# Check if jenkins.yaml file exists and is readable
docker exec jenkins-devops-green ls -la /usr/share/jenkins/ref/casc_configs/jenkins.yaml
```

**Solutions:**
1. Verify CASC plugin is installed: `docker exec jenkins-devops-green ls /var/jenkins_home/plugins/ | grep configuration-as-code`
2. Check file permissions: `docker exec jenkins-devops-green stat /usr/share/jenkins/ref/casc_configs/jenkins.yaml`
3. Rebuild containers with fixed configuration: `ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags jenkins-master-v2 -e jenkins_master_force_custom_rebuild=true`

### Issue 2: Container Startup Failures

**Diagnosis Steps:**
```bash
# Check container logs for errors
docker logs jenkins-devops-green 2>&1 | tail -50

# Verify image build success
docker images | grep jenkins-custom-devops

# Check Docker resource usage
docker system df
```

**Solutions:**
1. Increase container memory limits
2. Check available disk space
3. Rebuild base images: `ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags jenkins-images`

### Issue 3: Plugin Installation Issues

**Diagnosis Steps:**
```bash
# Check plugin installation logs
docker logs jenkins-devops-green 2>&1 | grep -i plugin

# Verify network connectivity from container
docker exec jenkins-devops-green curl -I https://updates.jenkins.io/
```

**Solutions:**
1. Rebuild images with plugin pre-installation
2. Check network connectivity and firewall settings
3. Use offline plugin installation if needed

## Performance Monitoring

### Container Resource Usage
```bash
# Monitor real-time resource usage
watch docker stats $(docker ps -q --filter "name=jenkins-")

# Check container logs size
docker ps -q --filter "name=jenkins-" | xargs docker inspect --format='{{.LogPath}}' | xargs du -sh
```

### Jenkins Startup Time
```bash
# Measure startup time
start_time=$(date +%s)
until curl -f http://localhost:8189/login >/dev/null 2>&1; do
    sleep 2
done
end_time=$(date +%s)
echo "Jenkins startup time: $((end_time - start_time)) seconds"
```

### Health Monitoring
```bash
# Check all team containers health
for container in $(docker ps --filter "name=jenkins-" --format "{{.Names}}"); do
    echo "=== $container ==="
    docker exec $container curl -f http://localhost:8080/login >/dev/null 2>&1 && echo "✅ Healthy" || echo "❌ Unhealthy"
done
```

## Success Criteria

### ✅ Deployment Success Indicators
1. **No Setup Wizard**: Accessing Jenkins URL shows dashboard, not setup wizard
2. **CASC Configuration Applied**: System message shows correct team information
3. **Admin Access**: Can log in with configured admin credentials
4. **Plugin Functionality**: CASC and other required plugins are working
5. **Container Health**: All containers show healthy status
6. **API Access**: Jenkins API responds correctly
7. **Team Isolation**: Each team has separate, functional Jenkins instance

### 📊 Performance Benchmarks
- **Container Startup Time**: < 2 minutes for full startup
- **Memory Usage**: < configured limits (2-3GB per team)
- **CPU Usage**: < 50% during idle state
- **Disk Usage**: < 5GB per team initially

## Post-Deployment Steps

### 1. Create Initial Jobs
```bash
# Access Jenkins and create a test pipeline
# Use Job DSL to create team-specific folder structure
```

### 2. Configure Team-Specific Settings
- Set up team credentials
- Configure webhook endpoints
- Set up notification channels

### 3. Backup Configuration
```bash
# Create initial backup after successful deployment
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags backup
```

### 4. Set Up Monitoring
```bash
# Deploy monitoring stack if not already done
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags monitoring
```

## Maintenance Commands

### Regular Health Checks
```bash
# Weekly validation
./scripts/validate-jenkins-casc.sh devops
./scripts/validate-jenkins-casc.sh dev-qa

# Monthly resource cleanup
docker system prune -f
docker volume prune -f
```

### Configuration Updates
```bash
# Update team configurations
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags jenkins-master-v2

# Update only CASC configurations without container rebuild
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags jcasc
```

This comprehensive guide ensures successful deployment and validation of the fixed Jenkins CASC configuration, eliminating the setup wizard issue while maintaining full team functionality and security.