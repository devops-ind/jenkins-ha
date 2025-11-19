# High-Availability Role v2 Deployment Strategy

## Executive Summary

This deployment strategy outlines the comprehensive migration from the current complex high-availability role (775 lines across 7 task files) to a simplified high-availability-v2 role (~530 lines across 4 task files) while maintaining all enterprise features and ensuring zero-downtime migration.

## Current State Analysis

### Existing Role Structure (775 lines total)
```
tasks/
├── main.yml (168 lines) - Orchestration and deployment status
├── validation.yml (84 lines) - Configuration validation
├── configuration.yml (172 lines) - System setup and user creation
├── networking.yml (76 lines) - Network infrastructure
├── volumes.yml (5 lines) - Volume management wrapper
├── containers.yml (30 lines) - Container management wrapper
├── volumes/docker.yml (26 lines) - Docker volume operations
└── containers/docker.yml (214 lines) - Complex Docker container deployment
```

### Key Enterprise Features to Preserve
- Multi-team HAProxy load balancing with wildcard domains
- Containerized HAProxy deployment with Docker
- SSL/TLS termination and certificate management
- VIP management with keepalived integration
- Health monitoring and automated failover
- Blue-green routing support for Jenkins teams
- Management scripts for operational tasks
- Production-grade security constraints
- Comprehensive validation framework

## Target Architecture (530 lines total)

### Simplified Structure
```
tasks/
├── main.yml (120 lines) - Orchestration + deployment mode detection + final status
├── setup.yml (150 lines) - Unified validation + system setup + networking  
├── haproxy.yml (180 lines) - HAProxy configuration + container deployment + volumes
└── monitoring.yml (80 lines) - VIP management + health monitoring + management scripts
```

## Phase 1: Pre-Migration Analysis and Preparation

### 1.1 Environment Assessment
```bash
# Analyze current HA deployment state
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags ha --check

# Document current HAProxy container status
ansible load_balancers -i ansible/inventories/production/hosts.yml -m shell -a "docker ps | grep jenkins-haproxy"

# Backup current HA configuration
ansible load_balancers -i ansible/inventories/production/hosts.yml -m shell -a "cp -r /etc/haproxy /etc/haproxy.backup.$(date +%Y%m%d_%H%M%S)"

# Capture current team routing status
ansible load_balancers -i ansible/inventories/production/hosts.yml -m shell -a "/usr/local/bin/haproxy-container-manager.sh status"
```

### 1.2 Risk Assessment Matrix
| Risk Category | Impact | Probability | Mitigation |
|--------------|--------|-------------|------------|
| HAProxy Service Disruption | High | Low | Blue-green HAProxy deployment |
| SSL Certificate Issues | Medium | Low | Pre-validation and backup |
| Team Routing Failure | High | Low | Gradual team migration |
| VIP Failover Problems | Medium | Medium | Keepalived validation |
| Container Startup Issues | Medium | Medium | Fallback image strategies |

### 1.3 Compatibility Validation
```bash
# Validate current team configurations
ansible-playbook ansible/site.yml --tags validation -e validation_mode=strict

# Test HAProxy configuration syntax
ansible load_balancers -i ansible/inventories/production/hosts.yml -m shell -a "docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg"

# Verify SSL certificate validity
ansible load_balancers -i ansible/inventories/production/hosts.yml -m shell -a "openssl x509 -in /etc/haproxy/ssl/combined.pem -text -noout | grep 'Not After'"
```

## Phase 2: Development and Testing Strategy

### 2.1 Create high-availability-v2 Role Structure
```bash
# Create new role directory
mkdir -p ansible/roles/high-availability-v2/{tasks,defaults,handlers,templates}

# Copy existing defaults and templates
cp -r ansible/roles/high-availability/defaults/* ansible/roles/high-availability-v2/defaults/
cp -r ansible/roles/high-availability/templates/* ansible/roles/high-availability-v2/templates/
cp -r ansible/roles/high-availability/handlers/* ansible/roles/high-availability-v2/handlers/
```

### 2.2 Simplified Task Implementation

