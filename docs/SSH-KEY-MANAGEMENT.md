# SSH Key Management Guide

## Overview

This guide explains how to use the Jenkins SSH Key Exchange pipeline job to securely distribute Jenkins SSH public keys to remote hosts for passwordless authentication.

## SSH Key Exchange Job

### Purpose
The SSH Key Exchange job automates the process of distributing Jenkins master SSH public keys to remote hosts, enabling passwordless authentication for:
- Application deployments
- Infrastructure automation
- Remote server management
- Backup operations
- Monitoring agent installation

### Job Location
- **Job Name**: `Infrastructure/SSH-Key-Exchange`  
- **Job DSL Script**: `jenkins-dsl/infrastructure/ssh-key-exchange.groovy`

## Prerequisites

### 1. Jenkins Credentials Setup

#### SSH Private Key Credential
Create an SSH private key credential in Jenkins:

1. Navigate to **Manage Jenkins** → **Manage Credentials**
2. Select appropriate domain (usually "Global")
3. Click **Add Credentials**
4. Choose **SSH Username with private key**
5. Configure:
   - **ID**: `jenkins-ssh-key` (or custom ID)
   - **Description**: `Jenkins Master SSH Key`
   - **Username**: `jenkins` (or appropriate user)
   - **Private Key**: Enter directly or from file
   - **Passphrase**: If key is encrypted

#### Username/Password Credential (Optional)
For initial authentication to hosts that don't have Jenkins keys yet:

1. Add **Username with password** credential
2. Configure:
   - **ID**: `remote-host-password`
   - **Username**: Target host username (e.g., `root`)
   - **Password**: Target host password

### 2. Required Tools on Jenkins Agent

Ensure the following tools are available on Jenkins agents:
```bash
# SSH client tools
ssh
ssh-keygen
sshpass  # For password-based authentication

# Network tools  
curl
netcat (nc) or similar connectivity testing tools
```

## Using the SSH Key Exchange Job

### Step 1: Test Connectivity (Recommended)

Before running the SSH Key Exchange job, use the **SSH Connectivity Test** job:

1. Navigate to `Infrastructure/SSH-Connectivity-Test`
2. Configure parameters:
   - **TARGET_HOSTS**: `192.168.1.10,192.168.1.11,server1.example.com`
   - **SSH_USERNAME**: `root`
   - **SSH_PORT**: `22`
   - **TEST_METHOD**: `both` or `password_only`
   - **SSH_PRIVATE_KEY_ID**: `jenkins-ssh-key`
   - **TARGET_HOST_PASSWORD**: `remote-host-password`
3. Click **Build with Parameters**

### Step 2: Run SSH Key Exchange

1. Navigate to `Infrastructure/SSH-Key-Exchange`
2. Configure parameters:

#### Required Parameters
- **TARGET_HOSTS**: Comma-separated list of target IPs/hostnames
  ```
  192.168.1.10,192.168.1.11,server1.example.com
  ```
- **SSH_USERNAME**: Username for SSH connections (default: `root`)
- **SSH_PRIVATE_KEY_ID**: Jenkins credential ID (default: `jenkins-ssh-key`)

#### Authentication Parameters
- **TARGET_HOST_PASSWORD**: Password credential for initial auth
- **AUTH_METHOD**: Choose authentication method:
  - `password`: Use password authentication only
  - `existing_key`: Use existing SSH key authentication  
  - `both`: Try existing key first, fallback to password

#### Optional Parameters
- **SSH_PORT**: SSH port on target hosts (default: `22`)
- **VALIDATE_CONNECTIVITY**: Test before and after deployment (default: `true`)
- **BACKUP_AUTHORIZED_KEYS**: Backup existing keys (default: `true`)
- **DRY_RUN**: Test without making changes (default: `false`)
- **EXECUTION_MODE**: Process hosts in `parallel` or `sequential`

3. Click **Build with Parameters**

### Step 3: Verify Results

The job will provide detailed output including:
- Connectivity test results
- Public key deployment status
- Post-deployment verification
- Generated reports in build artifacts

## Example Scenarios

### Scenario 1: New Infrastructure Setup

Setting up SSH keys for a new set of servers:

```yaml
TARGET_HOSTS: "10.0.1.10,10.0.1.11,10.0.1.12"
SSH_USERNAME: "root"
AUTH_METHOD: "password"
TARGET_HOST_PASSWORD: "server-root-password"
VALIDATE_CONNECTIVITY: true
BACKUP_AUTHORIZED_KEYS: true
DRY_RUN: false
EXECUTION_MODE: "parallel"
```

### Scenario 2: Adding New Server to Existing Infrastructure

Adding a new server to an existing Jenkins-managed infrastructure:

```yaml
TARGET_HOSTS: "10.0.1.20"
SSH_USERNAME: "ubuntu"
AUTH_METHOD: "password"
TARGET_HOST_PASSWORD: "ubuntu-server-password"  
VALIDATE_CONNECTIVITY: true
BACKUP_AUTHORIZED_KEYS: true
DRY_RUN: false
```

### Scenario 3: Key Rotation/Update

Updating SSH keys on existing infrastructure:

```yaml
TARGET_HOSTS: "server1.example.com,server2.example.com"
SSH_USERNAME: "jenkins"
AUTH_METHOD: "existing_key"
SSH_PRIVATE_KEY_ID: "new-jenkins-ssh-key"
VALIDATE_CONNECTIVITY: true
BACKUP_AUTHORIZED_KEYS: true
```

