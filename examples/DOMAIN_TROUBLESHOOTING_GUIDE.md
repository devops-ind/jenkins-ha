# Jenkins HA Domain Troubleshooting Guide

This comprehensive guide helps troubleshoot domain routing issues in the Jenkins HA setup with HAProxy, multiple Jenkins teams, and monitoring services.

## 🚨 Common Domain Issues & Solutions

### 1. **Domain Not Resolving**

#### Symptoms:
```bash
$ curl https://devops.jenkins.example.com/login
curl: (6) Could not resolve host: devops.jenkins.example.com
```

#### Diagnosis:
```bash
# Test DNS resolution
nslookup devops.jenkins.example.com
dig devops.jenkins.example.com +short

# Check /etc/hosts file
grep jenkins /etc/hosts
```

#### Solutions:

**For DNS Issues:**
```bash
# Add to DNS provider
devops.jenkins.example.com    A    192.168.188.142

# Or use wildcard
*.jenkins.example.com         A    192.168.188.142
```

**For Local Testing:**
```bash
# Add to /etc/hosts
echo "192.168.188.142 devops.jenkins.example.com" | sudo tee -a /etc/hosts
echo "192.168.188.142 prometheus.jenkins.example.com" | sudo tee -a /etc/hosts
```

**Clear DNS Cache:**
```bash
# Linux
sudo systemctl flush-dns

# macOS  
sudo dscacheutil -flushcache

# Windows
ipconfig /flushdns
```

---

### 2. **HAProxy Not Routing Correctly (502/503 Errors)**

#### Symptoms:
```bash
$ curl -H "Host: devops.jenkins.example.com" http://192.168.188.142:8000/login
HTTP/1.1 502 Bad Gateway
```

#### Diagnosis:
```bash
# Check HAProxy container status
docker ps | grep haproxy
docker logs jenkins-haproxy --tail 20

# Check HAProxy configuration
docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Test HAProxy stats
curl -u admin:admin123 http://192.168.188.142:8404/stats
```

#### Solutions:

**HAProxy Container Issues:**
```bash
# Restart HAProxy container
docker restart jenkins-haproxy

# Check container health
docker inspect jenkins-haproxy --format='{{.State.Health.Status}}'

# View detailed container info
docker inspect jenkins-haproxy
```

**Configuration Issues:**
```bash
# Regenerate HAProxy configuration
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags haproxy,configuration

# Validate configuration syntax
docker run --rm -v /etc/haproxy/haproxy.cfg:/tmp/haproxy.cfg:ro \
  haproxy:2.8 haproxy -c -f /tmp/haproxy.cfg
```

**Backend Service Issues:**
```bash
# Check if Jenkins containers are running
docker ps | grep jenkins

# Test direct backend access
curl http://192.168.188.142:8080/login  # DevOps blue
curl http://192.168.188.142:8081/login  # Developer blue
curl http://192.168.188.142:9090/graph  # Prometheus
```

---

### 3. **Jenkins Teams Not Accessible**

#### Symptoms:
```bash
$ curl https://devops.jenkins.example.com/login
HTTP/1.1 404 Not Found
# or connection timeout
```

#### Diagnosis:
```bash
# Check jenkins team containers
docker ps | grep jenkins-
docker logs jenkins-devops-blue --tail 20

# Verify ports are listening
netstat -tlnp | grep -E ':8080|:8081|:8082'
lsof -i :8080
```

#### Solutions:

**Container Not Running:**
```bash
# Start missing Jenkins containers
docker start jenkins-devops-blue
docker start jenkins-developer-blue
docker start jenkins-jenkins-blue

# Check container logs for startup issues
docker logs jenkins-devops-blue --tail 50

# Recreate container if needed
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins-master
```

**Port Conflicts:**
```bash
# Check if ports are already in use
sudo lsof -i :8080
sudo netstat -tlnp | grep :8080

# Kill conflicting processes
sudo kill -9 $(lsof -t -i:8080)

# Update port configuration if needed
vim ansible/inventories/production/group_vars/all/main.yml
```

**Blue-Green Environment Issues:**
```bash
# Check active environment configuration
grep -A 10 "active_environment" ansible/inventories/production/group_vars/all/main.yml

# Test both blue and green ports
curl http://192.168.188.142:8080/login   # Blue
curl http://192.168.188.142:8180/login   # Green

# Switch environments if needed
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags haproxy \
  -e 'jenkins_teams=[{"team_name": "devops", "active_environment": "green"}]'
```

---

### 4. **Monitoring Services Not Accessible**

#### Symptoms:
```bash
$ curl https://prometheus.jenkins.example.com/graph
HTTP/1.1 502 Bad Gateway
```

#### Diagnosis:
```bash
# Check monitoring containers
docker ps | grep -E 'prometheus|grafana|node-exporter'

# Test direct monitoring service access
curl http://192.168.188.142:9090/graph      # Prometheus
curl http://192.168.188.142:9300/login      # Grafana  
curl http://192.168.188.142:9100/metrics    # Node Exporter
```

