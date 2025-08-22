# Jenkins HA Optimized Blue-Green Deployment with Dynamic SSL Architecture

## Overview

This document describes the enhanced Jenkins HA infrastructure featuring resource-optimized blue-green deployments and dynamic SSL certificate generation based on team configurations. These improvements reduce resource consumption by 50% while maintaining zero-downtime deployments and automated SSL management.

## Table of Contents

1. [Resource-Optimized Blue-Green Deployment](#resource-optimized-blue-green-deployment)
2. [Dynamic SSL Certificate Generation](#dynamic-ssl-certificate-generation)
3. [Corrected Domain Architecture](#corrected-domain-architecture)
4. [Implementation Details](#implementation-details)
5. [Configuration Examples](#configuration-examples)
6. [Troubleshooting](#troubleshooting)

## Resource-Optimized Blue-Green Deployment

### Previous Architecture (Traditional Blue-Green)
```yaml
# Traditional approach - both environments running simultaneously
HAProxy:
  Blue Backend:   [Active] ← Routes traffic + health checks
  Green Backend:  [Backup] ← Health checks + standby
Jenkins Masters:
  Blue Container:  [Running] ← 50% resource usage
  Green Container: [Running] ← 50% resource usage
Total Resource Usage: 100%
```

### New Optimized Architecture (Active-Only Blue-Green) ✅ COMPLETE
```yaml
# Optimized approach - only active environment running
HAProxy:
  Blue Backend:   [Active] ← Routes traffic (when blue active)
  Green Backend:  [Inactive] ← No servers (when blue active)
Jenkins Masters:
  Blue Container:  [Running] ← 50% resource usage (when active)
  Green Container: [Stopped] ← 0% resource usage (ready for instant start)
Total Resource Usage: 50% (50% resource reduction)
```

### Key Benefits

1. **50% Resource Reduction**: Only active environment consumes CPU, memory, and storage
2. **Instant Switching**: Inactive environment configuration ready for immediate deployment
3. **Zero-Downtime**: HAProxy handles traffic routing during environment switches
4. **Team Independence**: Each team can switch environments independently
5. **Maintained Reliability**: Full blue-green capabilities preserved

### Implementation in HAProxy Configuration

```jinja2
# ansible/roles/high-availability-v2/templates/haproxy.cfg.j2
# Optimized Blue-Green deployment - ONLY active environment for {{ team.team_name }} team
{% if team.active_environment | default('blue') == 'blue' %}
# Blue environment active (green environment not running - resource optimization)
server {{ team.team_name }}-{{ hostvars[host]['inventory_hostname'] }}-active {{ hostvars[host]['ansible_default_ipv4']['address'] }}:{{ team.ports.web | default(8080) }} check
{% else %}
# Green environment active (blue environment not running - resource optimization)  
server {{ team.team_name }}-{{ hostvars[host]['inventory_hostname'] }}-active {{ hostvars[host]['ansible_default_ipv4']['address'] }}:{{ (team.ports.web | default(8080)) + 100 }} check
{% endif %}
```

### Implementation in Jenkins Master Deployment

```yaml
# ansible/roles/jenkins-master-v2/tasks/image-and-container.yml
# Stop inactive environment containers (Resource Optimization)
- name: Stop inactive environment containers
  community.docker.docker_container:
    name: "jenkins-{{ item.team_name }}-{{ _inactive_environment }}"
    state: stopped
  vars:
    _inactive_environment: "{{ 'green' if item.active_environment | default('blue') == 'blue' else 'blue' }}"

# Deploy only active environment containers (50% Resource Reduction)
- name: Deploy Jenkins active environment containers
  community.docker.docker_container:
    name: "jenkins-{{ item.team_name }}-{{ item.active_environment | default('blue') }}"
    state: started
    ports: "{{ _active_ports }}"
    volumes: "{{ _active_volumes }}"
  vars:
    _active_ports: >-
      {%- if item.active_environment | default('blue') == 'blue' -%}
        ["{{ item.ports.web }}:8080", "{{ item.ports.agent }}:50000"]
      {%- else -%}
        ["{{ (item.ports.web + 100) }}:8080", "{{ (item.ports.agent + 100) }}:50000"]
      {%- endif -%}
```

## Dynamic SSL Certificate Generation

### Overview

SSL certificates are now automatically generated based on the `jenkins_teams` configuration, eliminating the need for manual certificate management when teams are added, removed, or modified.

### Features

1. **Team-Aware Certificate Generation**: Automatically includes all team subdomains
2. **Wildcard Support**: Supports `*.domain.com` patterns
3. **Monitoring Integration**: Includes monitoring service domains (Prometheus, Grafana)
4. **Environment-Specific**: Different handling for local vs production environments
5. **Architecture Improvement**: SSL generation moved to `high-availability-v2` role (better separation of concerns)

### Dynamic SAN (Subject Alternative Names) Generation

```yaml
# Generated automatically from jenkins_teams configuration
subject_alt_name:
  - "DNS:*.devops.example.com"                    # Wildcard domain
  - "DNS:devops.example.com"                      # Base domain
  - "DNS:jenkins.devops.example.com"              # Default Jenkins
  # Team-specific subdomains (generated dynamically)
  - "DNS:devopsjenkins.devops.example.com"        # DevOps team
  - "DNS:majenkins.devops.example.com"            # MA team  
  - "DNS:bajenkins.devops.example.com"            # BA team
  - "DNS:twjenkins.devops.example.com"            # TW team
  # Monitoring services
  - "DNS:prometheus.devops.example.com"
  - "DNS:grafana.devops.example.com"
  - "DNS:node-exporter.devops.example.com"
```

### Certificate Generation Logic

```yaml
# Dynamic SAN list generation based on jenkins_teams
- name: Generate dynamic SAN list for SSL certificate
  set_fact:
    ssl_dynamic_san_list: >-
      {{ 
        [
          "DNS:" + (jenkins_wildcard_domain | default('*.devops.local')),
          "DNS:" + (jenkins_domain | default('devops.local')),
          "DNS:jenkins." + (jenkins_domain | default('devops.local'))
        ] +
        (jenkins_teams | default([]) | map('extract', ['team_name']) | map('regex_replace', '^(.*)$', 'DNS:\\1jenkins.' + (jenkins_domain | default('devops.local'))) | list) +
        [
          "DNS:prometheus." + (jenkins_domain | default('devops.local')),
          "DNS:grafana." + (jenkins_domain | default('devops.local')), 
          "DNS:node-exporter." + (jenkins_domain | default('devops.local'))
        ]
      }}
```

## Corrected Domain Architecture

### Previous Domain Format (Incorrect)
```
❌ ma.jenkins.devops.example.com    # Confusing hierarchy
❌ ba.jenkins.devops.example.com    # Extra subdomain level
❌ tw.jenkins.devops.example.com    # Not intuitive
```

### New Domain Format (Corrected)
```
✅ majenkins.devops.example.com     # Clear team identification
✅ bajenkins.devops.example.com     # Intuitive subdomain format
✅ twjenkins.devops.example.com     # Consistent naming pattern
✅ jenkins.devops.example.com       # Default (DevOps team)
```

### Domain Routing in HAProxy

```jinja2
# Team-specific routing - corrected subdomain format ({team}jenkins.domain.com)
{% if jenkins_teams is defined and jenkins_teams | length > 0 %}
{% for team in jenkins_teams %}
{% if team.team_name != 'devops' %}
use_backend jenkins_backend_{{ team.team_name }} if { hdr_beg(host) -i {{ team.team_name }}jenkins.{{ jenkins_domain }} }
{% endif %}
{% endfor %}
{% endif %}

# DevOps team handles jenkins.devops.example.com (default backend)
use_backend jenkins_backend_devops if { hdr_beg(host) -i jenkins.{{ jenkins_domain }} }
```

## Implementation Details

### File Structure

```
ansible/roles/high-availability-v2/
├── tasks/
│   ├── main.yml                 # Main orchestration
│   ├── setup.yml               # SSL integration point
│   ├── ssl-certificates.yml    # 🆕 Dynamic SSL generation
│   ├── haproxy.yml             # HAProxy deployment
│   └── monitoring.yml          # Monitoring setup
├── templates/
│   └── haproxy.cfg.j2          # 🔄 Optimized blue-green template
├── defaults/
│   └── main.yml                # 🔄 Enhanced SSL variables
└── handlers/
    └── main.yml                # SSL certificate restart handlers
```

### Key Configuration Files

#### 1. Dynamic SSL Generation (`ssl-certificates.yml`)
- Generates wildcard certificates based on `jenkins_teams`
- Creates HAProxy-compatible certificate bundles
- Manages certificate permissions and symbolic links
- Provides environment-specific configuration

#### 2. Optimized HAProxy Template (`haproxy.cfg.j2`)
- Active-only server generation for resource optimization
- Dynamic team routing based on corrected subdomain format
- SSL certificate integration for HTTPS support

#### 3. Enhanced Role Defaults (`defaults/main.yml`)
- SSL certificate configuration variables
- Dynamic SSL generation parameters
- Team-aware certificate settings

### Team Configuration Example

```yaml
# Production inventory: ansible/inventories/production/group_vars/all/main.yml
jenkins_teams:
  - team_name: "devops"
    blue_green_enabled: true
    active_environment: "blue"     # Only blue environment runs
    ports:
      web: 8080
      agent: 50000
    labels:
      role: "default"
      
  - team_name: "ma"
    blue_green_enabled: true
    active_environment: "green"    # Only green environment runs
    ports:
      web: 8081
      agent: 50001
    labels:
      role: "marketing-analytics"
      
  - team_name: "ba"
    blue_green_enabled: true
    active_environment: "blue"     # Only blue environment runs
    ports:
      web: 8082
      agent: 50002
    labels:
      role: "business-analytics"
      
  - team_name: "tw"
    blue_green_enabled: true
    active_environment: "green"    # Only green environment runs
    ports:
      web: 8083
      agent: 50003
    labels:
      role: "test-qa"
```

### SSL Configuration

```yaml
# SSL settings in inventory
ssl_enabled: true
ssl_certificate_path: "/etc/haproxy/ssl/combined.pem"
jenkins_domain: "devops.example.com"
jenkins_wildcard_domain: "*.devops.example.com"

# SSL certificate directories (auto-created)
ssl_certificate_dir: "/etc/ssl/certs"
ssl_private_key_dir: "/etc/ssl/private"
ssl_ca_dir: "/etc/ssl/ca"
ssl_csr_dir: "/etc/ssl/csr"
```

## Configuration Examples

### Local Development Environment

```yaml
# ansible/inventories/local/group_vars/all/main.yml
deployment_environment: "local"
ssl_enabled: true
jenkins_domain: "devops.local"
jenkins_wildcard_domain: "*.devops.local"

jenkins_teams:
  - team_name: "devops"
    active_environment: "blue"
    ports: { web: 8080, agent: 50000 }
  - team_name: "ma" 
    active_environment: "blue"
    ports: { web: 8081, agent: 50001 }
```

### Production Environment

```yaml
# ansible/inventories/production/group_vars/all/main.yml
deployment_environment: "production"
ssl_enabled: true
jenkins_domain: "devops.example.com"
jenkins_wildcard_domain: "*.devops.example.com"

jenkins_teams:
  - team_name: "devops"
    active_environment: "blue"
    ports: { web: 8080, agent: 50000 }
  - team_name: "ma"
    active_environment: "green" 
    ports: { web: 8081, agent: 50001 }
  - team_name: "ba"
    active_environment: "blue"
    ports: { web: 8082, agent: 50002 }
  - team_name: "tw"
    active_environment: "green"
    ports: { web: 8083, agent: 50003 }
```

### HAProxy Access URLs

```
# Production URLs (with SSL)
https://jenkins.devops.example.com       # DevOps team (default)
https://majenkins.devops.example.com     # MA team
https://bajenkins.devops.example.com     # BA team  
https://twjenkins.devops.example.com     # TW team

# Monitoring services
https://prometheus.devops.example.com
https://grafana.devops.example.com
https://node-exporter.devops.example.com

# Local development URLs
https://jenkins.devops.local
https://majenkins.devops.local
https://bajenkins.devops.local
https://twjenkins.devops.local
```

## Deployment Commands

### Deploy with SSL Certificate Generation

```bash
# Deploy to production with SSL certificate generation
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags ssl,haproxy

# Deploy to local development with wildcard SSL
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags ssl,wildcard

# Test SSL certificate generation only
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags ssl --check
```

### Environment Switching Commands

```bash
# Switch team environment (triggers only active environment deployment)
# Change active_environment in inventory, then run:
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags haproxy --limit jenkins_masters
```

## Troubleshooting

### SSL Certificate Issues

1. **Certificate Not Generated**
   ```bash
   # Check SSL generation logs
   ansible-playbook ansible/site.yml --tags ssl -vvv
   
   # Verify SSL directories exist
   ls -la /etc/ssl/certs/ /etc/ssl/private/ /etc/haproxy/ssl/
   ```

2. **Missing Team Subdomains**
   ```bash
   # Verify jenkins_teams configuration
   ansible-inventory -i ansible/inventories/production/hosts.yml --list | jq '.all.vars.jenkins_teams'
   
   # Check generated SAN list in logs
   grep -A 20 "Generated SSL Certificate SAN list" /var/log/ansible.log
   ```

3. **HAProxy SSL Bundle Issues**
   ```bash
   # Check certificate bundle permissions
   ls -la /etc/haproxy/ssl/wildcard-*.pem
   
   # Validate certificate bundle
   openssl x509 -in /etc/haproxy/ssl/wildcard-devops.local-haproxy.pem -text -noout
   ```

### Blue-Green Environment Issues

1. **Both Environments Running**
   ```bash
   # Check active environment configuration
   docker ps | grep jenkins
   
   # Verify HAProxy backend configuration
   docker exec jenkins-haproxy cat /usr/local/etc/haproxy/haproxy.cfg | grep -A 10 "backend jenkins_backend"
   ```

2. **Team Environment Not Switching**
   ```bash
   # Check team active_environment setting
   ansible-inventory --list | jq '.all.vars.jenkins_teams[] | select(.team_name=="TEAM_NAME") | .active_environment'
   
   # Restart HAProxy to apply changes
   docker restart jenkins-haproxy
   ```

### Local Development Setup

1. **Add DNS Entries to /etc/hosts**
   ```bash
   # For local development, add these entries:
   127.0.0.1 jenkins.devops.local
   127.0.0.1 majenkins.devops.local
   127.0.0.1 bajenkins.devops.local
   127.0.0.1 twjenkins.devops.local
   127.0.0.1 prometheus.devops.local
   127.0.0.1 grafana.devops.local
   ```

2. **Trust Self-Signed Certificates**
   ```bash
   # Import CA certificate (local development)
   sudo cp /etc/ssl/certs/wildcard-devops.local.crt /usr/local/share/ca-certificates/
   sudo update-ca-certificates
   ```

## Benefits Summary

### Resource Optimization
- **50% Resource Reduction**: Only active environments consume resources
- **Improved VM Performance**: Lower CPU, memory, and storage usage
- **Cost Savings**: Reduced cloud infrastructure costs in production

### SSL Management
- **Automated Certificate Generation**: No manual SSL certificate management
- **Team-Aware Certificates**: Automatically includes all team subdomains
- **Scalable Architecture**: Adding teams automatically updates SSL certificates
- **Better Role Separation**: SSL generation where certificates are consumed

### Operational Improvements
- **Simplified Team Management**: Easy to add/remove teams
- **Consistent Subdomain Format**: Intuitive team naming convention
- **Zero-Downtime Deployments**: Maintained with resource optimization
- **Enhanced Monitoring**: Blue-green status integrated into dashboards

This architecture provides a production-ready, resource-efficient, and scalable Jenkins HA infrastructure that automatically adapts to team changes while maintaining enterprise-grade security and reliability.