#### main.yml (120 lines)
```yaml
---
# HAProxy High Availability Role v2 - Unified Container Management
# Simplified orchestration with deployment mode detection

# Detect deployment mode and validate configuration
- name: Determine HAProxy deployment mode
  set_fact:
    haproxy_deployment_mode: "{{ 'multi-team' if jenkins_teams is defined and jenkins_teams | length > 0 else 'single-team' }}"
    haproxy_effective_teams: "{{ jenkins_teams if jenkins_teams is defined and jenkins_teams | length > 0 else [] }}"
  tags: ['always']

- name: Display HAProxy deployment configuration
  debug:
    msg: |
      HAProxy Deployment Mode: {{ haproxy_deployment_mode }}
      Teams: {{ haproxy_effective_teams | map(attribute='team_name') | list | join(', ') if haproxy_effective_teams else 'single-team' }}
      Container Runtime: {{ haproxy_container_runtime }}
      SSL Enabled: {{ ssl_enabled | default(false) }}
      Domain: {{ jenkins_domain | default('devops.example.com') }}
  tags: ['always']

# Unified setup phase
- name: Import unified setup tasks
  import_tasks: setup.yml
  tags: ['setup', 'validate', 'config', 'network']

# HAProxy deployment phase
- name: Import HAProxy deployment tasks
  import_tasks: haproxy.yml
  tags: ['haproxy', 'container', 'deploy', 'volumes']

# Monitoring and management phase
- name: Import monitoring tasks
  import_tasks: monitoring.yml
  tags: ['monitoring', 'ha', 'vip', 'service']

# Final status display (consolidated from current main.yml)
- name: Display multi-team HA configuration status
  debug:
    msg: |
      🎯 Jenkins Multi-Team High Availability Configuration (Containerized):
      
      🌐 Domain Configuration:
      Primary Domain: {{ jenkins_domain | default('devops.example.com') }}
      Wildcard Support: {{ jenkins_wildcard_domain | default('*.devops.example.com') }}
      SSL Enabled: {{ ssl_enabled | default(false) }}
      
      🐳 Containerized Load Balancer (HAProxy):
      Container: jenkins-haproxy ({{ haproxy_image_registry }}/{{ haproxy_image_name }}:{{ haproxy_image_tag }})
      Container Runtime: {{ haproxy_container_runtime }}
      Network Mode: {{ haproxy_network_mode }}
      {% if ssl_enabled | default(false) %}
      HTTPS: https://{{ jenkins_domain }}
      HTTP: http://{{ jenkins_domain }} (redirects to HTTPS)
      SSL Certificate: /etc/haproxy/ssl/combined.pem (wildcard)
      {% else %}
      HTTP: http://{{ jenkins_domain }}
      {% endif %}
      Stats: http://{{ ansible_default_ipv4.address }}:{{ haproxy_stats_port | default(8404) }}{{ haproxy_stats_uri | default('/stats') }}
      Management: /usr/local/bin/haproxy-container-manager.sh
      
      {% if jenkins_vip is defined and jenkins_vip != "" %}
      🎯 Virtual IP Configuration:
      VIP Address: {{ jenkins_vip }}
      VRRP: Enabled with keepalived
      Priority: {{ keepalived_priority | default(100) }}
      {% endif %}
      
      👥 Team Configuration:
      {% if jenkins_teams is defined and jenkins_teams | length > 0 %}
      {% for team in jenkins_teams %}
      • {{ team.team_name | title }} Team: https://{{ team.team_name }}.{{ jenkins_domain }}
        - Port: {{ team.ports.web | default(8080) }}
        - Blue-Green: {{ team.blue_green_enabled | default(true) }}
        - Active Environment: {{ team.active_environment | default('blue') }}
      {% endfor %}
      {% else %}
      Single team configuration
      {% endif %}
      
      🔍 Health Monitoring:
      Check Interval: {{ haproxy_check_interval | default('5s') }}
      Failure Threshold: {{ haproxy_check_fall | default(3) }}
      Recovery Threshold: {{ haproxy_check_rise | default(2) }}
      
      📊 Access URLs:
      {% if jenkins_teams is defined %}
      {% for team in jenkins_teams %}
      - {{ team.team_name | title }}: https://{{ team.team_name }}.{{ jenkins_domain }}
      {% endfor %}
      {% endif %}
      - HAProxy Stats: http://{{ ansible_default_ipv4.address }}:{{ haproxy_stats_port | default(8404) }}/stats
      - Container Management: /usr/local/bin/haproxy-container-manager.sh status
  tags: ['ha', 'info']
```

