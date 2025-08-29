# Jenkins HA Domain Testing Guide - Single VM Multi-Team Setup

This guide explains how to test wildcard domain routing for multiple Jenkins masters and monitoring services running on a single VM using HAProxy.

## 🏗️ Architecture Overview

### Domain Structure
The Jenkins HA setup uses wildcard domain routing to separate teams and services on a single VM:

```
jenkins.example.com (base domain)
├── devops.jenkins.example.com     → DevOps Jenkins (port 8080/8180)
├── developer.jenkins.example.com  → Developer Jenkins (port 8081/8181)  
├── jenkins.jenkins.example.com    → Admin Jenkins (port 8082/8182)
├── prometheus.jenkins.example.com → Prometheus (port 9090)
├── grafana.jenkins.example.com    → Grafana (port 9300)
└── node-exporter.jenkins.example.com → Node Exporter (port 9100)
```

### Blue-Green Port Strategy
Each Jenkins team has dual ports for zero-downtime deployment:
- **Blue Environment** (Active): Base port (8080, 8081, 8082)
- **Green Environment** (Standby): Base port + 100 (8180, 8181, 8182)
- **Monitoring Services**: Fixed ports (9090, 9300, 9100)

## 🌐 DNS Configuration

### Production DNS Setup
For production environments, configure DNS A records:

```dns
jenkins.example.com          A    192.168.86.30
*.jenkins.example.com        A    192.168.86.30
devops.jenkins.example.com   A    192.168.86.30
developer.jenkins.example.com A   192.168.86.30
prometheus.jenkins.example.com A  192.168.86.30
grafana.jenkins.example.com A    192.168.86.30
```

### Local Testing with /etc/hosts
For testing without DNS, add to `/etc/hosts`:

```bash
# Jenkins HA Teams
192.168.86.30 jenkins.example.com
192.168.86.30 devops.jenkins.example.com
192.168.86.30 developer.jenkins.example.com
192.168.86.30 jenkins.jenkins.example.com

# Monitoring Stack
192.168.86.30 prometheus.jenkins.example.com
192.168.86.30 grafana.jenkins.example.com  
192.168.86.30 node-exporter.jenkins.example.com

# HAProxy Stats
192.168.86.30 haproxy-stats.jenkins.example.com
```

## 🚀 Deployment and Testing

### 1. Deploy Jenkins HA Infrastructure

```bash
# Deploy complete infrastructure
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

# Deploy only HAProxy for routing updates
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags haproxy
```

### 2. Verify HAProxy Configuration

```bash
# Check HAProxy configuration syntax
docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# View HAProxy stats
curl -u admin:admin123 http://192.168.86.30:8404/stats

# Test configuration generation
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags configuration --check
```

### 3. Test Domain Routing

#### Jenkins Team Access Tests

```bash
# Test DevOps team (Blue environment - port 8080)
curl -H "Host: devops.jenkins.example.com" http://192.168.86.30:8000/login
# Expected: Jenkins login page

# Test Developer team (Blue environment - port 8081)  
curl -H "Host: developer.jenkins.example.com" http://192.168.86.30:8000/login
# Expected: Jenkins login page

# Test Jenkins admin team (Blue environment - port 8082)
curl -H "Host: jenkins.jenkins.example.com" http://192.168.86.30:8000/login
# Expected: Jenkins login page
```

#### Monitoring Services Tests

```bash
# Test Prometheus access
curl -H "Host: prometheus.jenkins.example.com" http://192.168.86.30:9090/graph
# Expected: Prometheus web interface

# Test Grafana access  
curl -H "Host: grafana.jenkins.example.com" http://192.168.86.30:9300/login
# Expected: Grafana login page

# Test Node Exporter metrics
curl -H "Host: node-exporter.jenkins.example.com" http://192.168.86.30:9100/metrics
# Expected: Prometheus metrics
```

#### Browser Testing

```bash
# Open team-specific Jenkins instances
firefox https://devops.jenkins.example.com
firefox https://developer.jenkins.example.com  
firefox https://jenkins.jenkins.example.com

# Open monitoring services
firefox https://prometheus.jenkins.example.com
firefox https://grafana.jenkins.example.com
```

## 🔄 Blue-Green Deployment Testing

