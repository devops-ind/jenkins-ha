// Health Check Pipeline Job
// References: pipelines/Jenkinsfile.health-check

pipelineJob('Infrastructure/Health-Check') {
    displayName('Health Check Pipeline')
    description('''
        Infrastructure Pipeline: Comprehensive Health Monitoring
        
        This pipeline performs:
        - Jenkins master and agent health checks
        - Service availability monitoring
        - Resource utilization checks
        - Network connectivity validation
        
        Script: pipelines/Jenkinsfile.health-check
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('30')
                    numToKeepStr('50')
                    artifactDaysToKeepStr('-1')
                    artifactNumToKeepStr('-1')
                }
            }
        }
        
        pipelineTriggers {
            triggers {
                cron {
                    spec('H/15 * * * *')  // Every 15 minutes
                }
            }
        }
        
        parameters {
            choiceParam {
                name('CHECK_SCOPE')
                description('Scope of health checks')
                choices(['all', 'masters-only', 'services-only', 'network-only'])
            }
            booleanParam {
                name('DETAILED_REPORTING')
                description('Generate detailed health reports')
                defaultValue(false)
            }
            booleanParam {
                name('SEND_ALERTS')
                description('Send alerts for failed health checks')
                defaultValue(true)
            }
        }
    }
    
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
            scriptPath('pipelines/Jenkinsfile.health-check')
            lightweight(false)  // Full repository checkout required for ansible code
        }
    }
}

println "Health Check pipeline job created successfully"