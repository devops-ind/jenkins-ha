# Jenkins Configuration as Code (JCasC) Migration

This document describes the migration from manual job creation to Jenkins Configuration as Code (JCasC) for the Jenkins HA infrastructure.

## Overview

The Jenkins infrastructure has been migrated from using manual job creation with Groovy scripts to using Jenkins Configuration as Code (JCasC). This provides several benefits:

- **Version Control**: All Jenkins configuration is stored in version-controlled YAML files
- **Reproducibility**: Jenkins instances can be recreated with identical configuration
- **Automation**: Configuration changes are applied automatically on Jenkins startup
- **Consistency**: All environments use the same configuration management approach

## JCasC Configuration Files

### Main Configuration
- **Location**: `ansible/roles/jenkins-master/templates/jcasc/jenkins-config.yml.j2`
- **Purpose**: Contains Jenkins system configuration, security settings, credentials, tools, and plugins

### Jobs Configuration
- **Location**: `ansible/roles/jenkins-master/templates/jcasc/jenkins-jobs.yml.j2`
- **Purpose**: Defines all Jenkins jobs using Job DSL syntax within JCasC

## Migrated Jobs

The following infrastructure jobs have been migrated to JCasC:

### Infrastructure Folder Jobs

1. **Infrastructure/Image-Builder**
   - Builds and pushes Jenkins Docker images to Harbor registry
   - Scheduled: Weekly on Sunday at 1 AM
   - Parameters: Force rebuild, push to Harbor, image tag, images to build

2. **Infrastructure/Backup-Pipeline**
   - Automated backup operations and verification
   - Scheduled: Configurable (default: daily at 2 AM weekdays)
   - Parameters: Backup type, verification, cleanup, custom tag

3. **Infrastructure/Infrastructure-Update**
   - Self-updating Jenkins infrastructure
   - Manual trigger with parameters
   - Parameters: Image tag, restart services, update reason, scope

4. **Infrastructure/Monitoring-Setup**
   - Monitoring stack setup and configuration
   - Manual trigger
   - Parameters: Monitoring action, restart services, validate metrics

5. **Infrastructure/Security-Scan**
   - Security scanning and compliance checks
   - Scheduled: Weekly on Monday at 3 AM
   - Parameters: Scan type, fail on high severity, generate reports

6. **Infrastructure/Health-Check**
   - Comprehensive infrastructure health monitoring
   - Scheduled: Every 15 minutes
   - Parameters: Check scope, detailed reporting, send alerts

## Configuration Structure

### Jenkins System Configuration
```yaml
jenkins:
  systemMessage: "Jenkins HA Infrastructure managed by JCasC"
  numExecutors: 2
  mode: EXCLUSIVE
  securityRealm: # Local user database
  authorizationStrategy: # Matrix-based security
  clouds: # Docker cloud configuration for agents
```

### Credentials Management
```yaml
credentials:
  system:
    domainCredentials:
      - credentials:
          - usernamePassword: # Harbor registry
          - usernamePassword: # Git repository
          - string: # Slack webhook
          - string: # Borg backup passphrase (if enabled)
```

### Agent Configuration
Docker cloud agents are defined with labels:
- `dind docker-manager static privileged` - Docker-in-Docker agent
- `maven java-build static` - Maven build agent
- `python python-build static` - Python build agent
- `nodejs frontend-build static` - Node.js build agent

## Deployment Process

### Ansible Integration
The JCasC configuration is deployed via Ansible:

1. **Configuration Generation**: Ansible templates generate JCasC YAML files with environment-specific variables
2. **File Deployment**: JCasC files are placed in `$JENKINS_HOME/casc_configs/`
3. **Environment Setup**: Jenkins container is configured with `CASC_JENKINS_CONFIG` environment variable
4. **Service Restart**: Jenkins service is restarted to load new configuration

### Environment Variables
The systemd service includes:
```bash
CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs
JENKINS_HOME=/var/jenkins_home
HARBOR_REGISTRY_URL=<registry-url>
HARBOR_PROJECT_NAME=<project-name>
```

## Pipeline Integration

### Jenkinsfile Location
Pipeline scripts are stored in the `pipelines/` directory:
- `pipelines/Jenkinsfile.image-builder`
- `pipelines/Jenkinsfile.backup`
- `pipelines/Jenkinsfile.infrastructure-update`
- `pipelines/Jenkinsfile.monitoring`
- `pipelines/Jenkinsfile.security-scan`
- `pipelines/Jenkinsfile.health-check`

### SCM Integration
Jobs are configured to pull pipeline scripts from the Git repository:
```yaml
definition:
  cpsScm:
    scm:
      git:
        remote:
          url: '{{ jenkins_infrastructure_repo_url }}'
          credentials: '{{ git_credentials_id }}'
        branch: '*/main'
    scriptPath: 'pipelines/Jenkinsfile.image-builder'
```

## Management Operations

### Configuration Updates
1. **Modify JCasC templates** in `ansible/roles/jenkins-master/templates/jcasc/`
2. **Run Ansible playbook** to deploy updated configuration
3. **Jenkins automatically reloads** configuration on next restart

### Manual Configuration Reload
Access the JCasC management interface:
- **Web UI**: `http://jenkins:8080/configuration-as-code/`
- **Reload**: `http://jenkins:8080/configuration-as-code/reload`

### Validation
```bash
# Test JCasC configuration syntax
ansible-playbook ansible/site.yml --tags jenkins,deploy --check

# Validate specific environment
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags jenkins --check
```

## Migration Benefits

### Before (Manual Job Creation)
- Job definitions in XML format
- Manual job creation via Jenkins CLI
- Groovy scripts for complex job setup
- Error-prone job organization and folder creation

### After (JCasC)
- Declarative YAML configuration
- Automatic job creation on Jenkins startup
- Version-controlled configuration
- Consistent job organization via code

## Troubleshooting

### Common Issues

1. **JCasC Plugin Missing**
   - Ensure `configuration-as-code` plugin is installed
   - Check `plugins.txt.j2` includes required plugins

2. **Configuration Not Loading**
   - Verify `CASC_JENKINS_CONFIG` environment variable
   - Check Jenkins logs for JCasC errors
   - Validate YAML syntax

3. **Credentials Not Working**
   - Ensure credential IDs match between JCasC and job references
   - Verify vault variables are properly decrypted

4. **Job Creation Failures**
   - Check Job DSL plugin is installed
   - Verify pipeline script paths exist in repository
   - Review Jenkins system logs

### Log Locations
- **Jenkins Logs**: `$JENKINS_HOME/logs/jenkins.log`
- **JCasC Logs**: Available in Jenkins system logs
- **Ansible Logs**: `ansible/logs/ansible.log`

## Security Considerations

### Secrets Management
- All sensitive data stored in Ansible Vault
- JCasC references vault variables for credentials
- Environment variables used for non-sensitive configuration

### Access Control
- Matrix-based authorization strategy
- Admin user created via JCasC
- Agent-based permissions for build operations

## Future Enhancements

1. **Environment-Specific Configurations**
   - Separate JCasC files for production/staging
   - Environment-specific job parameters

2. **Plugin Management**
   - Automated plugin updates via JCasC
   - Plugin version pinning for stability

3. **Advanced Job DSL**
   - Shared job templates
   - Dynamic job generation based on repository structure

4. **Integration Testing**
   - Automated JCasC configuration validation
   - Test environments for configuration changes