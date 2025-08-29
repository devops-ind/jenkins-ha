# DNS and /etc/hosts Configuration Guide for Jenkins HA

This guide provides comprehensive DNS and local hosts file configuration for testing Jenkins HA with wildcard domain routing.

## 🌐 Production DNS Configuration

### Primary DNS Records (Recommended)
Configure these A records in your DNS provider:

```dns
# Base domain
jenkins.example.com                    A    192.168.86.30

# Wildcard record (covers all subdomains)
*.jenkins.example.com                  A    192.168.86.30

# Specific team records (optional, covered by wildcard)
devops.jenkins.example.com            A    192.168.86.30
developer.jenkins.example.com         A    192.168.86.30
jenkins.jenkins.example.com           A    192.168.86.30

# Monitoring services (optional, covered by wildcard)
prometheus.jenkins.example.com        A    192.168.86.30
grafana.jenkins.example.com          A    192.168.86.30
node-exporter.jenkins.example.com     A    192.168.86.30
haproxy-stats.jenkins.example.com     A    192.168.86.30
```

### Alternative: Individual A Records (No Wildcard Support)
If your DNS provider doesn't support wildcard records:

```dns
jenkins.example.com                    A    192.168.86.30
devops.jenkins.example.com            A    192.168.86.30
developer.jenkins.example.com         A    192.168.86.30
jenkins.jenkins.example.com           A    192.168.86.30
prometheus.jenkins.example.com        A    192.168.86.30
grafana.jenkins.example.com          A    192.168.86.30
node-exporter.jenkins.example.com     A    192.168.86.30
haproxy-stats.jenkins.example.com     A    192.168.86.30
```

### SSL Certificate Configuration (if using HTTPS)
For SSL/TLS, you'll need a wildcard certificate:

```certificate
Subject: CN=*.jenkins.example.com
SAN: 
  - DNS:jenkins.example.com
  - DNS:*.jenkins.example.com
```

## 🏠 Local Testing with /etc/hosts

### For Linux/macOS Systems
Edit `/etc/hosts` file:

```bash
sudo vim /etc/hosts
```

Add these entries:

```hosts
# Jenkins HA Multi-Team Configuration
192.168.86.30 jenkins.example.com

# Jenkins Teams - Blue/Green Deployments
192.168.86.30 devops.jenkins.example.com
192.168.86.30 developer.jenkins.example.com  
192.168.86.30 jenkins.jenkins.example.com

# Monitoring Stack
192.168.86.30 prometheus.jenkins.example.com
192.168.86.30 grafana.jenkins.example.com
192.168.86.30 node-exporter.jenkins.example.com

# HAProxy Management
192.168.86.30 haproxy-stats.jenkins.example.com

# Optional: Alternative team domains for testing
192.168.86.30 staging.jenkins.example.com
192.168.86.30 prod.jenkins.example.com
192.168.86.30 test.jenkins.example.com
```

### For Windows Systems
Edit `C:\Windows\System32\drivers\etc\hosts`:

```powershell
# Run as Administrator
notepad C:\Windows\System32\drivers\etc\hosts
```

Add the same entries as Linux/macOS above.

### Automated /etc/hosts Management
Script to add/remove entries:

```bash
#!/bin/bash
# File: scripts/manage-hosts.sh

JENKINS_IP="192.168.86.30"
DOMAIN="jenkins.example.com"

add_hosts() {
    echo "Adding Jenkins HA hosts entries..."
    
    # Backup original hosts file
    sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
    
    # Add entries
    cat <<EOF | sudo tee -a /etc/hosts
# Jenkins HA Configuration - Added $(date)
$JENKINS_IP $DOMAIN
$JENKINS_IP devops.$DOMAIN
$JENKINS_IP developer.$DOMAIN
$JENKINS_IP jenkins.$DOMAIN
$JENKINS_IP prometheus.$DOMAIN
$JENKINS_IP grafana.$DOMAIN
$JENKINS_IP node-exporter.$DOMAIN
$JENKINS_IP haproxy-stats.$DOMAIN
EOF
    
    echo "✅ Hosts entries added successfully"
}

remove_hosts() {
    echo "Removing Jenkins HA hosts entries..."
    sudo sed -i '/# Jenkins HA Configuration/,/^$/d' /etc/hosts
    echo "✅ Hosts entries removed successfully"
}

case "$1" in
    add)
        add_hosts
        ;;
    remove)
        remove_hosts
        ;;
    *)
        echo "Usage: $0 {add|remove}"
        exit 1
        ;;
esac
```