### Switch Environment
```bash
# Switch devops team to green environment
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags haproxy \
  -e '{"jenkins_teams": [{"team_name": "devops", "active_environment": "green", "ports": {"web": 8080}}]}'

# Verify routing to green port (8180)
curl -v -H "Host: devops.jenkins.example.com" http://192.168.86.30:8000/login
# Should show routing to port 8180
```

### Deployment Health Checks
```bash
# Check all team health endpoints
for team in devops developer jenkins; do
  echo "Testing $team team health..."
  curl -f -H "Host: $team.jenkins.example.com" \
    http://192.168.86.30:8000/api/json?pretty=true
done
```

## 📊 Monitoring and Troubleshooting

### HAProxy Stats Dashboard
Access comprehensive routing statistics:
```bash
# Web interface
http://192.168.86.30:8404/stats

# Command line stats
echo "show stat" | socat stdio /run/haproxy/admin.sock
```

### Container Logs
```bash
# HAProxy logs
docker logs jenkins-haproxy --tail 50 -f

# Individual Jenkins containers  
docker logs jenkins-devops-blue --tail 50
docker logs jenkins-developer-blue --tail 50
docker logs jenkins-jenkins-blue --tail 50
```

### Port Verification
```bash
# Verify all ports are listening
netstat -tlnp | grep -E ':8080|:8081|:8082|:8180|:8181|:8182|:9090|:9300|:9100'

# Test direct port access (bypassing domain routing)
curl http://192.168.86.30:8080/login  # DevOps blue
curl http://192.168.86.30:8081/login  # Developer blue  
curl http://192.168.86.30:8082/login  # Jenkins blue
```

## 🔧 Common Issues and Solutions

### Issue: Domain routing not working
**Solution:**
1. Verify `/etc/hosts` entries or DNS configuration
2. Check HAProxy container is running: `docker ps | grep haproxy`
3. Validate HAProxy configuration: `docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg`

### Issue: SSL certificate errors
**Solution:**
```bash
# For testing, use HTTP instead of HTTPS
curl -H "Host: devops.jenkins.example.com" http://192.168.86.30:8000/login

# Or ignore SSL for testing
curl -k -H "Host: devops.jenkins.example.com" https://192.168.86.30:8000/login
```

### Issue: Backend services unavailable (502/503 errors)
**Solution:**
```bash
# Check if Jenkins containers are running
docker ps | grep jenkins

# Check container health
docker exec jenkins-devops-blue curl -f http://localhost:8080/login

# Restart failed containers
docker restart jenkins-devops-blue
```

### Issue: Port conflicts
**Solution:**
1. Ensure no other services using Jenkins ports: `lsof -i :8080-8082`
2. Check firewall allows the ports: `firewall-cmd --list-ports`
3. Verify container port mapping: `docker port jenkins-devops-blue`

## 📈 Performance Testing

### Load Testing with curl
```bash
# Test concurrent requests to different teams
for i in {1..10}; do
  curl -H "Host: devops.jenkins.example.com" http://192.168.86.30:8000/login &
  curl -H "Host: developer.jenkins.example.com" http://192.168.86.30:8000/login &
  curl -H "Host: jenkins.jenkins.example.com" http://192.168.86.30:8000/login &
done
wait
```

### HAProxy Performance Metrics
```bash
# View connection statistics
echo "show info" | socat stdio /run/haproxy/admin.sock | grep -E "CurrConns|MaxConn"

# Backend server statistics  
echo "show stat" | socat stdio /run/haproxy/admin.sock | grep "jenkins-"
```

## 🔒 Security Validation

### SSL/TLS Testing (when enabled)
```bash
# Test SSL certificate validity
openssl s_client -connect jenkins.example.com:443 -servername devops.jenkins.example.com

# Test SSL routing for each team
curl -v https://devops.jenkins.example.com/login
curl -v https://developer.jenkins.example.com/login
curl -v https://jenkins.jenkins.example.com/login
```

### Security Headers Validation
```bash
# Check security headers are applied
curl -I -H "Host: devops.jenkins.example.com" http://192.168.86.30:8000/login | grep -E "X-Content-Type|X-Frame|X-XSS"
```

---

## 📝 Summary

This guide covers comprehensive testing of the Jenkins HA domain configuration including:
- ✅ Multi-team domain routing validation
- ✅ Monitoring services domain integration  
- ✅ Blue-green deployment verification
- ✅ Performance and security testing
- ✅ Troubleshooting common issues

The single VM setup with wildcard domain routing provides a scalable foundation for multi-team Jenkins environments with integrated monitoring and zero-downtime deployments.