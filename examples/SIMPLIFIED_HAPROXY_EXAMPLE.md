# Simplified HAProxy Multi-Team Configuration

This document shows the new simplified HAProxy configuration for managing multiple Jenkins teams with clear default behavior.

## 🎯 **New Team Structure**

### **Teams Configuration**
- **devops** → Default team (handles both `jenkins.example.com` and `devops.jenkins.example.com`)
- **ma** → Marketing Analytics team (`ma.jenkins.example.com`)
- **ba** → Business Analytics team (`ba.jenkins.example.com`)
- **tw** → Test/QA team (`tw.jenkins.example.com`)

### **Port Assignments**
```yaml
devops: 8080/8180 (blue/green)
ma:     8081/8181 (blue/green)
ba:     8082/8182 (blue/green)  
tw:     8083/8183 (blue/green)
```

## 🌐 **Domain Routing Logic**

### **Frontend Routing (Simplified)**
```haproxy
# Monitoring services (highest priority)
prometheus.jenkins.example.com  → prometheus_backend
grafana.jenkins.example.com     → grafana_backend
node-exporter.jenkins.example.com → node_exporter_backend

# Team-specific routing
ma.jenkins.example.com          → jenkins_backend_ma
ba.jenkins.example.com          → jenkins_backend_ba
tw.jenkins.example.com          → jenkins_backend_tw

# DevOps team (explicit)
devops.jenkins.example.com      → jenkins_backend_devops

# Default (base domain)
jenkins.example.com             → jenkins_backend_devops (default)
```

### **What Changed**
❌ **Removed:** Confusing `primary_team` logic  
❌ **Removed:** Complex `jenkins_backend_default` vs `jenkins_backend_jenkins`  
❌ **Removed:** Fallback team configurations  
✅ **Added:** Clear team separation  
✅ **Added:** Predictable default behavior  
✅ **Added:** Consistent naming pattern  

## 📋 **Generated HAProxy Configuration Example**

Based on the new configuration, here's what gets generated:

### **Frontend Section**
```haproxy
frontend jenkins_http
    bind *:8000
    
    # Monitoring services routing (high priority - checked first)
    use_backend prometheus_backend if { hdr_beg(host) -i prometheus.jenkins.example.com }
    use_backend grafana_backend if { hdr_beg(host) -i grafana.jenkins.example.com }
    use_backend node_exporter_backend if { hdr_beg(host) -i node-exporter.jenkins.example.com }
    
    # Team-specific routing - specific subdomains first
    use_backend jenkins_backend_ma if { hdr_beg(host) -i ma.jenkins.example.com }
    use_backend jenkins_backend_ba if { hdr_beg(host) -i ba.jenkins.example.com }
    use_backend jenkins_backend_tw if { hdr_beg(host) -i tw.jenkins.example.com }
    
    # DevOps team handles both devops.jenkins.example.com AND jenkins.example.com (default)
    use_backend jenkins_backend_devops if { hdr_beg(host) -i devops.jenkins.example.com }
    
    # Default backend - routes to devops team
    default_backend jenkins_backend_devops
```

### **Backend Sections**
```haproxy
# DevOps team backend (default)
backend jenkins_backend_devops
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200
    
    # Blue environment active, green as backup
    server devops-centos9-vm-blue 192.168.86.30:8080 check inter 5s fall 3 rise 2
    server devops-centos9-vm-green 192.168.86.30:8180 check inter 5s fall 3 rise 2 backup
    
    # Team-specific headers
    http-response set-header X-Jenkins-Team devops
    http-response set-header X-Jenkins-Environment blue
    http-response set-header X-Team-Role default

# Marketing Analytics team backend
backend jenkins_backend_ma
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200
    
    # Blue environment active, green as backup
    server ma-centos9-vm-blue 192.168.86.30:8081 check inter 5s fall 3 rise 2
    server ma-centos9-vm-green 192.168.86.30:8181 check inter 5s fall 3 rise 2 backup
    
    # Team-specific headers
    http-response set-header X-Jenkins-Team ma
    http-response set-header X-Jenkins-Environment blue
    http-response set-header X-Team-Role marketing-analytics

# Business Analytics team backend
backend jenkins_backend_ba
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200
    
    # Blue environment active, green as backup
    server ba-centos9-vm-blue 192.168.86.30:8082 check inter 5s fall 3 rise 2
    server ba-centos9-vm-green 192.168.86.30:8182 check inter 5s fall 3 rise 2 backup
    
    # Team-specific headers
    http-response set-header X-Jenkins-Team ba
    http-response set-header X-Jenkins-Environment blue
    http-response set-header X-Team-Role business-analytics

# Test/QA team backend  
backend jenkins_backend_tw
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200
    
    # Blue environment active, green as backup
    server tw-centos9-vm-blue 192.168.86.30:8083 check inter 5s fall 3 rise 2
    server tw-centos9-vm-green 192.168.86.30:8183 check inter 5s fall 3 rise 2 backup
    
    # Team-specific headers
    http-response set-header X-Jenkins-Team tw
    http-response set-header X-Jenkins-Environment blue
    http-response set-header X-Team-Role test-qa
```

