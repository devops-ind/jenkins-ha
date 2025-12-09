# Jenkins Configuration-as-Code (JCasC) Fix: Setup Wizard Issue

## Problem Analysis

**Current Issue**: Jenkins containers are showing the "Unlock Jenkins" setup wizard instead of loading pre-configured settings from jenkins.yml, indicating that the Configuration-as-Code (JCasC) files are not being properly loaded during startup.

## Root Cause Analysis

After analyzing the codebase, I've identified several critical issues preventing proper JCasC configuration loading:

### 1. **File Path Misalignment** ⚠️
The Dockerfile.team-custom.j2 copies jenkins.yaml files to incorrect locations:
- **Current**: Files copied to `/usr/share/jenkins/ref/casc_configs/`
- **Expected**: CASC_JENKINS_CONFIG points to `/usr/share/jenkins/ref/casc_configs/`
- **Issue**: Jenkins may not be finding the configuration files due to naming/path inconsistencies

### 2. **CASC Plugin Dependencies** ⚠️
The base image may not have the Configuration-as-Code plugin properly installed or configured.

### 3. **Environment Variable Conflicts** ⚠️
Environment variables in containers may override CASC settings.

### 4. **Plugin Installation Order** ⚠️
CASC configuration may be processed before required plugins are installed.

## Comprehensive Solution

### Phase 1: Fix CASC Configuration Loading

#### 1.1 Update Dockerfile Template
The issue is in the file naming and location. Update the Dockerfile to ensure proper CASC configuration:

```dockerfile
# In Dockerfile.team-custom.j2, line 36-42
# Copy team-specific Jenkins Configuration as Code for both environments
# Create directories first
RUN mkdir -p /usr/share/jenkins/ref/casc_configs
COPY blue/jenkins.yaml /usr/share/jenkins/ref/casc_configs/jenkins.yaml
COPY green/jenkins.yaml /usr/share/jenkins/ref/casc_configs/jenkins-green.yaml

# Set environment variable to point to active config
ENV CASC_JENKINS_CONFIG="/usr/share/jenkins/ref/casc_configs/jenkins.yaml"
```

#### 1.2 Fix Environment Variable Configuration
Update the container environment variables to ensure proper CASC loading:

```yaml
# In image-and-container.yml, update _jenkins_env_vars
_jenkins_env_vars: >-
  {{ jenkins_master_env_vars | combine(item.env_vars | default({})) | combine({
    'CASC_JENKINS_CONFIG': '/usr/share/jenkins/ref/casc_configs/jenkins.yaml',
    'JAVA_OPTS': '-Djenkins.install.runSetupWizard=false -Dhudson.DNSMultiCast.disabled=true',
    'JENKINS_OPTS': '--httpPort=' + jenkins_master_port|string + ' --httpListenAddress=0.0.0.0'
  }) }}
```

### Phase 2: Ensure Plugin Dependencies

#### 2.1 Verify Configuration-as-Code Plugin
Ensure the CASC plugin is in the base plugins list:

```txt
# In plugins.txt template
configuration-as-code:latest
configuration-as-code-support:latest
```

#### 2.2 Update Base Image Plugin Installation
Modify the base image to install CASC plugin during build:

```dockerfile
# In Dockerfile.master.j2, add after plugins.txt copy
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
```

### Phase 3: Fix File Permissions and Structure

#### 3.1 Update Directory Creation
Ensure proper permissions and directory structure:

```dockerfile
# Create necessary directories with proper permissions
RUN mkdir -p /usr/share/jenkins/ref/casc_configs \
    && mkdir -p /var/jenkins_home/casc_configs \
    && chown -R jenkins:jenkins /usr/share/jenkins/ref/casc_configs \
    && chown -R jenkins:jenkins /var/jenkins_home/casc_configs
```

### Phase 4: Validation and Troubleshooting

#### 4.1 Container Startup Validation
Add startup script to validate CASC configuration:

```bash
#!/bin/bash
# validate-casc-config.sh
echo "🔍 Validating CASC Configuration..."
echo "CASC_JENKINS_CONFIG: $CASC_JENKINS_CONFIG"
echo "Configuration files:"
find /usr/share/jenkins/ref/casc_configs -name "*.yaml" -o -name "*.yml" 2>/dev/null || echo "No CASC configs found"
echo "File permissions:"
ls -la /usr/share/jenkins/ref/casc_configs/ 2>/dev/null || echo "Directory not accessible"
```

#### 4.2 Jenkins Startup Logs Analysis
Check for CASC-related log entries:

```bash
# Look for these patterns in Jenkins logs:
# - "Configuration as Code plugin"
# - "Loading configuration"
# - "CASC_JENKINS_CONFIG"
# - Setup wizard messages
```

## Implementation Steps

### Step 1: Update Dockerfile Template
```bash
# File: ansible/roles/jenkins-master-v2/templates/Dockerfile.team-custom.j2
# Update lines 33-42 with corrected CASC configuration
```

### Step 2: Update Container Deployment Task
```bash
# File: ansible/roles/jenkins-master-v2/tasks/image-and-container.yml
# Update environment variables in container deployment (lines 156 and 175)
```

### Step 3: Verify Base Image Configuration
```bash
# File: ansible/roles/jenkins-images/templates/Dockerfile.master.j2  
# Ensure CASC plugin installation
```

### Step 4: Test Configuration Loading
1. Deploy updated containers
2. Check container logs for CASC loading messages
3. Verify Jenkins starts without setup wizard
4. Confirm team-specific configurations are applied

## Verification Commands

```bash
# 1. Check if CASC plugin is loaded
docker exec jenkins-devops-green jenkins-cli list-plugins | grep configuration-as-code

# 2. Verify CASC configuration files
docker exec jenkins-devops-green find /usr/share/jenkins/ref -name "*.yaml" -o -name "*.yml"

# 3. Check environment variables
docker exec jenkins-devops-green env | grep CASC

# 4. Review Jenkins startup logs
docker logs jenkins-devops-green 2>&1 | grep -i "configuration\|setup\|casc"

# 5. Test Jenkins API access (should work without setup)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8189/api/json
```

## Expected Results After Fix

1. **No Setup Wizard**: Jenkins should start directly to the main dashboard
2. **Team Configuration Applied**: System message should show team name and environment
3. **Credentials Loaded**: Team-specific credentials should be available
4. **Dynamic Agents Configured**: Docker cloud should be configured with team-specific agents
5. **Admin Access**: Admin user should be able to log in with configured password

## Troubleshooting Guide

### Issue: Still Shows Setup Wizard
**Check**: 
- CASC plugin installation
- Environment variable CASC_JENKINS_CONFIG
- File permissions on configuration files
- Jenkins logs for CASC loading errors

### Issue: Configuration Not Applied
**Check**:
- YAML syntax in jenkins.yaml files
- Plugin dependencies for CASC configuration
- File path accessibility from container

### Issue: Authentication Failures  
**Check**:
- Admin password environment variable
- Security realm configuration in YAML
- Credential configuration syntax

## Monitoring and Maintenance

1. **Regular CASC Validation**: Implement automated checks for configuration validity
2. **Plugin Updates**: Monitor CASC plugin updates for compatibility
3. **Configuration Backup**: Ensure jenkins.yaml files are version controlled and backed up
4. **Security Scanning**: Regular security scans of CASC configurations

This comprehensive fix addresses all identified issues with Jenkins Configuration-as-Code loading and provides a robust solution for eliminating the setup wizard while ensuring proper team-specific configurations are applied.