# Jenkins DSL Sandbox Implementation Guide

This document explains the Jenkins DSL sandbox implementation in the Jenkins HA infrastructure, designed to eliminate constant manual approval requirements while maintaining security.

## Overview

The Jenkins DSL sandbox implementation provides:
- **Automatic execution** of DSL jobs without manual approval
- **Security boundaries** through Groovy sandbox
- **Pre-approved safe operations** for common DSL patterns  
- **Comprehensive logging** and audit trail

## Key Components

### 1. Jenkins Configuration as Code (JCasC)

**Location**: `ansible/roles/jenkins-master/templates/jcasc/jenkins-config.yml.j2`

Key sandbox configurations:
```yaml
security:
  scriptApproval:
    approvedSignatures:
      # Pre-approved safe method signatures
      - "method groovy.lang.GroovyObject getProperty java.lang.String"
      - "staticMethod jenkins.model.Jenkins getInstance"
      # ... additional signatures

unclassified:
  globalJobDslSecurityConfiguration:
    useScriptSecurity: true  # Enable script security with sandbox
```

### 2. Initialization Script

**Location**: `ansible/roles/jenkins-master/files/init-scripts/setup-dsl-approval.groovy`

This Groovy init script automatically:
- Pre-approves 50+ safe method signatures
- Configures Job DSL security settings
- Runs on Jenkins startup to establish sandbox boundaries

### 3. DSL Seed Jobs

**Location**: `jenkins-dsl/seed.groovy`

The main seed script that:
- Runs in sandbox mode (`sandbox(true)`)
- Creates all folders, views, and jobs
- Uses only pre-approved operations
- Provides comprehensive error handling

## Sandbox-Safe DSL Patterns

### ✅ Safe Operations

```groovy
// Basic job creation
pipelineJob('Infrastructure/My-Job') {
    displayName('My Job')
    description('Job description')
    
    parameters {
        stringParam('VERSION', '1.0.0', 'Version to build')
        booleanParam('SKIP_TESTS', false, 'Skip tests')
        choiceParam('ENV', ['dev', 'prod'], 'Environment')
    }
    
    definition {
        cps {
            script('''
                pipeline {
                    agent any
                    stages {
                        stage('Build') {
                            steps {
                                echo "Building version: ${params.VERSION}"
                            }
                        }
                    }
                }
            ''')
            sandbox(true)  // Always enable sandbox
        }
    }
}
```

### ❌ Operations Requiring Approval

```groovy
// Avoid these patterns as they require manual approval:

// File system operations
new File('/etc/passwd').text

// System commands
"rm -rf /".execute()

// Jenkins internal APIs (non-whitelisted)
Jenkins.instance.doRestart()

// Reflection and class loading
Class.forName('java.lang.Runtime')
```

## Pre-Approved Method Signatures

The initialization script pre-approves these categories:

### String Operations
- `split()`, `trim()`, `toLowerCase()`, `toUpperCase()`
- `replace()`, `replaceAll()`, `substring()`
- `startsWith()`, `endsWith()`, `contains()`, `matches()`

### Collections
- `List.add()`, `Map.get()`, `Map.put()`, `Set.contains()`
- `Collection.size()`, `Collection.isEmpty()`

### Jenkins APIs
- `Jenkins.getInstance()`
- `ItemGroup.getItem()`, `Item.getName()`
- Basic job and folder operations

### Date/Time
- `Date` constructors and basic methods
- `SimpleDateFormat` operations

### Math Operations  
- `Math.max()`, `Math.min()`, `Math.abs()`
- `Math.round()`, `Math.ceil()`, `Math.floor()`

## DSL Job Examples

### Simple Pipeline Job
```groovy
pipelineJob('Examples/Simple-Pipeline') {
    displayName('Simple Sandbox-Safe Pipeline')
    
    definition {
        cps {
            script('''
                pipeline {
                    agent any
                    stages {
                        stage('Build') {
                            steps {
                                echo 'Building...'
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

### Multibranch Pipeline
```groovy
multibranchPipelineJob('Examples/Multibranch-Pipeline') {
    branchSources {
        git {
            remote('https://github.com/org/repo.git')
            credentialsId('git-credentials')
        }
    }
    
    factory {
        workflowBranchProjectFactory {
            scriptPath('Jenkinsfile')
        }
    }
}
```

### List View
```groovy
listView('Infrastructure Jobs') {
    description('All infrastructure jobs')
    
    jobs {
        regex('Infrastructure/.*')
    }
    
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
        buildButton()
    }
}
```

## Deployment Process

### 1. Automatic Setup
When Jenkins starts, the initialization script:
```groovy
// Pre-approves safe signatures
scriptApproval.approveSignature(signature)

