# Inventory Management Guide

## Overview

This guide provides comprehensive information on managing Ansible inventory for the Jenkins HA infrastructure, including host configuration, group management, variable hierarchy, and environment-specific inventory organization.

## Inventory Structure

### Directory Layout

```
ansible/inventories/
├── production/
│   ├── hosts.yml                 # Production inventory
│   ├── group_vars/
│   │   ├── all/
│   │   │   ├── main.yml         # Common variables
│   │   │   └── vault.yml        # Encrypted secrets
│   │   ├── jenkins_masters/
│   │   │   └── main.yml         # Master-specific variables
│   │   ├── jenkins_agents/
│   │   │   └── main.yml         # Agent-specific variables
│   │   ├── load_balancers/
│   │   │   └── main.yml         # Load balancer variables
│   │   └── monitoring/
│   │       └── main.yml         # Monitoring variables
│   └── host_vars/
│       ├── jenkins-master-01.yml
│       ├── jenkins-master-02.yml
├── staging/
│   ├── hosts.yml
│   ├── group_vars/
│   └── host_vars/
├── development/
│   ├── hosts.yml
│   ├── group_vars/
│   └── host_vars/
└── dr/
    ├── hosts.yml
    ├── group_vars/
    └── host_vars/
```

### Production Inventory Configuration

**Primary Inventory File (`ansible/inventories/production/hosts.yml`):**

