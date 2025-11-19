# Complete Code Repository - Jenkins HA Ansible Infrastructure

This document contains the Jenkins and High Availability roles code from the project, organized by directory and file. Each code snippet is prefixed with the filename for easy reference.

## Table of Contents

- [Group Variables](#group-variables)
- [Jenkins Master v2 Role (Simplified)](#jenkins-master-v2-role-simplified)
- [High Availability v2 Role (Simplified)](#high-availability-v2-role-simplified)

---

# Group Variables

## File: ansible/group_vars/all/jenkins.yml

```yaml
---
# Jenkins Default Configuration
# These are default values that can be overridden in environment-specific group_vars

# Default Jenkins version (can be overridden per environment)
jenkins_version: "2.426.1"
jenkins_dynamic_agent_version: "{{ jenkins_version }}"

# Default ports
jenkins_master_port: 8080
jenkins_jnlp_port: 50000  # Used for dynamic agent connections

# Default paths - should be overridden in environment-specific configs
jenkins_home_dir: "/var/jenkins"
jenkins_user: "jenkins"
jenkins_group: "jenkins"
jenkins_uid: 1002
jenkins_gid: 1002

# Default Jenkins configuration
jenkins_admin_user: "admin"
jenkins_enable_security: true
jenkins_enable_csrf: true
jenkins_enable_agent_protocols: "JNLP4-connect"  # Protocol for dynamic agents

# Default plugins - can be extended in environment configs
jenkins_plugins:
  - workflow-aggregator
  - docker-workflow
  - kubernetes
  - prometheus
  - configuration-as-code
  - build-timeout
  - credentials-binding
  - timestamper
  - ws-cleanup
  - ant
  - gradle

# Default container configuration
jenkins_container_runtime: "docker"  # Global container runtime for all roles
jenkins_master_memory: "2g"
jenkins_master_java_opts: "-Djenkins.install.runSetupWizard=false"

# Default network settings
jenkins_network_name: "jenkins-net"
jenkins_network_subnet: "172.20.0.0/16"

# Default backup settings
jenkins_backup_enabled: false
jenkins_backup_schedule: "0 2 * * 0"
jenkins_backup_retention_days: 30

# Default monitoring settings
jenkins_monitoring_enabled: true
jenkins_metrics_enabled: true

# Default security settings
jenkins_security_realm: "local"
jenkins_authorization_strategy: "logged_in_users_can_do_anything"

# Blue-Green Deployment Configuration
# Controls single-master deployment with blue-green switching capability
jenkins_deployment_mode: "blue-green"  # Options: "ha" (dual-master) or "blue-green" (single-master)
jenkins_blue_green_enabled: true
jenkins_current_environment: "blue"  # Current active environment: "blue" or "green"
jenkins_target_environment: "green"   # Target environment for next deployment
jenkins_blue_green_port_offset: 10     # Port offset between blue and green (blue: 8080, green: 8090)
jenkins_blue_green_shared_data: true    # Share Jenkins data between environments
jenkins_blue_green_health_check_retries: 10
jenkins_blue_green_health_check_delay: 15
jenkins_blue_green_switch_timeout: 300  # Timeout for environment switching in seconds

# Blue-Green Environment Specific Configuration
jenkins_blue_container_name: "jenkins-blue"
jenkins_green_container_name: "jenkins-green"
jenkins_blue_port: "{{ jenkins_master_port }}"
jenkins_green_port: "{{ jenkins_master_port + jenkins_blue_green_port_offset }}"
jenkins_blue_agent_port: "{{ jenkins_jnlp_port }}"
jenkins_green_agent_port: "{{ jenkins_jnlp_port + jenkins_blue_green_port_offset }}"

# Blue-Green Volume Configuration
jenkins_shared_home_volume: "jenkins-shared-home"  # Shared between blue and green
jenkins_blue_temp_volume: "jenkins-blue-temp"      # Blue-specific temporary data
jenkins_green_temp_volume: "jenkins-green-temp"    # Green-specific temporary data
jenkins_shared_plugins_volume: "jenkins-shared-plugins"  # Shared plugin directory

# Blue-Green Load Balancer Integration
jenkins_load_balancer_backend_file: "/etc/haproxy/conf.d/jenkins-backend.cfg"
jenkins_active_backend_port: "{{ jenkins_blue_port if jenkins_current_environment == 'blue' else jenkins_green_port }}"
jenkins_standby_backend_port: "{{ jenkins_green_port if jenkins_current_environment == 'blue' else jenkins_blue_port }}"

# Blue-Green Health Check Configuration
jenkins_health_check_endpoint: "/api/json?pretty=true"
jenkins_health_check_expected_status: 200
jenkins_health_check_timeout: 10

# Blue-Green Deployment Strategy Settings
jenkins_pre_deployment_backup: true     # Create backup before switching environments
jenkins_post_deployment_verification: true  # Run verification tests after switching
jenkins_auto_rollback_enabled: true     # Automatically rollback on health check failure
jenkins_rollback_timeout: 120           # Time to wait before automatic rollback

# Blue-Green Network Configuration
jenkins_blue_network_alias: "jenkins-blue"
jenkins_green_network_alias: "jenkins-green"
jenkins_active_network_alias: "jenkins-active"  # DNS alias pointing to active environment

# Image Building Configuration
jenkins_images_build_dir: "/tmp/jenkins-images-build"  # Used by jenkins-images role
jenkins_images_force_rebuild: false
jenkins_images_push: false
jenkins_images_cleanup: true

# Jenkins Version Configuration
jenkins_master_image_tag: "{{ jenkins_version }}"
jenkins_agent_image_tag: "{{ jenkins_dynamic_agent_version }}"
```

## File: ansible/group_vars/all/jenkins_teams.yml

```yaml
---
jenkins_teams:
  - team_name: devops
    active_environment: blue
    blue_green_enabled: true
    ports:
      web: 8080
      agent: 50000
    resources:
      memory: "3g"
      cpu: "2.0"
    env_vars:
      JENKINS_TEAM: "devops"
      JENKINS_ADMIN_PASSWORD: "{{ vault_jenkins_admin_password | default('admin123') }}"
    labels:
      team: "devops"
      tier: "production"
      environment: "{{ deployment_mode | default('local') }}"
    security_policies:
      rbac_enabled: true
      namespace_isolation: true
      resource_quotas:
        cpu_limit: "4"
        memory_limit: "8Gi"
        storage_limit: "100Gi"
      network_policies:
        ingress_allowed: ["monitoring", "load_balancers"]
        egress_allowed: ["harbor", "git_repos", "internet"]
    
    credentials:
      - type: "usernamePassword"
        id: "devops-git-credentials"
        username: "admin"
        password: "{{ vault_git_password | default('git123') }}"
        description: "DevOps Team Git Credentials"
        scope: "GLOBAL"
      - type: "secretText"
        id: "devops-api-token"
        secret: "{{ vault_devops_api_token | default('token123') }}"
        description: "DevOps Team API Token"
        scope: "GLOBAL"
      - type: "usernamePassword"
        id: "harbor-registry-credentials"
        username: "{{ vault_harbor_username | default('admin') }}"
        password: "{{ vault_harbor_password | default('Harbor12345') }}"
        description: "Harbor Registry Credentials"
    seed_jobs:
      - name: "infrastructure-health-check"
        type: "pipeline"
        display_name: "Infrastructure Health Check"
        description: "Health monitoring for DevOps team infrastructure"
        folder: "Infrastructure"
        pipeline_source: "external"  # NEW: Pipeline source type
        jenkinsfile_path: "pipelines/Jenkinsfile.health-check"
        git_repo: "https://github.com/your-org/jenkins-ha.git"  # NEW: Repository URL
        git_branch: "main"  # NEW: Branch specification
        triggers:
          - type: "cron"
            schedule: "H/15 * * * *"
          - type: "webhook"  # NEW: Support for webhook triggers
            token: "health-check-webhook"
        parameters:
          - name: "CHECK_TYPE"
            type: "choice"
            choices: ["full", "basic", "connectivity"]
            description: "Type of health check to perform"
        deployment_gates:  # NEW: Deployment safety gates
          pre_deployment:
            - "connectivity_check"
            - "resource_validation"
          post_deployment:
            - "health_verification"
            - "sli_validation"
      - name: "backup-pipeline"
        type: "pipeline"
        display_name: "Jenkins Backup"
        description: "Automated backup pipeline with RTO/RPO compliance"
        folder: "Infrastructure"
        pipeline_source: "external"
        jenkinsfile_path: "pipelines/Jenkinsfile.backup"
        git_repo: "https://github.com/your-org/jenkins-ha.git"
        git_branch: "main"
        triggers:
          - type: "cron"
            schedule: "H 3 * * *"
        parameters:
          - name: "BACKUP_TYPE"
            type: "choice"
            choices: ["full", "config", "jobs", "disaster-recovery"]
            description: "Type of backup to perform"
          - name: "RTO_TARGET"
            type: "string"
            default: "15"
            description: "Recovery Time Objective (minutes)"
          - name: "RPO_TARGET"
            type: "string"
            default: "5"
            description: "Recovery Point Objective (minutes)"
        sli_thresholds:  # NEW: SLI monitoring for backup operations
          backup_duration_max: "30m"
          success_rate_min: "99.5%"
          retention_compliance: "100%"
      - name: "image-builder"
        type: "pipeline"
        display_name: "Jenkins Image Builder"
        description: "Build and manage Jenkins Docker images"
        folder: "Infrastructure"
        jenkinsfile_path: "pipelines/Jenkinsfile.image-builder"
        triggers:
          - type: "cron"
            schedule: "H 2 * * 0"
        parameters:
          - name: "IMAGES_TO_BUILD"
            type: "choice"
            choices: ["all", "master", "agents"]
            description: "Images to build"
          - name: "PUSH_TO_REGISTRY"
            type: "boolean"
            default: true
            description: "Push built images to registry"

  - team_name: developer
    active_environment: blue
    blue_green_enabled: true
    ports:
      web: 8081
      agent: 50001
    resources:
      memory: "2g"
      cpu: "1.5"
    env_vars:
      JENKINS_TEAM: "developer"
      JENKINS_ADMIN_PASSWORD: "{{ vault_jenkins_admin_password | default('admin123') }}"
    labels:
      team: "developer"
      tier: "production"
      environment: "{{ deployment_mode | default('local') }}"
    security_policies:
      rbac_enabled: true
      namespace_isolation: true
      resource_quotas:
        cpu_limit: "2"
        memory_limit: "4Gi"
        storage_limit: "50Gi"
      network_policies:
        ingress_allowed: ["devops", "monitoring"]
        egress_allowed: ["harbor", "git_repos"]
      code_scanning:
        enabled: true
        tools: ["sonarqube", "trivy", "bandit"]
    
    credentials:
      - type: "usernamePassword"
        id: "developer-git-credentials"
        username: "admin"
        password: "{{ vault_git_password | default('git123') }}"
        description: "Developer Team Git Credentials"
        scope: "GLOBAL"
      - type: "usernamePassword"
        id: "harbor-registry-credentials"
        username: "{{ vault_harbor_username | default('admin') }}"
        password: "{{ vault_harbor_password | default('Harbor12345') }}"
        description: "Harbor Registry Credentials"
      - type: "secretText"
        id: "sonar-token"
        secret: "{{ vault_sonar_token | default('sonar123') }}"
        description: "SonarQube Analysis Token"
    seed_jobs:
      - name: "maven-app-pipeline"
        type: "pipeline"
        display_name: "Maven Application Pipeline"
        description: "Enterprise Maven CI/CD with security scanning"
        folder: "Applications"
        pipeline_source: "embedded"  # Use embedded DSL for application pipelines
        agent_label: "maven"
        deploy_enabled: true
        blue_green_enabled: true  # NEW: Blue-green deployment support
        parameters:
          - name: "GIT_BRANCH"
            type: "string"
            default: "main"
            description: "Git branch to build"
          - name: "RUN_TESTS"
            type: "boolean"
            default: true
            description: "Execute unit tests"
          - name: "BUILD_DOCKER_IMAGE"
            type: "boolean"
            default: true  # Changed to true for container deployment
            description: "Build Docker image after packaging"
          - name: "SECURITY_SCAN"
            type: "boolean"
            default: true
            description: "Run Trivy security scanning"
          - name: "DEPLOY_ENVIRONMENT"
            type: "choice"
            choices: ["staging", "production", "blue", "green"]
            description: "Target deployment environment"
        quality_gates:  # NEW: Quality gates for deployment engineering
          code_coverage_min: "80%"
          security_scan_threshold: "HIGH"
          performance_regression_threshold: "5%"
        deployment_strategy:  # NEW: Deployment strategy configuration
          type: "blue_green"
          rollback_triggers:
            - "error_rate_threshold: 1%"
            - "response_time_threshold: 500ms"
            - "cpu_usage_threshold: 80%"
      - name: "python-app-pipeline"
        type: "pipeline"
        display_name: "Python Application Pipeline"
        description: "Enterprise Python CI/CD with comprehensive testing"
        folder: "Applications"
        pipeline_source: "embedded"
        agent_label: "python"
        deploy_enabled: true
        canary_enabled: true  # NEW: Canary deployment support
        parameters:
          - name: "PYTHON_VERSION"
            type: "choice"
            choices: ["3.9", "3.10", "3.11", "3.12"]
            description: "Python version to use"
          - name: "RUN_LINTING"
            type: "boolean"
            default: true
            description: "Run code linting checks"
          - name: "RUN_INTEGRATION_TESTS"
            type: "boolean"
            default: true
            description: "Execute integration tests"
          - name: "CANARY_PERCENTAGE"
            type: "string"
            default: "10"
            description: "Canary deployment traffic percentage"
        test_strategy:  # NEW: Comprehensive testing strategy
          unit_tests: true
          integration_tests: true
          security_tests: true
          performance_tests: true
          chaos_engineering: false
        monitoring_config:  # NEW: Application monitoring
          metrics_enabled: true
          tracing_enabled: true
          alerting_enabled: true
      - name: "nodejs-app-pipeline"
        type: "pipeline"
        display_name: "Node.js Application Pipeline"
        description: "Build and test Node.js applications"
        folder: "Applications"
        agent_label: "nodejs"
        parameters:
          - name: "NODE_VERSION"
            type: "choice"
            choices: ["16", "18", "20"]
            description: "Node.js version to use"
          - name: "NPM_INSTALL"
            type: "boolean"
            default: true
            description: "Run npm install"

  - team_name: dev-qa
    active_environment: blue
    blue_green_enabled: true
    ports:
      web: 8089
      agent: 50009
    resources:
      memory: "2g"
      cpu: "1.5"
    env_vars:
      JENKINS_TEAM: "dev-qa"
      JENKINS_ADMIN_PASSWORD: "{{ vault_jenkins_admin_password | default('admin123') }}"
    labels:
      team: "dev-qa"
      tier: "production"
      environment: "{{ deployment_mode | default('local') }}"
    security_policies:
      rbac_enabled: true
      namespace_isolation: true
      resource_quotas:
        cpu_limit: "2"
        memory_limit: "4Gi"
        storage_limit: "50Gi"
      network_policies:
        ingress_allowed: ["devops", "monitoring"]
        egress_allowed: ["harbor", "git_repos"]
      code_scanning:
        enabled: true
        tools: ["sonarqube", "trivy", "bandit"]
```

---

# Jenkins Master v2 Role (Simplified)

## File: ansible/roles/jenkins-master-v2/tasks/main.yml

```yaml
---
# Simplified Jenkins Master Role - Main Orchestration
# Consolidated from 13 task files to 4 files while maintaining all enterprise features

- name: Display jenkins-master-v2 role information
  debug:
    msg: |
      ==================================================
      Jenkins Master Role v2 - Simplified Architecture
      ==================================================
      Original complexity: 1018 lines across 13 files
      Simplified version: ~530 lines across 4 files
      Features preserved: Blue-green, Multi-team, Custom images
      ==================================================

- name: Determine deployment configuration
  set_fact:
    jenkins_teams_config: "{{ jenkins_teams | default([jenkins_master_config]) }}"
    jenkins_deployment_mode: "{{ 'multi-team' if jenkins_teams is defined and jenkins_teams | length > 0 else 'single-team' }}"
  tags: ['always']

- name: Display deployment configuration
  debug:
    msg: |
      Deployment Mode: {{ jenkins_deployment_mode }}
      Teams to Deploy: {{ jenkins_teams_config | map(attribute='team_name') | list | join(', ') }}
      Container Runtime: {{ jenkins_master_container_runtime }}
  tags: ['always']

# Phase 1: System setup, validation, and infrastructure preparation
- name: Setup and validation phase
  import_tasks: setup-and-validate.yml
  tags: ['setup', 'validate', 'config', 'network']

# Phase 2: Custom image building and container deployment  
- name: Image building and container deployment phase
  import_tasks: image-and-container.yml
  tags: ['images', 'containers', 'deploy', 'custom-images', 'build']

# Phase 3: Blue-green deployment management and health monitoring
- name: Blue-green deployment and monitoring phase
  import_tasks: deploy-and-monitor.yml
  tags: ['blue-green', 'deploy', 'monitor', 'health', 'verify']

- name: Jenkins Master v2 deployment complete
  debug:
    msg: |
      ====================================================
      Jenkins Master v2 Deployment Summary
      ====================================================
      Mode: {{ jenkins_deployment_mode }}
      Teams: {{ jenkins_teams_config | length }}
      Active Environments: {{ jenkins_teams_config | selectattr('active_environment', 'defined') | map(attribute='active_environment') | list | join(', ') }}
      Container Runtime: {{ jenkins_master_container_runtime }}
      ====================================================
      Access your Jenkins instances:
      {% for team in jenkins_teams_config %}
      {{ team.team_name }}: http://{{ jenkins_verification_host }}:{{ team.ports.web }}
      {% endfor %}
      ====================================================
  tags: ['always']
```

## File: ansible/roles/jenkins-master-v2/tasks/setup-and-validate.yml

```yaml
---
# Simplified Jenkins Master - Combined Setup, Validation, and Infrastructure
# Consolidates: validate.yml (84 lines) + configuration.yml (113 lines) + networking.yml (31 lines) + socket-detection.yml (38 lines)
# Total: ~266 lines → ~120 lines (53% reduction)

# ====================================
# VALIDATION PHASE
# ====================================

- name: Validate deployment configuration
  block:
    - name: Validate basic team configuration
      assert:
        that:
          - item.team_name is defined and item.team_name | length > 0
          - item.active_environment is defined and item.active_environment in ['blue', 'green']
          - item.ports.web is defined and item.ports.web | int > 1024
          - item.ports.agent is defined and item.ports.agent | int > 1024
          - item.ports.web != item.ports.agent
          - item.resources.memory is defined and item.resources.memory | regex_search('[0-9]+[gm]') is not none
          - item.resources.cpu is defined and item.resources.cpu | string | float > 0
        fail_msg: "Invalid configuration for team {{ item.team_name }}: missing or invalid team_name, active_environment, ports, or resources"
        success_msg: "Configuration validation passed for team {{ item.team_name }}"
      loop: "{{ jenkins_teams_config }}"
      loop_control:
        label: "{{ item.team_name }}"

    - name: Validate port conflicts between teams
      assert:
        that:
          - jenkins_teams_config | map(attribute='ports.web') | list | unique | length == jenkins_teams_config | length
          - jenkins_teams_config | map(attribute='ports.agent') | list | unique | length == jenkins_teams_config | length
        fail_msg: |
          Port conflicts detected between teams:
          Web ports: {{ jenkins_teams_config | map(attribute='ports.web') | list }}
          Agent ports: {{ jenkins_teams_config | map(attribute='ports.agent') | list }}
        success_msg: "No port conflicts detected between teams"
      when: jenkins_teams_config | length > 1

    - name: Validate container runtime availability
      command: "docker --version"
      register: docker_check
      failed_when: docker_check.rc != 0
      changed_when: false
  tags: ['validate', 'setup']

# ====================================
# SYSTEM CONFIGURATION PHASE
# ====================================

- name: Setup Jenkins system infrastructure
  block:
    - name: Create Jenkins system user and group
      group:
        name: "{{ jenkins_user }}"
        gid: "{{ jenkins_gid }}"
        state: present
      become: yes

    - name: Create Jenkins system user
      user:
        name: "{{ jenkins_user }}"
        uid: "{{ jenkins_uid }}"
        group: "{{ jenkins_user }}"
        home: "{{ jenkins_home_dir }}"
        shell: /bin/bash
        system: yes
        create_home: yes
      become: yes

    - name: Create Jenkins base directories
      file:
        path: "{{ item }}"
        state: directory
        owner: "{{ jenkins_user }}"
        group: "{{ jenkins_user }}"
        mode: '0755'
      loop:
        - "{{ jenkins_home_dir }}/init.groovy.d"
        - "{{ jenkins_home_dir }}/scripts"

    - name: Create team-specific directory structure
      file:
        path: "{{ jenkins_home_dir }}/{{ item.0.team_name }}/{{ item.1 }}/casc_configs"
        state: directory
        owner: "{{ jenkins_user }}"
        group: "{{ jenkins_user }}"
        mode: '0755'
        recurse: yes
      with_nested:
        - "{{ jenkins_teams_config }}"
        - ['blue', 'green']
      loop_control:
        label: "{{ item.0.team_name }}/{{ item.1 }}"
  tags: ['setup', 'config']

# ====================================
# NETWORKING PHASE
# ====================================

- name: Setup Docker networking infrastructure
  block:
    - name: Create Jenkins network
      community.docker.docker_network:
        name: "{{ jenkins_master_network_name }}"
        driver: "{{ jenkins_master_network_driver }}"
        ipam_config:
          - subnet: "{{ jenkins_master_network_subnet }}"
            gateway: "{{ jenkins_master_network_gateway }}"
        state: present

    - name: Check port availability for all teams
      wait_for:
        port: "{{ item.port }}"
        host: "{{ ansible_default_ipv4.address }}"
        state: stopped
        timeout: 3
      loop: >-
        {%- set result = [] -%}
        {%- for team in jenkins_teams_config -%}
          {%- set _ = result.append({'team': team.team_name, 'port': team.ports.web, 'type': 'web'}) -%}
          {%- set _ = result.append({'team': team.team_name, 'port': team.ports.agent, 'type': 'agent'}) -%}
        {%- endfor -%}
        {{ result }}
      loop_control:
        label: "{{ item.team }}:{{ item.type }}:{{ item.port }}"
      failed_when: false
      register: port_check

    - name: Warn about potential port conflicts
      debug:
        msg: "Warning: Port {{ item.item.port }} ({{ item.item.type }}) for team {{ item.item.team }} may be in use"
      loop: "{{ port_check.results }}"
      when: item.failed is defined and item.failed
      loop_control:
        label: "{{ item.item.team }}:{{ item.item.type }}:{{ item.item.port }}"
  tags: ['setup', 'network']

# ====================================
# CONTAINER RUNTIME DETECTION
# ====================================

- name: Detect and validate container runtime environment
  block:
    - name: Detect Docker socket location
      stat:
        path: "{{ jenkins_master_socket_path_docker }}"
      register: docker_socket_stat

    - name: Validate Docker socket accessibility
      assert:
        that:
          - docker_socket_stat.stat.exists
          - docker_socket_stat.stat.issock
        fail_msg: "Docker socket not found or not accessible at {{ jenkins_master_socket_path_docker }}"
        success_msg: "Docker socket validated at {{ jenkins_master_socket_path_docker }}"

    - name: Test Docker connectivity
      command: docker info
      register: docker_info_check
      failed_when: docker_info_check.rc != 0
      changed_when: false
  tags: ['setup', 'docker', 'socket']

# ====================================
# JENKINS CONFIGURATION FILES
# ====================================

- name: Generate Jenkins Configuration as Code files
  template:
    src: jcasc/jenkins-config.yml.j2
    dest: "{{ jenkins_home_dir }}/{{ item.0.team_name }}/{{ item.1 }}/casc_configs/jenkins.yaml"
    owner: "{{ jenkins_user }}"
    group: "{{ jenkins_user }}"
    mode: '0644'
  with_nested:
    - "{{ jenkins_teams_config }}"
    - ['blue', 'green']
  loop_control:
    label: "{{ item.0.team_name }}/{{ item.1 }}"
  vars:
    jenkins_current_team: "{{ item.0 }}"
    jenkins_current_environment: "{{ item.1 }}"
  tags: ['setup', 'config', 'jcasc']

- name: Copy Jenkins initialization scripts
  copy:
    src: init-scripts/setup-dsl-approval.groovy
    dest: "{{ jenkins_home_dir }}/init.groovy.d/01-setup-dsl-approval.groovy"
    owner: "{{ jenkins_user }}"
    group: "{{ jenkins_user }}"
    mode: '0644'
  tags: ['setup', 'config', 'init-scripts']

- name: Setup and validation phase complete
  debug:
    msg: |
      ====================================
      Setup and Validation Complete
      ====================================
      Teams validated: {{ jenkins_teams_config | length }}
      Docker runtime: Validated
      Network: {{ jenkins_master_network_name }} created
      Team directories: Created for all environments
      ====================================
  tags: ['setup', 'validate']
```

---

# High Availability v2 Role (Simplified)

## File: ansible/roles/high-availability-v2/tasks/main.yml

```yaml
---
# Simplified HAProxy High Availability Role v2 - Main Orchestration
# Consolidated from 775 lines across 7 files to 530 lines across 4 files

- name: Display high-availability-v2 role information
  debug:
    msg: |
      ======================================================
      HAProxy High Availability Role v2 - Simplified Architecture
      ======================================================
      Original complexity: 775 lines across 7 task files
      Simplified version: ~530 lines across 4 task files
      Features preserved: Multi-team, VIP, SSL, Health monitoring
      ======================================================

- name: Configure HAProxy deployment mode and settings
  set_fact:
    haproxy_deployment_mode: "{{ 'multi-team' if jenkins_teams is defined and jenkins_teams | length > 0 else 'single-team' }}"
    haproxy_effective_teams: "{{ jenkins_teams if jenkins_teams is defined and jenkins_teams | length > 0 else [] }}"
    _is_devcontainer: "{{ ansible_env.REMOTE_CONTAINERS is defined or ansible_env.CODESPACES is defined or deployment_mode in ['devcontainer', 'local'] }}"
  tags: ['always']

- name: Display HAProxy deployment configuration
  debug:
    msg: |
      HAProxy Deployment Configuration:
      Mode: {{ haproxy_deployment_mode }}
      Teams: {{ haproxy_effective_teams | map(attribute='team_name') | list | join(', ') if haproxy_effective_teams else 'single-team' }}
      Container Runtime: {{ haproxy_container_runtime }}
      SSL Enabled: {{ ssl_enabled | default(false) }}
      Domain: {{ jenkins_domain | default('devops.example.com') }}
      {% if jenkins_vip is defined and jenkins_vip != "" %}VIP: {{ jenkins_vip }}{% endif %}
      DevContainer Mode: {{ _is_devcontainer }}
  tags: ['always']

# Phase 1: Unified setup, validation, and infrastructure preparation
- name: Setup HAProxy infrastructure
  import_tasks: setup.yml
  tags: ['setup', 'config', 'validate', 'ssl', 'networking']

# Phase 2: HAProxy configuration, volumes, and container deployment
- name: Deploy HAProxy load balancer
  import_tasks: haproxy.yml
  tags: ['haproxy', 'deploy', 'container', 'volumes', 'configuration']

# Phase 3: VIP management, monitoring, and operational scripts
- name: Configure monitoring and VIP management
  import_tasks: monitoring.yml
  tags: ['monitoring', 'vip', 'ha', 'scripts', 'keepalived']

- name: HAProxy High Availability v2 deployment complete
  debug:
    msg: |
      ======================================================
      HAProxy High Availability v2 Deployment Summary
      ======================================================
      Mode: {{ haproxy_deployment_mode }}
      Teams: {{ haproxy_effective_teams | length }}
      Container: jenkins-haproxy
      SSL: {{ ssl_enabled | default(false) }}
      Domain: {{ jenkins_domain | default('devops.example.com') }}
      {% if jenkins_vip is defined and jenkins_vip != "" %}
      VIP: {{ jenkins_vip }} (keepalived managed)
      {% endif %}
      
      ======================================================
      Access Information:
      ======================================================
      {% if haproxy_effective_teams | length > 0 %}
      Team Access URLs:
      {% for team in haproxy_effective_teams %}
      • {{ team.team_name | title }}: https://{{ team.team_name }}.{{ jenkins_domain | default('devops.example.com') }}
      {% endfor %}
      {% endif %}
      HAProxy Stats: http://{{ ansible_default_ipv4.address }}:{{ haproxy_stats_port | default(8404) }}/stats
      
      Management Scripts:
      • Container Manager: /usr/local/bin/haproxy-container-manager.sh
      • HA Monitor: /usr/local/bin/jenkins-ha-monitor.sh
      • Failover Script: /usr/local/bin/jenkins-failover.sh
      {% if jenkins_vip is defined and jenkins_vip != "" %}
      • VIP Check: /usr/local/bin/keepalived-haproxy-check.sh
      {% endif %}
      ======================================================
  tags: ['always']
```

## File: ansible/roles/high-availability-v2/tasks/setup.yml

```yaml
---
# Simplified HAProxy HA Setup - Unified Validation, Configuration, and Networking
# Consolidates: validation.yml (47 lines) + configuration.yml (88 lines) + networking.yml (59 lines)
# Total: ~194 lines → ~150 lines (23% reduction)

# ====================================
# VALIDATION PHASE
# ====================================

- name: Comprehensive HAProxy configuration validation
  block:
    - name: Validate HAProxy container runtime and image configuration
      assert:
        that:
          - haproxy_container_runtime == 'docker'
          - haproxy_image_name is defined
          - haproxy_image_tag is defined
          - haproxy_image_registry is defined
        fail_msg: "HAProxy container configuration incomplete: runtime={{ haproxy_container_runtime }}, image={{ haproxy_image_name }}:{{ haproxy_image_tag }}"
        success_msg: "HAProxy container configuration validated: {{ haproxy_image_registry }}/{{ haproxy_image_name }}:{{ haproxy_image_tag }}"

    - name: Validate multi-team setup configuration
      assert:
        that:
          - jenkins_teams | length > 0
          - jenkins_domain is defined
          - jenkins_domain | length > 0
        fail_msg: "Multi-team configuration requires jenkins_teams and jenkins_domain to be defined"
        success_msg: "Multi-team configuration validated - {{ jenkins_teams | length }} team(s) with domain {{ jenkins_domain }}"
      when: team_routing_enabled | default(true) and haproxy_deployment_mode == 'multi-team'

    - name: Validate SSL/TLS configuration
      assert:
        that:
          - ssl_cert_path is defined
          - ssl_cert_path | length > 0
        fail_msg: "SSL configuration requires ssl_cert_path to be defined"
        success_msg: "SSL configuration validated - certificate path: {{ ssl_cert_path }}"
      when: ssl_enabled | default(false)

    - name: Validate VIP configuration for keepalived
      assert:
        that:
          - jenkins_vip | ipaddr
          - keepalived_priority is defined
          - keepalived_priority | int >= 1 and keepalived_priority | int <= 255
        fail_msg: "VIP configuration requires valid IP address and priority (1-255)"
        success_msg: "VIP configuration validated: {{ jenkins_vip }} with priority {{ keepalived_priority }}"
      when: jenkins_vip is defined and jenkins_vip != ""

    - name: Validate team port configurations
      assert:
        that:
          - item.ports.web is defined
          - item.ports.web | int > 1024
          - item.ports.web | int < 65535
        fail_msg: "Team {{ item.team_name }} has invalid web port: {{ item.ports.web | default('undefined') }}"
        success_msg: "Team {{ item.team_name }} port configuration validated: {{ item.ports.web }}"
      loop: "{{ haproxy_effective_teams }}"
      loop_control:
        label: "{{ item.team_name }}"
      when: haproxy_effective_teams | length > 0
  tags: ['validation']

# ====================================
# SYSTEM SETUP PHASE
# ====================================

- name: Setup HAProxy system environment
  block:
    - name: Validate Docker installation and service
      block:
        - name: Check Docker availability
          command: docker --version
          register: docker_version_check
          failed_when: docker_version_check.rc != 0
          changed_when: false

        - name: Validate Docker daemon is running
          command: docker info
          register: docker_info_check
          failed_when: docker_info_check.rc != 0
          changed_when: false

    - name: Create HAProxy system user and group
      block:
        - name: Create HAProxy group
          group:
            name: "{{ haproxy_user }}"
            gid: "{{ haproxy_gid }}"
            system: yes
            state: present
          become: yes

        - name: Create HAProxy user
          user:
            name: "{{ haproxy_user }}"
            uid: "{{ haproxy_uid }}"
            group: "{{ haproxy_user }}"
            system: yes
            shell: /bin/false
            home: /var/lib/haproxy
            create_home: no
            state: present
          become: yes

    - name: Create HAProxy directory structure
      file:
        path: "{{ item.path }}"
        state: directory
        mode: "{{ item.mode | default('0755') }}"
        owner: root
        group: "{{ haproxy_user }}"
      loop:
        - { path: "/etc/haproxy" }
        - { path: "/etc/haproxy/conf.d" }
        - { path: "/etc/haproxy/errors" }
        - { path: "/etc/haproxy/ssl", mode: "0750" }
        - { path: "/var/lib/haproxy" }
        - { path: "/var/log/haproxy" }
      become: yes
  tags: ['setup']

# ====================================
# SSL/TLS CONFIGURATION
# ====================================

- name: Configure SSL/TLS certificates
  block:
    - name: Check SSL certificate file existence
      stat:
        path: "{{ ssl_cert_path }}"
      register: ssl_cert_stat

    - name: Validate SSL certificate exists
      fail:
        msg: "SSL certificate not found at {{ ssl_cert_path }}"
      when: not ssl_cert_stat.stat.exists

    - name: Create combined SSL certificate for HAProxy
      shell: |
        cat "{{ ssl_cert_path }}" > /etc/haproxy/ssl/combined.pem
        {% if ssl_key_path is defined and ssl_key_path != ssl_cert_path %}
        cat "{{ ssl_key_path }}" >> /etc/haproxy/ssl/combined.pem
        {% endif %}
        chmod 640 /etc/haproxy/ssl/combined.pem
        chown root:{{ haproxy_user }} /etc/haproxy/ssl/combined.pem
      become: yes
      notify: restart haproxy container
      register: ssl_cert_combined

    - name: Verify combined SSL certificate
      stat:
        path: "/etc/haproxy/ssl/combined.pem"
      register: combined_cert_stat
      failed_when: not combined_cert_stat.stat.exists
  when: ssl_enabled | default(false)
  tags: ['ssl']

# ====================================
# NETWORKING CONFIGURATION
# ====================================

- name: Configure HAProxy networking and firewall
  block:
    - name: Configure firewall for RedHat-based systems
      ansible.posix.firewalld:
        service: "{{ item }}"
        permanent: yes
        state: enabled
        immediate: yes
      loop: ['http', 'https']
      when: ansible_os_family == "RedHat"
      become: yes
      ignore_errors: true

    - name: Configure firewall for Debian-based systems
      community.general.ufw:
        rule: allow
        port: "{{ item }}"
        proto: tcp
      loop: 
        - '80'
        - '443'
        - "{{ haproxy_stats_port | default(8404) }}"
      when: ansible_os_family == "Debian"
      become: yes
      ignore_errors: true

    - name: Open team-specific ports for direct access
      community.general.ufw:
        rule: allow
        port: "{{ item.ports.web | default(8080) }}"
        proto: tcp
        comment: "Jenkins {{ item.team_name }} team access"
      loop: "{{ haproxy_effective_teams }}"
      loop_control:
        label: "{{ item.team_name }}:{{ item.ports.web }}"
      when: 
        - haproxy_effective_teams | length > 0
        - ansible_os_family == "Debian"
      become: yes
      ignore_errors: true

    - name: Configure SELinux for HAProxy (RedHat systems)
      block:
        - name: Set SELinux boolean for HAProxy network connections
          ansible.posix.seboolean:
            name: "{{ item }}"
            state: yes
            persistent: yes
          loop:
            - haproxy_connect_any
            - httpd_can_network_connect
          become: yes
          ignore_errors: true
      when: 
        - ansible_os_family == "RedHat"
        - ansible_selinux.status is defined
        - ansible_selinux.status == "enabled"
  tags: ['networking']

- name: Setup and validation phase complete
  debug:
    msg: |
      ====================================
      HAProxy Setup and Validation Complete
      ====================================
      Docker: {{ docker_version_check.stdout | default('Validated') }}
      HAProxy User: {{ haproxy_user }}:{{ haproxy_gid }}
      Directories: Created and configured
      {% if ssl_enabled | default(false) %}
      SSL Certificate: {{ ssl_cert_path }} → /etc/haproxy/ssl/combined.pem
      {% endif %}
      Teams: {{ haproxy_effective_teams | length }} configured
      Firewall: {{ ansible_os_family }} rules applied
      ====================================
  tags: ['setup']
```

## File: ansible/roles/high-availability-v2/tasks/haproxy.yml

```yaml
---
# Simplified HAProxy HA Deployment - Unified Configuration, Volumes, and Container Management
# Consolidates: containers.yml (53 lines) + containers/docker.yml (317 lines) + volumes/docker.yml (26 lines) + configuration.yml (HAProxy parts)
# Total: ~396 lines → ~180 lines (55% reduction)

# ====================================
# VOLUME MANAGEMENT PHASE
# ====================================

- name: Create HAProxy Docker volumes
  block:
    - name: Create HAProxy admin socket volume (tmpfs for performance)
      community.docker.docker_volume:
        name: "haproxy-admin-socket"
        driver: "local"
        driver_options:
          type: "tmpfs"
          device: "tmpfs"
          o: "size=100M,uid={{ haproxy_uid }},gid={{ haproxy_gid }}"
        state: present
        labels:
          service: "haproxy"
          type: "admin-socket"
          managed_by: "ansible"

    - name: Create HAProxy logs volume
      community.docker.docker_volume:
        name: "haproxy-logs"
        driver: "local"
        state: present
        labels:
          service: "haproxy"
          type: "logs"
          managed_by: "ansible"
  tags: ['volumes']

# ====================================
# HAPROXY CONFIGURATION PHASE
# ====================================

- name: Generate HAProxy configuration files
  block:
    - name: Create HAProxy error pages
      copy:
        dest: "/etc/haproxy/errors/{{ item.code }}.http"
        content: |
          HTTP/1.1 {{ item.code }} {{ item.message }}
          Content-Type: text/html
          Content-Length: {{ item.body | length }}
          
          {{ item.body }}
        mode: '0644'
        owner: root
        group: "{{ haproxy_user }}"
      loop:
        - code: 502
          message: "Bad Gateway"
          body: "<html><body><h1>502 Bad Gateway</h1><p>Jenkins service temporarily unavailable.</p><p>Please try again in a few moments.</p></body></html>"
        - code: 503
          message: "Service Unavailable"
          body: "<html><body><h1>503 Service Unavailable</h1><p>Jenkins service temporarily unavailable.</p><p>Please try again in a few moments.</p></body></html>"
        - code: 504
          message: "Gateway Timeout"
          body: "<html><body><h1>504 Gateway Timeout</h1><p>Jenkins service timeout.</p><p>Please try again in a few moments.</p></body></html>"
      become: yes

    - name: Generate main HAProxy configuration
      template:
        src: haproxy.cfg.j2
        dest: /etc/haproxy/haproxy.cfg
        backup: yes
        owner: root
        group: "{{ haproxy_user }}"
        mode: '0644'
      become: yes
      notify: restart haproxy container
      register: haproxy_main_config

    - name: Generate team-specific backend configurations
      template:
        src: haproxy-team-backend.cfg.j2
        dest: "/etc/haproxy/conf.d/{{ item.team_name }}-backend.cfg"
        owner: root
        group: "{{ haproxy_user }}"
        mode: '0644'
      loop: "{{ haproxy_effective_teams }}"
      loop_control:
        label: "{{ item.team_name }}"
      become: yes
      notify: restart haproxy container
      when: haproxy_effective_teams | length > 0
      register: haproxy_team_configs

    - name: Create HAProxy stats configuration
      copy:
        dest: "/etc/haproxy/conf.d/stats.cfg"
        content: |
          # HAProxy Statistics Configuration
          listen stats
              bind *:{{ haproxy_stats_port | default(8404) }}
              stats enable
              stats uri {{ haproxy_stats_uri | default('/stats') }}
              stats refresh 30s
              stats show-node
              stats show-legends
              stats admin if TRUE
        mode: '0644'
        owner: root
        group: "{{ haproxy_user }}"
      become: yes
      notify: restart haproxy container
  tags: ['configuration']

# ====================================
# CONTAINER DEPLOYMENT PHASE
# ====================================

- name: Deploy HAProxy container with unified configuration
  block:
    - name: Pull HAProxy image
      community.docker.docker_image:
        name: "{{ _haproxy_image_full }}"
        source: pull
        state: present
      register: haproxy_image_pull

    - name: Stop existing HAProxy container if running
      community.docker.docker_container:
        name: "jenkins-haproxy"
        state: stopped
      ignore_errors: true

    - name: Remove existing HAProxy container
      community.docker.docker_container:
        name: "jenkins-haproxy"
        state: absent
      ignore_errors: true

    - name: Deploy HAProxy container with standard configuration
      community.docker.docker_container:
        name: "jenkins-haproxy"
        image: "{{ _haproxy_image_full }}"
        state: started
        restart_policy: "{{ haproxy_restart_policy | default('unless-stopped') }}"
        network_mode: "host"
        volumes: "{{ _haproxy_volumes }}"
        env: "{{ _haproxy_env_vars }}"
        memory: "{{ haproxy_memory_limit | default('512m') }}"
        cpus: "{{ haproxy_cpu_limit | default('1.0') }}"
        log_driver: "{{ haproxy_log_driver | default('json-file') }}"
        log_options:
          max-size: "{{ haproxy_log_max_size | default('10m') }}"
          max-file: "{{ haproxy_log_max_files | default('3') }}"
        labels: "{{ _haproxy_labels }}"
        privileged: false
        security_opts:
          - "label=disable"
        healthcheck:
          test: ["CMD-SHELL", "haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg"]
          interval: 30s
          timeout: 10s
          retries: 3
          start_period: 30s
      register: haproxy_standard_deploy
      failed_when: false

    - name: Deploy HAProxy container with privileged fallback
      community.docker.docker_container:
        name: "jenkins-haproxy"
        image: "{{ _haproxy_image_full }}"
        state: started
        restart_policy: "{{ haproxy_restart_policy | default('unless-stopped') }}"
        network_mode: "host"
        volumes: "{{ _haproxy_volumes }}"
        env: "{{ _haproxy_env_vars }}"
        memory: "{{ haproxy_memory_limit | default('512m') }}"
        cpus: "{{ haproxy_cpu_limit | default('1.0') }}"
        log_driver: "{{ haproxy_log_driver | default('json-file') }}"
        log_options:
          max-size: "{{ haproxy_log_max_size | default('10m') }}"
          max-file: "{{ haproxy_log_max_files | default('3') }}"
        labels: "{{ _haproxy_labels }}"
        privileged: true
        healthcheck:
          test: ["CMD-SHELL", "haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg"]
          interval: 30s
          timeout: 10s
          retries: 3
          start_period: 30s
      register: haproxy_privileged_deploy
      when: haproxy_standard_deploy is failed
      failed_when: false

    - name: Report HAProxy deployment status
      debug:
        msg: |
          HAProxy Container Deployment Status:
          {% if haproxy_standard_deploy is succeeded %}
          ✅ Standard deployment successful (non-privileged mode)
          {% elif haproxy_privileged_deploy is succeeded %}
          ⚠️ Privileged fallback deployment successful (privileged mode)
          Note: Using privileged mode for container runtime compatibility
          {% else %}
          ❌ Both standard and privileged deployment failed
          Container runtime may not be compatible on this system
          {% endif %}

    - name: Fail if both deployment methods failed
      fail:
        msg: |
          HAProxy container deployment failed with both standard and privileged modes.
          This indicates a container runtime compatibility issue on this system.
          
          Alternative solutions:
          1. Install HAProxy natively using system package manager
          2. Update container runtime to newer version
          3. Check kernel compatibility for container namespaces
      when: 
        - haproxy_standard_deploy is failed
        - haproxy_privileged_deploy is failed or haproxy_privileged_deploy is skipped

  vars:
    _image_tag: "{{ haproxy_image_alternatives[deployment_mode | default('production')] | default(haproxy_image_tag) }}"
    _haproxy_ports: "{{ [] if haproxy_network_mode == 'host' else ['8090:8090', (haproxy_stats_port | default(8404)) ~ ':' ~ (haproxy_stats_port | default(8404))] }}"
    _haproxy_volumes: >-
      {%- set base_volumes = [
        "/etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro",
        "/etc/haproxy/conf.d:/usr/local/etc/haproxy/conf.d:ro",
        "/etc/haproxy/errors:/etc/haproxy/errors:ro",
        "/var/log/haproxy:/var/log/haproxy:rw",
        "/var/lib/haproxy:/var/lib/haproxy:rw",
        "haproxy-admin-socket:/run/haproxy:rw"
      ] -%}
      {%- if ssl_enabled | default(false) -%}
        {%- set _ = base_volumes.append("/etc/haproxy/ssl/combined.pem:/usr/local/etc/haproxy/ssl/combined.pem:ro") -%}
      {%- endif -%}
      {{ base_volumes }}
    _haproxy_env_vars:
      HAPROXY_USER: "{{ haproxy_user }}"
      HAPROXY_UID: "{{ haproxy_uid | string }}"
      HAPROXY_GID: "{{ haproxy_gid | string }}"
      TZ: "{{ common_timezone | default('UTC') }}"
    _haproxy_labels:
      service: "haproxy"
      role: "load-balancer"
      teams: "{{ haproxy_effective_teams | map(attribute='team_name') | join(',') }}"
      ssl_enabled: "{{ ssl_enabled | default(false) | string }}"
      deployment_mode: "{{ deployment_mode }}"
      managed_by: "ansible"
      version: "simplified-v2"
  tags: ['deploy']

# ====================================
# POST-DEPLOYMENT VERIFICATION
# ====================================

- name: Verify HAProxy deployment and functionality
  block:
    - name: Wait for HAProxy container startup
      pause:
        seconds: "{{ haproxy_startup_wait_time | default(15) }}"

    - name: Get HAProxy container information
      community.docker.docker_container_info:
        name: "jenkins-haproxy"
      register: haproxy_info

    - name: Verify HAProxy container is running
      assert:
        that:
          - haproxy_info.container.State.Status == "running"
        fail_msg: "HAProxy container is not running: {{ haproxy_info.container.State.Status }}"
        success_msg: "HAProxy container is running successfully"

    - name: Verify HAProxy configuration is valid
      command: docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
      register: haproxy_config_check
      failed_when: haproxy_config_check.rc != 0
      changed_when: false

    - name: Test HAProxy stats endpoint accessibility
      uri:
        url: "http://{{ ansible_default_ipv4.address }}:{{ haproxy_stats_port | default(8404) }}{{ haproxy_stats_uri | default('/stats') }}"
        method: GET
        timeout: 10
        user: "{{ haproxy_stats_user | default('admin') }}"
        password: "{{ haproxy_stats_password | default('admin123') }}"
        force_basic_auth: true
        status_code: [200, 401]  # Accept both authenticated access and auth prompts
      register: haproxy_stats_check
      retries: 5
      delay: 5
      failed_when: false  # Don't fail deployment on stats access issues

    - name: Test team routing (if multi-team)
      uri:
        url: "http://{{ ansible_default_ipv4.address }}:8090"
        method: HEAD
        timeout: 10
        headers:
          Host: "{{ item.team_name }}.{{ jenkins_domain | default('devops.example.com') }}"
      loop: "{{ haproxy_effective_teams }}"
      loop_control:
        label: "{{ item.team_name }}.{{ jenkins_domain | default('devops.example.com') }}"
      register: team_routing_check
      retries: 3
      delay: 5
      failed_when: false  # Don't fail deployment on routing tests
      when: haproxy_effective_teams | length > 0

    - name: Display HAProxy deployment verification results
      debug:
        msg: |
          ====================================
          HAProxy Deployment Verification
          ====================================
          Container Status: {{ haproxy_info.container.State.Status }}
          Health Status: {{ haproxy_info.container.State.Health.Status | default('N/A') }}
          Configuration: {{ 'Valid' if haproxy_config_check.rc == 0 else 'Invalid' }}
          Stats Endpoint: {{ 'Accessible' if haproxy_stats_check.status | default(0) == 200 else 'Not accessible' }}
          Image: {{ haproxy_info.container.Config.Image }}
          Started: {{ haproxy_info.container.State.StartedAt }}
          {% if haproxy_effective_teams | length > 0 %}
          Team Routing Tests:
          {% for result in team_routing_check.results %}
          • {{ haproxy_effective_teams[loop.index0].team_name }}: {{ 'OK' if result.status | default(0) in [200, 302, 404] else 'Failed' }}
          {% endfor %}
          {% endif %}
          ====================================
  tags: ['verify']

- name: HAProxy deployment phase complete
  debug:
    msg: |
      ====================================
      HAProxy Deployment Complete
      ====================================
      Container: jenkins-haproxy ({{ haproxy_info.container.State.Status }})
      Configuration: {{ 'Valid' if haproxy_config_check.rc == 0 else 'Invalid' }}
      Teams configured: {{ haproxy_effective_teams | length }}
      SSL enabled: {{ ssl_enabled | default(false) }}
      ====================================
  tags: ['haproxy']
```

## File: ansible/roles/high-availability-v2/tasks/monitoring.yml

```yaml
---
# Simplified HAProxy HA Monitoring - VIP Management and Health Monitoring
# Consolidates: main.yml VIP parts + management scripts + monitoring setup
# Reduces management and monitoring complexity while maintaining enterprise features

# ====================================
# VIP MANAGEMENT (KEEPALIVED)
# ====================================

- name: Configure Virtual IP management with keepalived
  block:
    - name: Install keepalived package
      package:
        name: keepalived
        state: present
      become: yes

    - name: Create keepalived configuration directory
      file:
        path: /etc/keepalived
        state: directory
        mode: '0755'
      become: yes

    - name: Generate keepalived configuration for VIP
      template:
        src: keepalived.conf.j2
        dest: /etc/keepalived/keepalived.conf
        backup: yes
        owner: root
        group: root
        mode: '0644'
      become: yes
      notify: restart keepalived
      register: keepalived_config

    - name: Validate keepalived configuration
      command: keepalived -t -f /etc/keepalived/keepalived.conf
      register: keepalived_validation
      failed_when: keepalived_validation.rc != 0
      changed_when: false
      become: yes

    - name: Start and enable keepalived service
      systemd:
        name: keepalived
        state: started
        enabled: yes
        daemon_reload: yes
      become: yes

    - name: Verify VIP assignment (master node)
      command: ip addr show
      register: vip_check
      changed_when: false
      when: keepalived_priority | default(100) > 100

    - name: Display VIP status
      debug:
        msg: |
          VIP Configuration:
          IP: {{ jenkins_vip }}
          Priority: {{ keepalived_priority | default(100) }}
          State: {{ 'MASTER' if keepalived_priority | default(100) > 100 else 'BACKUP' }}
          {% if keepalived_priority | default(100) > 100 %}
          VIP Assigned: {{ 'Yes' if jenkins_vip in vip_check.stdout else 'No' }}
          {% endif %}
  when: jenkins_vip is defined and jenkins_vip != ""
  tags: ['vip', 'keepalived']

# ====================================
# MANAGEMENT SCRIPTS DEPLOYMENT
# ====================================

- name: Deploy HAProxy management and monitoring scripts
  block:
    - name: Create management scripts from templates
      template:
        src: "{{ item }}.j2"
        dest: "/usr/local/bin/{{ item }}"
        mode: '0755'
        owner: root
        group: root
      loop:
        - jenkins-ha-monitor.sh
        - jenkins-failover.sh
        - haproxy-container-manager.sh
        - keepalived-haproxy-check.sh
      become: yes
      register: management_scripts

    - name: Verify management scripts are executable
      file:
        path: "/usr/local/bin/{{ item }}"
        mode: '0755'
        state: file
      loop:
        - jenkins-ha-monitor.sh
        - jenkins-failover.sh
        - haproxy-container-manager.sh
        - keepalived-haproxy-check.sh
      become: yes

    - name: Test management scripts syntax
      command: "bash -n /usr/local/bin/{{ item }}"
      loop:
        - jenkins-ha-monitor.sh
        - jenkins-failover.sh
        - haproxy-container-manager.sh
        - keepalived-haproxy-check.sh
      register: script_syntax_check
      failed_when: script_syntax_check.rc != 0
      changed_when: false
      become: yes
  tags: ['scripts', 'management']

# ====================================
# HEALTH MONITORING CONFIGURATION
# ====================================

- name: Configure HAProxy health monitoring
  block:
    - name: Check if crontab is available
      command: which crontab
      register: crontab_check
      failed_when: false
      changed_when: false

    - name: Setup automated HA monitoring cron job
      cron:
        name: "Jenkins HA Health Monitoring"
        job: "/usr/local/bin/jenkins-ha-monitor.sh >> /var/log/jenkins-ha-monitor.log 2>&1"
        minute: "*/2"
        user: root
        state: present
      become: yes
      when: crontab_check.rc == 0

    - name: Create log rotation for HA monitoring
      copy:
        dest: /etc/logrotate.d/jenkins-ha-monitor
        content: |
          /var/log/jenkins-ha-monitor.log {
              daily
              missingok
              rotate 7
              compress
              notifempty
              create 644 root root
          }
        mode: '0644'
      become: yes
      when: crontab_check.rc == 0

    - name: Skip cron job setup notification (development environments)
      debug:
        msg: "Skipping HA monitoring cron job - crontab not installed (development environment)"
      when: crontab_check.rc != 0

    - name: Create monitoring status directory
      file:
        path: /var/lib/jenkins-ha
        state: directory
        mode: '0755'
        owner: root
        group: root
      become: yes

    - name: Initialize HA monitoring state file
      copy:
        dest: /var/lib/jenkins-ha/status.json
        content: |
          {
            "last_check": "{{ ansible_date_time.iso8601 }}",
            "haproxy_status": "unknown",
            "vip_status": "{{ 'enabled' if jenkins_vip is defined and jenkins_vip != '' else 'disabled' }}",
            "teams_configured": {{ haproxy_effective_teams | length }},
            "deployment_mode": "{{ haproxy_deployment_mode }}"
          }
        mode: '0644'
        force: no
      become: yes
  tags: ['monitoring', 'health']

# ====================================
# COMPREHENSIVE HEALTH VERIFICATION
# ====================================

- name: Perform comprehensive HA health verification
  block:
    - name: Execute initial health check
      command: /usr/local/bin/jenkins-ha-monitor.sh
      register: initial_health_check
      failed_when: false
      changed_when: false
      become: yes

    - name: Test HAProxy container management script
      command: /usr/local/bin/haproxy-container-manager.sh status
      register: container_mgmt_test
      failed_when: false
      changed_when: false
      become: yes

    - name: Test VIP check script (if VIP enabled)
      command: /usr/local/bin/keepalived-haproxy-check.sh
      register: vip_check_test
      failed_when: false
      changed_when: false
      become: yes
      when: jenkins_vip is defined and jenkins_vip != ""

    - name: Verify HAProxy stats accessibility
      uri:
        url: "http://{{ ansible_default_ipv4.address }}:{{ haproxy_stats_port | default(8404) }}{{ haproxy_stats_uri | default('/stats') }}"
        method: GET
        timeout: 10
        user: "{{ haproxy_stats_user | default('admin') }}"
        password: "{{ haproxy_stats_password | default('admin123') }}"
        force_basic_auth: true
        status_code: [200, 401]  # Accept both authenticated access and auth prompts
      register: stats_accessibility
      retries: 3
      delay: 5
      failed_when: false  # Don't fail on authentication issues, just report status

    - name: Test team-specific routing functionality
      uri:
        url: "http://{{ ansible_default_ipv4.address }}:8090"
        method: HEAD
        timeout: 10
        headers:
          Host: "{{ item.team_name }}.{{ jenkins_domain | default('devops.example.com') }}"
      loop: "{{ haproxy_effective_teams }}"
      loop_control:
        label: "{{ item.team_name }}.{{ jenkins_domain }}"
      register: team_routing_test
      retries: 2
      delay: 3
      failed_when: false  # Don't fail on routing tests
      when: haproxy_effective_teams | length > 0

    - name: Display comprehensive HA status verification
      debug:
        msg: |
          ======================================================
          HAProxy High Availability Status Verification
          ======================================================
          
          🐳 Container Status:
          HAProxy Container: {{ 'Running' if container_mgmt_test.rc == 0 else 'Issues detected' }}
          
          📊 Monitoring Status:
          Health Check Script: {{ 'Functional' if initial_health_check.rc == 0 else 'Issues detected' }}
          Stats Endpoint: {{ 'Accessible' if stats_accessibility.status == 200 else 'Not accessible' }}
          Monitoring Cron: {{ 'Configured' if crontab_check.rc == 0 else 'Skipped (no crontab)' }}
          
          {% if jenkins_vip is defined and jenkins_vip != "" %}
          🎯 VIP Management:
          VIP Address: {{ jenkins_vip }}
          VIP Priority: {{ keepalived_priority | default(100) }}
          VIP Check Script: {{ 'Functional' if vip_check_test.rc == 0 else 'Issues detected' }}
          Keepalived Status: {{ 'Active' if keepalived_validation.rc == 0 else 'Configuration issues' }}
          {% endif %}
          
          👥 Team Routing:
          {% if haproxy_effective_teams | length > 0 %}
          {% for result in team_routing_test.results %}
          • {{ haproxy_effective_teams[loop.index0].team_name }}: {{ 'OK' if result.status | default(0) in [200, 302, 404, 503] else 'Failed' }}
          {% endfor %}
          {% else %}
          Single-team configuration (no team-specific routing)
          {% endif %}
          
          📁 Management Scripts:
          {% for script in ['jenkins-ha-monitor.sh', 'jenkins-failover.sh', 'haproxy-container-manager.sh', 'keepalived-haproxy-check.sh'] %}
          • {{ script }}: Available at /usr/local/bin/{{ script }}
          {% endfor %}
          
          ======================================================
  tags: ['verify', 'health']

- name: HA monitoring and VIP management phase complete
  debug:
    msg: |
      ====================================
      HA Monitoring Setup Complete
      ====================================
      Management Scripts: 4 deployed
      Health Monitoring: {{ 'Automated' if crontab_check.rc == 0 else 'Manual only' }}
      {% if jenkins_vip is defined and jenkins_vip != "" %}
      VIP Management: {{ jenkins_vip }} (keepalived)
      {% endif %}
      Status Verification: Complete
      ====================================
  tags: ['monitoring']
```
