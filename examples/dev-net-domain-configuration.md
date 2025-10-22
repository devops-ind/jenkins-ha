# Production Domain Configuration: `*.dev.net`

## Overview

This document describes the complete production domain configuration for Jenkins HA infrastructure using the wildcard domain `*.dev.net`.

**Date**: October 21, 2025
**Domain**: `dev.net`
**Wildcard**: `*.dev.net`
**Infrastructure IP**: `192.168.188.142`

---

## Changes Summary

### Inventory Updates

#### 1. Production Hosts (`ansible/inventories/production/hosts.yml`)

**Domain Variables** (Lines 40-41):
```yaml
jenkins_domain: "dev.net"
jenkins_wildcard_domain: "*.dev.net"
```

**Host FQDNs** (Updated across all host groups):
```yaml
# Jenkins Masters
jenkins_masters:
  hosts:
    centos9-vm:
      host_fqdn: centos9-vm.dev.net
      monitoring_fqdn: monitoring.dev.net

# Load Balancers
load_balancers:
  hosts:
    centos9-vm:
      host_fqdn: centos9-vm.dev.net

# Monitoring
monitoring:
  hosts:
    centos9-vm:
      host_fqdn: monitoring.dev.net
      monitoring_fqdn: monitoring.dev.net

# Shared Storage
shared_storage:
  hosts:
    centos9-vm:
      host_fqdn: centos9-vm.dev.net

# GlusterFS Servers
glusterfs_servers:
  hosts:
    centos9-vm:
      host_fqdn: centos9-vm.dev.net
```

#### 2. Production Group Variables (`ansible/inventories/production/group_vars/all/main.yml`)

**Domain Configuration** (Lines 94-98):
```yaml
jenkins_domain: "dev.net"
jenkins_wildcard_domain: "*.dev.net"
monitoring_domain: "dev.net"
monitoring_wildcard_domain: "*.dev.net"
```

**Derived Monitoring Service Domains**:
```yaml
prometheus_domain: "prometheus.dev.net"
grafana_domain: "grafana.dev.net"
node_exporter_domain: "node-exporter.dev.net"
```

---

## Service URLs

### Jenkins Team Services

| Team | Subdomain | Full URL | Port |
|------|-----------|----------|------|
| DevOps (default) | `devopsjenkins.dev.net` | `http://devopsjenkins.dev.net:8080` | 8080 |
| Marketing Analytics | `majenkins.dev.net` | `http://majenkins.dev.net:8081` | 8081 |
| Business Analytics | `bajenkins.dev.net` | `http://bajenkins.dev.net:8082` | 8082 |
| Test/QA | `twjenkins.dev.net` | `http://twjenkins.dev.net:8083` | 8083 |

**Default Team Access** (without team prefix):
- `jenkins.dev.net` → DevOps team (default backend)

### Monitoring Services

| Service | Subdomain | Full URL | Port |
|---------|-----------|----------|------|
| Prometheus | `prometheus.dev.net` | `http://prometheus.dev.net:9090` | 9090 |
| Grafana | `grafana.dev.net` | `http://grafana.dev.net:9300` | 9300 |
| Loki | `loki.dev.net` | `http://loki.dev.net:9400` | 9400 |
| Node Exporter | `node-exporter.dev.net` | `http://node-exporter.dev.net:9100` | 9100 |
| Alertmanager | `alertmanager.dev.net` | `http://alertmanager.dev.net:9093` | 9093 |

### Infrastructure Services

| Service | FQDN | IP Address | Purpose |
|---------|------|------------|---------|
| Jenkins VM | `centos9-vm.dev.net` | `192.168.188.142` | Primary infrastructure host |
| Monitoring Server | `monitoring.dev.net` | `192.168.188.142` | Monitoring server FQDN |

---

## SSL Certificate Configuration

### Wildcard Certificate Details

**Common Name (CN)**: `*.dev.net`

