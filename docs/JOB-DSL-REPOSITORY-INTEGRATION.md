# Job DSL Repository Integration Guide

## Overview

The Jenkins Job DSL system has been enhanced to use **cpsScm** (Pipeline Script from SCM) integration, providing Git-based job management with automatic synchronization and change detection.

## Architecture

```
Git Repository
├── jenkins-dsl/
│   ├── folders.groovy
│   ├── views.groovy
│   ├── seed-jobs.groovy
│   └── infrastructure/*.groovy
├── pipelines/
│   ├── Jenkinsfile.job-dsl-seed
│   └── Other Jenkinsfiles...
└── Other project files...

Jenkins Jobs:
├── Infrastructure/Job-DSL-Seed (cpsScm)
│   └── Executes: pipelines/Jenkinsfile.job-dsl-seed
└── Infrastructure/Repository-Monitor
    └── Monitors changes → Triggers Job-DSL-Seed
```

## Key Components

### 1. **Job-DSL-Seed Job** (Main Job)
- **Type**: Pipeline job with `cpsScm` definition
- **Location**: `Infrastructure/Job-DSL-Seed`
- **Pipeline Script**: `pipelines/Jenkinsfile.job-dsl-seed`
- **Purpose**: Process Job DSL scripts from Git repository

### 2. **Repository-Monitor Job** (Helper Job)
- **Type**: Pipeline job with embedded script
- **Location**: `Infrastructure/Repository-Monitor` 
- **Purpose**: Monitor Git repository for changes and trigger Job-DSL-Seed

### 3. **Pipeline Script**
- **File**: `pipelines/Jenkinsfile.job-dsl-seed`
- **Purpose**: Contains the actual Job DSL processing logic
- **Benefits**: Version controlled, testable, maintainable

## Benefits of cpsScm Approach

### **Git-Based Management**
- Pipeline logic version controlled in Git
- Changes tracked through commit history
- Collaborative development through pull requests
- Rollback capability for pipeline changes

### **Automatic Synchronization**
- Repository polling detects changes
- Automatic pipeline execution on updates
- No manual intervention required
- Consistent deployment across environments

### **Enhanced Features**
- Comprehensive change analysis
- Dry-run capabilities
- Detailed processing reports
- Error handling and validation

### **Separation of Concerns**
- Job DSL definitions: `jenkins-dsl/*.groovy`
- Pipeline logic: `pipelines/Jenkinsfile.job-dsl-seed`
- Job configuration: Job DSL seed job parameters

## Repository Structure

### Required Directory Structure
```
your-jenkins-repo/
├── jenkins-dsl/                    # Job DSL Scripts
│   ├── folders.groovy             # Folder definitions
│   ├── views.groovy              # View definitions  
│   ├── seed-jobs.groovy          # Seed job definitions
│   ├── infrastructure/           # Infrastructure jobs
│   │   ├── ssh-key-exchange.groovy
│   │   ├── ansible-image-builder.groovy
│   │   └── dynamic-ansible-executor.groovy
│   └── applications/             # Application jobs
│       └── *.groovy
├── pipelines/                     # Pipeline Scripts
│   ├── Jenkinsfile.job-dsl-seed  # Job DSL processing pipeline
│   ├── Jenkinsfile.backup        # Backup pipeline
│   └── Other Jenkinsfiles...
└── ansible/                      # Ansible configuration
    └── roles/
        └── jenkins-master/        # New reusable role
```

