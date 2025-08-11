# Job DSL Management

This document describes the Job DSL (Domain Specific Language) management system implemented in the Jenkins HA infrastructure for automated job creation and pipeline management.

## Table of Contents

- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Job DSL Seed Pipeline](#job-dsl-seed-pipeline)
- [Job Organization](#job-organization)
- [Creating New Jobs](#creating-new-jobs)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

The Job DSL system provides automated job creation and management through code, eliminating the need for manual job configuration through the Jenkins UI.

### Key Benefits

- **Infrastructure as Code**: All jobs defined in version-controlled Groovy scripts
- **Consistency**: Standardized job configurations across teams
- **Scalability**: Easy to create multiple similar jobs
- **Maintainability**: Centralized job definitions and easy updates
- **Team Isolation**: Separate job categories for different teams

## Directory Structure

The Job DSL scripts are organized in the `jenkins-dsl/` directory:

```
jenkins-dsl/
├── folders.groovy                     # Folder definitions
├── views.groovy                       # View definitions
├── infrastructure/                    # Infrastructure pipeline jobs
│   ├── image-builder.groovy          # Image building pipeline
│   ├── backup-pipeline.groovy        # Backup automation
│   ├── infrastructure-update.groovy  # Infrastructure updates
│   ├── monitoring-setup.groovy       # Monitoring stack
│   ├── security-scan.groovy          # Security scanning
│   ├── health-check.groovy           # Health monitoring
│   └── disaster-recovery.groovy      # Disaster recovery
└── applications/                     # Application build jobs
    ├── maven-build-sample.groovy     # Java/Maven builds
    ├── python-build-sample.groovy    # Python applications
    └── freestyle-sample.groovy       # Freestyle job examples
```

### File Organization Principles

1. **Separation by Type**: Infrastructure vs. Application jobs
2. **One Job Per File**: Each `.groovy` file creates one job
3. **Descriptive Names**: File names match job names
4. **Logical Grouping**: Related scripts in same directory

## Job DSL Seed Pipeline

The Job DSL Seed Pipeline (`Infrastructure/Job-DSL-Seed`) is responsible for processing all Job DSL scripts and creating/updating Jenkins jobs.

### Seed Pipeline Configuration

```yaml
# JCasC Configuration
pipeline:
  agent:
    label: 'python'  # Runs on dynamic python-agent
  
  parameters:
    - DSL_SCRIPTS_PATH: 'jenkins-dsl/**/*.groovy'
    - SEED_ACTION: ['generate-all', 'update-existing', 'dry-run', 'cleanup-orphaned']
    - VALIDATE_SCRIPTS: true
    - REMOVE_DISABLED: false
  
  triggers:
    - scm: 'H/15 * * * *'  # Poll SCM every 15 minutes
```

### Seed Pipeline Execution

1. **Script Discovery**: Finds all `.groovy` files matching `jenkins-dsl/**/*.groovy`
2. **Validation**: Syntax checking and content validation
3. **Job DSL Processing**: Executes Job DSL scripts to create/update jobs
4. **Cleanup**: Optionally removes orphaned jobs
5. **Verification**: Post-processing verification and reporting

### Manual Seed Job Execution

```bash
# Trigger seed job manually
curl -X POST http://jenkins-url:8080/job/Infrastructure/job/Job-DSL-Seed/build \
  --user admin:token \
  --data-urlencode json='{"parameter": [{"name":"SEED_ACTION", "value":"generate-all"}]}'

# Dry run to preview changes
curl -X POST http://jenkins-url:8080/job/Infrastructure/job/Job-DSL-Seed/build \
  --user admin:token \
  --data-urlencode json='{"parameter": [{"name":"SEED_ACTION", "value":"dry-run"}]}'
```

## Job Organization

### Infrastructure Jobs

Infrastructure jobs are located in `jenkins-dsl/infrastructure/` and reference pipeline scripts in `pipelines/`:

```groovy
// Example: jenkins-dsl/infrastructure/backup-pipeline.groovy
pipelineJob('Infrastructure/Backup-Pipeline') {
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(JENKINS_INFRASTRUCTURE_REPO_URL ?: 'https://github.com/company/jenkins-ha.git')
                        credentials(GIT_CREDENTIALS_ID ?: 'git-credentials')
                    }
                    branch('*/main')
                }
            }
            scriptPath('pipelines/Jenkinsfile.backup')  // References actual pipeline script
            lightweight(true)
        }
    }
}
```

### Application Jobs

Application jobs demonstrate dynamic agent usage and serve as templates:

```groovy
// Example: jenkins-dsl/applications/python-build-sample.groovy
pipelineJob('Applications/Python-Build-Sample') {
    definition {
        cps {
            script('''
                pipeline {
                    agent {
                        label 'python'  // Runs on dynamic python-agent
                    }
                    
                    stages {
                        stage('Build') {
                            steps {
                                echo "Building on python agent: ${env.NODE_NAME}"
                            }
                        }
                    }
                }
            ''')
            sandbox(true)
        }
    }
}
```

### Folders and Views

Organizational elements are defined in root-level files:

```groovy
// folders.groovy - Creates folder structure
folder('Infrastructure') {
    displayName('Infrastructure Management')
    description('Jobs for managing Jenkins infrastructure')
}

folder('Applications') {
    displayName('Application Jobs')
    description('Jobs for building and deploying applications')
}
```

```groovy
// views.groovy - Creates job views
listView('Infrastructure/Pipeline Jobs') {
    jobs {
        name('Infrastructure/Image-Builder')
        name('Infrastructure/Backup-Pipeline')
        // ... other jobs
    }
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
    }
}
```

## Creating New Jobs

### Step 1: Choose the Right Directory

- **Infrastructure jobs**: `jenkins-dsl/infrastructure/`
- **Application jobs**: `jenkins-dsl/applications/`
- **Team-specific jobs**: Create new subdirectory if needed

### Step 2: Create Job DSL Script

Create a new `.groovy` file with descriptive name:

```groovy
// jenkins-dsl/applications/nodejs-build-sample.groovy
pipelineJob('Applications/NodeJS-Build-Sample') {
    displayName('Node.js Build Sample')
    description('''
        Sample Node.js build pipeline that demonstrates:
        - NPM dependency installation
        - Unit tests with Jest
        - Docker image creation
        - Runs on dynamic nodejs-agent
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('30')
                    numToKeepStr('20')
                }
            }
        }
        
        parameters {
            choiceParam {
                name('NODE_VERSION')
                description('Node.js version to use')
                choices(['18', '20', '21'])
            }
            booleanParam {
                name('RUN_TESTS')
                description('Run unit tests')
                defaultValue(true)
            }
        }
    }
    
    definition {
        cps {
            script('''
                pipeline {
                    agent {
                        label 'nodejs'  // Runs on dynamic nodejs-agent
                    }
                    
                    options {
                        timeout(time: 30, unit: 'MINUTES')
                    }
                    
                    environment {
                        NPM_CACHE_DIR = '/home/jenkins/.cache/npm'
                    }
                    
                    stages {
                        stage('Setup') {
                            steps {
                                echo "Node.js version: \\$(node --version)"
                                echo "NPM version: \\$(npm --version)"
                            }
                        }
                        
                        stage('Install Dependencies') {
                            steps {
                                sh 'npm ci'
                            }
                        }
                        
                        stage('Run Tests') {
                            when {
                                expression { params.RUN_TESTS == true }
                            }
                            steps {
                                sh 'npm test'
                            }
                        }
                        
                        stage('Build') {
                            steps {
                                sh 'npm run build'
                            }
                        }
                    }
                    
                    post {
                        always {
                            echo "Build completed on nodejs agent: ${env.NODE_NAME}"
                        }
                        cleanup {
                            cleanWs()
                        }
                    }
                }
            ''')
            sandbox(true)
        }
    }
}

println "Node.js Build Sample job created successfully"
```

### Step 3: Update Views (Optional)

If creating a new job category, update `views.groovy`:

```groovy
// Add to existing view
listView('Applications/Sample Jobs') {
    jobs {
        name('Applications/Maven-Build-Sample')
        name('Applications/Python-Build-Sample')
        name('Applications/NodeJS-Build-Sample')  // Add new job
        name('Applications/Freestyle-Sample')
    }
}

// Or create new view
listView('Applications/Node.js Jobs') {
    displayName('Node.js Build Jobs')
    description('View for Node.js application builds')
    jobs {
        regex('.*[Nn]ode.*')
    }
}
```

### Step 4: Test and Deploy

1. **Commit Changes**:
   ```bash
   git add jenkins-dsl/applications/nodejs-build-sample.groovy
   git commit -m "Add Node.js build sample job"
   git push origin main
   ```

2. **Run Seed Job**:
   - Access Jenkins UI
   - Navigate to `Infrastructure/Job-DSL-Seed`
   - Click "Build with Parameters"
   - Select "generate-all" or "update-existing"
   - Click "Build"

3. **Verify Creation**:
   - Check that `Applications/NodeJS-Build-Sample` job appears
   - Verify job configuration
   - Test job execution

## Best Practices

### Script Organization

1. **One Job Per File**: Keep each job definition in its own file
2. **Descriptive Names**: File names should match job names
3. **Logical Grouping**: Group related jobs in subdirectories
4. **Consistent Naming**: Follow naming conventions (e.g., `team-purpose.groovy`)

### Job Configuration

1. **Use Parameters**: Make jobs configurable with parameters
2. **Set Build Retention**: Always configure build discarder
3. **Add Descriptions**: Provide clear job descriptions
4. **Include Cleanup**: Add post-build cleanup steps
5. **Specify Timeouts**: Set reasonable execution timeouts

### Dynamic Agent Usage

1. **Specify Labels**: Always specify agent labels for dynamic agents
2. **Use Appropriate Agents**: Match agent type to job requirements
   - `maven` for Java builds
   - `python` for Python applications
   - `nodejs` for Node.js applications
   - `dind` for Docker operations

3. **Cache Dependencies**: Leverage persistent caches
   - Maven: `/home/jenkins/.m2`
   - Python: `/home/jenkins/.cache/pip`
   - Node.js: `/home/jenkins/.cache/npm`

### Security Considerations

1. **Use Sandbox Mode**: Enable sandbox for pipeline scripts
2. **Validate Inputs**: Validate all user inputs and parameters
3. **Limit Permissions**: Use least privilege principle
4. **Secure Credentials**: Use Jenkins credential management
5. **Audit Changes**: Track all DSL script changes

### Pipeline References

When referencing external pipeline scripts:

```groovy
// ✅ Good: Reference existing pipeline script
definition {
    cpsScm {
        scm {
            git {
                remote {
                    url(JENKINS_INFRASTRUCTURE_REPO_URL)
                    credentials(GIT_CREDENTIALS_ID)
                }
                branch('*/main')
            }
        }
        scriptPath('pipelines/Jenkinsfile.my-pipeline')
        lightweight(true)
    }
}

// ❌ Avoid: Large inline pipeline scripts in DSL
definition {
    cps {
        script('''
            // Hundreds of lines of pipeline code...
        ''')
    }
}
```

## Troubleshooting

### Common Issues

#### 1. Job DSL Script Errors

**Symptom**: Seed job fails with script errors

**Diagnosis**:
```bash
# Check seed job console output
curl -s "http://jenkins-url:8080/job/Infrastructure/job/Job-DSL-Seed/lastBuild/consoleText"

# Validate script syntax locally
groovy -cp jenkins-dsl-core.jar jenkins-dsl/applications/my-job.groovy
```

**Resolution**:
- Fix syntax errors in DSL script
- Check for missing required parameters
- Validate Groovy syntax and Job DSL API usage

#### 2. Jobs Not Created

**Symptom**: DSL script runs without errors but jobs don't appear

**Diagnosis**:
```bash
# Check if files are found
echo "Files matched by pattern:"
find jenkins-dsl -name "*.groovy" -type f

# Verify seed job configuration
curl -s "http://jenkins-url:8080/job/Infrastructure/job/Job-DSL-Seed/config.xml"
```

**Resolution**:
- Verify DSL_SCRIPTS_PATH parameter
- Check file permissions and Git checkout
- Ensure job names don't conflict with existing jobs

#### 3. Permission Errors

**Symptom**: "User lacks permission" errors during job creation

**Diagnosis**:
```bash
# Check user permissions
curl -s -u admin:token "http://jenkins-url:8080/me/api/json" | jq .authorities

# Verify Job DSL security configuration
curl -s -u admin:token "http://jenkins-url:8080/configure"
```

**Resolution**:
- Grant appropriate permissions to seed job user
- Configure Job DSL security settings
- Use service account with sufficient privileges

#### 4. Script Approval Issues

**Symptom**: Scripts require administrative approval

**Diagnosis**:
```bash
# Check pending script approvals
curl -s -u admin:token "http://jenkins-url:8080/scriptApproval/" | grep pending
```

**Resolution**:
- Approve pending scripts in Jenkins UI
- Use sandbox mode for pipeline scripts
- Configure script approval policies

### Debugging Commands

```bash
# List all Job DSL scripts
find jenkins-dsl -name "*.groovy" -type f | sort

# Validate Groovy syntax
for script in jenkins-dsl/**/*.groovy; do
    echo "Checking $script"
    groovy -cp lib/job-dsl-core.jar "$script"
done

# Check seed job status
curl -s "http://jenkins-url:8080/job/Infrastructure/job/Job-DSL-Seed/api/json" | jq .lastBuild.result

# View recent seed job builds
curl -s "http://jenkins-url:8080/job/Infrastructure/job/Job-DSL-Seed/api/json" | jq .builds[0:5]

# Check Jenkins logs for DSL-related errors
tail -f /var/log/jenkins/jenkins.log | grep -i "job-dsl\|seed"
```

### Performance Optimization

1. **Incremental Processing**: Use "update-existing" for faster processing
2. **Parallel Execution**: Process independent job categories in parallel
3. **Lightweight Checkouts**: Use lightweight Git checkouts when possible
4. **Caching**: Cache dependencies and build tools
5. **Resource Limits**: Set appropriate memory and CPU limits

## Migration Guide

### From Manual Jobs to Job DSL

1. **Export Existing Configuration**:
   ```bash
   # Get job XML configuration
   curl -s "http://jenkins-url:8080/job/MyJob/config.xml" > my-job.xml
   ```

2. **Convert to Job DSL**:
   ```groovy
   // Analyze XML and create equivalent DSL
   pipelineJob('MyJob') {
       // Convert XML configuration to DSL syntax
   }
   ```

3. **Test and Validate**:
   ```bash
   # Create test job with DSL
   # Compare with original configuration
   # Verify functionality
   ```

4. **Deploy and Cleanup**:
   ```bash
   # Deploy via seed job
   # Verify new job works correctly
   # Remove old manual job
   ```

### Version Control Integration

```bash
# Git hooks for validation
# .git/hooks/pre-commit
#!/bin/bash
echo "Validating Job DSL scripts..."
for script in jenkins-dsl/**/*.groovy; do
    if ! groovy -cp lib/job-dsl-core.jar "$script"; then
        echo "❌ Script validation failed: $script"
        exit 1
    fi
done
echo "✅ All scripts validated"
```

---

For additional information, see:
- [Jenkins Job DSL API Reference](https://jenkinsci.github.io/job-dsl-plugin/)
- [Pipeline Syntax](docs/PIPELINE-SYNTAX.md)
- [Dynamic Agent Management](docs/DYNAMIC-AGENTS.md)
- [Security Configuration](docs/SECURITY.md)