## Security Best Practices

### 1. Credential Management
- Store all credentials in Jenkins credential store
- Use descriptive credential IDs
- Regularly rotate SSH keys and passwords
- Limit credential scope to necessary jobs

### 2. Network Security
- Run SSH key exchange from trusted networks
- Use VPN for remote server access
- Configure firewall rules appropriately
- Monitor SSH access logs

### 3. Key Management
- Generate strong SSH keys (RSA 4096-bit or Ed25519)
- Use unique keys for different environments (dev/staging/prod)
- Implement key rotation schedules
- Monitor unauthorized key usage

### 4. Access Control
- Limit Jenkins job execution permissions
- Use separate credentials for different environments
- Implement approval processes for production key deployments
- Log all key exchange activities

## Troubleshooting

### Common Issues

#### 1. Connection Timeout
```
Error: ssh: connect to host 192.168.1.10 port 22: Connection timed out
```
**Solutions**:
- Verify host IP/hostname is correct
- Check network connectivity
- Verify SSH service is running on target port
- Check firewall rules

#### 2. Authentication Failed
```
Error: Permission denied (publickey,password)
```
**Solutions**:
- Verify username is correct
- Check password credentials
- Ensure SSH service allows password authentication
- Verify user account exists and is not locked

#### 3. Key Already Exists
```
Output: Public key already exists in authorized_keys
```
**Solutions**:
- This is normal behavior - key deployment is idempotent
- Check if key verification passes
- Consider key rotation if using old keys

#### 4. Insufficient Permissions
```
Error: /home/user/.ssh/authorized_keys: Permission denied
```
**Solutions**:
- Verify user has write permissions to ~/.ssh/
- Check if filesystem is read-only
- Ensure correct SSH directory permissions (700)

### Debugging Steps

1. **Test Connectivity First**:
   ```bash
   # Manual SSH test
   ssh -o ConnectTimeout=10 user@hostname 'echo "Connection successful"'
   ```

2. **Check SSH Configuration**:
   ```bash
   # View SSH server configuration
   sudo sshd -T | grep -E "(PasswordAuthentication|PubkeyAuthentication|PermitRootLogin)"
   ```

3. **Verify Key Format**:
   ```bash
   # Validate public key format
   ssh-keygen -lf /path/to/public/key
   ```

4. **Check Logs**:
   ```bash
   # SSH server logs
   sudo tail -f /var/log/auth.log
   # or
   sudo journalctl -f -u ssh
   ```

## Integration with Other Jobs

### 1. Infrastructure Deployment Pipelines
Use SSH Key Exchange as a prerequisite step:

```groovy
pipeline {
    stages {
        stage('Setup SSH Access') {
            steps {
                build job: 'Infrastructure/SSH-Key-Exchange', parameters: [
                    string(name: 'TARGET_HOSTS', value: env.DEPLOYMENT_HOSTS),
                    string(name: 'SSH_USERNAME', value: 'deploy')
                ]
            }
        }
        
        stage('Deploy Application') {
            steps {
                // Application deployment steps using SSH key auth
            }
        }
    }
}
```

### 2. Dynamic Infrastructure Provisioning
Include in infrastructure provisioning workflows:

```groovy
stage('Provision Infrastructure') {
    steps {
        // Terraform/Ansible infrastructure provisioning
        sh 'terraform apply -auto-approve'
        
        // Extract host IPs from Terraform output
        script {
            def hostIPs = sh(
                script: 'terraform output -json server_ips | jq -r ".[]" | tr "\\n" ","',
                returnStdout: true
            ).trim()
            
            // Setup SSH keys on new infrastructure
            build job: 'Infrastructure/SSH-Key-Exchange', parameters: [
                string(name: 'TARGET_HOSTS', value: hostIPs),
                string(name: 'AUTH_METHOD', value: 'password')
            ]
        }
    }
}
```

### 3. Disaster Recovery Procedures
Include in DR runbooks:

```groovy
stage('Restore SSH Access') {
    when { 
        expression { params.DISASTER_RECOVERY_MODE }
    }
    steps {
        build job: 'Infrastructure/SSH-Key-Exchange', parameters: [
            string(name: 'TARGET_HOSTS', value: env.DR_HOSTS),
            string(name: 'SSH_PRIVATE_KEY_ID', value: 'dr-jenkins-ssh-key')
        ]
    }
}
```

## Monitoring and Alerting

### 1. Job Monitoring
- Set up build notifications for SSH Key Exchange failures
- Monitor job execution frequency and success rates
- Alert on consecutive failures

### 2. SSH Access Monitoring
- Monitor unauthorized SSH key additions
- Track SSH key usage patterns
- Alert on suspicious SSH activity

### 3. Compliance Reporting
- Generate periodic reports of SSH key deployments
- Track key rotation compliance
- Audit SSH access across infrastructure

## Related Documentation

- [Jenkins Credential Management](https://www.jenkins.io/doc/book/using/using-credentials/)
- [SSH Key Authentication Best Practices](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [Infrastructure Automation with Jenkins](./INFRASTRUCTURE-AUTOMATION.md)
- [Blue-Green Deployment Guide](./BLUE-GREEN-DEPLOYMENT.md)