### Processing Order
1. **folders.groovy** - Create folder structure first
2. **infrastructure/*.groovy** - Create infrastructure jobs
3. **applications/*.groovy** - Create application jobs  
4. **views.groovy** - Create views last (if PROCESS_VIEWS=true)

## Configuration Parameters

### Job-DSL-Seed Parameters
```yaml
# Repository Configuration
GIT_REPOSITORY: "https://github.com/your-org/jenkins-ha.git"
DSL_BRANCH: "main"
GIT_CREDENTIALS: "git-credentials"

# Processing Configuration  
DSL_SCRIPTS_PATH: "jenkins-dsl"
REMOVAL_ACTION: "IGNORE"  # IGNORE|DELETE|DISABLE
PROCESS_VIEWS: true
VALIDATE_BEFORE_APPLY: true

# Execution Options
DRY_RUN: false
LOG_LEVEL: "INFO"  # INFO|DEBUG|WARN
```

### Repository-Monitor Parameters
```yaml
# Monitoring Configuration
GIT_REPOSITORY: "https://github.com/your-org/jenkins-ha.git"
MONITOR_BRANCH: "main"
GIT_CREDENTIALS: "git-credentials"

# Behavior Configuration
POLLING_FREQUENCY: "10"  # minutes
AUTO_TRIGGER_SEED: true
ANALYZE_CHANGES: true
NOTIFICATION_CHANNEL: "#jenkins-ops"
```

## Usage Workflows

### 1. **Automatic Workflow** (Recommended)
```
Developer commits changes to jenkins-dsl/
     ↓
Repository-Monitor detects changes
     ↓
Job-DSL-Seed automatically triggered
     ↓
Jobs/Views created/updated in Jenkins
```

### 2. **Manual Workflow**
```
Developer commits changes to jenkins-dsl/
     ↓
Administrator manually runs Job-DSL-Seed
     ↓
Jobs/Views created/updated in Jenkins
```

### 3. **Testing Workflow**
```
Developer creates feature branch
     ↓
Job-DSL-Seed run with DRY_RUN=true
     ↓
Review dry-run results
     ↓
Merge to main branch for actual deployment
```

## Setting Up cpsScm Integration

### Step 1: Configure Git Credentials
```bash
# In Jenkins: Manage Jenkins → Manage Credentials
# Add Username/Password or SSH key credential
# ID: "git-credentials"
```

### Step 2: Create Job-DSL-Seed Job
```groovy
// In jenkins-dsl/seed-jobs.groovy
pipelineJob('Infrastructure/Job-DSL-Seed') {
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('${GIT_REPOSITORY}')
                        credentials('${GIT_CREDENTIALS}')
                    }
                    branches('*/${DSL_BRANCH}')
                }
            }
            scriptPath('pipelines/Jenkinsfile.job-dsl-seed')
        }
    }
}
```

### Step 3: Create Pipeline Script
```groovy
// In pipelines/Jenkinsfile.job-dsl-seed
pipeline {
    agent any
    stages {
        stage('Process Job DSL') {
            steps {
                jobDsl(
                    targets: 'jenkins-dsl/**/*.groovy',
                    removedJobAction: 'IGNORE'
                )
            }
        }
    }
}
```

### Step 4: Configure Repository Monitor
The Repository-Monitor job provides enhanced change detection and automatic triggering.

## Advanced Features

### Change Impact Analysis
```groovy
// Repository-Monitor analyzes:
// - Which files changed
// - Impact on Job DSL scripts
// - Change types (added/modified/deleted)
// - Automatic triggering decisions
```

### Comprehensive Reporting
```groovy
// Job-DSL-Seed generates:
// - Processing reports (Markdown + JSON)
// - Change summaries
// - Success/failure details
// - Artifact archiving
```

### Validation and Safety
```groovy
// Built-in safeguards:
// - Pre-processing validation
// - Dry-run capabilities
// - Error handling and rollback
// - Change impact assessment
```

## Troubleshooting

### Common Issues

#### 1. **Pipeline Script Not Found**
```
Error: Script 'pipelines/Jenkinsfile.job-dsl-seed' not found
```
**Solution**: Ensure the pipeline script exists in the repository at the correct path.

#### 2. **Git Credentials Issues**
```
Error: Authentication failed for repository
```
**Solution**: Verify Git credentials are configured correctly in Jenkins and have repository access.

#### 3. **Job DSL Processing Failures**
```
Error: Job DSL script compilation failed
```
**Solution**: 
- Run with `DRY_RUN=true` to test
- Enable `VALIDATE_BEFORE_APPLY=true`
- Check syntax of Job DSL scripts

#### 4. **Repository Monitor Not Triggering**
```
No automatic triggering of Job-DSL-Seed
```
**Solution**:
- Check polling configuration
- Verify `AUTO_TRIGGER_SEED=true`
- Ensure DSL script changes are detected

### Debugging Steps

#### 1. **Check Repository Access**
```bash
# Test Git access from Jenkins
git ls-remote https://github.com/your-org/jenkins-ha.git
```

#### 2. **Validate Job DSL Scripts**
```bash
# Run local syntax check
find jenkins-dsl -name "*.groovy" -exec groovy -c {} \;
```

#### 3. **Test Pipeline Script**
```bash
# Verify pipeline script syntax
groovy -c pipelines/Jenkinsfile.job-dsl-seed
```

#### 4. **Monitor Repository Changes**
```bash
# Check recent commits affecting DSL scripts
git log --oneline --since="24 hours ago" -- jenkins-dsl/
```

## Best Practices

### 1. **Repository Management**
- Use feature branches for Job DSL changes
- Test changes with dry-run before merging
- Keep Job DSL scripts focused and modular
- Document changes in commit messages

### 2. **Pipeline Configuration**
- Set appropriate polling frequencies
- Use validation and dry-run features
- Configure proper notifications
- Archive processing reports

### 3. **Error Handling**
- Monitor Job-DSL-Seed job health
- Set up alerts for processing failures
- Review change analysis reports
- Maintain rollback procedures

### 4. **Security**
- Secure Git repository access
- Use appropriate Jenkins permissions
- Protect main branch with reviews
- Audit Job DSL changes regularly

## Integration with Blue-Green Jenkins

### Multi-Team Support
```groovy
// Each team can have their own DSL scripts
jenkins-dsl/
├── teams/
│   ├── devops/
│   ├── developer/ 
│   └── qa/
└── shared/
    ├── folders.groovy
    └── views.groovy
```

### Environment-Specific Processing
```groovy
// Use parameters for environment-specific behavior
pipeline {
    parameters {
        choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'prod'])
    }
    stages {
        stage('Process DSL') {
            steps {
                jobDsl(
                    additionalParameters: [
                        ENVIRONMENT: params.ENVIRONMENT
                    ]
                )
            }
        }
    }
}
```

This cpsScm approach provides a robust, version-controlled, and automated Job DSL management system that scales with your blue-green Jenkins infrastructure and multi-team requirements.