#### Solutions:

**Monitoring Containers Down:**
```bash
# Start monitoring stack
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Start individual services
docker start prometheus-server
docker start grafana-server
docker start node-exporter
```

**HAProxy Monitoring Routing Not Configured:**
```bash
# Update HAProxy configuration to include monitoring backends
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags haproxy,configuration

# Verify monitoring backends in HAProxy stats
curl -u admin:admin123 http://192.168.188.142:8404/stats | grep -E 'prometheus|grafana|node'
```

**Monitoring Service Configuration Issues:**
```bash
# Check monitoring service logs
docker logs prometheus-server --tail 20
docker logs grafana-server --tail 20
docker logs node-exporter --tail 20

# Verify monitoring configuration
docker exec prometheus-server promtool check config /etc/prometheus/prometheus.yml
```

---

### 5. **SSL/TLS Certificate Issues**

#### Symptoms:
```bash
$ curl https://devops.jenkins.example.com/login
curl: (60) SSL certificate problem: self signed certificate
```

#### Diagnosis:
```bash
# Check SSL certificate
openssl s_client -connect jenkins.example.com:443 -servername devops.jenkins.example.com

# Verify certificate in HAProxy
docker exec jenkins-haproxy ls -la /usr/local/etc/haproxy/ssl/

# Check SSL configuration
grep -A 5 ssl_enabled ansible/inventories/production/group_vars/all/main.yml
```

#### Solutions:

**Self-Signed Certificate:**
```bash
# For testing, ignore SSL verification
curl -k https://devops.jenkins.example.com/login

# Or use HTTP for testing
curl http://devops.jenkins.example.com:8000/login
```

**Missing Certificate:**
```bash
# Place certificate in correct location
sudo cp /path/to/certificate.pem /etc/haproxy/ssl/combined.pem

# Update HAProxy configuration
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags haproxy,ssl

# Restart HAProxy to load new certificate
docker restart jenkins-haproxy
```

**Wildcard Certificate Issues:**
```bash
# Ensure certificate covers all subdomains
openssl x509 -in /etc/haproxy/ssl/combined.pem -text -noout | grep -A 1 "Subject Alternative Name"

# Should include:
# DNS:*.jenkins.example.com
# DNS:jenkins.example.com
```

---

## 🔍 Advanced Troubleshooting

### HAProxy Configuration Validation

```bash
# Generate configuration without applying
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags configuration --check --diff

# Test configuration with debugging
docker run --rm -v /etc/haproxy:/etc/haproxy:ro \
  haproxy:2.8 haproxy -f /etc/haproxy/haproxy.cfg -c -V

# Check routing rules
docker exec jenkins-haproxy cat /usr/local/etc/haproxy/haproxy.cfg | grep -A 5 "use_backend"
```

### Network Connectivity Testing

```bash
# Test from HAProxy container to backends
docker exec jenkins-haproxy curl -f http://192.168.188.142:8080/login
docker exec jenkins-haproxy curl -f http://192.168.188.142:9090/api/v1/status/config

# Test routing with verbose output
curl -v -H "Host: devops.jenkins.example.com" http://192.168.188.142:8000/login

# Check network interfaces and routing
ip route show
netstat -rn
```

### Container Networking Issues

```bash
# Check Docker networks
docker network ls
docker network inspect bridge

# Verify container connectivity
docker exec jenkins-haproxy ping -c 3 192.168.188.142
docker exec jenkins-devops-blue ping -c 3 192.168.188.142

# Check container IP addresses
docker inspect jenkins-haproxy --format='{{.NetworkSettings.IPAddress}}'
docker inspect jenkins-devops-blue --format='{{.NetworkSettings.IPAddress}}'
```

---

## 📊 Monitoring and Alerting

### Real-time HAProxy Monitoring

```bash
# Monitor HAProxy stats in real-time
watch -n 2 'curl -s -u admin:admin123 http://192.168.188.142:8404/stats | grep -E "devops|developer|jenkins|prometheus|grafana"'

# Monitor backend server status
echo "show stat" | socat stdio /run/haproxy/admin.sock | grep -E "UP|DOWN"

# Monitor HAProxy logs
docker logs jenkins-haproxy -f | grep -E "backend|server|health"
```

### Service Health Monitoring

```bash
# Create monitoring script
cat > monitor-services.sh << 'EOF'
#!/bin/bash
SERVICES=(
  "devops.jenkins.example.com:8000:/login"
  "developer.jenkins.example.com:8000:/login"
  "prometheus.jenkins.example.com:9090:/api/v1/status/config"
  "grafana.jenkins.example.com:9300:/api/health"
)

for service in "${SERVICES[@]}"; do
  IFS=':' read -r domain port path <<< "$service"
  echo -n "Testing $domain: "
  if curl -s -f -H "Host: $domain" "http://192.168.188.142:$port$path" > /dev/null; then
    echo "✅ OK"
  else
    echo "❌ FAILED"
  fi
done
EOF

chmod +x monitor-services.sh
./monitor-services.sh
```

