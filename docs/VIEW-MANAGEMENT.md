# Jenkins View Management Guide

## Overview

Jenkins views have been centralized to use **Job DSL as the single source of truth**, eliminating duplication between JCasC (Jenkins Configuration as Code) and Job DSL scripts.

## Problem Solved

### Before: Duplicated View Management
```
JCasC Template (jenkins-jobs.yml.j2)
├── Infrastructure/Python Jobs
├── Infrastructure/Seed Jobs  
├── Infrastructure/Pipeline Jobs
├── Infrastructure/Build Pipeline View
└── Infrastructure/Categorized View

Job DSL (views.groovy)
├── Infrastructure Dashboard
├── SSH Management
├── Recent Builds
└── Build Monitor
```

**Issues:**
- Views defined in two different places
- Potential conflicts and overwrites
- Maintenance overhead
- Unclear which source is authoritative

### After: Centralized View Management
```
Job DSL (views.groovy) - SINGLE SOURCE OF TRUTH
├── Infrastructure Views
├── Team Views
├── Monitoring Views  
├── Specialized Views
└── Dashboard Views
```

**Benefits:**
- Single source of truth
- Consistent management approach
- No conflicts or duplication
- Easier maintenance and updates

## View Categories

### 1. Infrastructure Views
- **Infrastructure Dashboard**: Main infrastructure jobs overview
- **Infrastructure/Pipeline Jobs**: All infrastructure pipeline jobs
- **Infrastructure/SSH Management**: SSH key and connectivity jobs
- **Infrastructure/Ansible Jobs**: Ansible automation jobs
- **Infrastructure/Seed Jobs**: Job DSL and seed jobs

### 2. Team Views
- **Team Overview**: All team-specific jobs across teams
- Supports DevOps, Developer, QA team job organization

### 3. Monitoring Views
- **Recent Builds**: Latest build activity across all projects
- **Failed Jobs**: Jobs requiring immediate attention
- **Operations Dashboard**: Key metrics and operational status

### 4. Specialized Views
- **Build Pipeline**: Visual pipeline flow and dependencies
- **Build Monitor**: Real-time build status monitor
- **Categorized View**: Jobs organized by function and category

## Managing Views

### Adding New Views

Edit `jenkins-dsl/views.groovy`:

```groovy
listView('New View Name') {
    description('Description of the new view')
    
    jobs {
        regex('pattern-to-match-jobs')
        name('specific-job-name')
    }
    
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
        lastDuration()
        buildButton()
    }
    
    // Optional filters
    jobFilters {
        status {
            matchType(MatchType.INCLUDE_MATCHED)
            status(Status.STABLE, Status.UNSTABLE, Status.FAILED)
        }
    }
}
```

### View Types Available

#### 1. List Views
```groovy
listView('View Name') {
    // Basic list of jobs with columns
}
```

#### 2. Build Pipeline Views
```groovy
buildPipelineView('Pipeline Name') {
    selectedJob('starting-job')
    numberOfBuilds(5)
    showPipelineParameters(true)
}
```

#### 3. Build Monitor Views
```groovy
buildMonitorView('Monitor Name') {
    displayCommitters(true)
    buildStatusDisplayedInColumns(false)
}
```

#### 4. Categorized Views
```groovy
categorizedJobsView('Categorized Name') {
    categorizationCriteria {
        regexGroupingRule {
            groupRegex('(.*?)-.*')
            namingRule('\\1')
        }
    }
}
```

#### 5. Dashboard Views
```groovy
dashboardView('Dashboard Name') {
    topPortlet {
        jenkinsJobsList {
            displayName('Job List')
        }
    }
}
```

### Updating Views

1. **Edit** `jenkins-dsl/views.groovy`
2. **Commit** changes to repository
3. **Run** Job DSL Seed job to apply changes
4. **Verify** views appear correctly in Jenkins UI

### View Deployment

Views are deployed through the Job DSL Seed job:

```yaml
# Job DSL Seed job processes views.groovy
job-dsl-seed
├── Process jenkins-dsl/folders.groovy (folders first)
├── Process jenkins-dsl/views.groovy (views)
├── Process jenkins-dsl/infrastructure/*.groovy (jobs)
└── Process jenkins-dsl/applications/*.groovy (application jobs)
```

## Configuration Examples

### Team-Specific View
```groovy
listView('DevOps Team Jobs') {
    description('Jobs specific to the DevOps team')
    
    jobs {
        regex('DevOps/.*')
        name('Infrastructure/SSH-Key-Exchange')
        name('Infrastructure/Dynamic-Ansible-Executor')
    }
    
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
        lastDuration()
        buildButton()
    }
    
    jobFilters {
        regex {
            matchType(MatchType.INCLUDE_MATCHED)
            matchValue('(DevOps|Infrastructure)/.*')
        }
    }
}
```