```yaml
all:
  children:
    jenkins_masters:
      hosts:
        jenkins-master-01:
          ansible_host: 10.0.2.10
          ansible_user: jenkins
          jenkins_master_port: 8080
          jenkins_master_priority: 100
          jenkins_role: primary
          keepalived_priority: 100
          keepalived_state: MASTER
        jenkins-master-02:
          ansible_host: 10.0.2.11
          ansible_user: jenkins
          jenkins_master_port: 8080
          jenkins_master_priority: 90
          jenkins_role: secondary
          keepalived_priority: 90
          keepalived_state: BACKUP
      vars:
        jenkins_version: "2.427.1"
        jenkins_home: "/opt/jenkins_home"
        jenkins_user: "jenkins"
        jenkins_group: "jenkins"
        jenkins_uid: 1000
        jenkins_gid: 1000

    jenkins_agents:
      children:
        maven_agents:
          hosts:
            jenkins-agent-maven-01:
              ansible_host: 10.0.2.20
              agent_labels: "maven java-11 java-17"
              agent_executors: 4
              agent_memory: "8g"
            jenkins-agent-maven-02:
              ansible_host: 10.0.2.21
              agent_labels: "maven java-11 java-17"
              agent_executors: 4
              agent_memory: "8g"
          vars:
            agent_type: "maven"
            java_versions: ["11", "17"]
            maven_versions: ["3.8.6", "3.9.4"]

        nodejs_agents:
          hosts:
            jenkins-agent-nodejs-01:
              ansible_host: 10.0.2.30
              agent_labels: "nodejs npm yarn"
              agent_executors: 2
              agent_memory: "4g"
            jenkins-agent-nodejs-02:
              ansible_host: 10.0.2.31
              agent_labels: "nodejs npm yarn"
              agent_executors: 2
              agent_memory: "4g"
          vars:
            agent_type: "nodejs"
            nodejs_versions: ["16", "18", "20"]

        python_agents:
          hosts:
            jenkins-agent-python-01:
              ansible_host: 10.0.2.40
              agent_labels: "python python3 pip"
              agent_executors: 3
              agent_memory: "6g"
            jenkins-agent-python-02:
              ansible_host: 10.0.2.41
              agent_labels: "python python3 pip"
              agent_executors: 3
              agent_memory: "6g"
          vars:
            agent_type: "python"
            python_versions: ["3.9", "3.10", "3.11"]

        dind_agents:
          hosts:
            jenkins-agent-dind-01:
              ansible_host: 10.0.2.50
              agent_labels: "docker dind containers"
              agent_executors: 2
              agent_memory: "8g"
              docker_in_docker: true
            jenkins-agent-dind-02:
              ansible_host: 10.0.2.51
              agent_labels: "docker dind containers"
              agent_executors: 2
              agent_memory: "8g"
              docker_in_docker: true
          vars:
            agent_type: "dind"
            docker_version: "24.0.6"

    load_balancers:
      hosts:
        lb-01:
          ansible_host: 10.0.1.10
          keepalived_priority: 100
          keepalived_state: MASTER
          haproxy_stats_port: 8404
        lb-02:
          ansible_host: 10.0.1.11
          keepalived_priority: 90
          keepalived_state: BACKUP
          haproxy_stats_port: 8404
      vars:
        jenkins_vip: "10.0.1.100"
        haproxy_version: "2.8"
        keepalived_interface: "eth0"
        keepalived_virtual_router_id: 50

      hosts:
          ansible_host: 10.0.3.10
      vars:

    monitoring:
      children:
        prometheus:
          hosts:
            prometheus-01:
              ansible_host: 10.0.4.10
              prometheus_retention: "30d"
              prometheus_storage_size: "100GB"
        grafana:
          hosts:
            grafana-01:
              ansible_host: 10.0.4.11
              grafana_admin_password: "{{ vault_grafana_admin_password }}"
              grafana_database_password: "{{ vault_grafana_db_password }}"
        alertmanager:
          hosts:
            alertmanager-01:
              ansible_host: 10.0.4.12
              alertmanager_smtp_password: "{{ vault_alertmanager_smtp_password }}"
      vars:
        monitoring_data_path: "/opt/monitoring"

    shared_storage:
      hosts:
        nfs-01:
          ansible_host: 10.0.5.10
          nfs_exports:
            - path: "/exports/jenkins_home"
              options: "rw,sync,no_subtree_check,no_root_squash"
              allowed: "10.0.2.0/24"
            - path: "/exports/backup"
              options: "rw,sync,no_subtree_check,no_root_squash"
              allowed: "10.0.5.0/24"
      vars:
        nfs_version: "4.1"

    backup:
      hosts:
        backup-01:
          ansible_host: 10.0.5.20
          backup_retention_days: 90
          backup_storage_path: "/backup"
      vars:
        backup_schedule:
          full: "0 2 * * 0"    # Weekly full backup
          incremental: "0 3 * * 1-6"  # Daily incremental

  vars:
    # Global environment variables
    environment: "production"
    domain: "company.com"
    timezone: "UTC"
    
    # Network configuration
    network_interface: "eth0"
    dns_servers:
      - "10.0.6.50"
      - "8.8.8.8"
    
    # Security settings
    ssh_port: 22
    fail2ban_enabled: true
    firewall_enabled: true
    
    # Container runtime
    container_runtime: "docker"  # or "podman"
    docker_version: "24.0.6"
    
    # SSL/TLS configuration
    ssl_certificate_authority: "internal"  # or "letsencrypt"
    ssl_key_size: 4096
    ssl_certificate_days: 365
```

## Host Variables Configuration

### Individual Host Configuration

**Jenkins Master Host Variables (`ansible/inventories/production/host_vars/jenkins-master-01.yml`):**

```yaml
# Host-specific configuration for jenkins-master-01
ansible_host: 10.0.2.10
ansible_user: jenkins
ansible_ssh_private_key_file: ~/.ssh/jenkins_rsa

# Jenkins configuration
jenkins_master_port: 8080
jenkins_https_port: 8443
jenkins_agent_port: 50000
jenkins_role: primary
jenkins_heap_size: "4g"

# HA configuration
keepalived_priority: 100
keepalived_state: MASTER
jenkins_master_priority: 100

# Resource limits
cpu_limit: "4"
memory_limit: "8g"
disk_space_threshold: "80%"

# Monitoring
node_exporter_port: 9100
jenkins_prometheus_port: 8081

# SSL certificates
ssl_certificate_path: "/etc/ssl/certs/jenkins-master-01.crt"
ssl_private_key_path: "/etc/ssl/private/jenkins-master-01.key"

# Custom JVM options
jenkins_java_options:
  - "-Xms2g"
  - "-Xmx4g"
  - "-XX:+UseG1GC"
  - "-XX:MaxGCPauseMillis=200"
  - "-Djava.awt.headless=true"
  - "-Dhudson.security.csrf.GlobalCrumbIssuerConfiguration.DISABLE_CSRF_PROTECTION=false"
```