#### setup.yml (150 lines)
```yaml
---
# HAProxy High Availability v2 - Unified Setup
# Combines validation, configuration, and networking

# ================================
# VALIDATION PHASE (from validation.yml)
# ================================
- name: Validate HAProxy container runtime
  assert:
    that:
      - haproxy_container_runtime == 'docker'
    fail_msg: "haproxy_container_runtime must be 'docker'"
    success_msg: "HAProxy container runtime validated: {{ haproxy_container_runtime }}"
  tags: ['validation', 'config']

- name: Validate team configuration for multi-team setup
  assert:
    that:
      - jenkins_teams is defined
      - jenkins_teams | length > 0
      - jenkins_domain is defined
      - jenkins_domain | length > 0
    fail_msg: "Multi-team configuration requires jenkins_teams and jenkins_domain to be defined"
    success_msg: "Team configuration validated - {{ jenkins_teams | length }} team(s) configured"
  when: team_routing_enabled | default(true)
  tags: ['validation', 'teams']

- name: Validate SSL configuration
  assert:
    that:
      - ssl_cert_path is defined
      - ssl_cert_path | length > 0
    fail_msg: "SSL configuration requires ssl_cert_path to be defined"
    success_msg: "SSL configuration validated - certificate path: {{ ssl_cert_path }}"
  when: ssl_enabled | default(false)
  tags: ['validation', 'ssl']

- name: Validate required HAProxy image configuration
  assert:
    that:
      - haproxy_image_name is defined
      - haproxy_image_tag is defined
      - haproxy_image_registry is defined
    fail_msg: "HAProxy image configuration incomplete"
    success_msg: "HAProxy image configuration validated: {{ haproxy_image_registry }}/{{ haproxy_image_name }}:{{ haproxy_image_tag }}"
  tags: ['validation', 'image']

- name: Check if SSL certificate files exist
  stat:
    path: "{{ item }}"
  loop:
    - "{{ ssl_cert_path }}"
    - "{{ ssl_key_path | default(ssl_cert_path) }}"
  register: ssl_cert_files
  when: ssl_enabled | default(false)
  tags: ['validation', 'ssl', 'files']

# ================================
# SYSTEM CONFIGURATION PHASE (from configuration.yml)
# ================================
- name: Check if Docker is available for HAProxy container
  command: docker --version
  register: docker_check
  failed_when: false
  changed_when: false
  tags: ['config', 'docker']

- name: Validate Docker installation
  fail:
    msg: |
      Docker is not installed or not available in PATH.
      Please install Docker first using the appropriate role or package manager.
      HAProxy containers require Docker to be installed and running.
  when: docker_check.rc != 0
  tags: ['config', 'docker']

- name: Check if Docker service is running
  command: docker info
  register: docker_info_check
  failed_when: false
  changed_when: false
  tags: ['config', 'service']

- name: Create HAProxy group
  group:
    name: "{{ haproxy_user }}"
    gid: "{{ haproxy_gid }}"
    system: yes
    state: present
  become: yes
  tags: ['config', 'user']

- name: Create HAProxy user
  user:
    name: "{{ haproxy_user }}"
    uid: "{{ haproxy_uid }}"
    group: "{{ haproxy_user }}"
    system: yes
    home: "/var/lib/haproxy"
    shell: "/bin/false"
    create_home: yes
    state: present
  become: yes
  tags: ['config', 'user']

# ================================
# NETWORKING CONFIGURATION PHASE (from networking.yml)
# ================================
- name: Create HAProxy configuration directories
  file:
    path: "{{ item }}"
    state: directory
    owner: "{{ haproxy_user }}"
    group: "{{ haproxy_user }}"
    mode: '0755'
  loop:
    - "/etc/haproxy"
    - "/etc/haproxy/conf.d"
    - "/etc/haproxy/errors"
    - "/var/log/haproxy"
    - "/var/lib/haproxy"
  become: yes
  tags: ['network', 'config']

- name: Create SSL directory structure
  file:
    path: "/etc/haproxy/ssl"
    state: directory
    owner: "{{ haproxy_user }}"
    group: "{{ haproxy_user }}"
    mode: '0700'
  become: yes
  when: ssl_enabled | default(false)
  tags: ['network', 'ssl']

- name: Generate main HAProxy configuration
  template:
    src: haproxy.cfg.j2
    dest: /etc/haproxy/haproxy.cfg
    owner: "{{ haproxy_user }}"
    group: "{{ haproxy_user }}"
    mode: '0644'
    backup: yes
  become: yes
  notify: restart haproxy container
  tags: ['network', 'config']

- name: Generate team-specific backend configurations
  template:
    src: haproxy-team-backend.cfg.j2
    dest: "/etc/haproxy/conf.d/{{ item.team_name }}-backend.cfg"
    owner: "{{ haproxy_user }}"
    group: "{{ haproxy_user }}"
    mode: '0644'
  loop: "{{ jenkins_teams | default([]) }}"
  become: yes
  notify: restart haproxy container
  when: jenkins_teams is defined and jenkins_teams | length > 0
  tags: ['network', 'teams']
```

