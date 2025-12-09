# Team DSL Management Guide

This guide provides comprehensive instructions for implementing and managing Jenkins Job DSL across multiple teams using external repositories.

## Overview

The Jenkins DSL management system enables teams to:
- **Own their job definitions** in dedicated repositories
- **Maintain security and compliance** through automated validation
- **Scale independently** without affecting other teams  
- **Follow best practices** with standardized templates

## Architecture

```mermaid
graph TB
    A[Team DSL Repository] --> B[DSL Processor Pipeline]
    B --> C[DSL Validation]
    C --> D{Validation Passed?}
    D -->|Yes| E[Execute DSL Scripts]
    D -->|No| F[Fail Build]
    E --> G[Jenkins Jobs Created]
    
    H[Ansible Configuration] --> I[Seed Job Template]
    I --> B
    
    J[Validation Framework] --> C
    K[Security Policies] --> C
```

## Quick Start

### 1. Configure Team in Ansible Inventory

Add `jenkins_dsl_repos` configuration to your team in the inventory file:

```yaml
# ansible/inventories/production/group_vars/all/main.yml
jenkins_teams_config:
  - team_name: "devops"
    # ... existing configuration ...
    jenkins_dsl_repos:
      - repo_url: "https://github.com/devops-team/jenkins-dsl.git"
        repo_branch: "main"
        dsl_directory: "dsl"
        credentials_id: "devops-git-credentials"
        scan_schedule: "H/30 * * * *"
        description: "DevOps team job definitions and pipelines"
```

### 2. Create Team DSL Repository

Create a new repository with this structure:

```
devops-team-jenkins-dsl/
├── dsl/
│   ├── pipelines/
│   │   ├── build-pipeline.groovy
│   │   └── deploy-pipeline.groovy
│   ├── jobs/
│   │   ├── maintenance-jobs.groovy
│   │   └── utility-jobs.groovy
│   └── views/
│       └── team-dashboards.groovy
├── Jenkinsfile.dsl-processor
├── README.md
└── .gitignore
```

### 3. Deploy Configuration

Run the Ansible deployment to create DSL processor jobs:

```bash
# Deploy to production
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags jenkins

# Deploy to local development
ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags jenkins
```

## Team DSL Repository Structure

### Recommended Directory Layout

```
team-{name}-jenkins-dsl/
├── dsl/                          # Main DSL scripts directory
│   ├── pipelines/                # Pipeline job definitions
│   │   ├── build/                # Build pipelines
│   │   ├── deploy/               # Deployment pipelines
│   │   └── maintenance/          # Maintenance pipelines
│   ├── jobs/                     # Other job types
│   │   ├── freestyle/            # Freestyle jobs
│   │   └── utility/              # Utility jobs
│   ├── views/                    # Jenkins views and dashboards
│   │   ├── dashboards/           # Team dashboards
│   │   └── filters/              # View filters
│   └── shared/                   # Shared templates and functions
│       ├── templates/            # Job templates
│       └── functions/            # Shared Groovy functions
├── Jenkinsfile.dsl-processor     # DSL processor pipeline (required)
├── validation/                   # Validation configurations
│   ├── .dsl-validation.yml       # Validation rules
│   └── security-policy.yml       # Security policies
├── docs/                         # Documentation
│   ├── README.md                 # Repository documentation
│   └── job-definitions.md        # Job definitions guide
├── examples/                     # Example DSL scripts
│   ├── pipeline-examples.groovy
│   └── job-examples.groovy
└── tests/                        # DSL tests (optional)
    └── validate-dsl.sh           # Local validation script
```

### Essential Files

#### 1. `Jenkinsfile.dsl-processor`

This file should be identical across all team repositories:

```groovy
#!/usr/bin/env groovy

/**
 * Team DSL Processor Pipeline
 * 
 * This pipeline processes Job DSL scripts for the team.
 * It uses the standard DSL processor pipeline from the main repository.
 */

// Load the standard DSL processor pipeline
// This is managed centrally and provides consistent processing
@Library('jenkins-shared-lib') _

// Use the standard pipeline with team-specific parameters
node {
    // The main pipeline handles all processing
    // Parameters are passed from the job configuration
    load "${WORKSPACE}/pipelines/Jenkinsfile.dsl-processor"
}
```

Alternatively, if not using shared libraries:

```groovy
#!/usr/bin/env groovy

pipeline {
    agent { 
        label "${params.TEAM_NAME}-python python-${params.TEAM_NAME}" 
    }
    
    stages {
        stage('Process DSL') {
            steps {
                script {
                    // Use jobDsl step to process all DSL files
                    def dslFiles = sh(
                        script: "find ${params.DSL_DIRECTORY} -name '*.groovy' -type f | tr '\\n' ','",
                        returnStdout: true
                    ).trim()
                    
                    if (dslFiles) {
                        jobDsl(
                            targets: dslFiles,
                            sandbox: true,
                            removedJobAction: 'IGNORE',
                            removedViewAction: 'IGNORE',
                            lookupStrategy: 'JENKINS_ROOT'
                        )
                    }
                }
            }
        }
    }
}
```

#### 2. `README.md`

```markdown
# Team Jenkins DSL Repository

This repository contains Jenkins Job DSL definitions for the **{TEAM_NAME}** team.

## Quick Start

1. Clone this repository
2. Make changes to DSL files in the `dsl/` directory
3. Commit and push changes
4. Jenkins will automatically process the changes

## Structure

- `dsl/pipelines/` - Pipeline job definitions
- `dsl/jobs/` - Other job types
- `dsl/views/` - Jenkins views and dashboards
- `examples/` - Example DSL scripts

## Validation

Run local validation before committing:

```bash
./tests/validate-dsl.sh --team {TEAM_NAME} --dsl-dir dsl
```

## Support

For questions or issues, contact the DevOps team or refer to the main Jenkins DSL documentation.
```

## DSL Script Best Practices

### 1. Team Namespacing

Always prefix jobs and folders with your team name:

```groovy
// ✅ GOOD - Properly namespaced
folder('DevOps') {
    displayName('DevOps Team')
}

pipelineJob('DevOps/Build/api-service-build') {
    displayName('API Service Build')
}

// ❌ BAD - No team namespace
pipelineJob('api-service-build') {
    displayName('API Service Build')
}
```

### 2. Security Compliance

Follow security best practices:

```groovy
// ✅ GOOD - Using credentials properly
pipelineJob('DevOps/Deploy/production-deploy') {
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/company/app.git')
                        credentials('team-git-credentials')  // Use credential ID
                    }
                }
            }
        }
    }
}

// ❌ BAD - Hardcoded credentials
git {
    remote {
        url('https://user:password@github.com/company/app.git')  // Never do this!
    }
}
```

### 3. Parameterization

Make jobs flexible with parameters:

```groovy
pipelineJob('DevOps/Deploy/application-deploy') {
    parameters {
        choiceParam('ENVIRONMENT', ['dev', 'staging', 'production'], 'Target environment')
        stringParam('VERSION', 'latest', 'Application version to deploy')
        booleanParam('DRY_RUN', false, 'Perform dry run only')
    }
    
    definition {
        cps {
            script('''
                pipeline {
                    agent { label 'devops-python' }
                    
                    stages {
                        stage('Deploy') {
                            when {
                                not { params.DRY_RUN }
                            }
                            steps {
                                echo "Deploying version ${params.VERSION} to ${params.ENVIRONMENT}"
                                // Deployment logic here
                            }
                        }
                    }
                }
            ''')
            sandbox(true)  // Always run in sandbox mode
        }
    }
}
```

### 4. Proper Error Handling

Include error handling and notifications:

```groovy
pipelineJob('DevOps/Build/critical-service') {
    definition {
        cps {
            script('''
                pipeline {
                    agent { label 'devops-maven' }
                    
                    post {
                        failure {
                            emailext(
                                subject: "Build Failed: ${env.JOB_NAME} - ${env.BUILD_NUMBER}",
                                body: "Build failed. Check console output: ${env.BUILD_URL}",
                                to: 'devops-team@company.com'
                            )
                        }
                        
                        success {
                            echo "Build completed successfully"
                        }
                    }
                }
            ''')
            sandbox(true)
        }
    }
}
```

## Configuration Reference

### jenkins_dsl_repos Configuration

```yaml
jenkins_dsl_repos:
  - repo_url: "https://github.com/team/jenkins-dsl.git"    # Required: Repository URL
    repo_branch: "main"                                    # Optional: Branch (default: main)
    dsl_directory: "dsl"                                   # Optional: DSL directory (default: dsl)
    credentials_id: "team-git-credentials"                 # Optional: Git credentials
    scan_schedule: "H/30 * * * *"                         # Optional: Scan schedule (default: H/30 * * * *)
    description: "Team job definitions"                    # Optional: Description
```

### Scan Schedule Examples

