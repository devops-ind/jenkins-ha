// View Definitions
// Creates all Jenkins views for organizing and displaying jobs

// Python Jobs View
listView('Infrastructure/Python Jobs') {
    displayName('Python Jobs View')
    description('View showing all Python-related jobs and seed jobs')
    jobs {
        name('Infrastructure/Job-DSL-Seed')
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
    filterBuildQueue(true)
    filterExecutors(true)
    recurse(false)
}

// Seed Jobs View
listView('Infrastructure/Seed Jobs') {
    displayName('Seed Jobs View')
    description('View for all seed and job generation jobs')
    jobs {
        name('Infrastructure/Job-DSL-Seed')
        regex('.*[Ss]eed.*')
        regex('.*[Gg]enerat.*')
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
    filterBuildQueue(true)
    filterExecutors(true)
}

// Pipeline Jobs View
listView('Infrastructure/Pipeline Jobs') {
    displayName('Pipeline Jobs View')
    description('View showing all infrastructure pipeline jobs')
    jobs {
        name('Infrastructure/Image-Builder')
        name('Infrastructure/Backup-Pipeline')
        name('Infrastructure/Infrastructure-Update')
        name('Infrastructure/Monitoring-Setup')
        name('Infrastructure/Security-Scan')
        name('Infrastructure/Health-Check')
        name('Infrastructure/Disaster-Recovery')
        name('Infrastructure/Job-DSL-Seed')
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
    filterBuildQueue(true)
    filterExecutors(true)
}

// Build Pipeline View
buildPipelineView('Infrastructure/Build Pipeline View') {
    displayName('Build Pipeline Flow')
    description('Pipeline view showing job dependencies and flow')
    selectedJob('Infrastructure/Job-DSL-Seed')
    numberOfBuilds(5)
    showPipelineParameters(true)
    showPipelineParametersInHeaders(true)
    showPipelineDefinitionHeader(true)
    refreshFrequency(30)
    triggerOnlyLatestJob(true)
    alwaysAllowManualTrigger(true)
}

// Categorized View
categorizedJobsView('Infrastructure/Categorized View') {
    displayName('Categorized Infrastructure View')
    description('Jobs organized by category and function')
    
    categorizationCriteria {
        regexGroupingRule {
            groupRegex('(.*)-.*')
            namingRule('\\1')
        }
    }
    
    jobFilters {
        regex {
            matchType(MatchType.INCLUDE_MATCHED)
            matchValue('Infrastructure/.*')
        }
    }
    
    columns {
        status()
        weather() 
        categorizedJob()
        lastSuccess()
        lastFailure()
        lastDuration()
        buildButton()
    }
}

// Sample Application Jobs View
listView('Applications/Sample Jobs') {
    displayName('Sample Application Jobs')
    description('View showing sample jobs created by Job DSL')
    
    jobs {
        name('Applications/Maven-Build-Sample')
        name('Applications/Python-Build-Sample')
        name('Applications/Freestyle-Sample')
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
    
    filterBuildQueue(true)
    filterExecutors(true)
}

println "All views created successfully"