**Agent Host Variables (`ansible/inventories/production/host_vars/jenkins-agent-maven-01.yml`):**

```yaml
# Host-specific configuration for maven agent
ansible_host: 10.0.2.20
ansible_user: jenkins

# Agent configuration
agent_name: "maven-agent-01"
agent_description: "Maven build agent with Java 11 and 17"
agent_labels: "maven java-11 java-17 linux"
agent_executors: 4
agent_memory: "8g"
agent_workspace: "/opt/jenkins/workspace"

# Tool versions
java_versions:
  - version: "11"
    path: "/usr/lib/jvm/java-11-openjdk"
  - version: "17"
    path: "/usr/lib/jvm/java-17-openjdk"

maven_versions:
  - version: "3.8.6"
    path: "/opt/maven/3.8.6"
  - version: "3.9.4"
    path: "/opt/maven/3.9.4"

# Container configuration
container_volumes:
  - "/opt/jenkins:/opt/jenkins"
  - "/var/run/docker.sock:/var/run/docker.sock"
  - "/tmp:/tmp"

# Resource limits
container_cpu_limit: "4"
container_memory_limit: "8g"
container_swap_limit: "2g"

# Network configuration
container_network: "jenkins-network"
container_hostname: "maven-agent-01"
```

## Group Variables Configuration

### All Hosts Variables (`ansible/inventories/production/group_vars/all/main.yml`)

```yaml
# Global configuration for all hosts
environment: "production"
company_domain: "company.com"
internal_domain: "internal.company.com"

# Time and locale
timezone: "UTC"
ntp_servers:
  - "pool.ntp.org"
  - "time.google.com"

# DNS configuration
dns_servers:
  - "10.0.6.50"    # Internal DNS
  - "8.8.8.8"      # Google DNS
  - "1.1.1.1"      # Cloudflare DNS

dns_search_domains:
  - "internal.company.com"
  - "company.com"

# Network configuration
network_interface: "eth0"
firewall_enabled: true
fail2ban_enabled: true

# SSH configuration
ssh_port: 22
ssh_max_auth_tries: 3
ssh_permit_root_login: false
ssh_password_authentication: false
ssh_key_based_auth: true

# User management
admin_users:
  - name: "ansible"
    key: "{{ vault_ansible_ssh_key }}"
    sudo: true
  - name: "jenkins"
    key: "{{ vault_jenkins_ssh_key }}"
    sudo: false

# Container runtime
container_runtime: "docker"
docker_version: "24.0.6"
docker_compose_version: "2.21.0"

# Docker daemon configuration
docker_daemon_options:
  log-driver: "json-file"
  log-opts:
    max-size: "10m"
    max-file: "3"
  storage-driver: "overlay2"
  userland-proxy: false
  live-restore: true

# Security settings
security_hardening_enabled: true
aide_enabled: true
rkhunter_enabled: true
lynis_enabled: true

# Backup configuration
backup_enabled: true
backup_retention_policy:
  daily: 7
  weekly: 4
  monthly: 12
  yearly: 2

# Monitoring
monitoring_enabled: true
log_aggregation_enabled: true
metrics_retention_days: 30

# SSL/TLS configuration
ssl_enabled: true
ssl_certificate_authority: "internal"
ssl_key_size: 4096
ssl_cipher_suites:
  - "ECDHE-RSA-AES256-GCM-SHA384"
  - "ECDHE-RSA-AES128-GCM-SHA256"
  - "ECDHE-RSA-AES256-SHA384"

# LDAP integration
ldap_enabled: true
ldap_server: "ldap.company.com"
ldap_port: 389
ldap_ssl: false
ldap_base_dn: "dc=company,dc=com"
ldap_bind_dn: "cn=jenkins,ou=service-accounts,dc=company,dc=com"
ldap_user_search: "ou=users,dc=company,dc=com"
ldap_group_search: "ou=groups,dc=company,dc=com"
```

