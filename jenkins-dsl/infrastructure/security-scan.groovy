// Security Scan Pipeline Job
// References: pipelines/Jenkinsfile.security-scan

pipelineJob('Infrastructure/Security-Scan') {
    displayName('Security Scan Pipeline')
    description('''
        Infrastructure Pipeline: Security Scanning and Compliance
        
        This pipeline performs:
        - Container image vulnerability scanning
        - Security compliance checks
        - Configuration security validation
        - Security report generation
        
        Script: pipelines/Jenkinsfile.security-scan
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('90')
                    numToKeepStr('40')
                    artifactDaysToKeepStr('30')
                    artifactNumToKeepStr('10')
                }
            }
        }
        
        pipelineTriggers {
            triggers {
                cron {
                    spec('H 3 * * 1')  // Weekly on Monday at 3 AM
                }
            }
        }
        
        parameters {
            choiceParam {
                name('SCAN_TYPE')
                description('Type of security scan to perform')
                choices(['full', 'images-only', 'configs-only', 'compliance-only'])
            }
            booleanParam {
                name('FAIL_ON_HIGH_SEVERITY')
                description('Fail pipeline on high severity vulnerabilities')
                defaultValue(true)
            }
            booleanParam {
                name('GENERATE_REPORTS')
                description('Generate detailed security reports')
                defaultValue(true)
            }
            booleanParam {
                name('SEND_NOTIFICATIONS')
                description('Send security scan notifications')
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
            scriptPath('pipelines/Jenkinsfile.security-scan')
            lightweight(false)  // Full repository checkout required for ansible code
        }
    }
}

println "Security Scan pipeline job created successfully"