## 🧪 **Testing the New Configuration**

### **Domain Access Tests**
```bash
# Default domain (routes to devops)
curl -H "Host: jenkins.example.com" http://192.168.86.30:8000/login
# Expected: DevOps Jenkins login page

# DevOps team (explicit)
curl -H "Host: devops.jenkins.example.com" http://192.168.86.30:8000/login
# Expected: DevOps Jenkins login page

# Marketing Analytics team
curl -H "Host: ma.jenkins.example.com" http://192.168.86.30:8000/login
# Expected: MA Jenkins login page

# Business Analytics team
curl -H "Host: ba.jenkins.example.com" http://192.168.86.30:8000/login
# Expected: BA Jenkins login page

# Test/QA team
curl -H "Host: tw.jenkins.example.com" http://192.168.86.30:8000/login
# Expected: TW Jenkins login page
```

### **Blue-Green Testing**
```bash
# Test blue environment (default)
curl -v -H "Host: devops.jenkins.example.com" http://192.168.86.30:8000/login
# Should show X-Jenkins-Environment: blue header

# Switch to green environment (update inventory)
# active_environment: "green" in devops team config
# Then test again - should route to port 8180
```

### **Team Headers Verification**
```bash
# Check team-specific headers
curl -I -H "Host: ma.jenkins.example.com" http://192.168.86.30:8000/login | grep -E "X-Jenkins-Team|X-Team-Role"
# Expected: 
# X-Jenkins-Team: ma
# X-Team-Role: marketing-analytics
```

## 📊 **Benefits of New Configuration**

### **✅ Simplified Logic**
- No more confusing `primary_team` concepts
- Clear separation between teams
- Predictable default behavior

### **✅ Better Maintainability**
- Each team has identical backend structure
- Easy to add new teams
- Clear naming conventions

### **✅ Enhanced Monitoring**
- Team-specific response headers
- Role identification in headers
- Blue-green environment tracking

### **✅ Scalability**
- Easy to add new teams by adding to `jenkins_teams`
- Consistent port allocation (+100 for green environments)
- Supports multiple Jenkins masters per team

## 🔧 **Adding New Teams**

To add a new team (e.g., "devtest"):

```yaml
# Add to jenkins_teams in group_vars/all/main.yml
- team_name: "devtest"
  blue_green_enabled: true
  active_environment: "blue"
  ports:
    web: 8084
    agent: 50004
  resources:
    memory: "2g"
    cpu: "1.0"
  env_vars: {}
  labels:
    tier: "production"
    environment: "prod"
    role: "development-testing"
```

The HAProxy configuration will automatically generate:
- Frontend routing: `devtest.jenkins.example.com → jenkins_backend_devtest`
- Backend configuration with blue (8084) and green (8184) ports
- Health checks and team-specific headers

## 🏆 **Summary**

The new simplified HAProxy configuration provides:
- **Clear team separation** with devops as default
- **Predictable routing behavior** 
- **Easier maintenance and troubleshooting**
- **Better team isolation** with dedicated backends
- **Consistent blue-green deployment** across all teams
- **Enhanced monitoring** with team-specific headers

This approach eliminates the confusion of the previous `primary_team` logic while maintaining all enterprise HA features.