```yaml
# Every 15 minutes
scan_schedule: "H/15 * * * *"

# Every hour at a random minute
scan_schedule: "H * * * *"

# Every 4 hours
scan_schedule: "H H/4 * * *"

# Daily at 2 AM
scan_schedule: "H 2 * * *"

# Only on weekdays at 9 AM
scan_schedule: "H 9 * * 1-5"
```

## Team Workflow

### 1. Development Workflow

```mermaid
graph TB
    A[Developer Creates DSL] --> B[Local Validation]
    B --> C[Commit & Push]
    C --> D[Jenkins Scans Repository]
    D --> E[DSL Validation Pipeline]
    E --> F{Validation Passes?}
    F -->|Yes| G[Jobs Created/Updated]
    F -->|No| H[Build Fails]
    H --> I[Developer Fixes Issues]
    I --> B
```

### 2. Best Practices for Teams

#### Development Process
1. **Local Validation**: Always validate DSL scripts locally before committing
2. **Small Changes**: Make incremental changes and test frequently
3. **Code Review**: Review DSL changes like any other code
4. **Documentation**: Document complex job logic and parameters

#### Repository Management
1. **Branch Protection**: Protect main branch and require reviews
2. **Semantic Versioning**: Tag releases for important changes
3. **Change Logs**: Maintain changelog for DSL modifications
4. **Backup Strategy**: Ensure repository is backed up

#### Security Guidelines
1. **No Secrets**: Never commit secrets or credentials
2. **Least Privilege**: Use minimal required permissions
3. **Sandbox Mode**: Always run DSL in sandbox mode
4. **Regular Audits**: Review DSL scripts for security issues

## Validation and Testing

### Local Validation

Before committing changes, validate DSL scripts locally:

```bash
# Clone the main infrastructure repository
git clone https://github.com/company/jenkins-ha.git

# Validate your DSL scripts
./jenkins-ha/scripts/validate-team-dsl.sh \
    --team devops \
    --dsl-dir ./dsl \
    --strict \
    --report-file validation-report.txt

# Review the validation report
cat validation-report.txt
```

### Automated Validation

The system automatically validates:

✅ **Syntax Validation**
- Groovy syntax correctness
- DSL structure validation
- Parameter validation

✅ **Security Validation**  
- No dangerous system calls
- No hardcoded credentials
- No unauthorized file system access

✅ **Team Boundary Validation**
- Jobs properly namespaced to team
- No cross-team folder access
- Proper resource isolation

✅ **Best Practices Validation**
- Sandbox mode enforcement
- Proper error handling
- Resource limit compliance

### Testing New DSL Scripts

```groovy
// Example test DSL script
// Place in tests/ directory - these are not processed by Jenkins

def testJobCreation() {
    // Test that basic job creation works
    pipelineJob('Test/sample-pipeline') {
        definition {
            cps {
                script('echo "Test pipeline"')
                sandbox(true)
            }
        }
    }
    
    println "✅ Test job creation successful"
}

// Run tests (this would be in a test framework)
testJobCreation()
```

## Advanced Features

### 1. Shared DSL Libraries

Create reusable DSL components:

```groovy
// dsl/shared/templates/standardPipeline.groovy

def createStandardPipeline(String jobName, String gitUrl, Map config = [:]) {
    pipelineJob("DevOps/${jobName}") {
        displayName(config.displayName ?: jobName)
        description(config.description ?: "Standard pipeline for ${jobName}")
        
        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url(gitUrl)
                            credentials(config.credentialsId ?: 'devops-git-credentials')
                        }
                        branch(config.branch ?: 'main')
                    }
                }
                scriptPath(config.jenkinsfile ?: 'Jenkinsfile')
            }
        }
        
        if (config.schedule) {
            triggers {
                cron(config.schedule)
            }
        }
        
        properties {
            buildDiscarder {
                strategy {
                    logRotator {
                        numToKeepStr(config.buildsToKeep ?: '10')
                        daysToKeepStr(config.daysToKeep ?: '30')
                    }
                }
            }
        }
    }
}

// Usage in other DSL scripts
evaluate(readFileFromWorkspace('dsl/shared/templates/standardPipeline.groovy'))

createStandardPipeline('api-service', 'https://github.com/company/api-service.git', [
    displayName: 'API Service Build',
    description: 'Builds and tests the API service',
    schedule: 'H H/4 * * *'
])
```

### 2. Environment-Specific Configuration

Support different configurations per environment:

