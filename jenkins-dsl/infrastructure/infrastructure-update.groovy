// Infrastructure Update Pipeline Job
// References: pipelines/Jenkinsfile.infrastructure-update

pipelineJob('Infrastructure/Infrastructure-Update') {
    displayName('Infrastructure Update Pipeline')
    description('''
        Infrastructure Pipeline: Update and Maintenance Operations
        
        This pipeline handles:
        - Rolling updates of Jenkins masters and agents
        - Configuration updates and deployments
        - System maintenance and health checks
        - Plugin updates and compatibility checks
        
        Script: pipelines/Jenkinsfile.infrastructure-update
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('60')
                    numToKeepStr('30')
                    artifactDaysToKeepStr('-1')
                    artifactNumToKeepStr('-1')
                }
            }
        }
        
        parameters {
            stringParam {
                name('IMAGE_TAG')
                description('Image tag to deploy (default: latest)')
                defaultValue('latest')
                trim(true)
            }
            booleanParam {
                name('RESTART_SERVICES')
                description('Restart Jenkins services after update')
                defaultValue(false)
            }
            stringParam {
                name('UPDATE_REASON')
                description('Reason for the update')
                defaultValue('Manual update')
                trim(true)
            }
            choiceParam {
                name('UPDATE_SCOPE')
                description('Scope of the update')
                choices(['all', 'masters-only', 'configuration-only'])
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
            scriptPath('pipelines/Jenkinsfile.infrastructure-update')
            lightweight(true)
        }
    }
}

println "Infrastructure Update pipeline job created successfully"