**Subject Alternative Names (SAN)**:
```
DNS:*.dev.net                    # Wildcard for all subdomains
DNS:dev.net                      # Base domain
DNS:jenkins.dev.net              # Jenkins base
DNS:devopsjenkins.dev.net        # DevOps team
DNS:majenkins.dev.net            # Marketing Analytics team
DNS:bajenkins.dev.net            # Business Analytics team
DNS:twjenkins.dev.net            # Test/QA team
DNS:prometheus.dev.net           # Prometheus monitoring
DNS:grafana.dev.net              # Grafana dashboards
DNS:node-exporter.dev.net        # Node exporter metrics
```

### Certificate Paths

| Component | Path | Description |
|-----------|------|-------------|
| Private Key | `/etc/ssl/private/wildcard-dev.net.key` | RSA 2048-bit private key |
| Certificate | `/etc/ssl/certs/wildcard-dev.net.crt` | X.509 certificate |
| CSR | `/etc/ssl/csr/wildcard-dev.net.csr` | Certificate Signing Request |
| HAProxy Bundle | `/etc/haproxy/ssl/wildcard-dev.net-haproxy.pem` | Combined cert + key |
| Combined | `/etc/haproxy/ssl/combined.pem` | Symlink to bundle |

### Certificate Generation

Certificates are auto-generated during deployment:

```bash
# Generate SSL certificates
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags ssl,wildcard

# Verify certificate SANs
openssl x509 -in /etc/ssl/certs/wildcard-dev.net.crt -text -noout | grep DNS
```

**Expected Output**:
```
DNS:*.dev.net, DNS:dev.net, DNS:jenkins.dev.net, DNS:devopsjenkins.dev.net,
DNS:majenkins.dev.net, DNS:bajenkins.dev.net, DNS:twjenkins.dev.net,
DNS:prometheus.dev.net, DNS:grafana.dev.net, DNS:node-exporter.dev.net
```

---

## DNS Configuration

### Option 1: BIND9 DNS Server (Recommended for Production)

**Zone File**: `/etc/bind/zones/db.dev.net`

```bind
$TTL    604800
@       IN      SOA     ns1.dev.net. admin.dev.net. (
                              2025102101         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

; Name servers
@       IN      NS      ns1.dev.net.
ns1     IN      A       192.168.188.142

; Wildcard record (covers all subdomains)
*       IN      A       192.168.188.142

; Explicit records (optional, for clarity)
@       IN      A       192.168.188.142
jenkins IN      A       192.168.188.142

; Infrastructure
centos9-vm              IN      A       192.168.188.142
monitoring              IN      A       192.168.188.142

; Jenkins Teams
devopsjenkins           IN      A       192.168.188.142
majenkins               IN      A       192.168.188.142
bajenkins               IN      A       192.168.188.142
twjenkins               IN      A       192.168.188.142

; Monitoring Services
prometheus              IN      A       192.168.188.142
grafana                 IN      A       192.168.188.142
loki                    IN      A       192.168.188.142
node-exporter           IN      A       192.168.188.142
alertmanager            IN      A       192.168.188.142
```

**BIND Configuration**: `/etc/bind/named.conf.local`

```bind
zone "dev.net" {
    type master;
    file "/etc/bind/zones/db.dev.net";
};
```

**Reload BIND**:
```bash
sudo named-checkzone dev.net /etc/bind/zones/db.dev.net
sudo named-checkconf
sudo systemctl reload bind9
```

---

### Option 2: dnsmasq (Simple Wildcard Support)

**Configuration**: `/etc/dnsmasq.d/dev.net.conf`

```conf
# Wildcard domain mapping
address=/dev.net/192.168.188.142

# Optional: Explicit mappings for clarity
address=/jenkins.dev.net/192.168.188.142
address=/devopsjenkins.dev.net/192.168.188.142
address=/majenkins.dev.net/192.168.188.142
address=/bajenkins.dev.net/192.168.188.142
address=/twjenkins.dev.net/192.168.188.142
address=/prometheus.dev.net/192.168.188.142
address=/grafana.dev.net/192.168.188.142
address=/monitoring.dev.net/192.168.188.142
address=/centos9-vm.dev.net/192.168.188.142
```

