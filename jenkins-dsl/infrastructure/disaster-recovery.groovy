// Disaster Recovery Pipeline Job
// References: pipelines/Jenkinsfile.disaster-recovery

pipelineJob('Infrastructure/Disaster-Recovery') {
    displayName('Disaster Recovery Pipeline')
    description('''
        Infrastructure Pipeline: Disaster Recovery Operations
        
        This pipeline handles:
        - Disaster recovery procedures
        - System restoration from backups
        - Emergency failover operations
        - Recovery validation and testing
        
        Script: pipelines/Jenkinsfile.disaster-recovery
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('180')
                    numToKeepStr('50')
                    artifactDaysToKeepStr('90')
                    artifactNumToKeepStr('20')
                }
            }
        }
        
        parameters {
            choiceParam {
                name('RECOVERY_TYPE')
                description('Type of recovery to perform')
                choices(['full-restore', 'partial-restore', 'failover', 'test-recovery'])
            }
            stringParam {
                name('BACKUP_TIMESTAMP')
                description('Specific backup timestamp to restore from')
                defaultValue('')
                trim(true)
            }
            booleanParam {
                name('VALIDATE_RECOVERY')
                description('Validate recovery operation')
                defaultValue(true)
            }
            booleanParam {
                name('DRY_RUN')
                description('Perform dry run without actual recovery')
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
            scriptPath('pipelines/Jenkinsfile.disaster-recovery')
            lightweight(false)  // Full repository checkout required for ansible code
        }
    }
}

println "Disaster Recovery pipeline job created successfully"