### Jenkins Masters Group Variables (`ansible/inventories/production/group_vars/jenkins_masters/main.yml`)

```yaml
# Jenkins Masters specific configuration
jenkins_version: "2.427.1"
jenkins_war_url: "https://get.jenkins.io/war-stable/{{ jenkins_version }}/jenkins.war"

# Jenkins directories
jenkins_home: "/opt/jenkins_home"
jenkins_user: "jenkins"
jenkins_group: "jenkins"
jenkins_uid: 1000
jenkins_gid: 1000

# Jenkins network configuration
jenkins_master_port: 8080
jenkins_https_port: 8443
jenkins_agent_port: 50000
jenkins_bind_address: "0.0.0.0"

# JVM configuration
jenkins_java_home: "/usr/lib/jvm/java-17-openjdk"
jenkins_heap_size: "4g"
jenkins_permgen_size: "256m"
jenkins_java_options:
  - "-server"
  - "-Xms{{ jenkins_heap_size }}"
  - "-Xmx{{ jenkins_heap_size }}"
  - "-XX:+UseG1GC"
  - "-XX:MaxGCPauseMillis=200"
  - "-Djava.awt.headless=true"
  - "-Dfile.encoding=UTF-8"
  - "-Dsun.jnu.encoding=UTF-8"

# Jenkins Configuration as Code (JCasC)
jenkins_casc_enabled: true
jenkins_casc_config_path: "/var/jenkins_home/casc_configs"

# Security configuration
jenkins_security_realm: "ldap"
jenkins_authorization_strategy: "roleBased"
jenkins_csrf_protection: true
jenkins_agent_protocols:
  - "JNLP4-connect"
  - "Ping"

# Plugin management
jenkins_plugins_state: "latest"
jenkins_plugin_timeout: 300
jenkins_plugins_install_dependencies: true

# Essential plugins list
jenkins_plugins:
  # Core functionality
  - name: "configuration-as-code"
    version: "latest"
  - name: "job-dsl"
    version: "latest"
  - name: "workflow-aggregator"  # Pipeline plugin
    version: "latest"
  
  # Security and authentication
  - name: "ldap"
    version: "latest"
  - name: "role-strategy"
    version: "latest"
  - name: "matrix-auth"
    version: "latest"
  
  # Source control
  - name: "git"
    version: "latest"
  - name: "github"
    version: "latest"
  - name: "gitlab-plugin"
    version: "latest"
  
  # Build tools
  - name: "maven-plugin"
    version: "latest"
  - name: "gradle"
    version: "latest"
  - name: "nodejs"
    version: "latest"
  
  # Container support
  - name: "docker-plugin"
    version: "latest"
  - name: "docker-workflow"
    version: "latest"
  - name: "kubernetes"
    version: "latest"
  
  # Monitoring and reporting
  - name: "prometheus"
    version: "latest"
  - name: "monitoring"
    version: "latest"
  - name: "build-monitor-plugin"
    version: "latest"

# High Availability configuration
ha_enabled: true
shared_storage_enabled: true
session_replication: false  # Not supported in Jenkins

# Shared storage configuration
nfs_server: "10.0.5.10"
nfs_mount_options: "hard,intr,rsize=1048576,wsize=1048576,vers=4.1"
jenkins_shared_directories:
  - src: "{{ nfs_server }}:/exports/jenkins_home"
    dest: "{{ jenkins_home }}"
    fstype: "nfs4"
    opts: "{{ nfs_mount_options }}"

# Backup configuration
backup_jenkins_home: true
backup_schedule: "0 2 * * *"  # Daily at 2 AM
backup_retention_days: 30

# Container configuration
jenkins_container_name: "jenkins-master"
jenkins_container_restart_policy: "unless-stopped"

jenkins_container_volumes:
  - "{{ jenkins_home }}:/var/jenkins_home"
  - "/etc/localtime:/etc/localtime:ro"
  - "/var/run/docker.sock:/var/run/docker.sock"

jenkins_container_environment:
  JENKINS_OPTS: "--httpPort={{ jenkins_master_port }} --httpsPort={{ jenkins_https_port }}"
  JAVA_OPTS: "{{ jenkins_java_options | join(' ') }}"
  JENKINS_SLAVE_AGENT_PORT: "{{ jenkins_agent_port }}"

# Monitoring configuration
monitoring_enabled: true
prometheus_metrics_enabled: true
jenkins_prometheus_endpoint: "/prometheus"
```