#### haproxy.yml (180 lines)
```yaml
---
# HAProxy High Availability v2 - Container Deployment
# Combines volumes and container management

# ================================
# VOLUME MANAGEMENT PHASE (from volumes.yml and volumes/docker.yml)
# ================================
- name: Create HAProxy admin socket volume
  community.docker.docker_volume:
    name: haproxy-admin-socket
    state: present
  tags: ['volumes', 'setup']

- name: Create HAProxy log volume
  community.docker.docker_volume:
    name: haproxy-logs
    state: present
  tags: ['volumes', 'setup']

# ================================
# SSL CERTIFICATE MANAGEMENT
# ================================
- name: Combine SSL certificate and key into single file
  shell: |
    cat {{ ssl_cert_path }} {{ ssl_key_path | default(ssl_cert_path) }} > /etc/haproxy/ssl/combined.pem
    chown {{ haproxy_user }}:{{ haproxy_user }} /etc/haproxy/ssl/combined.pem
    chmod 600 /etc/haproxy/ssl/combined.pem
  become: yes
  when: ssl_enabled | default(false)
  tags: ['ssl', 'certificate']

# ================================
# CONTAINER DEPLOYMENT PHASE (simplified from containers/docker.yml)
# ================================
- name: Detect devcontainer environment
  set_fact:
    _is_devcontainer: "{{ ansible_env.REMOTE_CONTAINERS is defined or ansible_env.CODESPACES is defined }}"
  tags: ['containers', 'detect']

- name: Set HAProxy image based on environment
  set_fact:
    _haproxy_image_tag: "{{ haproxy_image_alternatives.devcontainer if _is_devcontainer else haproxy_image_tag }}"
  tags: ['containers', 'image']

- name: Deploy HAProxy container with production configuration
  community.docker.docker_container:
    name: "jenkins-haproxy"
    image: "{{ haproxy_image_registry }}/{{ haproxy_image_name }}:{{ _haproxy_image_tag }}"
    state: started
    restart_policy: "{{ haproxy_restart_policy }}"
    network_mode: "{{ haproxy_network_mode }}"
    ports: "{{ _haproxy_ports }}"
    volumes: "{{ _haproxy_volumes | select() | list }}"
    env: "{{ haproxy_env_vars }}"
    memory: "{{ haproxy_memory_limit }}"
    cpus: "{{ haproxy_cpu_limit }}"
    log_driver: "{{ haproxy_log_driver }}"
    log_options:
      max-size: "{{ haproxy_log_max_size }}"
      max-file: "{{ haproxy_log_max_files }}"
    labels: "{{ haproxy_labels | combine(_haproxy_dynamic_labels) }}"
    user: "{{ _haproxy_container_user }}"
    healthcheck:
      test: ["CMD-SHELL", "{{ _haproxy_health_check_command }}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
  vars:
    _haproxy_ports: "{{ [] if haproxy_network_mode == 'host' else _haproxy_port_mappings }}"
    _haproxy_port_mappings:
      - "80:80"
      - "443:443"
      - "{{ haproxy_stats_port | default(8404) }}:{{ haproxy_stats_port | default(8404) }}"
    _haproxy_volumes:
      - "/etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro"
      - "/etc/haproxy/conf.d:/usr/local/etc/haproxy/conf.d:ro"
      - "{{ ssl_enabled | ternary('/etc/haproxy/ssl/combined.pem:/usr/local/etc/haproxy/ssl/combined.pem:ro', '') }}"
      - "/etc/haproxy/errors:/etc/haproxy/errors:ro"
      - "/var/log/haproxy:/var/log/haproxy:rw"
      - "/var/lib/haproxy:/var/lib/haproxy:rw"
      - "haproxy-admin-socket:/run/haproxy:rw"
    _haproxy_container_user: "{{ '' if deployment_mode in ['devcontainer', 'local'] else (haproxy_uid ~ ':' ~ haproxy_gid) }}"
    _haproxy_health_check_command: >-
      test -f /usr/local/etc/haproxy/haproxy.cfg
    _haproxy_dynamic_labels:
      teams: "{{ jenkins_teams | default([]) | map(attribute='team_name') | join(',') }}"
      ssl_enabled: "{{ ssl_enabled | default(false) | string }}"
      version: "{{ _haproxy_image_tag }}"
      deployment_mode: "{{ deployment_mode }}"
  register: haproxy_container_result
  when: not _is_devcontainer
  tags: ['containers', 'docker', 'deploy']

- name: Deploy HAProxy container with devcontainer compatibility
  community.docker.docker_container:
    name: "jenkins-haproxy"
    image: "{{ haproxy_image_registry }}/{{ haproxy_image_name }}:{{ _haproxy_image_tag }}"
    state: started
    restart_policy: "{{ haproxy_restart_policy }}"
    network_mode: "{{ haproxy_network_mode }}"
    ports: "{{ _haproxy_ports }}"
    volumes: "{{ _haproxy_volumes | select() | list }}"
    env: "{{ haproxy_env_vars }}"
    memory: "{{ haproxy_memory_limit }}"
    cpus: "{{ haproxy_cpu_limit }}"
    privileged: true
    security_opts:
      - "seccomp=unconfined"
      - "apparmor=unconfined"
    sysctls:
      net.ipv4.ip_unprivileged_port_start: 80
    capabilities:
      - NET_BIND_SERVICE
      - NET_ADMIN
    labels: "{{ haproxy_labels | combine(_haproxy_dynamic_labels) }}"
    healthcheck:
      test: ["CMD-SHELL", "{{ _haproxy_health_check_command }}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
  vars:
    _haproxy_ports: "{{ [] if haproxy_network_mode == 'host' else _haproxy_port_mappings }}"
    _haproxy_port_mappings:
      - "80:80"
      - "443:443"
      - "{{ haproxy_stats_port | default(8404) }}:{{ haproxy_stats_port | default(8404) }}"
    _haproxy_volumes:
      - "/etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro"
      - "/etc/haproxy/conf.d:/usr/local/etc/haproxy/conf.d:ro"
      - "{{ ssl_enabled | ternary('/etc/haproxy/ssl/combined.pem:/usr/local/etc/haproxy/ssl/combined.pem:ro', '') }}"
      - "/etc/haproxy/errors:/etc/haproxy/errors:ro"
      - "/var/log/haproxy:/var/log/haproxy:rw"
      - "/var/lib/haproxy:/var/lib/haproxy:rw"
      - "haproxy-admin-socket:/run/haproxy:rw"
    _haproxy_health_check_command: >-
      test -f /usr/local/etc/haproxy/haproxy.cfg
    _haproxy_dynamic_labels:
      teams: "{{ jenkins_teams | default([]) | map(attribute='team_name') | join(',') }}"
      ssl_enabled: "{{ ssl_enabled | default(false) | string }}"
      version: "{{ _haproxy_image_tag }}"
      deployment_mode: "{{ deployment_mode }}"
  when: _is_devcontainer
  tags: ['containers', 'docker', 'deploy', 'devcontainer']

- name: Wait for HAProxy container to be ready
  wait_for:
    port: "{{ haproxy_stats_port | default(8404) }}"
    host: "{{ ansible_default_ipv4.address }}"
    delay: "{{ haproxy_startup_wait_time }}"
    timeout: 120
  tags: ['containers', 'verify']

- name: Verify HAProxy configuration syntax
  command: docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
  register: haproxy_config_check
  failed_when: haproxy_config_check.rc != 0
  tags: ['containers', 'verify']
```

