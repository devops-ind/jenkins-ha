// Jenkins Backup Pipeline Job
// References: pipelines/Jenkinsfile.backup

pipelineJob('Infrastructure/Backup-Pipeline') {
    displayName('Jenkins Backup Pipeline')
    description('''
        Infrastructure Pipeline: Automated Backup and Recovery System
        
        This pipeline manages comprehensive backup operations for:
        - Jenkins home directory and job configurations
        - Docker volumes and shared storage
        - Configuration files and SSL certificates
        - Monitoring data and system configurations
        
        Script: pipelines/Jenkinsfile.backup
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('90')
                    numToKeepStr('50')
                    artifactDaysToKeepStr('-1')
                    artifactNumToKeepStr('-1')
                }
            }
        }
        
        pipelineTriggers {
            triggers {
                cron {
                    spec('0 2 * * 1-6')  // Daily incremental backups
                }
            }
        }
        
        parameters {
            choiceParam {
                name('BACKUP_TYPE')
                description('Type of backup to perform')
                choices(['incremental', 'full', 'configuration-only', 'volumes-only'])
            }
            booleanParam {
                name('VERIFY_BACKUP')
                description('Verify backup integrity after creation')
                defaultValue(true)
            }
            booleanParam {
                name('CLEANUP_OLD_BACKUPS')
                description('Clean up old backups according to retention policy')
                defaultValue(true)
            }
            stringParam {
                name('CUSTOM_TAG')
                description('Custom tag for backup (optional)')
                defaultValue('')
                trim(true)
            }
            booleanParam {
                name('SEND_NOTIFICATIONS')
                description('Send backup status notifications')
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
            scriptPath('pipelines/Jenkinsfile.backup')
            lightweight(true)
        }
    }
}

println "Backup pipeline job created successfully"