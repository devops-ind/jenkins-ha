# Local Development Setup Guide

## Overview

The simplified GlusterFS architecture automatically adapts for local development environments (devcontainers, local machines) by falling back to Docker volumes when GlusterFS is not available.

---

## Automatic Deployment Mode Detection

### Configuration Check

The system checks two variables to determine storage backend:

```yaml
# ansible/inventories/local/group_vars/all/main.yml
shared_storage_enabled: false  # Disabled for local dev
shared_storage_type: "local"   # Not "glusterfs"
```

When **BOTH** conditions are met for production:
- `shared_storage_enabled: true`
- `shared_storage_type: "glusterfs"`

Then GlusterFS direct mounts are used.

Otherwise, Docker volumes are created automatically.

---

## Storage Backend Comparison

### Production Mode (GlusterFS)

```yaml
# Configuration
shared_storage_enabled: true
shared_storage_type: "glusterfs"

# Container Volumes
volumes:
  - /var/jenkins/devops/data/blue:/var/jenkins_home  # GlusterFS FUSE mount
  - jenkins-devops-cache:/var/jenkins_home/.cache    # Docker volume (cache only)
```

**Characteristics**:
- ✅ Replicated across VMs (RPO < 5s)
- ✅ Zero data loss on VM failure
- ✅ Automatic failover (RTO < 30s)
- ✅ Blue/green isolation via subdirectories
- ❌ Requires GlusterFS infrastructure

---

### Local/DevContainer Mode (Docker Volumes)

```yaml
# Configuration
shared_storage_enabled: false
shared_storage_type: "local"  # or anything except "glusterfs"

# Container Volumes
volumes:
  - jenkins-devops-blue-home:/var/jenkins_home       # Docker volume
  - jenkins-devops-cache:/var/jenkins_home/.cache    # Docker volume
```

**Characteristics**:
- ✅ No infrastructure required
- ✅ Fast startup (no network filesystem)
- ✅ Works in devcontainers, Docker Desktop, Podman
- ✅ Simple local testing
- ❌ Not replicated (local only)
- ❌ No automatic failover

---

## Local Development Deployment

### Step 1: Verify Local Configuration

```bash
# Check local inventory settings
cat ansible/inventories/local/group_vars/all/main.yml | grep shared_storage

# Expected output:
# shared_storage_enabled: false
# shared_storage_type: "local"
```

### Step 2: Deploy to Local Environment

```bash
# Deploy Jenkins with automatic Docker volume fallback
ansible-playbook \
  -i ansible/inventories/local/hosts.yml \
  ansible/site.yml \
  --tags jenkins

# GlusterFS role automatically skipped (shared_storage_enabled: false)
```

### Step 3: Verify Docker Volumes Created

```bash
# List Jenkins Docker volumes
docker volume ls | grep jenkins

# Expected volumes:
# jenkins-devops-blue-home      # Blue environment data
# jenkins-devops-green-home     # Green environment data
# jenkins-devops-cache          # Cache directory
# jenkins-devops-m2-cache       # Maven cache
# jenkins-devops-pip-cache      # Python cache
# jenkins-devops-npm-cache      # Node.js cache
```

### Step 4: Verify Container Mounts

```bash
# Check blue environment volume mount
docker inspect jenkins-devops-blue | jq '.[].Mounts[] | select(.Destination=="/var/jenkins_home")'

# Expected output:
# {
#   "Type": "volume",
#   "Name": "jenkins-devops-blue-home",
#   "Source": "/var/lib/docker/volumes/jenkins-devops-blue-home/_data",
#   "Destination": "/var/jenkins_home",
#   "Driver": "local",
#   "Mode": "z",
#   "RW": true,
#   "Propagation": ""
# }
```

---

## DevContainer Configuration

### .devcontainer/docker-compose.yml

```yaml
version: '3.8'

services:
  jenkins-devops-blue:
    image: jenkins-devops:latest
    container_name: jenkins-devops-blue
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      # Docker volume (auto-created)
      - jenkins-devops-blue-home:/var/jenkins_home
      - jenkins-devops-cache:/var/jenkins_home/.cache
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - JENKINS_OPTS=--prefix=/
      - JAVA_OPTS=-Xmx2g

volumes:
  jenkins-devops-blue-home:
    driver: local
  jenkins-devops-cache:
    driver: local
```

**Note**: Ansible playbook will create these volumes automatically, no manual creation needed.

---

## Testing Blue-Green Switch Locally

### Step 1: Deploy Both Environments

```bash
# Blue environment
ansible-playbook \
  -i ansible/inventories/local/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "jenkins_teams_config=[{team_name: 'devops', active_environment: 'blue', ports: {web: 8080, agent: 50000}}]"

# Green environment
ansible-playbook \
  -i ansible/inventories/local/hosts.yml \
  ansible/site.yml \
  --tags jenkins \
  -e "jenkins_teams_config=[{team_name: 'devops', active_environment: 'green', ports: {web: 8080, agent: 50000}}]"
```

### Step 2: Verify Both Containers

```bash
# Check running containers
docker ps | grep jenkins

# Expected:
# jenkins-devops-blue   (or jenkins-devops-green, depending on active_environment)
```

### Step 3: Test Switch

```bash
# Update inventory active_environment from 'blue' to 'green'
# Then redeploy
ansible-playbook \
  -i ansible/inventories/local/hosts.yml \
  ansible/site.yml \
  --tags jenkins,haproxy

# Traffic now routes to green environment
```

---

## Differences from Production