#### monitoring.yml (80 lines)
```yaml
---
# HAProxy High Availability v2 - Monitoring and VIP Management
# Combines VIP management, health monitoring, and management scripts

# ================================
# MANAGEMENT SCRIPTS DEPLOYMENT
# ================================
- name: Create HA monitoring and management scripts
  template:
    src: "{{ item }}.j2"
    dest: "/usr/local/bin/{{ item }}"
    mode: '0755'
  loop:
    - jenkins-ha-monitor.sh
    - jenkins-failover.sh
    - haproxy-container-manager.sh
    - keepalived-haproxy-check.sh
  become: yes
  tags: ['ha', 'monitoring', 'scripts']

# ================================
# VIP MANAGEMENT WITH KEEPALIVED
# ================================
- name: Install keepalived for VIP management
  package:
    name: keepalived
    state: present
  become: yes
  when: jenkins_vip is defined and jenkins_vip != ""
  tags: ['ha', 'vip', 'install']

- name: Configure keepalived for VIP
  template:
    src: keepalived.conf.j2
    dest: /etc/keepalived/keepalived.conf
    backup: yes
  become: yes
  notify: restart keepalived
  when: jenkins_vip is defined and jenkins_vip != ""
  tags: ['ha', 'vip', 'config']

- name: Start and enable keepalived
  systemd:
    name: keepalived
    state: started
    enabled: yes
    daemon_reload: yes
  become: yes
  when: jenkins_vip is defined and jenkins_vip != ""
  tags: ['ha', 'service', 'vip']

# ================================
# HEALTH MONITORING SETUP
# ================================
- name: Check if crontab is available
  command: which crontab
  register: crontab_check
  failed_when: false
  changed_when: false
  tags: ['ha', 'monitoring']

- name: Setup HA monitoring cron job
  cron:
    name: "Jenkins HA Health Monitoring"
    job: "/usr/local/bin/jenkins-ha-monitor.sh"
    minute: "*/2"
    user: root
  become: yes
  when: crontab_check.rc == 0
  tags: ['ha', 'monitoring', 'cron']

- name: Skip cron job setup (crontab not available)
  debug:
    msg: "Skipping HA monitoring cron job - crontab not installed (development environment)"
  when: crontab_check.rc != 0
  tags: ['ha', 'monitoring']

# ================================
# VERIFICATION AND VALIDATION
# ================================
- name: Verify HAProxy stats endpoint
  uri:
    url: "http://{{ ansible_default_ipv4.address }}:{{ haproxy_stats_port | default(8404) }}/stats"
    method: GET
  register: stats_check
  retries: 3
  delay: 10
  tags: ['monitoring', 'verify']

- name: Verify team endpoints accessibility
  uri:
    url: "http://{{ item.team_name }}.{{ jenkins_domain }}"
    method: GET
    follow_redirects: no
    status_code: [200, 302, 503]  # 503 acceptable if Jenkins not ready
  loop: "{{ jenkins_teams | default([]) }}"
  register: team_endpoints_check
  retries: 3
  delay: 5
  when: jenkins_teams is defined and jenkins_teams | length > 0
  tags: ['monitoring', 'verify', 'teams']

- name: Display monitoring setup status
  debug:
    msg: |
      🔍 HA Monitoring Configuration:
      - Scripts deployed: /usr/local/bin/jenkins-ha-monitor.sh
      - Keepalived: {{ 'Enabled' if jenkins_vip is defined and jenkins_vip != '' else 'Disabled' }}
      - VIP Address: {{ jenkins_vip | default('Not configured') }}
      - Health checks: Every 2 minutes
      - HAProxy stats: http://{{ ansible_default_ipv4.address }}:{{ haproxy_stats_port | default(8404) }}/stats
  tags: ['monitoring', 'info']
```