## 🐳 Docker Internal Network Configuration

### Docker Compose Network Setup
If using Docker Compose for local development:

```yaml
# docker-compose.override.yml
version: '3.8'

networks:
  jenkins-network:
    external: false
    ipam:
      config:
        - subnet: 172.25.0.0/16

services:
  haproxy:
    networks:
      jenkins-network:
        aliases:
          - jenkins.example.com
          - devops.jenkins.example.com
          - developer.jenkins.example.com
          - jenkins.jenkins.example.com
          - prometheus.jenkins.example.com
          - grafana.jenkins.example.com
```

### Container Network Aliases
Add network aliases to HAProxy container:

```bash
docker run -d --name jenkins-haproxy \
  --network-alias jenkins.example.com \
  --network-alias devops.jenkins.example.com \
  --network-alias developer.jenkins.example.com \
  --network-alias jenkins.jenkins.example.com \
  --network-alias prometheus.jenkins.example.com \
  --network-alias grafana.jenkins.example.com \
  haproxy:2.8
```

## 🧪 Testing DNS Configuration

### Basic DNS Resolution Tests

```bash
# Test DNS resolution
nslookup jenkins.example.com
nslookup devops.jenkins.example.com
nslookup prometheus.jenkins.example.com

# Test with dig (more detailed)
dig jenkins.example.com
dig devops.jenkins.example.com +short
dig prometheus.jenkins.example.com +short

# Test wildcard resolution
dig random-subdomain.jenkins.example.com +short
```

### HTTP/HTTPS Connectivity Tests

```bash
# Test Jenkins teams
curl -H "Host: devops.jenkins.example.com" http://192.168.86.30:8000/login
curl -H "Host: developer.jenkins.example.com" http://192.168.86.30:8000/login
curl -H "Host: jenkins.jenkins.example.com" http://192.168.86.30:8000/login

# Test monitoring services
curl -H "Host: prometheus.jenkins.example.com" http://192.168.86.30:9090/graph
curl -H "Host: grafana.jenkins.example.com" http://192.168.86.30:9300/login
curl -H "Host: node-exporter.jenkins.example.com" http://192.168.86.30:9100/metrics

# Test HAProxy stats
curl -u admin:admin123 -H "Host: haproxy-stats.jenkins.example.com" http://192.168.86.30:8404/stats
```

### Browser Testing Checklist

```bash
# Team Jenkins Instances
✅ https://devops.jenkins.example.com → DevOps Jenkins Login
✅ https://developer.jenkins.example.com → Developer Jenkins Login  
✅ https://jenkins.jenkins.example.com → Admin Jenkins Login

# Monitoring Stack
✅ https://prometheus.jenkins.example.com → Prometheus Dashboard
✅ https://grafana.jenkins.example.com → Grafana Login
✅ https://node-exporter.jenkins.example.com/metrics → Metrics Output

# Management Interface
✅ https://haproxy-stats.jenkins.example.com/stats → HAProxy Statistics
```

## 🔧 Environment-Specific Configurations

### Development Environment (Local)
```hosts
# Local development on localhost
127.0.0.1 jenkins.local
127.0.0.1 devops.jenkins.local
127.0.0.1 developer.jenkins.local
127.0.0.1 jenkins.jenkins.local
127.0.0.1 prometheus.jenkins.local
127.0.0.1 grafana.jenkins.local
```

### Staging Environment
```hosts
# Staging environment
10.0.1.100 jenkins.staging.example.com
10.0.1.100 devops.jenkins.staging.example.com
10.0.1.100 developer.jenkins.staging.example.com
10.0.1.100 jenkins.jenkins.staging.example.com
10.0.1.100 prometheus.jenkins.staging.example.com
10.0.1.100 grafana.jenkins.staging.example.com
```

