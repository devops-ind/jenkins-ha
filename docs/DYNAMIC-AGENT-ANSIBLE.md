# Dynamic Agent Ansible Execution Guide

## Overview

This guide explains how to use Jenkins dynamic agents to execute Ansible roles directly on remote hosts. This approach provides true distributed execution where Jenkins provisionally creates temporary agents on target hosts and runs Ansible locally on each host.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Jenkins       │    │  Remote Host 1  │    │  Remote Host 2  │
│   Master        │    │                 │    │                 │
│                 │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ ┌─────────────┐ │    │ │   SSH       │ │    │ │   SSH       │ │
│ │   Pipeline  │ │────┤ │   Agent     │ │    │ │   Agent     │ │
│ │   Job       │ │    │ │             │ │    │ │             │ │
│ └─────────────┘ │    │ ├─────────────┤ │    │ ├─────────────┤ │
│                 │    │ │  Ansible    │ │    │ │  Ansible    │ │
└─────────────────┘    │ │  Execution  │ │    │ │  Execution  │ │
                       │ │  (Local)    │ │    │ │  (Local)    │ │
                       │ └─────────────┘ │    │ └─────────────┘ │
                       └─────────────────┘    └─────────────────┘
```

## Benefits of Dynamic Agent Approach

### 1. **True Distributed Execution**
- Ansible runs locally on each target host
- No network latency during playbook execution
- Better performance for file operations and system commands

### 2. **Scalable Architecture**
- Each host gets its own dedicated Jenkins agent
- Parallel execution across multiple hosts
- No bottlenecks through central control nodes

### 3. **Resource Efficiency**
- Agents are created on-demand
- Automatic cleanup after execution
- No persistent agent overhead

### 4. **Security Benefits**
- Each agent runs in isolated environment
- Direct SSH connection per host
- No shared execution environments

## Prerequisites

### 1. SSH Key Exchange
Ensure SSH keys are exchanged between Jenkins master and target hosts:

```bash
# Run SSH Key Exchange job first
TARGET_HOSTS: "192.168.1.10,192.168.1.11,192.168.1.12"
SSH_USERNAME: "jenkins"
AUTH_METHOD: "password"
```

### 2. Remote Host Requirements

#### Java Runtime
```bash
# Install Java on target hosts (required for Jenkins agent)
# RHEL/CentOS
sudo yum install -y java-11-openjdk

# Ubuntu/Debian  
sudo apt-get update && sudo apt-get install -y openjdk-11-jdk

# Verify installation
java -version
```

#### Python and Ansible
```bash
# Install Python 3 and pip
# RHEL/CentOS
sudo yum install -y python3 python3-pip

# Ubuntu/Debian
sudo apt-get install -y python3 python3-pip

# Install Ansible
pip3 install --user ansible
```

#### Git (for playbook checkout)
```bash
# RHEL/CentOS
sudo yum install -y git

# Ubuntu/Debian
sudo apt-get install -y git
```

### 3. Network Configuration
- SSH port (default 22) accessible from Jenkins master
- Firewall rules allow Jenkins agent communication
- DNS resolution or hosts file entries for target systems

## Using the Dynamic Ansible Executor

### Job Location
- **Job Name**: `Infrastructure/Dynamic-Ansible-Executor`
- **Job DSL**: `jenkins-dsl/infrastructure/dynamic-ansible-executor.groovy`

### Step 1: Configure Target Hosts

#### Format Options
```bash
# Simple hostname/IP format
192.168.1.10
192.168.1.11
build-server.example.com

# With custom agent labels
192.168.1.10:docker-builder
192.168.1.11:maven-builder
build-server.example.com:image-builder
```

#### Host Labels
Agent labels help organize and target specific types of hosts:
- `docker-builder` - Hosts with Docker/Podman for image building
- `maven-builder` - Hosts with Maven for Java builds
- `ansible-controller` - General-purpose Ansible execution
- `monitoring-agent` - Hosts for monitoring component deployment

### Step 2: Configure Authentication

#### SSH Credentials
```yaml
SSH_CREDENTIALS_ID: "jenkins-ssh-key"  # Jenkins credential ID
SSH_USERNAME: "jenkins"                # SSH username
SSH_PORT: "22"                        # SSH port
JAVA_PATH: "/usr/bin/java"            # Java path on remote hosts
AGENT_WORK_DIR: "/tmp/jenkins-agent"  # Agent working directory
```

### Step 3: Select Ansible Role

#### Available Roles
- `jenkins-images` - Build and manage Jenkins Docker images
- `harbor` - Deploy and configure Harbor registry
- `monitoring` - Deploy Prometheus/Grafana monitoring stack
- `backup` - Configure backup systems
- `security` - Apply security hardening
- `docker` - Install and configure Docker/Podman
- `common` - Apply common system configuration

### Step 4: Configure Execution Parameters

#### Execution Modes
```yaml
# Parallel execution (faster, more resource intensive)
AGENT_CONNECTION_MODE: "PARALLEL"