### 2.3 Testing Strategy

#### Local Environment Testing
```bash
# Test new role in local environment
cp ansible/roles/high-availability ansible/roles/high-availability-backup
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags ha -e high_availability_role=high-availability-v2

# Validate functionality
/usr/local/bin/haproxy-container-manager.sh status
curl -s http://localhost:8404/stats | grep -E "(frontend|backend)"
```

#### Staging Environment Validation
```bash
# Deploy to staging with new role
ansible-playbook -i ansible/inventories/staging/hosts.yml ansible/site.yml --tags ha -e high_availability_role=high-availability-v2

# Comprehensive testing
scripts/ha-setup.sh staging validate
scripts/blue-green-healthcheck.sh staging all
```

## Phase 3: Production Migration Strategy

### 3.1 Blue-Green Migration Approach

#### Step 1: Parallel Deployment Preparation
```bash
# Create migration validation playbook
cat > ansible/migration-validation.yml << 'EOF'
---
- hosts: load_balancers
  become: yes
  tasks:
    - name: Create HAProxy migration checkpoint
      shell: |
        mkdir -p /var/backup/ha-migration/$(date +%Y%m%d_%H%M%S)
        cp -r /etc/haproxy /var/backup/ha-migration/$(date +%Y%m%d_%H%M%S)/
        docker inspect jenkins-haproxy > /var/backup/ha-migration/$(date +%Y%m%d_%H%M%S)/container-state.json
        /usr/local/bin/haproxy-container-manager.sh status > /var/backup/ha-migration/$(date +%Y%m%d_%H%M%S)/current-status.log
      
    - name: Test new role without deployment
      include_role:
        name: high-availability-v2
      vars:
        haproxy_test_mode: true
      check_mode: yes
EOF

# Execute migration validation
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/migration-validation.yml
```

#### Step 2: Staged Migration Implementation
```bash
# Phase 1: Deploy to first load balancer (if multiple)
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --limit load_balancers[0] --tags ha -e high_availability_role=high-availability-v2

# Validate first node
ansible load_balancers[0] -i ansible/inventories/production/hosts.yml -m shell -a "/usr/local/bin/jenkins-ha-monitor.sh"

# Phase 2: Deploy to remaining load balancers
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --limit load_balancers[1:] --tags ha -e high_availability_role=high-availability-v2
```

### 3.2 Zero-Downtime Migration Procedures

#### HAProxy Container Migration
```bash
# Create zero-downtime migration script
cat > scripts/ha-zero-downtime-migration.sh << 'EOF'
#!/bin/bash
set -euo pipefail

INVENTORY_FILE="ansible/inventories/production/hosts.yml"
MIGRATION_LOG="/var/log/ha-migration-$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MIGRATION_LOG"
}

# Pre-migration health check
log "Starting HA role migration - Pre-migration health check"
ansible-playbook -i "$INVENTORY_FILE" ansible/site.yml --tags validation -e validation_mode=strict

# Create migration checkpoint
log "Creating migration checkpoint"
ansible load_balancers -i "$INVENTORY_FILE" -m shell -a "
    mkdir -p /var/backup/ha-migration/$(date +%Y%m%d_%H%M%S)
    cp -r /etc/haproxy /var/backup/ha-migration/$(date +%Y%m%d_%H%M%S)/
    docker inspect jenkins-haproxy > /var/backup/ha-migration/$(date +%Y%m%d_%H%M%S)/container-state.json
"

# Gradual migration by node
for node in $(ansible load_balancers -i "$INVENTORY_FILE" --list-hosts | tail -n +2); do
    log "Migrating node: $node"
    
    # Deploy new role to single node
    ansible-playbook -i "$INVENTORY_FILE" ansible/site.yml --limit "$node" --tags ha -e high_availability_role=high-availability-v2
    
    # Verify node health
    ansible "$node" -i "$INVENTORY_FILE" -m shell -a "/usr/local/bin/jenkins-ha-monitor.sh"
    
    # Wait for stability
    sleep 30
    
    log "Node $node migration completed successfully"
done

log "HA role migration completed successfully"
EOF

chmod +x scripts/ha-zero-downtime-migration.sh
```