## Environment-Specific Configurations

### Staging Environment

**Staging Inventory (`ansible/inventories/staging/hosts.yml`):**

```yaml
all:
  children:
    jenkins_masters:
      hosts:
        jenkins-master-staging-01:
          ansible_host: 192.168.100.10
          jenkins_role: standalone  # Single master for staging
        
    jenkins_agents:
      hosts:
        jenkins-agent-staging-01:
          ansible_host: 192.168.100.20
          agent_labels: "staging test"
          
    monitoring:
      hosts:
        monitoring-staging-01:
          ansible_host: 192.168.100.30
          
  vars:
    environment: "staging"
    domain: "staging.company.com"
    ssl_certificate_authority: "self-signed"
    backup_retention_days: 7
    jenkins_heap_size: "2g"  # Smaller resources for staging
```

### Development Environment

**Development Inventory (`ansible/inventories/development/hosts.yml`):**

```yaml
all:
  children:
    jenkins_masters:
      hosts:
        jenkins-master-dev-01:
          ansible_host: 192.168.200.10
          jenkins_role: standalone
          
    jenkins_agents:
      hosts:
        jenkins-agent-dev-01:
          ansible_host: 192.168.200.20
          agent_labels: "development experimental"
          
  vars:
    environment: "development"
    domain: "dev.company.com"
    ssl_enabled: false  # HTTP only for development
    security_hardening_enabled: false
    backup_enabled: false
    monitoring_enabled: false
    jenkins_heap_size: "1g"
```

## Inventory Validation

### Inventory Syntax Validation

```bash
# Validate inventory syntax
ansible-inventory -i ansible/inventories/production/hosts.yml --list

# Check inventory graph
ansible-inventory -i ansible/inventories/production/hosts.yml --graph

# Validate specific group
ansible-inventory -i ansible/inventories/production/hosts.yml --graph jenkins_masters

# Check host variables
ansible-inventory -i ansible/inventories/production/hosts.yml --host jenkins-master-01
```

### Connectivity Testing

```bash
# Test connectivity to all hosts
ansible all -i ansible/inventories/production/hosts.yml -m ping

# Test specific group connectivity
ansible jenkins_masters -i ansible/inventories/production/hosts.yml -m ping

# Test with verbose output
ansible all -i ansible/inventories/production/hosts.yml -m ping -vvv

# Test SSH connectivity
ansible all -i ansible/inventories/production/hosts.yml -m shell -a "hostname && date"
```

### Variable Testing

```bash
# Check variable resolution
ansible jenkins_masters -i ansible/inventories/production/hosts.yml -m debug -a "var=jenkins_version"

# Test vault variables
ansible jenkins_masters -i ansible/inventories/production/hosts.yml \
  -m debug -a "var=vault_jenkins_admin_password" \
  --vault-password-file=environments/vault-passwords/.vault_pass_production

# Display all variables for a host
ansible-inventory -i ansible/inventories/production/hosts.yml \
  --host jenkins-master-01 --vars
```

