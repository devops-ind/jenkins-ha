// Repository Monitor Job DSL
// Monitors Git repository for changes and triggers Job DSL Seed processing

pipelineJob('Infrastructure/Repository-Monitor') {
    displayName('Repository Monitor & Job DSL Trigger')
    description('''
        Monitors Git repository for Job DSL script changes and triggers processing.
        
        Features:
        • Continuous monitoring of Git repository
        • Change detection for Job DSL scripts
        • Automatic triggering of Job DSL Seed job
        • Branch comparison and diff analysis
        • Notification of repository changes
        
        This job complements the Job-DSL-Seed job by providing:
        • Enhanced monitoring capabilities
        • Pre-processing validation
        • Change impact analysis
        • Automated workflow triggering
    ''')
    
    parameters {
        stringParam('GIT_REPOSITORY', 'https://github.com/your-org/jenkins-ha.git', 'Git repository to monitor')
        stringParam('MONITOR_BRANCH', 'main', 'Git branch to monitor for changes')
        credentialsParam('GIT_CREDENTIALS') {
            type('com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl')
            description('Git repository credentials')
            defaultValue('git-credentials')
        }
        stringParam('DSL_SCRIPTS_PATH', 'jenkins-dsl', 'Path containing Job DSL scripts')
        choiceParam('POLLING_FREQUENCY', ['5', '10', '15', '30', '60'], 'Polling frequency in minutes')
        booleanParam('AUTO_TRIGGER_SEED', true, 'Automatically trigger Job DSL Seed on changes')
        booleanParam('ANALYZE_CHANGES', true, 'Perform detailed change analysis')
        stringParam('NOTIFICATION_CHANNEL', '#jenkins-ops', 'Slack channel for notifications (optional)')
    }
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    numToKeepStr('50')
                    daysToKeepStr('30')
                    artifactDaysToKeepStr('7')
                    artifactNumToKeepStr('10')
                }
            }
        }
        pipelineTriggers {
            triggers {
                scm("H/${params.POLLING_FREQUENCY ?: '10'} * * * *")
            }
        }
    }
    
    definition {
        cps {
            script('''
pipeline {
    agent any
    
    options {
        timeout(time: 15, unit: 'MINUTES')
        timestamps()
        ansiColor('xterm')
        skipDefaultCheckout()
    }
    
    environment {
        PREVIOUS_COMMIT_FILE = "${WORKSPACE}/.previous-commit"
        CHANGE_ANALYSIS_FILE = "${WORKSPACE}/change-analysis.txt"
    }
    
    stages {
        stage('Repository Checkout') {
            steps {
                script {
                    echo "🔄 Monitoring repository: ${params.GIT_REPOSITORY}"
                    echo "📋 Branch: ${params.MONITOR_BRANCH}"
                    
                    // Checkout repository
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: "*/${params.MONITOR_BRANCH}"]],
                        doGenerateSubmoduleConfigurations: false,
                        extensions: [[$class: 'CleanBeforeCheckout']],
                        submoduleCfg: [],
                        userRemoteConfigs: [[
                            credentialsId: params.GIT_CREDENTIALS,
                            url: params.GIT_REPOSITORY
                        ]]
                    ])
                    
                    // Get current commit info
                    env.CURRENT_COMMIT = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true
                    ).trim()
                    
                    env.CURRENT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    
                    env.COMMIT_MESSAGE = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()
                    
                    env.COMMIT_AUTHOR = sh(
                        script: 'git log -1 --pretty="%an <%ae>"',
                        returnStdout: true
                    ).trim()
                    
                    env.COMMIT_TIMESTAMP = sh(
                        script: 'git log -1 --pretty=%ci',
                        returnStdout: true
                    ).trim()
                    
                    echo "📊 Current commit: ${env.CURRENT_COMMIT_SHORT}"
                    echo "👤 Author: ${env.COMMIT_AUTHOR}"
                    echo "📅 Timestamp: ${env.COMMIT_TIMESTAMP}"
                    echo "💬 Message: ${env.COMMIT_MESSAGE}"
                }
            }
        }
        
        stage('Detect Changes') {
            steps {
                script {
                    def hasChanges = false
                    def previousCommit = ''
                    
                    // Read previous commit if exists
                    if (fileExists(env.PREVIOUS_COMMIT_FILE)) {
                        previousCommit = readFile(env.PREVIOUS_COMMIT_FILE).trim()
                        echo "📋 Previous commit: ${previousCommit}"
                    } else {
                        echo "📋 No previous commit found - first run"
                        previousCommit = env.CURRENT_COMMIT
                        hasChanges = true
                    }
                    
                    // Compare commits
                    if (previousCommit != env.CURRENT_COMMIT) {
                        hasChanges = true
                        echo "🔍 Changes detected between ${previousCommit} and ${env.CURRENT_COMMIT}"
                        
                        if (params.ANALYZE_CHANGES) {
                            // Analyze what changed
                            def changedFiles = sh(
                                script: "git diff --name-only ${previousCommit}..${env.CURRENT_COMMIT}",
                                returnStdout: true
                            ).trim()
                            
                            if (changedFiles) {
                                def fileList = changedFiles.split('\\n')
                                env.CHANGED_FILES_COUNT = fileList.size().toString()
                                env.CHANGED_FILES = changedFiles
                                
                                echo "📁 Changed files (${env.CHANGED_FILES_COUNT}):"
                                fileList.each { file ->
                                    echo "   • ${file}"
                                }
                                
                                // Check if Job DSL scripts changed
                                def dslChanges = fileList.findAll { 
                                    it.startsWith(params.DSL_SCRIPTS_PATH) && it.endsWith('.groovy')
                                }
                                
                                if (dslChanges) {
                                    env.DSL_CHANGES_COUNT = dslChanges.size().toString()
                                    env.DSL_CHANGED_FILES = dslChanges.join('\\n')
                                    
                                    echo "🎯 Job DSL script changes detected (${env.DSL_CHANGES_COUNT}):"
                                    dslChanges.each { file ->
                                        echo "   • ${file}"
                                    }
                                } else {
                                    env.DSL_CHANGES_COUNT = '0'
                                    echo "ℹ️  No Job DSL script changes detected"
                                }
                                
                                // Analyze change types
                                def addedFiles = sh(
                                    script: "git diff --name-only --diff-filter=A ${previousCommit}..${env.CURRENT_COMMIT}",
                                    returnStdout: true
                                ).trim()
                                
                                def modifiedFiles = sh(
                                    script: "git diff --name-only --diff-filter=M ${previousCommit}..${env.CURRENT_COMMIT}",
                                    returnStdout: true
                                ).trim()
                                
                                def deletedFiles = sh(
                                    script: "git diff --name-only --diff-filter=D ${previousCommit}..${env.CURRENT_COMMIT}",
                                    returnStdout: true
                                ).trim()
                                
                                env.ADDED_FILES_COUNT = addedFiles ? addedFiles.split('\\n').size().toString() : '0'
                                env.MODIFIED_FILES_COUNT = modifiedFiles ? modifiedFiles.split('\\n').size().toString() : '0'
                                env.DELETED_FILES_COUNT = deletedFiles ? deletedFiles.split('\\n').size().toString() : '0'
                                
                                echo "📈 Change analysis:"
                                echo "   Added: ${env.ADDED_FILES_COUNT} files"
                                echo "   Modified: ${env.MODIFIED_FILES_COUNT} files"
                                echo "   Deleted: ${env.DELETED_FILES_COUNT} files"
                            } else {
                                echo "ℹ️  No file changes detected (possibly commit message only)"
                                hasChanges = false
                            }
                        }
                    } else {
                        echo "ℹ️  No new commits detected"
                    }
                    
                    env.HAS_CHANGES = hasChanges.toString()
                    env.PREVIOUS_COMMIT = previousCommit
                }
            }
        }
        
        stage('Generate Change Report') {
            when {
                expression { env.HAS_CHANGES == 'true' }
            }
            steps {
                script {
                    echo "📋 Generating change analysis report..."
                    
                    def report = """# Repository Change Analysis Report

## Commit Information
- **Current Commit**: ${env.CURRENT_COMMIT}
- **Previous Commit**: ${env.PREVIOUS_COMMIT}
- **Author**: ${env.COMMIT_AUTHOR}
- **Timestamp**: ${env.COMMIT_TIMESTAMP}
- **Message**: ${env.COMMIT_MESSAGE}

## Change Summary
- **Total Files Changed**: ${env.CHANGED_FILES_COUNT ?: '0'}
- **Added Files**: ${env.ADDED_FILES_COUNT ?: '0'}
- **Modified Files**: ${env.MODIFIED_FILES_COUNT ?: '0'}
- **Deleted Files**: ${env.DELETED_FILES_COUNT ?: '0'}

## Job DSL Impact
- **DSL Scripts Changed**: ${env.DSL_CHANGES_COUNT ?: '0'}
- **Auto-trigger Seed Job**: ${params.AUTO_TRIGGER_SEED}
"""
                    
                    if (env.DSL_CHANGED_FILES) {
                        report += """
### Changed Job DSL Scripts
${env.DSL_CHANGED_FILES}
"""
                    }
                    
                    if (env.CHANGED_FILES) {
                        report += """
### All Changed Files
${env.CHANGED_FILES}
"""
                    }
                    
                    report += """
## Recommended Actions
"""
                    
                    if (env.DSL_CHANGES_COUNT?.toInteger() > 0) {
                        report += """
1. ✅ **Job DSL Seed job will be triggered automatically**
2. 🔍 Review Job DSL script changes before deployment
3. 🧪 Consider running Seed job in dry-run mode first
4. 📋 Verify job configurations after processing
"""
                    } else {
                        report += """
1. ℹ️  No Job DSL scripts changed - Seed job trigger not required
2. 📋 Changes may affect other pipeline jobs or configurations
3. 🔍 Review changes for impact on Jenkins infrastructure
"""
                    }
                    
                    writeFile file: env.CHANGE_ANALYSIS_FILE, text: report
                    echo "✅ Change analysis report generated"
                }
            }
        }
        
        stage('Trigger Job DSL Seed') {
            when {
                allOf {
                    expression { env.HAS_CHANGES == 'true' }
                    expression { params.AUTO_TRIGGER_SEED }
                    expression { env.DSL_CHANGES_COUNT?.toInteger() > 0 }
                }
            }
            steps {
                script {
                    echo "🚀 Triggering Job DSL Seed job due to DSL script changes..."
                    
                    try {
                        def seedJobParams = [
                            string(name: 'GIT_REPOSITORY', value: params.GIT_REPOSITORY),
                            string(name: 'DSL_BRANCH', value: params.MONITOR_BRANCH),
                            string(name: 'GIT_CREDENTIALS', value: params.GIT_CREDENTIALS),
                            string(name: 'DSL_SCRIPTS_PATH', value: params.DSL_SCRIPTS_PATH),
                            choice(name: 'REMOVAL_ACTION', choices: ['IGNORE', 'DELETE', 'DISABLE'], value: 'IGNORE'),
                            booleanParam(name: 'DRY_RUN', value: false),
                            choice(name: 'LOG_LEVEL', choices: ['INFO', 'DEBUG', 'WARN'], value: 'INFO'),
                            booleanParam(name: 'PROCESS_VIEWS', value: true),
                            booleanParam(name: 'VALIDATE_BEFORE_APPLY', value: true)
                        ]
                        
                        def seedBuild = build job: 'Infrastructure/Job-DSL-Seed', 
                                            parameters: seedJobParams,
                                            wait: false,
                                            propagate: false
                        
                        env.SEED_BUILD_NUMBER = seedBuild.number.toString()
                        env.SEED_BUILD_URL = seedBuild.absoluteUrl
                        
                        echo "✅ Job DSL Seed job triggered successfully"
                        echo "   Build Number: ${env.SEED_BUILD_NUMBER}"
                        echo "   Build URL: ${env.SEED_BUILD_URL}"
                        
                    } catch (Exception e) {
                        echo "❌ Failed to trigger Job DSL Seed job: ${e.message}"
                        unstable "Failed to trigger Job DSL Seed job"
                    }
                }
            }
        }
        
        stage('Update State') {
            when {
                expression { env.HAS_CHANGES == 'true' }
            }
            steps {
                script {
                    // Store current commit as previous for next run
                    writeFile file: env.PREVIOUS_COMMIT_FILE, text: env.CURRENT_COMMIT
                    echo "✅ Updated state with current commit: ${env.CURRENT_COMMIT_SHORT}"
                }
            }
        }
    }
    
    post {
        always {
            script {
                // Archive change analysis report if it exists
                if (fileExists(env.CHANGE_ANALYSIS_FILE)) {
                    archiveArtifacts(
                        artifacts: 'change-analysis.txt',
                        allowEmptyArchive: true,
                        fingerprint: false
                    )
                }
            }
        }
        
        success {
            script {
                if (env.HAS_CHANGES == 'true') {
                    def message = env.DSL_CHANGES_COUNT?.toInteger() > 0 ?
                        "🔄 Repository changes detected and Job DSL Seed triggered (${env.DSL_CHANGES_COUNT} DSL scripts changed)" :
                        "🔄 Repository changes detected (no DSL script changes)"
                    
                    echo "✅ ${message}"
                    
                    // Optional: Send notification
                    if (params.NOTIFICATION_CHANNEL && env.SLACK_WEBHOOK) {
                        slackSend(
                            channel: params.NOTIFICATION_CHANNEL,
                            color: 'good',
                            message: """${message}
                            
📋 **Commit**: ${env.CURRENT_COMMIT_SHORT} by ${env.COMMIT_AUTHOR}
💬 **Message**: ${env.COMMIT_MESSAGE}
${env.SEED_BUILD_URL ? "🔗 **Seed Job**: ${env.SEED_BUILD_URL}" : ""}"""
                        )
                    }
                } else {
                    echo "ℹ️  Repository monitoring completed - no changes detected"
                }
            }
        }
        
        failure {
            script {
                echo "❌ Repository monitoring failed!"
                
                if (params.NOTIFICATION_CHANNEL && env.SLACK_WEBHOOK) {
                    slackSend(
                        channel: params.NOTIFICATION_CHANNEL,
                        color: 'danger',
                        message: "❌ Repository monitor failed for ${params.GIT_REPOSITORY} (branch: ${params.MONITOR_BRANCH})"
                    )
                }
            }
        }
    }
}
            ''')
            sandbox()
        }
    }
}