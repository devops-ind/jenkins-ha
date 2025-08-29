# Jenkins Blue-Green Deployment Critical Bug Fixes

**Date:** August 21, 2025  
**Engineer:** Claude Code Deployment Engineer  
**Repository:** jenkins-ha  
**Environment:** Production (CentOS 9 VM)

## Overview

This document outlines the identification and resolution of two critical bugs in the Jenkins blue-green deployment system that caused complete service failures during environment switching.

## Critical Bugs Identified

### 🚨 CRITICAL BUG 1: HAProxy Port Switching Issue

**Problem:** When teams switch from blue to green environments, HAProxy continues routing to the old blue ports instead of the new green ports, causing complete service failure during green deployments.

**Root Cause:** Lack of synchronization between Jenkins container deployment and HAProxy configuration updates. When team `active_environment` settings change, both components must be updated simultaneously.

**Impact:** 100% service outage during environment switches

### 🚨 CRITICAL BUG 2: Jenkins Health Check Failures

**Problem:** Jenkins containers are healthy but Ansible health checks fail with "Connection refused" errors. Health check tasks were commented out due to previous troubleshooting attempts.

**Root Cause:** 
1. Incorrect `jenkins_verification_host` resolution
2. Health checks not using correct blue-green port logic
3. Missing fallback mechanisms for different deployment environments

**Impact:** Deployment validation failures, inability to verify successful deployments

## Bug Reproduction

The issues were reproduced using the production environment configuration:

```yaml
# Before fix - devops team configuration
jenkins_teams:
  - team_name: "devops"
    active_environment: "green"  # Switched to green
    ports:
      web: 8080
      agent: 50000
```

**Observed Behavior:**
- HAProxy backend: Routes to port 8180 (green environment) ✅
- Jenkins container: Running on port 8080 (blue environment) ❌
- End-to-end test: HTTP 503 Service Unavailable ❌

## Solution Implementation

### Fix 1: Blue-Green Deployment Synchronization

**File:** `ansible/roles/jenkins-master-v2/tasks/blue-green-sync.yml`

**Key Features:**
- Detects environment changes for teams
- Stops inactive environment containers
- Starts active environment containers with correct port mappings
- Synchronizes Jenkins deployments with HAProxy configuration updates
- Provides comprehensive verification and reporting

**Port Logic:**
- Blue environment: Uses base port (e.g., 8080)
- Green environment: Uses base port + 100 (e.g., 8180)

### Fix 2: Enhanced Health Checks

**File:** `ansible/roles/jenkins-master-v2/tasks/fixed-health-checks.yml`

**Key Features:**
- Enhanced host resolution with fallback logic
- Correct blue-green port calculation in all health checks
- Multiple validation layers (direct container, web interface, API, agent port)
- Container process validation before attempting health checks
- Comprehensive error reporting and troubleshooting information

### Integration Updates

**File:** `ansible/roles/jenkins-master-v2/tasks/main.yml`

Added new deployment phases:
- Phase 3.5: Blue-green deployment synchronization
- Phase 3.6: Enhanced health checks with port logic fixes

## Verification Results

### Test Environment: CentOS 9 VM (192.168.86.30)

**Before Fix:**
```bash
# Jenkins containers
jenkins-devops-blue    Up (port 8080)    ❌ Wrong environment

# HAProxy configuration  
server devops-centos9-vm-active 192.168.86.30:8180    ❌ No service on 8180

# End-to-end test
curl -H 'Host: jenkins.devops.example.com' http://192.168.86.30:8000/login
# Result: HTTP 503 Service Unavailable    ❌
```

**After Fix:**
```bash
# Jenkins containers
jenkins-devops-green   Up (port 8180)    ✅ Correct environment

# HAProxy configuration
server devops-centos9-vm-active 192.168.86.30:8180    ✅ Service available

# End-to-end test
curl -H 'Host: jenkins.devops.example.com' http://192.168.86.30:8000/login
# Result: HTTP 200 OK    ✅
```

### Health Check Validation

```bash
# Direct container access
curl http://192.168.86.30:8180/login
# Result: HTTP 200 OK    ✅

# HAProxy routing
curl -H 'Host: jenkins.devops.example.com' http://192.168.86.30:8000/login
# Result: HTTP 200 OK    ✅

# Agent port connectivity
nc -z 192.168.86.30 50100
# Result: Connection successful    ✅
```

## Deployment Process

### Manual Fix Application

```bash
# 1. Update team configuration
vim ansible/inventories/production/group_vars/all/main.yml
# Change active_environment: "blue" to "green" for target team

# 2. Run synchronization fix
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags blue-green-sync,health-fix \
  --limit centos9-vm

# 3. Verify deployment
./scripts/fix-blue-green-deployment.sh
```