| Feature | Production (GlusterFS) | Local (Docker Volumes) |
|---------|------------------------|------------------------|
| **Storage Backend** | GlusterFS FUSE mount | Docker local volume |
| **Replication** | Real-time across VMs | None (single host) |
| **Data Persistence** | Survives VM failure | Survives container restart |
| **Blue-Green Isolation** | Subdirectories on same volume | Separate Docker volumes |
| **Failover** | Automatic (< 30s) | Manual container restart |
| **Performance** | Network filesystem | Local disk (faster) |
| **Setup Complexity** | Requires GlusterFS cluster | Zero infrastructure |
| **Use Case** | Production HA | Local development |

---

## Troubleshooting Local Development

### Issue: Containers Won't Start

**Symptoms**: Container exits immediately

**Solution**:
```bash
# Check logs
docker logs jenkins-devops-blue

# Common issues:
# 1. Volume mount permission denied
docker volume rm jenkins-devops-blue-home
docker volume create jenkins-devops-blue-home

# 2. Port already in use
lsof -i :8080
kill <pid>
```

---

### Issue: Data Not Persisting

**Symptoms**: Jobs/configuration lost after container restart

**Solution**:
```bash
# Verify volume exists
docker volume inspect jenkins-devops-blue-home

# Check data in volume
docker run --rm \
  -v jenkins-devops-blue-home:/data \
  alpine ls -la /data

# Should show: jobs/, builds/, config.xml, etc.
```

---

### Issue: Want to Test with GlusterFS Locally

**Symptoms**: Want to simulate production GlusterFS setup locally

**Solution**:

```bash
# Option 1: Install GlusterFS in local VM cluster
# See: examples/glusterfs-migration-guide.md for setup

# Option 2: Mock GlusterFS with local directory mount
# Edit: ansible/inventories/local/group_vars/all/main.yml
shared_storage_enabled: true
shared_storage_type: "glusterfs"

# Create mock directories
mkdir -p /var/jenkins/devops/data/blue
mkdir -p /var/jenkins/devops/data/green
sudo chown -R 1000:1000 /var/jenkins/devops/

# Deploy (will use directory mounts instead of Docker volumes)
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags jenkins
```

---

## Migration from Local to Production

When moving from local development to production:

### Step 1: Backup Local Data

```bash
# Export blue environment data
docker run --rm \
  -v jenkins-devops-blue-home:/source:ro \
  -v $(pwd)/backup:/backup \
  alpine tar czf /backup/local-blue.tar.gz -C /source .
```

### Step 2: Deploy GlusterFS in Production

```bash
# See: examples/glusterfs-migration-guide.md
ansible-playbook \
  -i ansible/inventories/production/hosts.yml \
  ansible/site.yml \
  --tags glusterfs
```

### Step 3: Import Data to Production

```bash
# Copy to GlusterFS mount
scp backup/local-blue.tar.gz vm1:/tmp/

# Extract on production
ssh vm1 "tar xzf /tmp/local-blue.tar.gz -C /var/jenkins/devops/data/blue/"
```

---

## Environment Variables Reference

### Production Configuration
```yaml
# ansible/inventories/production/group_vars/all/main.yml
deployment_environment: "production"
deployment_mode: "production"
shared_storage_enabled: true
shared_storage_type: "glusterfs"
```

### Local Configuration
```yaml
# ansible/inventories/local/group_vars/all/main.yml
deployment_environment: "local"
deployment_mode: "local"
shared_storage_enabled: false
shared_storage_type: "local"
```

---

## Conditional Logic Reference

The volume mount decision is made here:

```yaml
# ansible/roles/jenkins-master-v2/tasks/image-and-container.yml:219
_active_volumes:
  - "{% if shared_storage_enabled | default(false) and shared_storage_type | default('local') == 'glusterfs' %}/var/jenkins/{{ item.team_name }}/data/{{ item.active_environment }}{% else %}jenkins-{{ item.team_name }}-{{ item.active_environment }}-home{% endif %}:{{ jenkins_master_container_home }}"
```

**Breakdown**:
```
IF (shared_storage_enabled == true AND shared_storage_type == "glusterfs"):
    Use: /var/jenkins/{team}/data/{env}  (GlusterFS mount)
ELSE:
    Use: jenkins-{team}-{env}-home       (Docker volume)
```

---

## Quick Start Commands

### Start Local Development
```bash
# Clone repository
git clone <repo-url>
cd jenkins-ha

# Deploy to local
make deploy-local

# Or manually
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml

# Access Jenkins
open http://localhost:8080
```

### Clean Up Local Volumes
```bash
# Stop containers
docker stop $(docker ps -q --filter "name=jenkins")

# Remove volumes
docker volume rm $(docker volume ls -q --filter "name=jenkins")

# Redeploy fresh
make deploy-local
```

---

## Summary

The simplified GlusterFS architecture provides:

1. **Automatic Adaptation**: No code changes needed for local vs production
2. **Simple Local Development**: Zero infrastructure required
3. **Production-Ready**: Just enable GlusterFS in production inventory
4. **Consistent Behavior**: Same Jenkins functionality in both modes
5. **Easy Migration**: Export from Docker volumes, import to GlusterFS

**Local Development**: `shared_storage_enabled: false` → Docker volumes
**Production**: `shared_storage_enabled: true` + `shared_storage_type: glusterfs` → GlusterFS

---

**Version**: 1.0
**Last Updated**: 2025-01-07
**Tested**: Docker Desktop 24.x, DevContainers, Local VMs