---

## 🧰 Troubleshooting Tools

### Essential Commands Reference

```bash
# DNS and Network
nslookup devops.jenkins.example.com
dig devops.jenkins.example.com +short
ping devops.jenkins.example.com

# Container Management
docker ps | grep -E 'jenkins|haproxy|prometheus|grafana'
docker logs jenkins-haproxy --tail 50 -f
docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Port and Network Testing
netstat -tlnp | grep -E ':8080|:8081|:8082|:9090|:9300'
lsof -i :8000
curl -v -H "Host: devops.jenkins.example.com" http://192.168.188.142:8000/login

# HAProxy Management
echo "show info" | socat stdio /run/haproxy/admin.sock
echo "show stat" | socat stdio /run/haproxy/admin.sock
curl -u admin:admin123 http://192.168.188.142:8404/stats
```

### Automated Diagnostics Script

```bash
#!/bin/bash
# jenkins-ha-diagnostics.sh - Comprehensive diagnostic tool

echo "🔍 Jenkins HA Domain Diagnostics"
echo "================================="

# 1. DNS Resolution Test
echo -e "\n1. DNS Resolution Test"
domains=("jenkins.example.com" "devops.jenkins.example.com" "prometheus.jenkins.example.com")
for domain in "${domains[@]}"; do
  echo -n "  $domain: "
  if nslookup "$domain" > /dev/null 2>&1; then
    echo "✅ Resolved"
  else
    echo "❌ Failed"
  fi
done

# 2. Container Status
echo -e "\n2. Container Status"
containers=("jenkins-haproxy" "jenkins-devops-blue" "prometheus-server" "grafana-server")
for container in "${containers[@]}"; do
  echo -n "  $container: "
  if docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
    echo "✅ Running"
  else
    echo "❌ Not running"
  fi
done

# 3. Port Connectivity
echo -e "\n3. Port Connectivity"
ports=("8000:HAProxy" "8080:DevOps" "9090:Prometheus" "9300:Grafana")
for port_info in "${ports[@]}"; do
  IFS=':' read -r port service <<< "$port_info"
  echo -n "  Port $port ($service): "
  if nc -z 192.168.188.142 "$port" 2>/dev/null; then
    echo "✅ Open"
  else
    echo "❌ Closed"
  fi
done

# 4. HAProxy Configuration
echo -e "\n4. HAProxy Configuration"
if docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg > /dev/null 2>&1; then
  echo "  ✅ Configuration valid"
else
  echo "  ❌ Configuration invalid"
fi

# 5. Service Health
echo -e "\n5. Service Health"
services=(
  "devops.jenkins.example.com:8000:/login"
  "prometheus.jenkins.example.com:9090:/api/v1/status/config"
  "grafana.jenkins.example.com:9300:/api/health"
)

for service in "${services[@]}"; do
  IFS=':' read -r domain port path <<< "$service"
  echo -n "  $domain: "
  if curl -s -f -H "Host: $domain" "http://192.168.188.142:$port$path" > /dev/null; then
    echo "✅ Healthy"
  else
    echo "❌ Unhealthy"
  fi
done

echo -e "\n✅ Diagnostics complete"
```

---

## 📋 Quick Fix Checklist

When experiencing domain routing issues, work through this checklist:

### ✅ **Basic Checks**
- [ ] DNS/hosts file configured correctly
- [ ] HAProxy container is running
- [ ] Backend services (Jenkins/monitoring) are running
- [ ] Ports are not blocked by firewall

### ✅ **HAProxy Checks**  
- [ ] Configuration syntax is valid
- [ ] Routing rules include all teams and monitoring services
- [ ] SSL certificate is valid (if using HTTPS)
- [ ] Stats page accessible

### ✅ **Service Checks**
- [ ] Jenkins containers respond on direct ports
- [ ] Monitoring services respond on direct ports  
- [ ] Blue-green environments configured correctly
- [ ] Container logs show no errors

### ✅ **Network Checks**
- [ ] No port conflicts with other services
- [ ] Container networking is functional
- [ ] Security groups/firewalls allow traffic
- [ ] Load balancer health checks passing

---

## 🆘 Emergency Recovery

If all services are down:

```bash
# 1. Quick service restart
docker restart jenkins-haproxy jenkins-devops-blue prometheus-server grafana-server

# 2. Full infrastructure redeployment
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

# 3. Rollback to previous configuration
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags haproxy \
  -e jenkins_teams='[{"team_name": "devops", "active_environment": "blue"}]'

# 4. Access services directly (bypass HAProxy)
# Jenkins: http://192.168.188.142:8080
# Prometheus: http://192.168.188.142:9090  
# Grafana: http://192.168.188.142:9300
```

This comprehensive troubleshooting guide should help resolve most domain routing issues in the Jenkins HA environment.