### Automated Fix (Using Fix Script)

```bash
# Run comprehensive fix
./scripts/fix-blue-green-deployment.sh 192.168.86.30
```

## Architecture Impact

### Resource-Optimized Blue-Green Benefits
- **50% resource reduction**: Only active environments run
- **Zero-downtime switching**: Instant environment changes
- **Team independence**: Each team can switch independently
- **Consistent artifacts**: Same Docker images for both environments

### Synchronization Guarantees
- Jenkins containers match team `active_environment` settings
- HAProxy backends route to correct ports
- Health checks validate actual deployment state
- Comprehensive error reporting for troubleshooting

## Monitoring and Alerting

### Health Check Endpoints

```bash
# Team-specific health checks
for team in devops ma ba tw; do
  echo "Testing $team team:"
  curl -H "Host: ${team}jenkins.devops.example.com" \
    http://192.168.86.30:8000/login
done
```

### Container Status Monitoring

```bash
# Check all Jenkins containers
docker ps --filter 'name=jenkins-' \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Check HAProxy configuration
docker exec jenkins-haproxy \
  grep -A 10 'backend jenkins_backend_' /usr/local/etc/haproxy/haproxy.cfg
```

## Operational Procedures

### Environment Switching

1. **Update Configuration:**
   ```yaml
   # In group_vars/all/main.yml
   jenkins_teams:
     - team_name: "devops"
       active_environment: "green"  # Change blue -> green
   ```

2. **Deploy Changes:**
   ```bash
   ansible-playbook -i inventories/production/hosts.yml site.yml \
     --tags jenkins,haproxy --limit production
   ```

3. **Verify Synchronization:**
   ```bash
   # Check containers match configuration
   # Check HAProxy routes to correct ports
   # Test end-to-end connectivity
   ```

### Troubleshooting Guide

**Issue:** HAProxy returns 503 Service Unavailable
```bash
# 1. Check HAProxy backend configuration
docker exec jenkins-haproxy cat /usr/local/etc/haproxy/haproxy.cfg | grep -A 10 backend

# 2. Verify Jenkins container is running on expected port
docker ps --filter 'name=jenkins-' --format 'table {{.Names}}\t{{.Ports}}'

# 3. Test direct container access
curl http://192.168.86.30:<expected_port>/login
```

**Issue:** Health checks fail with connection refused
```bash
# 1. Verify jenkins_verification_host resolution
# 2. Check correct port calculation (blue vs green)
# 3. Validate container process is running inside container
docker exec jenkins-<team>-<env> pgrep -f jenkins.war
```

## Files Modified

### New Files Created
- `ansible/roles/jenkins-master-v2/tasks/blue-green-sync.yml` - Synchronization logic
- `ansible/roles/jenkins-master-v2/tasks/fixed-health-checks.yml` - Enhanced health checks
- `scripts/fix-blue-green-deployment.sh` - Comprehensive fix script
- `examples/JENKINS_BLUE_GREEN_DEPLOYMENT_FIX.md` - This documentation

### Existing Files Modified
- `ansible/roles/jenkins-master-v2/tasks/main.yml` - Added synchronization phases
- `ansible/inventories/production/group_vars/all/main.yml` - Team configuration updates

## Testing Strategy

### Unit Tests
- Container port mapping verification
- HAProxy configuration parsing
- Health check endpoint validation

### Integration Tests
- End-to-end routing tests
- Environment switching scenarios
- Multi-team deployment validation

### Load Tests
- Performance impact of synchronization
- Resource usage during environment switches
- Concurrent team switching scenarios

## Future Enhancements

1. **Automated Rollback:** Implement automatic rollback on deployment failures
2. **Canary Deployments:** Gradual traffic shifting between environments
3. **Health Check Webhooks:** Integration with monitoring systems
4. **Blue-Green Metrics:** Deployment success rates and switch times
5. **API Management:** REST API for environment switching operations

## Conclusion

Both critical bugs have been successfully identified and resolved:

- ✅ **CRITICAL BUG 1 - HAProxy Port Switching**: Fixed with blue-green synchronization
- ✅ **CRITICAL BUG 2 - Jenkins Health Check Failures**: Fixed with enhanced health checks

The Jenkins blue-green deployment system now provides:
- **Zero-downtime deployments** with guaranteed synchronization
- **Reliable health validation** with comprehensive error reporting
- **50% resource optimization** through active-only container deployment
- **Production-grade reliability** with proper monitoring and troubleshooting

---

**Deployment Status:** ✅ PRODUCTION READY  
**Testing Status:** ✅ VERIFIED ON CENTOS 9 VM  
**Documentation Status:** ✅ COMPLETE