**Restart dnsmasq**:
```bash
sudo systemctl restart dnsmasq
```

---

### Option 3: /etc/hosts (Testing Only)

**File**: `/etc/hosts`

```
# Jenkins HA Infrastructure - dev.net domain
192.168.188.142 dev.net

# Infrastructure
192.168.188.142 centos9-vm.dev.net
192.168.188.142 monitoring.dev.net

# Jenkins Teams
192.168.188.142 jenkins.dev.net
192.168.188.142 devopsjenkins.dev.net
192.168.188.142 majenkins.dev.net
192.168.188.142 bajenkins.dev.net
192.168.188.142 twjenkins.dev.net

# Monitoring Services
192.168.188.142 prometheus.dev.net
192.168.188.142 grafana.dev.net
192.168.188.142 loki.dev.net
192.168.188.142 node-exporter.dev.net
192.168.188.142 alertmanager.dev.net
```

**Update on all VMs**:
```bash
# Copy to all production VMs
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m copy -a "src=/etc/hosts dest=/etc/hosts backup=yes"
```

---

### Option 4: CoreDNS (Container-Based DNS)

**Corefile**: `/etc/coredns/Corefile`

```
dev.net {
    file /etc/coredns/dev.net.zone
    log
}

. {
    forward . 8.8.8.8 8.8.4.4
    log
    errors
}
```

**Zone File**: `/etc/coredns/dev.net.zone`

```
$ORIGIN dev.net.
$TTL 3600
@       IN SOA  ns1.dev.net. admin.dev.net. (
                2025102101 ; serial
                7200       ; refresh
                3600       ; retry
                1209600    ; expire
                3600       ; minimum
)

        IN NS   ns1.dev.net.
*       IN A    192.168.188.142
```

**Docker Deployment**:
```bash
docker run -d --name coredns \
  -v /etc/coredns:/etc/coredns \
  -p 53:53/udp \
  -p 53:53/tcp \
  coredns/coredns -conf /etc/coredns/Corefile
```

---

## HAProxy Routing Configuration

### Domain-Based Routing Rules

**Template**: `ansible/roles/high-availability-v2/templates/haproxy.cfg.j2`

```haproxy
frontend jenkins_frontend
    bind *:8090
    mode http

    # Monitoring service routing
    use_backend prometheus_backend if { hdr_beg(host) -i prometheus.dev.net }
    use_backend grafana_backend if { hdr_beg(host) -i grafana.dev.net }
    use_backend node_exporter_backend if { hdr_beg(host) -i node-exporter.dev.net }

    # Team-specific Jenkins routing
    use_backend jenkins_backend_devops if { hdr_beg(host) -i devopsjenkins.dev.net }
    use_backend jenkins_backend_ma if { hdr_beg(host) -i majenkins.dev.net }
    use_backend jenkins_backend_ba if { hdr_beg(host) -i bajenkins.dev.net }
    use_backend jenkins_backend_tw if { hdr_beg(host) -i twjenkins.dev.net }

    # Default backend (jenkins.dev.net)
    default_backend jenkins_backend_devops
```

**Note**: These rules are auto-generated from `jenkins_domain` variable.

---

## Deployment and Validation

### Full Deployment

```bash
# Deploy infrastructure with new domain
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

# Deploy SSL certificates only
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags ssl,wildcard

# Deploy HAProxy only
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags high-availability,haproxy

# Deploy monitoring only
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring
```

### DNS Validation

