// Monitoring Stack Setup Pipeline Job
// References: pipelines/Jenkinsfile.monitoring

pipelineJob('Infrastructure/Monitoring-Setup') {
    displayName('Monitoring Stack Setup')
    description('''
        Infrastructure Pipeline: Setup and Configure Monitoring Stack
        
        This pipeline manages:
        - Prometheus metrics collection setup
        - Grafana dashboards deployment
        - Alerting rules configuration
        - Performance metrics validation
        
        Script: pipelines/Jenkinsfile.monitoring
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('30')
                    numToKeepStr('20')
                    artifactDaysToKeepStr('-1')
                    artifactNumToKeepStr('-1')
                }
            }
        }
        
        parameters {
            choiceParam {
                name('MONITORING_ACTION')
                description('Monitoring operation to perform')
                choices(['setup', 'update-dashboards', 'update-rules', 'health-check', 'reset'])
            }
            booleanParam {
                name('RESTART_SERVICES')
                description('Restart monitoring services after changes')
                defaultValue(true)
            }
            booleanParam {
                name('VALIDATE_METRICS')
                description('Validate metrics collection after setup')
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
            scriptPath('pipelines/Jenkinsfile.monitoring')
            lightweight(true)
        }
    }
}

println "Monitoring Setup pipeline job created successfully"