### 3.3 Rollback Procedures

#### Immediate Rollback Script
```bash
# Create comprehensive rollback script
cat > scripts/ha-rollback.sh << 'EOF'
#!/bin/bash
set -euo pipefail

INVENTORY_FILE="ansible/inventories/production/hosts.yml"
BACKUP_DIR="/var/backup/ha-migration"
ROLLBACK_LOG="/var/log/ha-rollback-$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ROLLBACK_LOG"
}

rollback_node() {
    local node=$1
    local latest_backup=$2
    
    log "Rolling back node: $node"
    
    # Stop new HAProxy container
    ansible "$node" -i "$INVENTORY_FILE" -m shell -a "docker stop jenkins-haproxy || true"
    
    # Restore configuration
    ansible "$node" -i "$INVENTORY_FILE" -m shell -a "
        cp -r $latest_backup/haproxy/* /etc/haproxy/
        chown -R haproxy:haproxy /etc/haproxy
    "
    
    # Restart with original configuration
    ansible-playbook -i "$INVENTORY_FILE" ansible/site.yml --limit "$node" --tags ha -e high_availability_role=high-availability
    
    # Verify rollback
    ansible "$node" -i "$INVENTORY_FILE" -m shell -a "/usr/local/bin/jenkins-ha-monitor.sh"
    
    log "Rollback completed for node: $node"
}

# Find latest backup
LATEST_BACKUP=$(ansible load_balancers[0] -i "$INVENTORY_FILE" -m shell -a "ls -1t $BACKUP_DIR | head -1" | grep -v '|' | tail -1)

log "Starting rollback using backup: $LATEST_BACKUP"

# Rollback all nodes
for node in $(ansible load_balancers -i "$INVENTORY_FILE" --list-hosts | tail -n +2); do
    rollback_node "$node" "$BACKUP_DIR/$LATEST_BACKUP"
done

log "Complete rollback finished successfully"
EOF

chmod +x scripts/ha-rollback.sh
```

## Phase 4: Validation and Verification

### 4.1 Comprehensive Testing Suite

#### Functional Testing
```bash
# Create comprehensive validation playbook
cat > ansible/ha-v2-validation.yml << 'EOF'
---
- hosts: load_balancers
  become: yes
  vars:
    validation_tests:
      - name: "HAProxy container status"
        command: "docker ps | grep jenkins-haproxy"
        expected_rc: 0
      - name: "HAProxy configuration syntax"
        command: "docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg"
        expected_rc: 0
      - name: "HAProxy stats endpoint"
        command: "curl -s -o /dev/null -w '%{http_code}' http://localhost:{{ haproxy_stats_port | default(8404) }}/stats"
        expected_output: "200"
      - name: "SSL certificate validity"
        command: "openssl x509 -in /etc/haproxy/ssl/combined.pem -checkend 86400 -noout"
        expected_rc: 0
        when: "{{ ssl_enabled | default(false) }}"
      - name: "VIP functionality"
        command: "ip addr show | grep {{ jenkins_vip }}"
        expected_rc: 0
        when: "{{ jenkins_vip is defined and jenkins_vip != '' }}"

  tasks:
    - name: Execute validation tests
      shell: "{{ item.command }}"
      register: test_results
      failed_when: >
        (item.expected_rc is defined and test_results.rc != item.expected_rc) or
        (item.expected_output is defined and item.expected_output not in test_results.stdout)
      when: item.when | default(true)
      loop: "{{ validation_tests }}"
      loop_control:
        label: "{{ item.name }}"

    - name: Verify team routing
      uri:
        url: "http://{{ item.team_name }}.{{ jenkins_domain }}"
        method: GET
        follow_redirects: no
        status_code: [200, 302, 503]
      loop: "{{ jenkins_teams | default([]) }}"
      when: jenkins_teams is defined

    - name: Generate validation report
      template:
        src: validation-report.j2
        dest: "/tmp/ha-v2-validation-report-{{ ansible_date_time.epoch }}.txt"
        mode: '0644'
EOF

# Execute validation
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/ha-v2-validation.yml
```

### 4.2 Performance Benchmarking

#### Load Testing
```bash
# HAProxy performance validation
cat > scripts/ha-performance-test.sh << 'EOF'
#!/bin/bash

# Basic load test
ab -n 1000 -c 10 http://devops.example.com/

# Team routing test
for team in devops developer; do
    echo "Testing $team.devops.example.com"
    ab -n 100 -c 5 http://$team.devops.example.com/
done

# SSL termination test (if enabled)
ab -n 100 -c 5 https://devops.example.com/

# HAProxy stats monitoring during load
watch -n 5 'curl -s http://localhost:8404/stats | grep -E "(frontend|backend)"'
EOF

chmod +x scripts/ha-performance-test.sh
```