```bash
# Test DNS resolution (all should resolve to 192.168.188.142)
dig @localhost devopsjenkins.dev.net +short
dig @localhost majenkins.dev.net +short
dig @localhost prometheus.dev.net +short
dig @localhost grafana.dev.net +short

# Test wildcard resolution
dig @localhost test123.dev.net +short  # Should return 192.168.188.142

# Verify /etc/hosts if using hosts file
grep dev.net /etc/hosts
```

### SSL Certificate Validation

```bash
# Check certificate details
openssl x509 -in /etc/ssl/certs/wildcard-dev.net.crt -text -noout

# Verify certificate subject
openssl x509 -in /etc/ssl/certs/wildcard-dev.net.crt -subject -noout
# Expected: subject=CN = *.dev.net

# Verify SANs
openssl x509 -in /etc/ssl/certs/wildcard-dev.net.crt -text -noout | \
  grep -A 1 "Subject Alternative Name"

# Test HAProxy SSL bundle
openssl x509 -in /etc/haproxy/ssl/wildcard-dev.net-haproxy.pem -text -noout
```

### Service Access Validation

```bash
# Test Jenkins team access
curl -I http://devopsjenkins.dev.net:8090
curl -I http://majenkins.dev.net:8090
curl -I http://bajenkins.dev.net:8090
curl -I http://twjenkins.dev.net:8090

# Test monitoring services
curl -I http://prometheus.dev.net:9090
curl -I http://grafana.dev.net:9300
curl http://node-exporter.dev.net:9100/metrics | head -20

# Test HAProxy stats
curl -u admin:admin123 http://192.168.188.142:8404/stats
```

### HAProxy Configuration Validation

```bash
# Validate HAProxy config
docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Check HAProxy routing rules
docker exec jenkins-haproxy cat /usr/local/etc/haproxy/haproxy.cfg | \
  grep -E "use_backend|hdr_beg"

# Expected output should show dev.net domains
```

---

## Troubleshooting

### DNS Issues

**Problem**: Domains not resolving

**Solutions**:
```bash
# Check DNS configuration
nslookup devopsjenkins.dev.net

# Test with specific nameserver
nslookup devopsjenkins.dev.net 192.168.188.142

# Verify dnsmasq is running
systemctl status dnsmasq

# Check dnsmasq logs
journalctl -u dnsmasq -f

# Flush DNS cache
sudo systemd-resolve --flush-caches  # systemd-resolved
sudo killall -HUP mDNSResponder      # macOS

# Verify /etc/resolv.conf points to correct nameserver
cat /etc/resolv.conf
```

### SSL Certificate Issues

**Problem**: SSL certificate not trusted

**Solutions**:
```bash
# Check certificate validity
openssl x509 -in /etc/ssl/certs/wildcard-dev.net.crt -dates -noout

# Verify certificate chain
openssl verify /etc/ssl/certs/wildcard-dev.net.crt

# Check HAProxy SSL bundle
cat /etc/haproxy/ssl/wildcard-dev.net-haproxy.pem | \
  openssl x509 -text -noout

# Regenerate certificate if needed
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags ssl,wildcard --extra-vars "force_ssl_regeneration=true"
```

### HAProxy Routing Issues

**Problem**: Requests not routing to correct backend

**Solutions**:
```bash
# Check HAProxy logs
docker logs jenkins-haproxy --tail 100 -f

# Verify backend health
echo "show stat" | socat stdio /run/haproxy/admin.sock | grep jenkins_backend

# Test with Host header
curl -H "Host: devopsjenkins.dev.net" http://192.168.188.142:8090

# Check HAProxy configuration
docker exec jenkins-haproxy cat /usr/local/etc/haproxy/haproxy.cfg | \
  grep -A 5 "frontend jenkins_frontend"
```

### Monitoring Access Issues

**Problem**: Cannot access monitoring services

**Solutions**:
```bash
# Verify monitoring containers are running
docker ps | grep -E "prometheus|grafana|loki"

# Check Prometheus targets
curl http://prometheus.dev.net:9090/api/v1/targets | jq .

# Verify Grafana datasources
curl -u admin:admin123 http://grafana.dev.net:9300/api/datasources

# Check Loki health
curl http://loki.dev.net:9400/ready
```

