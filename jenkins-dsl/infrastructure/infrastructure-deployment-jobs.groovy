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

pipelineJob('Infrastructure/Blue-Green-Switch') {
    displayName('Blue-Green Switch')
    description('''
        Dedicated job for switching traffic between blue and green environments.

        Use this when:
        - You've already deployed to passive environment and validated it
        - You want to switch without full deployment cycle (8-15 min vs 30-50 min)
        - You need to quickly rollback to previous environment
        - A/B testing between environments

        Features:
        - Zero-downtime switching (0 seconds downtime)
        - Sequential (safer) or Parallel (faster) strategies
        - Pre-switch and post-switch validation
        - Automatic rollback on failure
        - Post-switch monitoring (10 minutes)
        - Manual approval gate (required for all environments)
        - Dry-run mode for testing

        Performance:
        - Sequential: 15-20 minutes (safer, one team at a time)
        - Parallel: 8-12 minutes (faster, all teams simultaneously)
        - Rollback: <30 seconds
    ''')

    parameters {
        choiceParam('SWITCH_SCOPE', ['team-specific', 'all-teams', 'vm-wide'], 'Scope of switch operation')
        stringParam('TEAMS_TO_SWITCH', 'all', 'Teams to switch (comma-separated): devops,ma,ba,tw OR all')
        choiceParam('TARGET_VM', ['jenkins_hosts_01', 'jenkins_hosts_02', 'all'], 'Target VM for switch operation')
        choiceParam('SWITCH_DIRECTION', ['auto', 'force-blue', 'force-green'], 'Switch direction (auto=detect current and toggle)')
        choiceParam('SWITCH_STRATEGY', ['sequential', 'parallel'], 'Sequential (safer) or Parallel (faster)')
        booleanParam('SKIP_PRE_SWITCH_VALIDATION', false, '⚠️ DANGEROUS: Skip pre-switch health checks')
        booleanParam('SKIP_POST_SWITCH_VALIDATION', false, 'Skip post-switch validation')
        booleanParam('AUTO_ROLLBACK_ON_FAILURE', true, 'Automatically rollback if validation fails')
        stringParam('ROLLBACK_TIMEOUT_SECONDS', '600', 'Rollback timeout in seconds (default=600=10min)')
        stringParam('MONITORING_DURATION_SECONDS', '600', 'Post-switch monitoring duration (default=600=10min)')
        choiceParam('NOTIFICATION_CHANNEL', ['teams', 'email', 'both', 'none'], 'Notification channel')
        booleanParam('DRY_RUN', false, 'Preview mode - show what would happen without executing')
    }

    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    numToKeepStr('50')
                    artifactNumToKeepStr('20')
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
            scriptPath('pipelines/Jenkinsfile.blue-green-switch')
            lightweight(true)
        }
    }

    triggers {
        // No automatic triggers - manual execution only
    }
}