## Inventory Management Scripts

### Dynamic Inventory Updates

**Script: `scripts/update-inventory.sh`**

```bash
#!/bin/bash
# Update inventory with new host information

ENVIRONMENT=$1
HOST_NAME=$2
HOST_IP=$3
HOST_GROUP=$4

if [ $# -ne 4 ]; then
    echo "Usage: $0 <environment> <hostname> <ip> <group>"
    echo "Example: $0 production jenkins-agent-03 10.0.2.22 maven_agents"
    exit 1
fi

INVENTORY_FILE="ansible/inventories/${ENVIRONMENT}/hosts.yml"

# Backup original inventory
cp "$INVENTORY_FILE" "${INVENTORY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Add new host (using yq for YAML manipulation)
yq eval ".all.children.${HOST_GROUP}.hosts.${HOST_NAME}.ansible_host = \"${HOST_IP}\"" \
   -i "$INVENTORY_FILE"

echo "Added $HOST_NAME ($HOST_IP) to $HOST_GROUP in $ENVIRONMENT environment"

# Validate updated inventory
ansible-inventory -i "$INVENTORY_FILE" --list > /dev/null
if [ $? -eq 0 ]; then
    echo "Inventory validation successful"
else
    echo "Inventory validation failed, restoring backup"
    cp "${INVENTORY_FILE}.backup.*" "$INVENTORY_FILE"
    exit 1
fi
```

### Inventory Reporting

**Script: `scripts/inventory-report.sh`**

```bash
#!/bin/bash
# Generate inventory report

ENVIRONMENT=${1:-production}
INVENTORY_FILE="ansible/inventories/${ENVIRONMENT}/hosts.yml"

echo "=== Jenkins HA Infrastructure Inventory Report ==="
echo "Environment: $ENVIRONMENT"
echo "Generated: $(date)"
echo

# Host counts by group
echo "=== Host Count Summary ==="
ansible-inventory -i "$INVENTORY_FILE" --graph | grep -E "^\s*\|--" | \
while read line; do
    group=$(echo "$line" | sed 's/.*@//' | sed 's/://')
    count=$(ansible-inventory -i "$INVENTORY_FILE" --list | \
           jq -r ".${group}.hosts // {} | keys | length" 2>/dev/null || echo "0")
    printf "%-20s: %s hosts\n" "$group" "$count"
done

echo

# Detailed host information
echo "=== Detailed Host Information ==="
ansible-inventory -i "$INVENTORY_FILE" --list | \
jq -r '._meta.hostvars | to_entries[] | 
       "\(.key): \(.value.ansible_host // "N/A") (\(.value.ansible_user // "N/A"))"' | \
sort

echo

# Group membership
echo "=== Group Membership ==="
ansible-inventory -i "$INVENTORY_FILE" --graph --vars
```

## Best Practices

### Inventory Organization

1. **Environment Separation**: Keep separate inventories for each environment
2. **Group Hierarchy**: Use nested groups for logical organization
3. **Variable Precedence**: Understand Ansible variable precedence rules
4. **Consistent Naming**: Use consistent hostname and variable naming conventions
5. **Documentation**: Comment complex configurations in inventory files

### Security Considerations

1. **Vault Usage**: Store sensitive variables in encrypted vault files
2. **SSH Keys**: Use key-based authentication with role-specific keys
3. **Access Control**: Limit inventory file access to authorized personnel
4. **Regular Audits**: Regularly audit inventory configurations and access

### Maintenance Procedures

1. **Regular Validation**: Run inventory validation as part of CI/CD pipeline
2. **Backup Strategy**: Maintain backups of inventory configurations
3. **Change Management**: Use version control for all inventory changes
4. **Testing**: Test inventory changes in staging before production

---

**Document Version:** 1.0
**Last Updated:** {{ ansible_date_time.date }}
**Next Review:** Monthly
**Owner:** Infrastructure Team