---

## Migration from Old Domain

If migrating from previous domain configuration:

### Backup Current Configuration

```bash
# Backup inventory
cp ansible/inventories/production/hosts.yml \
   ansible/inventories/production/hosts.yml.bak

# Backup group vars
cp ansible/inventories/production/group_vars/all/main.yml \
   ansible/inventories/production/group_vars/all/main.yml.bak

# Backup SSL certificates
tar czf /tmp/ssl-backup-$(date +%Y%m%d).tar.gz /etc/ssl/certs /etc/ssl/private /etc/haproxy/ssl
```

### Update and Deploy

```bash
# 1. Update inventory (already done)
# 2. Update DNS configuration
# 3. Deploy new configuration
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

# 4. Verify all services
./scripts/health-check.sh
```

### Rollback Procedure

If issues occur:

```bash
# 1. Restore inventory
cp ansible/inventories/production/hosts.yml.bak \
   ansible/inventories/production/hosts.yml

# 2. Restore group vars
cp ansible/inventories/production/group_vars/all/main.yml.bak \
   ansible/inventories/production/group_vars/all/main.yml

# 3. Redeploy
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml
```

---

## Security Considerations

### Wildcard Certificate Limitations

- Wildcard certificates (`*.dev.net`) cover single-level subdomains only
- Does NOT cover: `nested.subdomain.dev.net` (multi-level)
- DOES cover: `anything.dev.net` (single-level)

### DNS Security

- Use DNSSEC if deploying in public environments
- Restrict DNS zone transfers (`allow-transfer` in BIND)
- Consider DNS firewall rules

### Certificate Management

- Certificates are self-signed (suitable for internal use)
- For production internet-facing deployment, use Let's Encrypt or commercial CA
- Automate certificate renewal (current validity: 365 days)

---

## Future Enhancements

### Adding New Teams

New teams automatically get subdomain configuration:

```yaml
# ansible/inventories/production/group_vars/all/main.yml
jenkins_teams_config:
  - team_name: "devops"
    ...
  - team_name: "newteam"  # Automatically gets newteamjenkins.dev.net
    ...
```

SSL certificates will auto-regenerate with new SAN:
- `DNS:newteamjenkins.dev.net`

### Multi-VM Deployment

When adding second VM (`192.168.188.143`):

```yaml
# Update DNS with both IPs
devopsjenkins.dev.net.  IN  A  192.168.188.142
devopsjenkins.dev.net.  IN  A  192.168.188.143

# Or use round-robin DNS
*.dev.net.  IN  A  192.168.188.142
*.dev.net.  IN  A  192.168.188.143
```

### Load Balancer VIP

For production HA with Keepalived VIP (e.g., `192.168.188.100`):

```bind
# Update DNS to point to VIP
*.dev.net.  IN  A  192.168.188.100
```

---

## Summary

### Changes Made

1. ✅ Updated `jenkins_domain` to `dev.net`
2. ✅ Updated `jenkins_wildcard_domain` to `*.dev.net`
3. ✅ Updated all `host_fqdn` to `*.dev.net` pattern
4. ✅ Updated `monitoring_domain` to `dev.net`
5. ✅ Validated Ansible syntax (passed)

### What Updates Automatically

- SSL wildcard certificate: `*.dev.net` with team-specific SANs
- HAProxy routing: All team subdomains (`{team}jenkins.dev.net`)
- Jenkins URLs: Team-specific Jenkins instances
- Monitoring URLs: Service-specific subdomains
- Admin emails: `admin@dev.net`

### DNS Required

Choose one DNS solution:
1. **BIND9** (production-grade)
2. **dnsmasq** (simple wildcard support)
3. **/etc/hosts** (testing only)
4. **CoreDNS** (container-based)

### Deployment Command

```bash
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml
```

---