### 4.3 Security Validation

#### Security Testing
```bash
# SSL/TLS security validation
cat > scripts/ha-security-validation.sh << 'EOF'
#!/bin/bash

# SSL certificate validation
openssl s_client -connect devops.example.com:443 -servername devops.example.com < /dev/null

# SSL configuration strength
nmap --script ssl-enum-ciphers -p 443 devops.example.com

# HAProxy security headers
curl -I https://devops.example.com | grep -E "(Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options)"

# Container security
docker inspect jenkins-haproxy | jq '.[] | {Privileged: .HostConfig.Privileged, SecurityOpt: .HostConfig.SecurityOpt}'
EOF

chmod +x scripts/ha-security-validation.sh
```

## Phase 5: Production Deployment and Monitoring

### 5.1 Production Deployment Schedule

#### Deployment Timeline
```
Week 1: Development and local testing
Week 2: Staging environment validation
Week 3: Production deployment preparation
Week 4: Production deployment execution
```

#### Deployment Windows
- **Primary Window**: Saturday 02:00-06:00 UTC (low traffic)
- **Backup Window**: Sunday 02:00-06:00 UTC
- **Emergency Rollback**: Any time within 24 hours

### 5.2 Monitoring and Alerting

#### Enhanced Monitoring Setup
```yaml
# Enhanced monitoring configuration
ha_monitoring_v2:
  metrics_collection:
    - haproxy_container_status
    - ssl_certificate_expiry
    - vip_availability
    - team_routing_health
    - performance_benchmarks
  
  alert_thresholds:
    container_restart_rate: 3/hour
    ssl_expiry_warning: 30 days
    response_time_degradation: 20%
    error_rate_spike: 5%
  
  dashboard_panels:
    - HAProxy container health
    - Team routing status
    - SSL certificate monitoring
    - VIP failover events
    - Performance metrics
```

### 5.3 Post-Deployment Validation

#### 24-Hour Monitoring Protocol
```bash
# Continuous monitoring script
cat > scripts/ha-post-deployment-monitor.sh << 'EOF'
#!/bin/bash

MONITOR_LOG="/var/log/ha-post-deployment-$(date +%Y%m%d).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MONITOR_LOG"
}

while true; do
    # Check HAProxy container
    if ! docker ps | grep -q jenkins-haproxy; then
        log "ALERT: HAProxy container not running"
    fi
    
    # Check team endpoints
    for team in devops developer; do
        if ! curl -s -f http://$team.devops.example.com > /dev/null; then
            log "WARNING: Team $team endpoint not responding"
        fi
    done
    
    # Check VIP status
    if ! ip addr show | grep -q "{{ jenkins_vip }}"; then
        log "WARNING: VIP not active on this node"
    fi
    
    sleep 300  # 5-minute intervals
done
EOF

chmod +x scripts/ha-post-deployment-monitor.sh
```

## Success Criteria and KPIs

### Technical Success Metrics
- **Line Count Reduction**: 775 → 530 lines (31% reduction)
- **File Simplification**: 7 → 4 task files (43% reduction)
- **Zero Downtime**: No service interruption during migration
- **Feature Preservation**: 100% enterprise feature retention
- **Performance**: No degradation in response times
- **Security**: Maintained security posture

### Operational Success Metrics
- **Deployment Time**: <2 hours total migration time
- **Rollback Capability**: <15 minutes rollback time
- **Team Impact**: Zero team workflow disruption
- **Documentation**: Complete operational runbooks
- **Training**: All team members trained on new procedures

## Risk Mitigation Summary

### High-Risk Scenarios
1. **HAProxy Container Failure**: Blue-green deployment with immediate rollback
2. **SSL Certificate Issues**: Pre-validated certificates with backup procedures
3. **VIP Failover Problems**: Keepalived validation with manual override
4. **Team Routing Disruption**: Gradual migration with per-team validation

### Mitigation Strategies
- Comprehensive backup procedures before migration
- Parallel deployment validation
- Automated rollback triggers
- 24/7 monitoring during migration window
- Expert team on standby during deployment

## Conclusion

This deployment strategy provides a comprehensive, enterprise-grade approach to migrating from the complex high-availability role to the simplified high-availability-v2 role while maintaining zero-downtime and preserving all critical enterprise features. The phased approach, extensive validation procedures, and robust rollback mechanisms ensure safe deployment in production environments.

The simplified role structure will improve maintainability, reduce complexity, and enhance deployment reliability while preserving the multi-team HAProxy load balancing, VIP management, SSL termination, and health monitoring capabilities essential for enterprise Jenkins infrastructure.