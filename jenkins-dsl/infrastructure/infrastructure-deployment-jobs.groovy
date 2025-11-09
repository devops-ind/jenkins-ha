// Job DSL Script for Infrastructure Deployment Jobs
// Creates: Infrastructure-Deployment and Infrastructure-Rollback jobs

folder('Infrastructure') {
    displayName('Infrastructure Management')
    description('Jobs for deploying and managing infrastructure components')
}

pipelineJob('Infrastructure/Infrastructure-Deployment') {
    displayName('Infrastructure Deployment')
    description('''
        Unified pipeline for deploying infrastructure components with blue-green deployment support.

        Components:
        - Jenkins Masters (with GlusterFS data recovery and blue-green deployment)
        - HAProxy (rolling update with zero downtime)
        - Monitoring Stack (Prometheus, Grafana, Loki, Alertmanager)

        Features:
        - Deploy to specific VMs or all VMs
        - Deploy specific teams or all teams
        - Data recovery from GlusterFS
        - Comprehensive validation
        - Manual approval gates
        - Automatic rollback on failure
        - Zero-downtime blue-green switching
    ''')

    parameters {
        choiceParam('COMPONENT', ['jenkins-masters', 'haproxy', 'monitoring', 'all'], 'Component to deploy')
        choiceParam('TARGET_VM', ['jenkins_hosts_01', 'jenkins_hosts_02', 'monitoring', 'all'], 'Target VM for deployment')
        stringParam('DEPLOY_TEAMS', 'all', 'Teams to deploy (comma-separated): devops,ma,ba,tw OR all')
        choiceParam('TARGET_ENVIRONMENT', ['auto', 'blue', 'green'], 'Blue-green environment (auto=detect passive)')
        booleanParam('SKIP_DATA_RECOVERY', false, 'Skip GlusterFS data recovery (for fresh deployment)')
        booleanParam('SKIP_VALIDATION', false, 'Skip post-deployment validation tests')
        booleanParam('DRY_RUN', false, 'Dry-run mode (Ansible --check)')
        booleanParam('AUTO_SWITCH', false, 'Automatically switch after validation (no approval gate)')
        choiceParam('NOTIFICATION_CHANNEL', ['teams', 'email', 'both'], 'Notification channel')
    }

    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    numToKeepStr('30')
                    artifactNumToKeepStr('10')
                }
            }
        }
        disableConcurrentBuilds()
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('${GIT_REPO_URL}')
                        credentials('git-credentials')
                    }
                    branch('*/main')
                }
            }
            scriptPath('pipelines/Jenkinsfile.infrastructure-deployment')
            lightweight(true)
        }
    }

    triggers {
        // No automatic triggers - manual execution only
    }
}

pipelineJob('Infrastructure/Infrastructure-Rollback') {
    displayName('Infrastructure Rollback')
    description('''
        Emergency rollback pipeline for infrastructure deployments.

        Switches back to previous active environment in case of issues.

        Rollback Time: <30 seconds (blue-green architecture)
    ''')

    parameters {
        choiceParam('TARGET_VM', ['jenkins_hosts_01', 'jenkins_hosts_02', 'all'], 'Target VM for rollback')
        stringParam('ROLLBACK_TEAMS', 'all', 'Teams to rollback (comma-separated) OR all')
        stringParam('ROLLBACK_REASON', '', 'Reason for rollback (required)')
    }

    definition {
        cps {
            script('''
pipeline {
    agent { label 'master' }

    stages {
        stage('Validate Rollback Request') {
            steps {
                script {
                    if (params.ROLLBACK_REASON.trim() == '') {
                        error("Rollback reason is required!")
                    }

                    echo """
                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    🔄 Infrastructure Rollback
                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    Target VM: ${params.TARGET_VM}
                    Teams: ${params.ROLLBACK_TEAMS}
                    Reason: ${params.ROLLBACK_REASON}
                    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    """
                }
            }
        }

        stage('Execute Rollback') {
            steps {
                script {
                    def targetLimit = params.TARGET_VM == 'all' ? 'jenkins_masters' : params.TARGET_VM
                    def extraVars = ""

                    if (params.ROLLBACK_TEAMS != 'all') {
                        extraVars = "-e 'deploy_teams=${params.ROLLBACK_TEAMS}'"
                    }

                    sh """
                        ansible-playbook -i ansible/inventories/production/hosts.yml \\
                            ansible/playbooks/blue-green-switch.yml \\
                            --limit ${targetLimit} \\
                            ${extraVars} \\
                            -e 'rollback_mode=true'
                    """
                }
            }
        }

        stage('Verify Rollback') {
            steps {
                script {
                    sleep(10)

                    sh """
                        ansible jenkins_masters -i ansible/inventories/production/hosts.yml \\
                            -m uri \\
                            -a 'url=http://localhost:8080/login status_code=200,403'
                    """
                }
            }
        }
    }

    post {
        success {
            echo "✅ Rollback completed successfully"
        }
        failure {
            echo "❌ Rollback failed - manual intervention required!"
        }
    }
}
            '''.stripIndent())
            sandbox(true)
        }
    }
}