## Variable Naming Convention

### `jenkins_teams_config` vs `jenkins_teams`

The infrastructure uses two related but distinct variable names for team configuration:

#### `jenkins_teams_config` (Inventory Variable)
- **Location**: Inventory files (`hosts.yml`, `group_vars/all/main.yml`)
- **Purpose**: Define team configurations in inventory
- **Format**: List of team objects with full configuration
- **Used in**: Production and local inventories

**Example**:
```yaml
# ansible/inventories/production/group_vars/all/main.yml
jenkins_teams_config:
  - team_name: "devops"
    blue_green_enabled: true
    active_environment: "green"
    ports:
      web: 8080
      agent: 50000
```

#### `jenkins_teams` (Role Variable)
- **Location**: Roles (monitoring, jenkins-master-v2)
- **Purpose**: Normalized team data passed to roles
- **Format**: Same list format, but filtered/processed
- **Used in**: Template rendering, role logic

**Mapping Flow**:
```
Inventory                site.yml pre_tasks         Role
---------                ------------------         ----
jenkins_teams_config  →  Filter/process teams  →  jenkins_teams
```

#### Role Normalization Pattern

Both `jenkins-master-v2` and `monitoring` roles normalize variables to handle both naming conventions:

**jenkins-master-v2 Pattern** (`tasks/main.yml:18`):
```yaml
- name: Determine deployment configuration
  set_fact:
    jenkins_teams_config: "{{ jenkins_teams_config | default(jenkins_teams) | default([jenkins_master_config]) }}"
```

**monitoring Role Pattern** (`tasks/main.yml:47`):
```yaml
- name: Normalize Jenkins teams configuration for monitoring
  set_fact:
    jenkins_teams: "{{ jenkins_teams | default(jenkins_teams_config) | default([]) }}"
```

#### Why Two Variables?

1. **Separation of Concerns**: Inventory defines configuration (`jenkins_teams_config`), roles consume normalized data (`jenkins_teams`)
2. **Filtering**: `site.yml` can filter teams before passing to roles
3. **Backward Compatibility**: Supports both direct and filtered team configurations
4. **Role Independence**: Roles work standalone or as part of full playbook

#### Best Practices

1. **In Inventory Files**: Always use `jenkins_teams_config`
   - Production: `ansible/inventories/production/group_vars/all/main.yml`
   - Local: `ansible/inventories/local/group_vars/all/main.yml`

2. **In Roles**: Always normalize at the start of `tasks/main.yml`
   - Monitoring role: `jenkins_teams | default(jenkins_teams_config) | default([])`
   - Jenkins role: `jenkins_teams_config | default(jenkins_teams) | default([...])`

3. **In Templates**: Use `jenkins_teams` with safe defaults
   ```jinja2
   {% for team in jenkins_teams | default([]) %}
     # Team configuration for {{ team.team_name }}
   {% endfor %}
   ```

4. **In site.yml**: Filter `jenkins_teams_config`, pass as `jenkins_teams`
   ```yaml
   pre_tasks:
     - name: Prepare teams for monitoring
       set_fact:
         jenkins_teams_for_monitoring: "{{ jenkins_teams_config | default([]) }}"

   roles:
     - role: monitoring
       vars:
         jenkins_teams: "{{ jenkins_teams_for_monitoring }}"
   ```

---

## References

- **Inventory**: `ansible/inventories/production/hosts.yml`
- **Group Variables**: `ansible/inventories/production/group_vars/all/main.yml`
- **SSL Template**: `ansible/roles/high-availability-v2/tasks/ssl-certificates.yml`
- **HAProxy Template**: `ansible/roles/high-availability-v2/templates/haproxy.cfg.j2`
- **Main Documentation**: `CLAUDE.md`
- **Variable Normalization**:
  - `ansible/roles/monitoring/tasks/main.yml` (line 47)
  - `ansible/roles/jenkins-master-v2/tasks/main.yml` (line 18)