```groovy
// dsl/shared/config/environments.groovy

def environments = [
    dev: [
        agents: ['devops-maven-dev'],
        schedule: 'H/15 * * * *',
        notifications: false
    ],
    staging: [
        agents: ['devops-maven-staging'],
        schedule: 'H H * * *',
        notifications: true
    ],
    production: [
        agents: ['devops-maven-prod'],
        schedule: 'H 2 * * *',
        notifications: true,
        approvals: true
    ]
]

def getEnvironmentConfig(String env) {
    return environments[env] ?: environments.dev
}
```

### 3. Dynamic Job Generation

Generate jobs based on configuration:

```groovy
// dsl/pipelines/dynamic-microservices.groovy

def services = [
    'user-service': [
        gitUrl: 'https://github.com/company/user-service.git',
        buildAgent: 'java11'
    ],
    'payment-service': [
        gitUrl: 'https://github.com/company/payment-service.git',
        buildAgent: 'java11'
    ],
    'notification-service': [
        gitUrl: 'https://github.com/company/notification-service.git',
        buildAgent: 'nodejs'
    ]
]

services.each { serviceName, config ->
    pipelineJob("DevOps/Microservices/${serviceName}") {
        displayName("${serviceName.split('-').collect { it.capitalize() }.join(' ')}")
        
        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url(config.gitUrl)
                            credentials('devops-git-credentials')
                        }
                    }
                }
            }
        }
        
        properties {
            pipelineTriggers([
                [$class: 'GitHubPushTrigger']
            ])
        }
    }
}
```

## Troubleshooting

### Common Issues

#### 1. Script Approval Required

**Error**: `Scripts not permitted to use method...`

**Solution**:
1. Go to Jenkins → Manage Jenkins → In-process Script Approval
2. Approve the required methods
3. Re-run the DSL job

#### 2. Validation Failures

**Error**: DSL validation fails with security violations

**Solution**:
```bash
# Run local validation to see specific issues
./scripts/validate-team-dsl.sh --team YOUR_TEAM --dsl-dir dsl --verbose

# Fix identified issues and re-validate
./scripts/validate-team-dsl.sh --team YOUR_TEAM --dsl-dir dsl --strict
```

#### 3. Jobs Not Being Created

**Possible Causes**:
- DSL syntax errors
- Team boundary violations  
- Missing credentials
- Repository access issues

**Debugging Steps**:
1. Check DSL processor job console output
2. Verify repository access and credentials
3. Run local validation
4. Check Jenkins system logs

#### 4. Performance Issues

**Symptoms**: DSL processing takes too long

**Solutions**:
- Reduce scan frequency
- Optimize DSL scripts
- Split large DSL files
- Use more specific file patterns

### Getting Help

1. **Check Documentation**: Review this guide and Jenkins DSL documentation
2. **Local Validation**: Use the validation script to identify issues
3. **Console Logs**: Check DSL processor job logs for detailed errors
4. **Team Support**: Contact the DevOps team for assistance
5. **Jenkins Documentation**: Refer to [Jenkins Job DSL Plugin](https://plugins.jenkins.io/job-dsl/) documentation

## Migration Guide

### Migrating from Embedded DSL

If you have existing DSL embedded in the seed job, follow these steps:

1. **Create Team Repository**:
   ```bash
   git clone https://github.com/company/team-dsl-template.git devops-jenkins-dsl
   cd devops-jenkins-dsl
   ```

2. **Extract Existing DSL**:
   - Copy DSL scripts from seed job to `dsl/` directory
   - Organize by type (pipelines, jobs, views)
   - Update job names to include team namespace

3. **Update Inventory Configuration**:
   ```yaml
   # Add jenkins_dsl_repos to your team configuration
   jenkins_dsl_repos:
     - repo_url: "https://github.com/company/devops-jenkins-dsl.git"
       # ... other configuration
   ```

4. **Test Migration**:
   ```bash
   # Validate DSL scripts
   ./scripts/validate-team-dsl.sh --team devops --dsl-dir dsl
   
   # Test in development environment first
   ansible-playbook -i ansible/inventories/local/hosts.yml ansible/site.yml --tags jenkins
   ```

5. **Deploy to Production**:
   ```bash
   # Deploy to production after testing
   ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags jenkins
   ```

## Conclusion

This DSL management system provides a scalable, secure, and maintainable approach to Jenkins job management across multiple teams. By following the best practices and guidelines in this document, teams can:

- Maintain full control over their Jenkins jobs
- Ensure security and compliance through automated validation
- Scale independently without affecting other teams
- Follow consistent patterns and best practices

For additional support or questions, refer to the troubleshooting section or contact the DevOps team.