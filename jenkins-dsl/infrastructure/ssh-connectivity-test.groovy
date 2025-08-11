// SSH Connectivity Test Pipeline Job DSL
// Test SSH connectivity to multiple hosts before deployments

pipelineJob('Infrastructure/SSH-Connectivity-Test') {
    displayName('SSH Connectivity Test')
    description('''
        Tests SSH connectivity to remote hosts using various authentication methods.
        
        Features:
        • Tests password and key-based authentication
        • Parallel connectivity testing
        • Detailed connectivity reports
        • Integration with SSH Key Exchange job
        • Host discovery and validation
    ''')
    
    parameters {
        textParam('TARGET_HOSTS', '', 'List of target hosts (one per line or comma-separated)')
        stringParam('SSH_USERNAME', 'root', 'SSH username for connections')
        stringParam('SSH_PORT', '22', 'SSH port to test')
        credentialsParam('SSH_PRIVATE_KEY_ID') {
            type('com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey')
            description('SSH private key credential for key-based auth testing')
            defaultValue('jenkins-ssh-key')
        }
        credentialsParam('TARGET_HOST_PASSWORD') {
            type('com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl')
            description('Username/password for password-based auth testing (optional)')
            defaultValue('')
        }
        choiceParam('TEST_METHOD', ['both', 'key_only', 'password_only'], 'Authentication methods to test')
        booleanParam('DETAILED_OUTPUT', true, 'Show detailed connection information')
        booleanParam('TEST_SUDO', false, 'Test sudo access on remote hosts')
        stringParam('CONNECTION_TIMEOUT', '10', 'Connection timeout in seconds')
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
    }
    
    environment {
        SSH_OPTS = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=${params.CONNECTION_TIMEOUT}"
    }
    
    stages {
        stage('Parse and Validate Hosts') {
            steps {
                script {
                    def hostInput = params.TARGET_HOSTS?.trim()
                    if (!hostInput) {
                        error "TARGET_HOSTS parameter is required"
                    }
                    
                    // Parse hosts (support both comma-separated and newline-separated)
                    def hosts = hostInput.split('[,\\n]').collect { it.trim() }.findAll { it && !it.startsWith('#') }
                    
                    if (hosts.isEmpty()) {
                        error "No valid hosts found in TARGET_HOSTS"
                    }
                    
                    env.HOST_COUNT = hosts.size().toString()
                    env.HOST_LIST = hosts.join(' ')
                    
                    echo "📋 Parsed ${env.HOST_COUNT} target hosts:"
                    hosts.eachWithIndex { host, index ->
                        echo "  ${index + 1}. ${host}"
                    }
                }
            }
        }
        
        stage('Test SSH Connectivity') {
            steps {
                script {
                    def hosts = env.HOST_LIST.split(' ')
                    def results = [:]
                    def testMethods = []
                    
                    // Determine which authentication methods to test
                    switch (params.TEST_METHOD) {
                        case 'both':
                            testMethods = ['key', 'password']
                            break
                        case 'key_only':
                            testMethods = ['key']
                            break
                        case 'password_only':
                            testMethods = ['password']
                            break
                    }
                    
                    echo "🔍 Testing connectivity with methods: ${testMethods.join(', ')}"
                    
                    def testHost = { host ->
                        def hostResults = [:]
                        
                        testMethods.each { method ->
                            try {
                                def testCommand = params.DETAILED_OUTPUT ? 
                                    "echo 'Host: '; hostname; echo 'User: '; whoami; echo 'OS: '; uname -a; echo 'Uptime: '; uptime; echo 'Disk: '; df -h /" :
                                    "echo 'SSH connection successful'; whoami"
                                
                                def startTime = System.currentTimeMillis()
                                def output = ''
                                
                                if (method == 'key') {
                                    withCredentials([sshUserPrivateKey(
                                        credentialsId: params.SSH_PRIVATE_KEY_ID,
                                        keyFileVariable: 'SSH_KEY_FILE'
                                    )]) {
                                        output = sh(
                                            script: """
                                                ssh ${env.SSH_OPTS} -i \${SSH_KEY_FILE} -p ${params.SSH_PORT} ${params.SSH_USERNAME}@${host} '${testCommand}'
                                            """,
                                            returnStdout: true
                                        ).trim()
                                    }
                                } else if (method == 'password' && params.TARGET_HOST_PASSWORD) {
                                    withCredentials([usernamePassword(
                                        credentialsId: params.TARGET_HOST_PASSWORD,
                                        usernameVariable: 'TARGET_USER',
                                        passwordVariable: 'TARGET_PASS'
                                    )]) {
                                        output = sh(
                                            script: """
                                                sshpass -p '\${TARGET_PASS}' ssh ${env.SSH_OPTS} -p ${params.SSH_PORT} \${TARGET_USER}@${host} '${testCommand}'
                                            """,
                                            returnStdout: true
                                        ).trim()
                                    }
                                } else {
                                    hostResults[method] = [status: 'skipped', reason: 'No credentials provided']
                                    return
                                }
                                
                                def duration = System.currentTimeMillis() - startTime
                                
                                hostResults[method] = [
                                    status: 'success',
                                    duration: duration,
                                    output: output
                                ]
                                
                                // Test sudo if requested
                                if (params.TEST_SUDO) {
                                    try {
                                        def sudoOutput = ''
                                        if (method == 'key') {
                                            withCredentials([sshUserPrivateKey(
                                                credentialsId: params.SSH_PRIVATE_KEY_ID,
                                                keyFileVariable: 'SSH_KEY_FILE'
                                            )]) {
                                                sudoOutput = sh(
                                                    script: """
                                                        ssh ${env.SSH_OPTS} -i \${SSH_KEY_FILE} -p ${params.SSH_PORT} ${params.SSH_USERNAME}@${host} 'sudo -n whoami'
                                                    """,
                                                    returnStdout: true
                                                ).trim()
                                            }
                                        } else if (method == 'password') {
                                            withCredentials([usernamePassword(
                                                credentialsId: params.TARGET_HOST_PASSWORD,
                                                usernameVariable: 'TARGET_USER',
                                                passwordVariable: 'TARGET_PASS'
                                            )]) {
                                                sudoOutput = sh(
                                                    script: """
                                                        sshpass -p '\${TARGET_PASS}' ssh ${env.SSH_OPTS} -p ${params.SSH_PORT} \${TARGET_USER}@${host} 'sudo -n whoami'
                                                    """,
                                                    returnStdout: true
                                                ).trim()
                                            }
                                        }
                                        hostResults[method]['sudo'] = 'success'
                                        hostResults[method]['sudo_user'] = sudoOutput
                                    } catch (Exception e) {
                                        hostResults[method]['sudo'] = 'failed'
                                        hostResults[method]['sudo_error'] = e.message
                                    }
                                }
                                
                            } catch (Exception e) {
                                hostResults[method] = [
                                    status: 'failed',
                                    error: e.message
                                ]
                            }
                        }
                        
                        return hostResults
                    }
                    
                    // Execute connectivity tests in parallel
                    def parallelTests = [:]
                    hosts.each { host ->
                        parallelTests[host] = {
                            results[host] = testHost(host)
                        }
                    }
                    
                    parallel parallelTests
                    
                    // Report results
                    echo "\\n📊 SSH Connectivity Test Results:"
                    echo "=" * 60
                    
                    def overallSuccess = 0
                    def overallFail = 0
                    def detailedResults = []
                    
                    results.each { host, hostResults ->
                        echo "\\n🖥️  Host: ${host}"
                        echo "   Port: ${params.SSH_PORT}"
                        
                        def hostSuccess = false
                        
                        hostResults.each { method, result ->
                            if (result.status == 'success') {
                                echo "   ✅ ${method.toUpperCase()} auth: SUCCESS (${result.duration}ms)"
                                hostSuccess = true
                                if (params.DETAILED_OUTPUT && result.output) {
                                    result.output.split('\\n').each { line ->
                                        echo "      ${line}"
                                    }
                                }
                                if (params.TEST_SUDO) {
                                    def sudoStatus = result.sudo == 'success' ? "✅ (as ${result.sudo_user})" : "❌ ${result.sudo_error ?: 'failed'}"
                                    echo "      SUDO: ${sudoStatus}"
                                }
                            } else if (result.status == 'failed') {
                                echo "   ❌ ${method.toUpperCase()} auth: FAILED - ${result.error}"
                            } else if (result.status == 'skipped') {
                                echo "   ⏭️  ${method.toUpperCase()} auth: SKIPPED - ${result.reason}"
                            }
                        }
                        
                        if (hostSuccess) {
                            overallSuccess++
                            detailedResults.add([host: host, status: 'success'])
                        } else {
                            overallFail++
                            detailedResults.add([host: host, status: 'failed'])
                        }
                    }
                    
                    echo "\\n" + "=" * 60
                    echo "📈 Summary: ${overallSuccess} successful, ${overallFail} failed (${hosts.size()} total)"
                    
                    // Store results for reporting
                    env.TEST_RESULTS = writeJSON returnText: true, json: [
                        totalHosts: hosts.size(),
                        successful: overallSuccess,
                        failed: overallFail,
                        details: detailedResults,
                        testMethods: testMethods
                    ]
                    
                    if (overallSuccess == 0) {
                        error "No hosts are accessible via SSH"
                    } else if (overallFail > 0) {
                        unstable "Some hosts failed SSH connectivity tests"
                    }
                }
            }
        }
        
        stage('Generate Connectivity Report') {
            steps {
                script {
                    def testResults = readJSON text: env.TEST_RESULTS
                    
                    def report = """
# SSH Connectivity Test Report

**Build**: ${env.BUILD_NUMBER}  
**Date**: ${new Date()}  
**Test Methods**: ${testResults.testMethods.join(', ')}  
**Connection Timeout**: ${params.CONNECTION_TIMEOUT}s

## Summary
- **Total Hosts**: ${testResults.totalHosts}
- **Successful**: ${testResults.successful}
- **Failed**: ${testResults.failed}
- **Success Rate**: ${Math.round((testResults.successful / testResults.totalHosts) * 100)}%

## Detailed Results
"""
                    
                    testResults.details.each { result ->
                        def status = result.status == 'success' ? '✅' : '❌'
                        report += "- **${result.host}**: ${status} ${result.status}\\n"
                    }
                    
                    report += """

## Recommendations
"""
                    
                    if (testResults.failed > 0) {
                        report += """
### Failed Connections
For hosts that failed connectivity tests:
1. Verify host IP addresses and DNS resolution
2. Check SSH service is running on target port
3. Verify firewall rules allow SSH connections
4. Confirm SSH credentials are correct
5. Consider running SSH Key Exchange job for failed hosts
"""
                    }
                    
                    if (testResults.successful > 0) {
                        report += """
### Successful Connections
For hosts with successful connectivity:
1. Consider running SSH Key Exchange job to set up passwordless auth
2. Verify sudo permissions if required for deployments
3. Update inventory files with confirmed connectivity
"""
                    }
                    
                    writeFile file: 'ssh-connectivity-report.md', text: report
                    archiveArtifacts artifacts: 'ssh-connectivity-report.md', allowEmptyArchive: false
                    
                    // Create build badge
                    def badgeText = "${testResults.successful}/${testResults.totalHosts} hosts accessible"
                    def badgeColor = testResults.failed == 0 ? 'brightgreen' : (testResults.successful > 0 ? 'yellow' : 'red')
                    
                    addShortText(
                        text: badgeText,
                        color: badgeColor,
                        background: 'white',
                        border: 1
                    )
                }
            }
        }
    }
    
    post {
        success {
            echo "🎉 SSH connectivity test completed successfully!"
        }
        
        failure {
            echo "❌ SSH connectivity test failed!"
        }
        
        unstable {
            echo "⚠️  SSH connectivity test completed with warnings!"
        }
    }
}
            ''')
            sandbox()
        }
    }
}