# Sequential execution (slower, less resource intensive)  
AGENT_CONNECTION_MODE: "SEQUENTIAL"
```

#### Agent Management
```yaml
# Cleanup agents after execution (recommended)
KEEP_AGENTS_ONLINE: false

# Keep agents online for reuse
KEEP_AGENTS_ONLINE: true

# Agent connection timeout
AGENT_TIMEOUT: "300"
```

#### Extra Variables
```yaml
# Example extra variables for image building
harbor_registry_url: "harbor.example.com"
harbor_project: "jenkins"
jenkins_images_build: true
jenkins_images_push: true
jenkins_master_image_tag: "latest"

# Example variables for monitoring deployment
prometheus_retention_time: "30d"
grafana_admin_password: "secure-password"
monitoring_enabled: true
```

## Example Execution Scenarios

### Scenario 1: Build Jenkins Images on Multiple Hosts

```yaml
TARGET_HOSTS: |
  build-01.example.com:docker-builder
  build-02.example.com:docker-builder
  build-03.example.com:docker-builder

SSH_CREDENTIALS_ID: "jenkins-ssh-key"
SSH_USERNAME: "jenkins"
ANSIBLE_ROLE: "jenkins-images"

ANSIBLE_EXTRA_VARS: |
  jenkins_images_build: true
  jenkins_images_push: true
  harbor_registry_url: "harbor.example.com"
  harbor_project: "jenkins"
  jenkins_master_image_tag: "v2.426.1"
  
  # Build multiple variants
  jenkins_image_variants:
    - name: "jenkins-master"
      dockerfile: "Dockerfile.master"
    - name: "jenkins-agent-maven"  
      dockerfile: "Dockerfile.agent-maven"
    - name: "jenkins-agent-nodejs"
      dockerfile: "Dockerfile.agent-nodejs"

AGENT_CONNECTION_MODE: "PARALLEL"
COLLECT_ARTIFACTS: true
```

### Scenario 2: Deploy Monitoring Stack

```yaml
TARGET_HOSTS: |
  monitor-01.prod.example.com
  monitor-02.prod.example.com

SSH_CREDENTIALS_ID: "jenkins-ssh-key"
SSH_USERNAME: "monitoring"
ANSIBLE_ROLE: "monitoring"

ANSIBLE_EXTRA_VARS: |
  deployment_mode: "production"
  prometheus_retention_time: "90d"
  prometheus_storage_size: "100GB"
  grafana_admin_password: "${GRAFANA_ADMIN_PASSWORD}"
  
  # Configure data sources
  prometheus_datasources:
    - name: "Jenkins Metrics"
      url: "http://jenkins.example.com:8080/prometheus"
    - name: "Node Exporter"
      url: "http://localhost:9100/metrics"

AGENT_CONNECTION_MODE: "SEQUENTIAL"
KEEP_AGENTS_ONLINE: false
```

### Scenario 3: Harbor Registry Deployment

```yaml
TARGET_HOSTS: |
  harbor-01.example.com:harbor-primary
  harbor-02.example.com:harbor-replica

SSH_CREDENTIALS_ID: "jenkins-ssh-key"  
SSH_USERNAME: "harbor"
ANSIBLE_ROLE: "harbor"

ANSIBLE_EXTRA_VARS: |
  harbor_admin_password: "${HARBOR_ADMIN_PASSWORD}"
  harbor_database_password: "${HARBOR_DB_PASSWORD}"
  harbor_hostname: "harbor.example.com"
  harbor_protocol: "https"
  harbor_port: 443
  
  # SSL configuration
  harbor_ssl_cert: "/etc/harbor/certs/harbor.crt"
  harbor_ssl_key: "/etc/harbor/certs/harbor.key"
  
  # Storage configuration
  harbor_data_volume: "/data/harbor"
  harbor_log_rotate_size: "200M"

AGENT_CONNECTION_MODE: "SEQUENTIAL"
COLLECT_ARTIFACTS: true
```

## Advanced Configuration

### Custom Agent Labels and Targeting

```yaml
# Define specialized agents
TARGET_HOSTS: |
  gpu-builder-01:cuda-builder
  gpu-builder-02:cuda-builder
  cpu-builder-01:standard-builder
  cpu-builder-02:standard-builder

