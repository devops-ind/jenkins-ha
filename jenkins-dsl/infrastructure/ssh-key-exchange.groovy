// SSH Key Exchange Pipeline Job DSL
// Securely distribute Jenkins SSH keys to remote hosts

pipelineJob('Infrastructure/SSH-Key-Exchange') {
    displayName('SSH Key Exchange - Deploy Jenkins Keys to Remote Hosts')
    description('''
        Distributes Jenkins SSH public keys to remote hosts for passwordless authentication.
        
        Features:
        • Uses Jenkins SSH credentials for secure key management
        • Supports password or key-based initial authentication
        • Validates SSH connectivity before and after key deployment
        • Logs deployment status and provides rollback capability
        • Multi-host support with parallel execution
        
        Security:
        • All credentials stored in Jenkins credential store
        • Passwords masked in console output
        • SSH keys never exposed in logs
        • Supports both password and existing key authentication
    ''')
    
    parameters {
        stringParam('TARGET_HOSTS', '', 'Comma-separated list of target host IPs or hostnames (e.g., 192.168.188.142,server1.example.com)')
        stringParam('SSH_USERNAME', 'root', 'Username for SSH connection to target hosts')
        credentialsParam('SSH_PRIVATE_KEY_ID') {
            type('com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey')
            description('Jenkins SSH private key credential to use for authentication')
            defaultValue('jenkins-ssh-key')
        }
        credentialsParam('TARGET_HOST_PASSWORD') {
            type('com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl')
            description('Username/password for initial authentication to target hosts (optional if key auth already works)')
            defaultValue('')
        }
        choiceParam('AUTH_METHOD', ['password', 'existing_key', 'both'], 'Authentication method for initial connection')
        stringParam('SSH_PORT', '22', 'SSH port on target hosts')
        booleanParam('VALIDATE_CONNECTIVITY', true, 'Validate SSH connectivity before and after key deployment')
        booleanParam('BACKUP_AUTHORIZED_KEYS', true, 'Create backup of existing authorized_keys file')
        booleanParam('DRY_RUN', false, 'Perform dry run without making changes')
        choiceParam('EXECUTION_MODE', ['parallel', 'sequential'], 'How to process multiple hosts')
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
        disableConcurrentBuilds()
        parameters {
            // Parameters defined above
        }
    }
    
    definition {
        cps {
            script('''
pipeline {
    agent any
    
    options {
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        ansiColor('xterm')
        skipStagesAfterUnstable()
    }
    
    environment {
        SSH_OPTS = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
        BACKUP_SUFFIX = "_backup_${BUILD_NUMBER}_${BUILD_TIMESTAMP}"
    }
    
    stages {
        stage('Validate Parameters') {
            steps {
                script {
                    if (!params.TARGET_HOSTS?.trim()) {
                        error "TARGET_HOSTS parameter is required"
                    }
                    
                    if (!params.SSH_PRIVATE_KEY_ID?.trim()) {
                        error "SSH_PRIVATE_KEY_ID parameter is required"
                    }
                    
                    if (params.AUTH_METHOD in ['password', 'both'] && !params.TARGET_HOST_PASSWORD?.trim()) {
                        error "TARGET_HOST_PASSWORD is required when using password authentication"
                    }
                    
                    // Parse and validate hosts
                    def hosts = params.TARGET_HOSTS.split(',').collect { it.trim() }.findAll { it }
                    if (hosts.isEmpty()) {
                        error "No valid hosts found in TARGET_HOSTS"
                    }
                    
                    env.HOST_COUNT = hosts.size().toString()
                    env.HOST_LIST = hosts.join(' ')
                    
                    echo "✓ Validated ${env.HOST_COUNT} target hosts: ${env.HOST_LIST}"
                    echo "✓ SSH Username: ${params.SSH_USERNAME}"
                    echo "✓ SSH Port: ${params.SSH_PORT}"
                    echo "✓ Authentication Method: ${params.AUTH_METHOD}"
                    echo "✓ Execution Mode: ${params.EXECUTION_MODE}"
                    echo "✓ Dry Run: ${params.DRY_RUN}"
                }
            }
        }
        
        stage('Prepare SSH Configuration') {
            steps {
                script {
                    // Extract public key from private key credential
                    withCredentials([sshUserPrivateKey(
                        credentialsId: params.SSH_PRIVATE_KEY_ID,
                        keyFileVariable: 'SSH_PRIVATE_KEY_FILE',
                        usernameVariable: 'SSH_KEY_USERNAME'
                    )]) {
                        // Generate public key from private key
                        def pubKeyResult = sh(
                            script: "ssh-keygen -y -f ${SSH_PRIVATE_KEY_FILE}",
                            returnStdout: true
                        ).trim()
                        
                        if (!pubKeyResult) {
                            error "Failed to extract public key from private key credential"
                        }
                        
                        // Add comment to public key
                        def pubKeyWithComment = "${pubKeyResult} jenkins-master-${env.JENKINS_URL?.replaceAll('https?://', '')?.replaceAll('/', '-') ?: 'unknown'}-${env.BUILD_NUMBER}"
                        
                        writeFile file: 'jenkins_public_key.pub', text: pubKeyWithComment
                        env.PUBLIC_KEY_FINGERPRINT = sh(
                            script: "ssh-keygen -lf jenkins_public_key.pub | awk '{print \$2}'",
                            returnStdout: true
                        ).trim()
                        
                        echo "✓ Generated public key with fingerprint: ${env.PUBLIC_KEY_FINGERPRINT}"
                    }
                }
            }
        }
        
        stage('Test Initial Connectivity') {
            when { 
                expression { params.VALIDATE_CONNECTIVITY }
            }
            steps {
                script {
                    def hosts = params.TARGET_HOSTS.split(',').collect { it.trim() }.findAll { it }
                    def connectivityResults = [:]
                    
                    echo "🔍 Testing initial connectivity to ${hosts.size()} hosts..."
                    
                    def testConnectivity = { host ->
                        try {
                            def testCmd = "echo 'Connection test successful'"
                            
                            if (params.AUTH_METHOD in ['password', 'both'] && params.TARGET_HOST_PASSWORD) {
                                withCredentials([usernamePassword(
                                    credentialsId: params.TARGET_HOST_PASSWORD,
                                    usernameVariable: 'TARGET_USER',
                                    passwordVariable: 'TARGET_PASS'
                                )]) {
                                    sh """
                                        sshpass -p '\${TARGET_PASS}' ssh ${env.SSH_OPTS} -p ${params.SSH_PORT} \${TARGET_USER}@${host} '${testCmd}'
                                    """
                                }
                                return [status: 'success', method: 'password']
                            } else if (params.AUTH_METHOD in ['existing_key', 'both']) {
                                withCredentials([sshUserPrivateKey(
                                    credentialsId: params.SSH_PRIVATE_KEY_ID,
                                    keyFileVariable: 'SSH_KEY_FILE'
                                )]) {
                                    sh """
                                        ssh ${env.SSH_OPTS} -i \${SSH_KEY_FILE} -p ${params.SSH_PORT} ${params.SSH_USERNAME}@${host} '${testCmd}'
                                    """
                                }
                                return [status: 'success', method: 'key']
                            }
                        } catch (Exception e) {
                            return [status: 'failed', error: e.message]
                        }
                    }
                    
                    if (params.EXECUTION_MODE == 'parallel') {
                        def parallelTests = [:]
                        hosts.each { host ->
                            parallelTests[host] = {
                                connectivityResults[host] = testConnectivity(host)
                            }
                        }
                        parallel parallelTests
                    } else {
                        hosts.each { host ->
                            connectivityResults[host] = testConnectivity(host)
                        }
                    }
                    
                    // Report results
                    def successCount = 0
                    def failCount = 0
                    
                    connectivityResults.each { host, result ->
                        if (result.status == 'success') {
                            echo "✓ ${host}: Connected successfully via ${result.method}"
                            successCount++
                        } else {
                            echo "✗ ${host}: Connection failed - ${result.error}"
                            failCount++
                        }
                    }
                    
                    echo "📊 Connectivity Summary: ${successCount} successful, ${failCount} failed"
                    
                    if (failCount > 0 && successCount == 0) {
                        error "No hosts are reachable. Please check credentials and network connectivity."
                    }
                    
                    env.CONNECTIVITY_RESULTS = writeJSON returnText: true, json: connectivityResults
                }
            }
        }
        
        stage('Deploy SSH Keys') {
            steps {
                script {
                    def hosts = params.TARGET_HOSTS.split(',').collect { it.trim() }.findAll { it }
                    def deploymentResults = [:]
                    
                    echo "🚀 Deploying SSH keys to ${hosts.size()} hosts..."
                    
                    def deployToHost = { host ->
                        try {
                            def publicKey = readFile('jenkins_public_key.pub')
                            
                            def deploymentScript = """
                                # Create .ssh directory if it doesn't exist
                                mkdir -p ~/.ssh
                                chmod 700 ~/.ssh
                                
                                # Backup existing authorized_keys if requested
                                if [ "${params.BACKUP_AUTHORIZED_KEYS}" = "true" ] && [ -f ~/.ssh/authorized_keys ]; then
                                    cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys${env.BACKUP_SUFFIX}
                                    echo "Backup created: ~/.ssh/authorized_keys${env.BACKUP_SUFFIX}"
                                fi
                                
                                # Check if key already exists
                                if [ -f ~/.ssh/authorized_keys ]; then
                                    if grep -q "${publicKey.split(' ')[1]}" ~/.ssh/authorized_keys; then
                                        echo "Public key already exists in authorized_keys"
                                        exit 0
                                    fi
                                fi
                                
                                # Add the public key
                                if [ "${params.DRY_RUN}" = "false" ]; then
                                    echo "${publicKey}" >> ~/.ssh/authorized_keys
                                    chmod 600 ~/.ssh/authorized_keys
                                    echo "Public key added to authorized_keys"
                                else
                                    echo "[DRY RUN] Would add public key to authorized_keys"
                                fi
                                
                                # Verify authorized_keys file
                                if [ -f ~/.ssh/authorized_keys ]; then
                                    echo "authorized_keys file contains \$(wc -l < ~/.ssh/authorized_keys) keys"
                                fi
                            """
                            
                            // Deploy using appropriate authentication method
                            if (params.AUTH_METHOD in ['password', 'both'] && params.TARGET_HOST_PASSWORD) {
                                withCredentials([usernamePassword(
                                    credentialsId: params.TARGET_HOST_PASSWORD,
                                    usernameVariable: 'TARGET_USER',
                                    passwordVariable: 'TARGET_PASS'
                                )]) {
                                    def result = sh(
                                        script: """
                                            sshpass -p '\${TARGET_PASS}' ssh ${env.SSH_OPTS} -p ${params.SSH_PORT} \${TARGET_USER}@${host} '${deploymentScript}'
                                        """,
                                        returnStdout: true
                                    ).trim()
                                    
                                    return [status: 'success', method: 'password', output: result]
                                }
                            } else if (params.AUTH_METHOD in ['existing_key', 'both']) {
                                withCredentials([sshUserPrivateKey(
                                    credentialsId: params.SSH_PRIVATE_KEY_ID,
                                    keyFileVariable: 'SSH_KEY_FILE'
                                )]) {
                                    def result = sh(
                                        script: """
                                            ssh ${env.SSH_OPTS} -i \${SSH_KEY_FILE} -p ${params.SSH_PORT} ${params.SSH_USERNAME}@${host} '${deploymentScript}'
                                        """,
                                        returnStdout: true
                                    ).trim()
                                    
                                    return [status: 'success', method: 'key', output: result]
                                }
                            }
                        } catch (Exception e) {
                            return [status: 'failed', error: e.message]
                        }
                    }
                    
                    // Execute deployment
                    if (params.EXECUTION_MODE == 'parallel') {
                        def parallelDeployments = [:]
                        hosts.each { host ->
                            parallelDeployments[host] = {
                                deploymentResults[host] = deployToHost(host)
                            }
                        }
                        parallel parallelDeployments
                    } else {
                        hosts.each { host ->
                            deploymentResults[host] = deployToHost(host)
                        }
                    }
                    
                    // Report deployment results
                    def successCount = 0
                    def failCount = 0
                    
                    deploymentResults.each { host, result ->
                        if (result.status == 'success') {
                            echo "✓ ${host}: Key deployed successfully via ${result.method}"
                            if (result.output) {
                                echo "   Output: ${result.output}"
                            }
                            successCount++
                        } else {
                            echo "✗ ${host}: Deployment failed - ${result.error}"
                            failCount++
                        }
                    }
                    
                    echo "📊 Deployment Summary: ${successCount} successful, ${failCount} failed"
                    env.DEPLOYMENT_RESULTS = writeJSON returnText: true, json: deploymentResults
                    
                    if (successCount == 0) {
                        error "SSH key deployment failed on all hosts"
                    }
                }
            }
        }
        
        stage('Verify Key-based Authentication') {
            when { 
                expression { params.VALIDATE_CONNECTIVITY && !params.DRY_RUN }
            }
            steps {
                script {
                    def hosts = params.TARGET_HOSTS.split(',').collect { it.trim() }.findAll { it }
                    def verificationResults = [:]
                    
                    echo "🔐 Verifying key-based authentication on ${hosts.size()} hosts..."
                    
                    def verifyHost = { host ->
                        try {
                            withCredentials([sshUserPrivateKey(
                                credentialsId: params.SSH_PRIVATE_KEY_ID,
                                keyFileVariable: 'SSH_KEY_FILE'
                            )]) {
                                def result = sh(
                                    script: """
                                        ssh ${env.SSH_OPTS} -i \${SSH_KEY_FILE} -p ${params.SSH_PORT} ${params.SSH_USERNAME}@${host} 'echo "Key-based authentication successful"; whoami; date'
                                    """,
                                    returnStdout: true
                                ).trim()
                                
                                return [status: 'success', output: result]
                            }
                        } catch (Exception e) {
                            return [status: 'failed', error: e.message]
                        }
                    }
                    
                    // Execute verification
                    if (params.EXECUTION_MODE == 'parallel') {
                        def parallelVerifications = [:]
                        hosts.each { host ->
                            parallelVerifications[host] = {
                                verificationResults[host] = verifyHost(host)
                            }
                        }
                        parallel parallelVerifications
                    } else {
                        hosts.each { host ->
                            verificationResults[host] = verifyHost(host)
                        }
                    }
                    
                    // Report verification results
                    def successCount = 0
                    def failCount = 0
                    
                    verificationResults.each { host, result ->
                        if (result.status == 'success') {
                            echo "✓ ${host}: Key authentication verified"
                            successCount++
                        } else {
                            echo "⚠ ${host}: Key authentication failed - ${result.error}"
                            failCount++
                        }
                    }
                    
                    echo "📊 Verification Summary: ${successCount} successful, ${failCount} failed"
                    
                    if (failCount > 0) {
                        unstable("Key-based authentication failed on ${failCount} hosts")
                    }
                }
            }
        }
        
        stage('Generate Report') {
            steps {
                script {
                    def report = """
# SSH Key Exchange Report

**Build**: ${env.BUILD_NUMBER}  
**Date**: ${new Date()}  
**Jenkins Master**: ${env.JENKINS_URL}  
**Public Key Fingerprint**: ${env.PUBLIC_KEY_FINGERPRINT}

## Parameters
- **Target Hosts**: ${params.TARGET_HOSTS}
- **SSH Username**: ${params.SSH_USERNAME}
- **SSH Port**: ${params.SSH_PORT}
- **Authentication Method**: ${params.AUTH_METHOD}
- **Execution Mode**: ${params.EXECUTION_MODE}
- **Dry Run**: ${params.DRY_RUN}
- **Backup Authorized Keys**: ${params.BACKUP_AUTHORIZED_KEYS}

## Results Summary
"""
                    
                    if (env.DEPLOYMENT_RESULTS) {
                        def deploymentResults = readJSON text: env.DEPLOYMENT_RESULTS
                        report += "\\n### Deployment Results\\n"
                        
                        deploymentResults.each { host, result ->
                            def status = result.status == 'success' ? '✓' : '✗'
                            report += "- **${host}**: ${status} ${result.status}\\n"
                        }
                    }
                    
                    writeFile file: 'ssh-key-exchange-report.md', text: report
                    archiveArtifacts artifacts: 'ssh-key-exchange-report.md', allowEmptyArchive: false
                    
                    echo "📋 Report generated and archived"
                }
            }
        }
    }
    
    post {
        always {
            // Clean up sensitive files
            sh '''
                rm -f jenkins_public_key.pub 2>/dev/null || true
                rm -f ssh_key_temp 2>/dev/null || true
            '''
        }
        
        success {
            echo "🎉 SSH key exchange completed successfully!"
        }
        
        failure {
            echo "❌ SSH key exchange failed. Check the logs for details."
        }
        
        unstable {
            echo "⚠ SSH key exchange completed with warnings. Some hosts may need manual verification."
        }
    }
}
            ''')
            sandbox()
        }
    }
}