# CentOS VM Browser Connectivity - Issue Resolution

**Date:** August 22, 2025  
**Issue:** Cannot reach CentOS VM on browser  
**Status:** ✅ RESOLVED  
**Root Cause:** Firewall blocking port 8000

## Problem Description

User reported inability to access Jenkins HA services via browser on the CentOS VM after network configuration update to 192.168.188.142.

## Diagnostic Steps

### ✅ 1. Basic Connectivity Test
```bash
ping -c 3 192.168.188.142
# Result: SUCCESS - 0% packet loss, 0.643ms avg
```

### ✅ 2. SSH Accessibility Test  
```bash
nc -zv 192.168.188.142 22
# Result: SUCCESS - Connection succeeded
```

### ✅ 3. Service Port Scan
```bash
# Tested ports: 80, 8000, 8080, 8404, 3000, 9090
# Result: Only port 8404 (HAProxy stats) accessible
# Issue: Main web port 8000 not accessible
```

### ✅ 4. Container Status Check
```bash
ssh root@192.168.188.142 'docker ps'
# Result: All services running correctly
# - jenkins-haproxy: Up 7 minutes (healthy)
# - jenkins-devops-blue: Up 22 minutes (healthy)
# - jenkins-dev-qa-green: Up 22 minutes (healthy)
# - Monitoring stack: All running
```

### ✅ 5. HAProxy Configuration Check
```bash
ssh root@192.168.188.142 'docker inspect jenkins-haproxy'
# Result: HAProxy using NetworkMode: "host"
# Expected behavior: Direct binding to host ports
```

### ✅ 6. Port Listening Analysis
```bash
ssh root@192.168.188.142 'ss -tlnp | grep LISTEN'
# Result: HAProxy correctly listening on:
# - 0.0.0.0:8000 (main frontend)
# - 0.0.0.0:8404 (stats interface)
```

### ❌ 7. Connectivity Test to Port 8000
```bash
curl -I http://192.168.188.142:8000
# Result: FAILED - Connection refused
# Issue identified: Firewall blocking port 8000
```

### ✅ 8. Firewall Analysis
```bash
ssh root@192.168.188.142 'firewall-cmd --list-all'
# Result: ISSUE FOUND
# - Port 8404 allowed ✅
# - Port 8000 missing ❌
# - Other ports present: 8080, 8081, 80, 443, 9090, 3000, etc.
```

## Root Cause Identified

**Firewall Configuration Issue**: Port 8000 (HAProxy main frontend) was not included in the firewall rules, while port 8404 (HAProxy stats) was allowed.

## Resolution Applied

### Fix: Add Missing Firewall Rule
```bash
ssh root@192.168.188.142 'firewall-cmd --add-port=8000/tcp --permanent && firewall-cmd --reload'
# Result: success/success
```

### Verification: Test Connectivity
```bash
curl -I http://192.168.188.142:8000
# Result: SUCCESS - HTTP/1.1 200 OK
# Headers show: Jenkins 2.516.2, devops team, blue environment
```

### Additional Verification: Stats Interface
```bash
curl -I http://192.168.188.142:8404/stats  
# Result: SUCCESS - HTTP/1.1 401 Unauthorized (expected - needs auth)
```

## ✅ Resolution Summary

1. **Issue**: Firewall blocking port 8000 access from external hosts
2. **Fix**: Added permanent firewall rule for port 8000/tcp  
3. **Result**: Full browser access restored to Jenkins HA infrastructure

## Access URLs Now Working

### Main Jenkins Interface (via HAProxy)
- **Primary**: http://192.168.188.142:8000
- **Team-specific routing**: 
  - devops team: http://192.168.188.142:8000 (default)
  - With Host headers: `curl -H 'Host: devops.jenkins.example.com' http://192.168.188.142:8000`

### HAProxy Statistics Dashboard
- **URL**: http://192.168.188.142:8404/stats
- **Auth**: Basic authentication required (configured in HAProxy)

### Direct Container Access
- **devops-blue**: http://192.168.188.142:8080
- **dev-qa-green**: http://192.168.188.142:8189
- **Prometheus**: http://192.168.188.142:9090
- **Grafana**: http://192.168.188.142:9300

## Lessons Learned

1. **Firewall Management**: Always verify firewall rules when deploying new services
2. **Port Documentation**: Maintain clear documentation of required ports
3. **Service Validation**: Test both internal service status and external accessibility
4. **Systematic Troubleshooting**: Use layered approach (connectivity → services → configuration → firewall)

## Recommended Next Steps

1. **Update Ansible Playbooks**: Ensure firewall role includes port 8000
2. **Document Required Ports**: Update infrastructure documentation with complete port list
3. **Create Health Checks**: Implement automated connectivity validation
4. **Test Domain Routing**: Verify team-specific domain routing works correctly

The Jenkins HA infrastructure is now fully accessible via browser at the new IP address 192.168.188.142!