# Later target specific agents in pipeline stages
node('cuda-builder') {
    // GPU-intensive tasks
}

node('standard-builder') {
    // Standard build tasks  
}
```

### Multi-Stage Execution

```groovy
pipeline {
    agent none
    
    stages {
        stage('Provision Agents') {
            // Use Dynamic Ansible Executor to provision agents
            steps {
                build job: 'Infrastructure/Dynamic-Ansible-Executor'
            }
        }
        
        stage('Application Build') {
            parallel {
                stage('Build on GPU Hosts') {
                    agent { label 'cuda-builder' }
                    steps {
                        // GPU-specific build steps
                    }
                }
                
                stage('Build on CPU Hosts') {
                    agent { label 'standard-builder' }
                    steps {
                        // CPU build steps  
                    }
                }
            }
        }
    }
}
```

### Environment-Specific Configurations

```yaml
# Development environment
TARGET_HOSTS: |
  dev-build-01.internal:dev-builder
  dev-build-02.internal:dev-builder

ANSIBLE_EXTRA_VARS: |
  deployment_mode: "development"
  jenkins_debug_enabled: true
  jenkins_security_enabled: false

# Production environment  
TARGET_HOSTS: |
  prod-build-01.example.com:prod-builder
  prod-build-02.example.com:prod-builder

ANSIBLE_EXTRA_VARS: |
  deployment_mode: "production"
  jenkins_debug_enabled: false
  jenkins_security_enabled: true
  jenkins_ssl_enabled: true
```

## Monitoring and Troubleshooting

### Agent Connection Issues

#### Problem: Agent fails to connect
```
Agent agent-192-168-1-10-123 failed to come online within 120 seconds
```

**Solutions:**
1. Verify SSH connectivity:
   ```bash
   ssh -p 22 jenkins@192.168.1.10 "echo 'SSH test successful'"
   ```

2. Check Java installation:
   ```bash
   ssh jenkins@192.168.1.10 "java -version"
   ```

3. Verify firewall rules:
   ```bash
   # Check if agent port is accessible
   ssh jenkins@192.168.1.10 "netstat -tlnp | grep :22"
   ```

4. Check disk space:
   ```bash
   ssh jenkins@192.168.1.10 "df -h /tmp"
   ```

#### Problem: Permission denied errors
```
Permission denied (publickey)
```

**Solutions:**
1. Re-run SSH Key Exchange job
2. Verify SSH key permissions:
   ```bash
   ssh jenkins@host "ls -la ~/.ssh/"
   ```
3. Check SSH daemon configuration:
   ```bash
   sudo sshd -T | grep -E "(PubkeyAuthentication|AuthorizedKeysFile)"
   ```

### Ansible Execution Issues

#### Problem: Ansible role fails
```
TASK [role-name : task-name] *************************
fatal: [localhost]: FAILED! => {"msg": "Task failed"}
```

**Solutions:**
1. Check Ansible version compatibility:
   ```bash
   node('agent-name') {
       sh 'ansible --version'
   }
   ```

2. Verify role dependencies:
   ```bash
   # Check if required collections are installed
   ansible-galaxy collection list
   ```

3. Validate extra variables:
   ```yaml
   # Test with minimal variables first
   ANSIBLE_EXTRA_VARS: |
     deployment_mode: "localhost"
     ansible_connection: "local"
   ```

### Performance Optimization

#### 1. Agent Connection Optimization
```yaml
# Increase timeout for slow networks
AGENT_TIMEOUT: "600"

# Use sequential mode for resource-constrained environments
AGENT_CONNECTION_MODE: "SEQUENTIAL"

# Optimize Java heap for agents
JAVA_PATH: "/usr/bin/java -Xmx512m -Xms256m"
```

#### 2. Ansible Execution Optimization
```yaml
ANSIBLE_EXTRA_VARS: |
  # Increase parallel execution
  ansible_forks: 10
  
  # Reduce gather_facts overhead  
  gather_facts: false
  
  # Use faster SSH multiplexing
  ansible_ssh_pipelining: true
```

#### 3. Network Optimization
```yaml
# Use compression for large file transfers
ANSIBLE_EXTRA_VARS: |
  ansible_ssh_args: "-C -o ControlMaster=auto -o ControlPersist=60s"
