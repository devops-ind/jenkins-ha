# Simple Job DSL Setup Guide

## Overview

A streamlined Job DSL setup with embedded pipeline script in JCasC template. This keeps everything in one place for maximum simplicity.

## Architecture

```
Git Repository
├── jenkins-dsl/                    # Job DSL Scripts
│   ├── folders.groovy             # Folder definitions
│   ├── views.groovy               # View definitions
│   ├── infrastructure/            # Infrastructure jobs
│   │   ├── ssh-key-exchange.groovy
│   │   ├── ansible-image-builder.groovy
│   │   └── dynamic-ansible-executor.groovy
│   └── applications/              # Application jobs
│       └── *.groovy
├── pipelines/                     # Other Pipeline Scripts  
│   ├── Jenkinsfile.backup         # Backup pipeline
│   └── Other Jenkinsfiles...
└── ansible/                      # Ansible configuration
    └── roles/
        └── jenkins-master/        # Reusable Jenkins master role

Jenkins:
└── Infrastructure/Job-DSL-Seed   # Single seed job with embedded pipeline
    └── Pipeline script embedded in JCasC template
```

## Key Components

### 1. **Job DSL Seed Job** 
- **Created by**: JCasC template (`jenkins-jobs.yml.j2`)
- **Location**: `Infrastructure/Job-DSL-Seed`
- **Type**: Pipeline job with embedded script
- **Pipeline Script**: Embedded directly in JCasC template (no separate file)

### 2. **Embedded Pipeline Script**
- **Location**: Inside `jenkins-jobs.yml.j2`
- **Purpose**: Simple Job DSL processing logic
- **Features**: Git checkout, dry-run support, result reporting, error handling

### 3. **Job DSL Scripts**
- **Location**: `jenkins-dsl/**/*.groovy`
- **Processing Order**: All `.groovy` files in jenkins-dsl directory
- **Types**: Folders, jobs, views

## Configuration

### Job Parameters
```yaml
# Git Configuration
GIT_REPOSITORY: "https://github.com/your-org/jenkins-ha.git"
DSL_BRANCH: "main"
GIT_CREDENTIALS: "git-credentials"

# Processing Options
REMOVAL_ACTION: "IGNORE"  # IGNORE|DELETE|DISABLE
DRY_RUN: false           # Test mode
```

### Automatic Polling
- **Frequency**: Every 15 minutes (`H/15 * * * *`)
- **Trigger**: SCM changes in repository
- **Branch**: Configurable via `DSL_BRANCH` parameter

## Usage

### 1. **Automatic Processing**
```
Developer commits to jenkins-dsl/
       ↓
Jenkins polls repository (every 15 min)
       ↓
Job-DSL-Seed triggered automatically
       ↓
Jobs/Views created/updated
```

### 2. **Manual Processing**
```
1. Go to Infrastructure/Job-DSL-Seed
2. Click "Build with Parameters"
3. Configure repository/branch if needed
4. Click "Build"
```

### 3. **Testing Changes**
```
1. Set DRY_RUN = true
2. Run job to see what would be changed
3. Review output
4. Run with DRY_RUN = false to apply changes
```

## Repository Setup

### Required Structure
```
your-jenkins-repo/
├── jenkins-dsl/
│   ├── folders.groovy
│   ├── views.groovy
│   ├── infrastructure/
│   │   └── *.groovy
│   └── applications/
│       └── *.groovy
└── pipelines/
    ├── Jenkinsfile.job-dsl-seed
    └── Other pipeline files...
```

### Example Job DSL Script
```groovy
// jenkins-dsl/infrastructure/example-job.groovy
pipelineJob('Infrastructure/Example-Job') {
    displayName('Example Pipeline Job')
    description('Example job created via Job DSL')
    
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/your-org/jenkins-ha.git')
                        credentials('git-credentials')
                    }
                    branches('*/main')
                }
            }
            scriptPath('pipelines/Jenkinsfile.example')
        }
    }
}
```

## Benefits

### **Simple Setup**
- Single Job DSL seed job
- Minimal configuration required
- Easy to understand and maintain

### **Git Integration**
- Repository-based job definitions
- Version controlled pipeline scripts  
- Automatic polling for changes
- Branch-based development workflow

### **Flexible Processing**
- Dry-run mode for testing
- Configurable removal actions
- Clear result reporting
- Error handling and recovery

## Best Practices

### 1. **Repository Management**
- Keep Job DSL scripts organized in folders
- Use descriptive file names
- Test changes with dry-run before applying
- Use feature branches for development

### 2. **Job Organization**
- Group related jobs in subfolders
- Use consistent naming conventions
- Include proper descriptions
- Maintain folder structure

### 3. **Testing Workflow**
```
1. Create feature branch
2. Make Job DSL changes
3. Test with DRY_RUN=true
4. Review dry-run output
5. Merge to main branch
6. Automatic processing applies changes
```

### 4. **Maintenance**
- Monitor Job DSL Seed job health
- Review job creation/updates regularly
- Clean up orphaned jobs periodically
- Keep pipeline script updated

## Troubleshooting

### Common Issues

#### **Job DSL Seed Job Fails**
- Check Git repository accessibility
- Verify credentials are correct
- Check Job DSL script syntax
- Review pipeline script logs

#### **Jobs Not Created**
- Verify Job DSL scripts are in `jenkins-dsl/` directory
- Check for syntax errors in DSL scripts
- Ensure proper Git repository structure
- Review REMOVAL_ACTION setting

#### **Polling Not Working**
- Check SCM polling configuration
- Verify repository URL and credentials
- Check Jenkins SCM polling logs
- Ensure branch name is correct

### Debugging Steps

1. **Test Repository Access**
   ```bash
   git clone https://github.com/your-org/jenkins-ha.git
   cd jenkins-ha
   ls jenkins-dsl/
   ```

2. **Validate Job DSL Scripts**
   ```bash
   find jenkins-dsl -name "*.groovy" -exec echo "Checking {}" \;
   ```

3. **Test with Dry Run**
   - Set `DRY_RUN = true`
   - Run Job DSL Seed job
   - Review what would be processed

4. **Check Pipeline Script**
   - Review `pipelines/Jenkinsfile.job-dsl-seed`
   - Ensure script exists in repository
   - Verify script path in Job DSL definition

This streamlined approach provides all the benefits of repository-based Job DSL management while keeping the setup simple and maintainable.