### Environment-Specific View
```groovy
listView('Production Jobs') {
    description('Jobs running in production environment')
    
    jobs {
        regex('.*')
    }
    
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
        lastDuration()
        buildButton()
    }
    
    jobFilters {
        regex {
            matchType(MatchType.INCLUDE_MATCHED)
            matchValue('.*prod.*|.*production.*')
        }
    }
}
```

### Status-Based View
```groovy
listView('Unstable Jobs') {
    description('Jobs that are currently unstable')
    
    jobs {
        regex('.*')
    }
    
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
        lastDuration()
        buildButton()
    }
    
    jobFilters {
        status {
            matchType(MatchType.INCLUDE_MATCHED)
            status(Status.UNSTABLE)
        }
    }
}
```

## Migration from JCasC Views

### Old JCasC View Definition
```yaml
# In jenkins-jobs.yml.j2 (REMOVED)
- script: |
    listView('Infrastructure/Python Jobs') {
      displayName('Python Jobs View')
      description('View showing all Python-related jobs')
      jobs {
        name('Infrastructure/Job-DSL-Seed')
        regex('.*[Pp]ython.*')
      }
    }
```

### New Job DSL View Definition
```groovy
// In views.groovy (CURRENT)
listView('Infrastructure/Python Jobs') {
    displayName('Python Jobs')
    description('Python-related jobs and agents')
    
    jobs {
        name('job-dsl-seed')
        regex('.*[Pp]ython.*')
    }
    
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
        lastDuration()
        buildButton()
    }
}
```

## Best Practices

### 1. **Naming Conventions**
```groovy
// Use descriptive, hierarchical names
'Infrastructure Dashboard'           // Main dashboards
'Infrastructure/SSH Management'      // Functional groups
'Team/DevOps Jobs'                  // Team-specific views
'Status/Failed Jobs'                // Status-based views
```

### 2. **Job Selection Patterns**
```groovy
// Use specific names when possible
name('specific-job-name')

// Use regex for patterns  
regex('Infrastructure/.*')

// Combine for comprehensive coverage
jobs {
    name('important-specific-job')
    regex('pattern-for-group')
}
```

### 3. **Filter Usage**
```groovy
// Filter by status
jobFilters {
    status {
        matchType(MatchType.INCLUDE_MATCHED)
        status(Status.FAILED, Status.UNSTABLE)
    }
}

// Filter by regex
jobFilters {
    regex {
        matchType(MatchType.INCLUDE_MATCHED)
        matchValue('(Production|Staging)/.*')
    }
}

// Filter by build trend
jobFilters {
    buildTrend {
        includeMatched(true)
        buildCountType(BuildCountType.LATEST)
        amount(10)
        status(Status.STABLE, Status.FAILED)
    }
}
```

### 4. **Column Configuration**
```groovy
// Standard columns for most views
columns {
    status()           // Build status icon
    weather()          // Weather icon (trend)
    name()            // Job name
    lastSuccess()     // Last successful build
    lastFailure()     // Last failed build  
    lastDuration()    // Build duration
    buildButton()     // Build trigger button
}

// Additional specialized columns
columns {
    status()
    weather()
    name()
    lastBuildConsole()     // Console output link
    configureProject()     // Configuration link
    favoriteColumn()       // Favorite star
    buildButton()
}
```

## Troubleshooting

### Views Not Appearing
1. **Check Job DSL Seed job**: Ensure it ran successfully
2. **Verify syntax**: Check views.groovy for syntax errors
3. **Check permissions**: Ensure proper Jenkins permissions
4. **Review logs**: Check Job DSL Seed job console output

### Views Not Updating
1. **Run Job DSL Seed job**: Manually trigger to update views
2. **Check job patterns**: Verify job regex patterns match existing jobs
3. **Clear browser cache**: Refresh Jenkins UI
4. **Check job filters**: Ensure filters aren't excluding jobs

### Permission Issues
```groovy
// Views inherit permissions from Jenkins security settings
// Ensure users have appropriate view permissions:
// - Job/Read: To see jobs in views
// - View/Read: To access views
// - View/Configure: To modify views (for administrators)
```

## Maintenance

### Regular Tasks
1. **Review view relevance**: Remove unused views
2. **Update job patterns**: Adjust regex patterns as jobs change
3. **Optimize performance**: Avoid overly broad regex patterns
4. **Test view functionality**: Verify views show expected jobs

### Version Control
- All view changes tracked in Git
- Review changes through pull requests  
- Test view changes in staging environments
- Document view purposes and patterns

This centralized approach ensures consistent, maintainable view management across all Jenkins masters in your blue-green infrastructure.