```

## Security Considerations

### 1. SSH Key Management
- Use unique SSH keys for different environments
- Implement key rotation policies
- Monitor SSH access logs
- Use SSH key passphrases when possible

### 2. Agent Security
- Limit agent working directory permissions
- Clean up sensitive files after execution
- Use temporary credentials when possible
- Monitor agent resource usage

### 3. Network Security
- Use VPN connections for remote execution
- Implement SSH jump hosts for multi-tier architectures
- Configure firewall rules restrictively
- Use SSH port forwarding for secure connections

### 4. Credential Management
- Store all secrets in Jenkins credential store
- Use credential binding in pipelines
- Implement credential rotation schedules
- Audit credential usage regularly

## Integration Patterns

### 1. CI/CD Pipeline Integration
```groovy
pipeline {
    stages {
        stage('Build Images') {
            steps {
                build job: 'Infrastructure/Dynamic-Ansible-Executor', parameters: [
                    text(name: 'TARGET_HOSTS', value: env.BUILD_HOSTS),
                    string(name: 'ANSIBLE_ROLE', value: 'jenkins-images'),
                    text(name: 'ANSIBLE_EXTRA_VARS', value: """
                        jenkins_images_build: true
                        jenkins_images_tag: ${env.BUILD_TAG}
                    """)
                ]
            }
        }
        
        stage('Deploy Services') {
            steps {
                build job: 'Infrastructure/Dynamic-Ansible-Executor', parameters: [
                    text(name: 'TARGET_HOSTS', value: env.DEPLOYMENT_HOSTS),
                    string(name: 'ANSIBLE_ROLE', value: 'monitoring'),
                    text(name: 'ANSIBLE_EXTRA_VARS', value: """
                        deployment_environment: ${env.DEPLOYMENT_ENV}
                        service_version: ${env.BUILD_TAG}
                    """)
                ]
            }
        }
    }
}
```

### 2. Infrastructure as Code
```groovy
// Terraform + Ansible integration
stage('Provision and Configure') {
    steps {
        // Provision infrastructure with Terraform
        sh 'terraform apply -auto-approve'
        
        script {
            // Get provisioned host IPs
            def hostIPs = sh(
                script: 'terraform output -json server_ips | jq -r ".[]" | tr "\\n" "\\n"',
                returnStdout: true
            ).trim()
            
            // Configure hosts with Ansible
            build job: 'Infrastructure/Dynamic-Ansible-Executor', parameters: [
                text(name: 'TARGET_HOSTS', value: hostIPs),
                string(name: 'ANSIBLE_ROLE', value: 'common'),
                text(name: 'ANSIBLE_EXTRA_VARS', value: """
                    provisioner: "terraform"
                    provision_timestamp: "${new Date()}"
                """)
            ]
        }
    }
}
```

### 3. Disaster Recovery
```groovy
stage('Emergency Rebuild') {
    when {
        expression { params.DISASTER_RECOVERY_MODE }
    }
    steps {
        parallel {
            stage('Rebuild Jenkins Images') {
                steps {
                    build job: 'Infrastructure/Dynamic-Ansible-Executor', parameters: [
                        text(name: 'TARGET_HOSTS', value: env.DR_BUILD_HOSTS),
                        string(name: 'ANSIBLE_ROLE', value: 'jenkins-images')
                    ]
                }
            }
            
            stage('Restore Monitoring') {
                steps {
                    build job: 'Infrastructure/Dynamic-Ansible-Executor', parameters: [
                        text(name: 'TARGET_HOSTS', value: env.DR_MONITOR_HOSTS),  
                        string(name: 'ANSIBLE_ROLE', value: 'monitoring')
                    ]
                }
            }
        }
    }
}
```

## Best Practices

### 1. **Start Small**
- Test with one host before scaling to multiple hosts
- Use dry-run mode for initial testing
- Validate connectivity before full deployment

### 2. **Resource Management**
- Monitor Jenkins master resource usage during parallel execution
- Implement agent timeout policies
- Clean up agents regularly

### 3. **Error Handling**
- Implement retry logic for transient failures
- Use sequential mode for critical deployments
- Collect artifacts for debugging

### 4. **Documentation**
- Document host-specific requirements  
- Maintain inventory of dynamic agent capabilities
- Track Ansible role dependencies

### 5. **Monitoring**
- Set up alerts for agent provisioning failures
- Monitor execution times and resource usage
- Track success/failure rates across hosts

This dynamic agent approach provides a powerful and scalable way to execute Ansible on remote hosts, giving you distributed execution capabilities while maintaining centralized control through Jenkins.