### Production Environment
```dns
# Production DNS (managed by DNS provider)
jenkins.example.com                    A    203.0.113.100
*.jenkins.example.com                  A    203.0.113.100
```

## 📱 Mobile/External Testing

### Port Forwarding for External Access
```bash
# SSH tunnel for external testing
ssh -L 8000:192.168.86.30:8000 \
    -L 9090:192.168.86.30:9090 \
    -L 9300:192.168.86.30:9300 \
    user@jenkins-host

# Then test locally
curl -H "Host: devops.jenkins.example.com" http://localhost:8000/login
```

### Cloud DNS Configuration
Example for AWS Route 53:

```json
{
    "Changes": [{
        "Action": "CREATE",
        "ResourceRecordSet": {
            "Name": "*.jenkins.example.com",
            "Type": "A",
            "TTL": 300,
            "ResourceRecords": [{"Value": "192.168.86.30"}]
        }
    }]
}
```

## 🛠️ Troubleshooting DNS Issues

### Common DNS Problems

1. **DNS Cache Issues**
```bash
# Clear DNS cache (Linux)
sudo systemctl flush-dns

# Clear DNS cache (macOS)
sudo dscacheutil -flushcache

# Clear DNS cache (Windows)
ipconfig /flushdns
```

2. **Hosts File Not Working**
```bash
# Verify hosts file syntax
cat /etc/hosts | grep jenkins

# Check file permissions
ls -la /etc/hosts

# Test with ping
ping devops.jenkins.example.com
```

3. **Wildcard DNS Not Resolving**
```bash
# Test specific vs wildcard
dig devops.jenkins.example.com
dig nonexistent.jenkins.example.com

# Check DNS server configuration
cat /etc/resolv.conf
```

### Validation Scripts

```bash
#!/bin/bash
# validate-dns.sh - Comprehensive DNS validation

DOMAIN="jenkins.example.com"
IP="192.168.86.30"

SERVICES=(
    "devops.$DOMAIN:8000"
    "developer.$DOMAIN:8000"
    "jenkins.$DOMAIN:8000"
    "prometheus.$DOMAIN:9090"
    "grafana.$DOMAIN:9300"
    "node-exporter.$DOMAIN:9100"
)

echo "🔍 DNS Resolution Test"
for service in "${SERVICES[@]}"; do
    subdomain="${service%:*}"
    echo -n "Testing $subdomain: "
    if nslookup "$subdomain" > /dev/null 2>&1; then
        echo "✅ Resolved"
    else
        echo "❌ Failed"
    fi
done

echo -e "\n🌐 HTTP Connectivity Test"
for service in "${SERVICES[@]}"; do
    subdomain="${service%:*}"
    port="${service#*:}"
    echo -n "Testing http://$subdomain: "
    if curl -s -H "Host: $subdomain" "http://$IP:$port" > /dev/null; then
        echo "✅ Connected"
    else
        echo "❌ Failed"
    fi
done
```

---

## 📋 Quick Reference

### Essential Commands
```bash
# Add hosts entries
sudo vim /etc/hosts

# Test DNS resolution  
nslookup devops.jenkins.example.com

# Test HTTP routing
curl -H "Host: devops.jenkins.example.com" http://192.168.86.30:8000/login

# Flush DNS cache
sudo systemctl flush-dns  # Linux
sudo dscacheutil -flushcache  # macOS
```

### Port Reference
- **Jenkins Teams**: 8000 (HAProxy frontend)
- **Direct Blue**: 8080 (devops), 8081 (developer), 8082 (jenkins)
- **Direct Green**: 8180 (devops), 8181 (developer), 8182 (jenkins)
- **Monitoring**: 9090 (prometheus), 9300 (grafana), 9100 (node-exporter)
- **HAProxy Stats**: 8404

This configuration enables seamless multi-team Jenkins access with integrated monitoring through wildcard domain routing.