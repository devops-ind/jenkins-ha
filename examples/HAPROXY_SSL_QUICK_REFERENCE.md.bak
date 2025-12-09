# HAProxy SSL Quick Reference Guide

## Immediate Solution for SSL Certificate Issues

### Problem
HAProxy container keeps restarting with error: "unable to stat SSL certificate from file '/usr/local/etc/haproxy/ssl/combined.pem' : No such file or directory"

### Quick Fix Commands

#### Option 1: Automated Recovery (Recommended)
```bash
# Navigate to project root
cd /Users/jitinchawla/Data/projects/jenkins-ha

# Run automated deployment with SSL
./scripts/deploy-haproxy-ssl.sh

# Or run troubleshooting if automated fails
ansible-playbook -i ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml --extra-vars "troubleshoot_mode=recover"
```

#### Option 2: Manual Step-by-Step
```bash
# 1. Generate SSL certificates first
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags ssl --extra-vars "ssl_enabled=true jenkins_domain=192.168.86.30"

# 2. Deploy HAProxy configuration
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags configuration --extra-vars "ssl_enabled=true"

# 3. Deploy HAProxy container
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags haproxy,deploy --extra-vars "ssl_enabled=true"

# 4. Verify deployment
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags verify
```

#### Option 3: Troubleshooting Only
```bash
# Diagnose issues
ansible-playbook -i ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml

# Fix issues automatically
ansible-playbook -i ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml --extra-vars "troubleshoot_mode=fix"

# Complete recovery
ansible-playbook -i ansible/inventories/local/hosts.yml troubleshoot-haproxy-ssl.yml --extra-vars "troubleshoot_mode=recover"
```

### Verification Commands

```bash
# Check container status
docker ps | grep jenkins-haproxy

# Check logs
docker logs jenkins-haproxy

# Test SSL certificate
openssl x509 -in /etc/haproxy/ssl/combined.pem -noout -text

# Test HTTPS connectivity
curl -k https://localhost/

# Check HAProxy stats
curl http://localhost:8404/stats
```

### Key Configuration Variables

For your environment, ensure these variables are set:

```yaml
# In your inventory or playbook
ssl_enabled: true
jenkins_domain: "192.168.86.30"
jenkins_wildcard_domain: "*.192.168.86.30"
haproxy_container_runtime: "docker"
haproxy_frontend_port: 80
haproxy_stats_port: 8404
```

### Expected Results

After successful deployment:
- ✅ HAProxy container running with SSL
- ✅ HTTPS accessible at https://192.168.86.30/
- ✅ HTTP redirects to HTTPS
- ✅ HAProxy stats at http://192.168.86.30:8404/stats
- ✅ SSL certificate valid and accessible

### Troubleshooting

If issues persist:

1. **Check certificate files**:
   ```bash
   ls -la /etc/haproxy/ssl/
   ```

2. **Verify permissions**:
   ```bash
   ls -la /etc/haproxy/ssl/combined.pem
   # Should show: -rw------- root haproxy
   ```

3. **Test certificate validity**:
   ```bash
   openssl x509 -in /etc/haproxy/ssl/combined.pem -noout -dates
   ```

4. **Check container mounts**:
   ```bash
   docker inspect jenkins-haproxy | grep -A5 -B5 ssl
   ```

### Contact Information

For persistent issues, provide this information:
- Container logs: `docker logs jenkins-haproxy`
- SSL file listing: `ls -la /etc/haproxy/ssl/`
- Certificate validity: `openssl x509 -in /etc/haproxy/ssl/combined.pem -noout -text`
- System info: `docker version && docker info`