// Configures DSL security  
globalJobDslSecurityConfig.useScriptSecurity = true
```

### 2. DSL Seed Job Execution
The seed job runs automatically:
- Pulls DSL scripts from Git
- Executes in sandbox mode
- Creates/updates all jobs and views
- No manual approval required for pre-approved operations

### 3. Monitoring and Logging
All DSL operations are logged with:
- Execution timestamps
- Success/failure status  
- Method signatures used
- Any approval requirements

## Troubleshooting

### Issue: "Scripts not permitted to use method..."

**Solution 1**: Add signature to initialization script
```groovy
// In setup-dsl-approval.groovy
def approvedSignatures = [
    "method your.package.Class methodName java.lang.String",
    // ... existing signatures
]
```

**Solution 2**: Use alternative sandbox-safe approach
```groovy
// Instead of direct API calls, use DSL methods
job('MyJob') {
    // Use DSL-provided methods instead of Jenkins APIs
}
```

**Solution 3**: Manual approval (last resort)
1. Go to Jenkins → Manage Jenkins → In-process Script Approval
2. Approve the specific signature
3. Re-run the DSL job

### Issue: DSL job fails with sandbox violations

**Check**:
1. Is `sandbox(true)` set in pipeline definition?
2. Are you using only pre-approved methods?
3. Review Jenkins logs for specific violations

**Fix**:
```groovy
definition {
    cps {
        script('...')
        sandbox(true)  // Ensure this is set
    }
}
```

### Issue: Job creation fails silently

**Debug steps**:
1. Check DSL job console output
2. Review Jenkins system logs
3. Verify Git repository access
4. Validate DSL script syntax

## Best Practices

### 1. Always Use Sandbox Mode
```groovy
definition {
    cps {
        script('...')
        sandbox(true)  // Always enable
    }
}
```

### 2. Validate DSL Scripts Locally
```bash
# Test DSL scripts before deployment
jenkins-cli.jar -s http://jenkins:8080 groovy script.groovy
```

### 3. Use Descriptive Names and Descriptions
```groovy
pipelineJob('Team/Feature-Build') {
    displayName('Feature Branch Builder')
    description('''
        Builds and tests feature branches
        • Runs unit tests
        • Performs code quality checks  
        • Deploys to staging environment
    ''')
}
```

### 4. Organize Jobs in Folders
```groovy
folder('Infrastructure') {
    displayName('Infrastructure Management')
    description('Infrastructure automation jobs')
}

pipelineJob('Infrastructure/Deploy') {
    // Job definition
}
```

### 5. Use Views for Organization
```groovy
listView('Failed Jobs') {
    jobFilters {
        status {
            status(Status.FAILED)
        }
    }
}
```

## Security Considerations

### Sandbox Boundaries
- Sandbox prevents access to Jenkins internals
- File system access is severely restricted
- Network operations are limited
- System commands are blocked

### Approved Operations Only
- Only pre-approved method signatures execute
- Unknown methods require manual approval
- Admin approval required for system modifications

### Audit Trail
- All DSL executions are logged
- Method signature usage tracked
- Failed approvals recorded
- Git commits tied to job changes

## Migration Guide

### From Manual Approval to Sandbox

1. **Update existing DSL scripts**:
   ```groovy
   // Add sandbox mode to all pipeline definitions
   definition {
       cps {
           script('...')
           sandbox(true)  // Add this
       }
   }
   ```

2. **Test in development**:
   - Deploy to dev environment first
   - Verify all jobs create successfully
   - Check for approval requirements

3. **Deploy initialization script**:
   - Ensure init script runs on startup
   - Verify signatures are pre-approved
   - Monitor Jenkins logs for issues

4. **Update documentation**:
   - Train team on sandbox patterns
   - Document approved operations
   - Create troubleshooting guides

## Monitoring and Maintenance

### Regular Tasks
- Review script approval queue monthly
- Update pre-approved signatures as needed
- Monitor DSL job execution logs
- Validate sandbox security boundaries

### Performance Monitoring
- DSL job execution time
- Git repository pull performance  
- Jenkins startup time with init scripts
- Method signature approval overhead

### Security Reviews
- Audit approved method signatures quarterly
- Review DSL script changes in Git
- Validate sandbox escape attempts
- Monitor Jenkins security advisories

## Conclusion

The DSL sandbox implementation provides secure, automated job management without constant manual intervention. By pre-approving safe operations and using sandbox mode, teams can iterate quickly on Jenkins job definitions while maintaining security boundaries.

For additional support, consult the Jenkins DSL plugin documentation and review the approved method signatures in the initialization script.