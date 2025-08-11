// View Definitions for Jenkins Job Organization
// This is the single source of truth for all Jenkins views

// =============================================================================
// INFRASTRUCTURE VIEWS
// =============================================================================

listView('Infrastructure Dashboard') {
    description('Infrastructure management jobs and monitoring - Main dashboard view')
    filterBuildQueue()
    filterExecutors()
    
    jobs {
        regex('Infrastructure/.*')
        name('job-dsl-seed')
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
            status(Status.STABLE, Status.UNSTABLE, Status.FAILED)
        }
    }
    
    recurse()
}

listView('Infrastructure/Pipeline Jobs') {
    displayName('Pipeline Jobs')
    description('All infrastructure pipeline jobs')
    
    jobs {
        name('Infrastructure/SSH-Key-Exchange')
        name('Infrastructure/SSH-Connectivity-Test') 
        name('Infrastructure/Ansible-Image-Builder')
        name('Infrastructure/Dynamic-Ansible-Executor')
        name('Infrastructure/Image-Builder')
        name('Infrastructure/Backup-Pipeline')
        name('Infrastructure/Infrastructure-Update')
        name('Infrastructure/Monitoring-Setup')
        name('Infrastructure/Security-Scan')
        name('Infrastructure/Health-Check')
        name('job-dsl-seed')
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

listView('Infrastructure/SSH Management') {
    displayName('SSH Management')
    description('SSH connectivity and key management jobs')
    
    jobs {
        name('Infrastructure/SSH-Key-Exchange')
        name('Infrastructure/SSH-Connectivity-Test')
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

listView('Infrastructure/Ansible Jobs') {
    displayName('Ansible Jobs')
    description('Ansible execution and automation jobs')
    
    jobs {
        name('Infrastructure/Ansible-Image-Builder')
        name('Infrastructure/Dynamic-Ansible-Executor')
        regex('.*[Aa]nsible.*')
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

listView('Infrastructure/Seed Jobs') {
    displayName('Seed & DSL Jobs')
    description('Job DSL seed jobs and generation jobs')
    
    jobs {
        name('Infrastructure/Job-DSL-Seed')
        regex('.*[Ss]eed.*')
        regex('.*[Dd][Ss][Ll].*')
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

// =============================================================================
// TEAM VIEWS (Dynamic based on teams)
// =============================================================================

listView('Team Overview') {
    description('Overview of all team-specific jobs and builds')
    
    jobs {
        regex('.*/.*')  // All jobs with team prefixes
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
            matchValue('(DevOps|Developer|QA)/.*')
        }
    }
}

// =============================================================================
// MONITORING AND STATUS VIEWS  
// =============================================================================

listView('Recent Builds') {
    description('Recently executed builds across all projects')
    
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
        buildTrend {
            includeMatched(true)
            buildCountType(BuildCountType.LATEST)
            amountType(AmountType.BUILDS)
            amount(20)
            status(Status.STABLE, Status.UNSTABLE, Status.FAILED, Status.ABORTED)
        }
    }
}

listView('Failed Jobs') {
    description('Jobs that have failed recently - requires attention')
    
    jobs {
        regex('.*')
    }
    
    columns {
        status()
        weather()
        name()
        lastFailure()
        lastDuration()
        buildButton()
    }
    
    jobFilters {
        status {
            matchType(MatchType.INCLUDE_MATCHED)
            status(Status.FAILED)
        }
    }
}

// =============================================================================
// SPECIALIZED VIEWS
// =============================================================================

buildPipelineView('Infrastructure/Build Pipeline') {
    displayName('Build Pipeline Flow')
    description('Pipeline view showing job dependencies and build flow')
    selectedJob('job-dsl-seed')
    numberOfBuilds(5)
    showPipelineParameters(true)
    showPipelineParametersInHeaders(true)
    showPipelineDefinitionHeader(true)
    refreshFrequency(30)
    triggerOnlyLatestJob(true)
    alwaysAllowManualTrigger(true)
}

buildMonitorView('Build Monitor') {
    description('Visual build monitor for all infrastructure jobs')
    
    jobs {
        regex('Infrastructure/.*')
        name('job-dsl-seed')
    }
    
    displayCommitters(true)
    buildStatusDisplayedInColumns(false)
}

categorizedJobsView('Infrastructure/Categorized View') {
    displayName('Categorized Infrastructure View')
    description('Jobs organized by category and function')
    
    categorizationCriteria {
        regexGroupingRule {
            groupRegex('Infrastructure/(.*?)-.*')
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

// =============================================================================
// DASHBOARD VIEWS FOR OPERATIONS
// =============================================================================

dashboardView('Operations Dashboard') {
    description('Operational dashboard with key metrics and status')
    
    jobs {
        regex('Infrastructure/.*')
        regex('.*/.*[Mm]onitor.*')
        regex('.*/.*[Hh]ealth.*')
        regex('.*/.*[Bb]ackup.*')
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
    
    topPortlet {
        jenkinsJobsList {
            displayName('Critical Infrastructure Jobs')
        }
    }
    
    leftPortlet {
        buildStatistics {
            displayName('Build Statistics')
        }
    }
    
    rightPortlet {
        testStatisticsChart {
            displayName('Test Trends')
        }
    }
    
    bottomPortlet {
        testTrendChart {
            displayName('Test Result Trends')
        }
    }
}

println "✅ All views created successfully - Single source of truth established"