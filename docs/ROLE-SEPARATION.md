# Role Separation and Architecture

This document explains the clear separation of responsibilities between the jenkins-master and high-availability roles.

## 🏗️ Role Architecture

### **Jenkins-Master Role**
**Purpose**: Deploy and manage Jenkins container instances  
**Scope**: Container lifecycle management only  
**Hosts**: `jenkins_masters` group

**Responsibilities:**
- ✅ Deploy Jenkins containers (blue-green environments)  
- ✅ Manage container volumes and storage
- ✅ Handle Jenkins configuration (JCasC)
- ✅ Blue-green environment switching
- ✅ Container health monitoring
- ❌ **NO HAProxy management** (disabled by default)

### **High-Availability Role** 
**Purpose**: Load balancing and traffic routing  
**Scope**: HAProxy container + multi-team routing  
**Hosts**: `load_balancers` group

**Responsibilities:**
- ✅ Deploy containerized HAProxy
- ✅ Multi-team subdomain routing (*.devops.example.com)
- ✅ SSL/TLS termination with wildcard certificates
- ✅ Blue-green backend configuration
- ✅ Health checks and failover
- ✅ VIP management with keepalived

## 🔄 Role Interaction Flow

```
1. jenkins-master role → Deploys Jenkins containers
   └── Jenkins containers listen on team-specific ports (8080, 8081, 8082...)

2. high-availability role → Deploys HAProxy container  
   └── HAProxy routes subdomains to Jenkins backend ports
       ├── jenkins.devops.example.com → 8080
       ├── dev.devops.example.com → 8081  
       └── staging.devops.example.com → 8082
```

## ⚠️ Previous Conflict (RESOLVED)

**Problem**: Both roles were trying to manage HAProxy configuration:
- `jenkins-master` created individual team configs (`/etc/haproxy/conf.d/jenkins-team.cfg`)  
- `high-availability` created unified config (`/etc/haproxy/haproxy.cfg`)

**Solution**: 
- ✅ `jenkins-master` HAProxy integration **disabled by default** (`jenkins_master_haproxy_enabled: false`)
- ✅ `high-availability` role **exclusively manages HAProxy**
- ✅ Clear role separation documented

## 🚀 Deployment Order

```yaml
# site.yml orchestration
1. Deploy Jenkins Containers:
   hosts: jenkins_masters
   roles: [jenkins-master]

2. Deploy HAProxy Load Balancer:  
   hosts: load_balancers
   roles: [high-availability]

3. Configure Monitoring:
   hosts: monitoring  
   roles: [monitoring]
```

## 🎯 Configuration Variables

### **For Jenkins Container Management:**
```yaml
# Use jenkins-master role variables
jenkins_teams:
  - team_name: "devops"
    active_environment: "blue"
    ports: { web: 8080, agent: 50000 }
```

### **For HAProxy Load Balancing:**
```yaml
# Use high-availability role variables  
haproxy_container_runtime: "docker"
ssl_enabled: true
jenkins_domain: "devops.example.com"
```

## ✅ Benefits of This Separation

1. **Single Responsibility**: Each role has a clear, focused purpose
2. **No Conflicts**: HAProxy managed by one role only
3. **Flexibility**: Can deploy Jenkins without HAProxy, or HAProxy without Jenkins
4. **Containerization**: Both services run in separate containers
5. **Scalability**: Independent scaling of Jenkins vs load balancing

## 🏷️ Tags for Selective Deployment

```bash
# Deploy only Jenkins containers
ansible-playbook site.yml --tags "jenkins,container"

# Deploy only HAProxy load balancer  
ansible-playbook site.yml --tags "ha,haproxy,loadbalancer"

# Deploy everything
ansible-playbook site.yml --tags "all"
```

This architecture provides clean separation while maintaining all multi-team functionality and wildcard subdomain routing.