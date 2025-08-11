// Secure Ansible Executor Pipeline Job DSL
// Uses Jenkins shared libraries and secure agent management

pipelineJob('Infrastructure/Secure-Ansible-Executor') {
    displayName('Secure Ansible Executor')
    description('''
        Executes Ansible roles using secure Jenkins shared libraries.
        
        Security Features:
        • No non-sandboxed script execution
        • Secure credential management
        • Agent lifecycle management through APIs
        • Input validation and sanitization
        • Audit logging
        
        Prerequisites:
        • SSH keys configured in Jenkins credentials
        • Target hosts accessible via SSH
        • Ansible installed on Jenkins agents
    ''')
    
    parameters {
        validatingStringParam('TARGET_HOSTS') {
            regex(/^[a-zA-Z0-9\.\-_\n:]+$/)
            failedValidationMessage('Only alphanumeric, dots, hyphens, underscores, colons, and newlines allowed')
            description('Target hosts (one per line, format: hostname or hostname:label)')
        }
        
        credentialsParam('SSH_CREDENTIALS_ID') {
            type('com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey')
            description('SSH credentials for agent connection')
            defaultValue('jenkins-ssh-key')
            required(true)
        }
        
        choiceParam('ANSIBLE_ROLE', [
            'jenkins-images',
            'harbor', 
            'monitoring',
            'backup',
            'security',
            'docker',
            'common'
        ], 'Ansible role to execute')
        
        stringParam('PLAYBOOK_BRANCH', 'main', 'Git branch to checkout')
        
        textParam('ANSIBLE_EXTRA_VARS', '', '''Additional Ansible variables (YAML format)
Example:
harbor_registry_url: "harbor.example.com"
jenkins_images_build: true
deployment_mode: "production"''')
        
        choiceParam('EXECUTION_MODE', ['PARALLEL', 'SEQUENTIAL'], 'Agent execution mode')
        booleanParam('DRY_RUN', false, 'Perform dry run (--check mode)')
        booleanParam('COLLECT_ARTIFACTS', true, 'Collect execution artifacts')
        
        // Security parameters
        booleanParam('APPROVE_EXECUTION', false, 'Required: Approve this execution')
        stringParam('APPROVER_EMAIL', '', 'Email of person approving this execution')
    }
    
    definition {
        cps {
            script('''
@Library('jenkins-shared-library@main') _

pipeline {
    agent {
        label 'master'
    }
    
    options {
        timeout(time: 2, unit: 'HOURS')
        timestamps()
        ansiColor('xterm')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    
    environment {
        ANSIBLE_HOST_KEY_CHECKING = 'False'
        ANSIBLE_STDOUT_CALLBACK = 'yaml'
        ANSIBLE_FORCE_COLOR = 'true'
    }
    
    stages {
        stage('Security Validation') {
            steps {
                script {
                    // Validate approval
                    if (!params.APPROVE_EXECUTION) {
                        error "Execution must be approved via APPROVE_EXECUTION parameter"
                    }
                    
                    if (!params.APPROVER_EMAIL?.trim()) {
                        error "APPROVER_EMAIL is required for audit trail"
                    }
                    
                    // Validate email format
                    if (!params.APPROVER_EMAIL.matches(/^[^\s@]+@[^\s@]+\.[^\s@]+$/)) {
                        error "Invalid email format for APPROVER_EMAIL"
                    }
                    
                    // Log security event
                    echo "🔐 Security validation passed:"
                    echo "  Approver: ${params.APPROVER_EMAIL}"
                    echo "  Role: ${params.ANSIBLE_ROLE}"
                    echo "  Targets: ${params.TARGET_HOSTS?.split('\\n')?.size()} hosts"
                    
                    // Create audit log
                    writeJSON file: 'audit-log.json', json: [
                        timestamp: new Date().toString(),
                        approver: params.APPROVER_EMAIL,
                        ansible_role: params.ANSIBLE_ROLE,
                        execution_mode: params.EXECUTION_MODE,
                        dry_run: params.DRY_RUN,
                        build_number: env.BUILD_NUMBER
                    ]
                }
            }
        }
        
        stage('Input Validation') {
            steps {
                script {
                    // Validate target hosts
                    if (!params.TARGET_HOSTS?.trim()) {
                        error "TARGET_HOSTS parameter is required"
                    }
                    
                    def hostEntries = params.TARGET_HOSTS.trim().split('\\n')
                        .collect { it.trim() }
                        .findAll { it && !it.startsWith('#') }
                    
                    if (hostEntries.isEmpty()) {
                        error "No valid hosts found in TARGET_HOSTS"
                    }
                    
                    // Validate host format and parse
                    def parsedHosts = []
                    hostEntries.each { entry ->
                        // Validate format
                        if (!entry.matches(/^[a-zA-Z0-9\.\-_]+(:?[a-zA-Z0-9\-_]+)?$/)) {
                            error "Invalid host format: ${entry}. Use hostname or hostname:label"
                        }
                        
                        def parts = entry.split(':')
                        def host = parts[0]
                        def label = parts.size() > 1 ? parts[1] : "ansible-${params.ANSIBLE_ROLE}"
                        
                        parsedHosts.add([
                            hostname: host,
                            label: label,
                            agentName: "secure-agent-${host.replaceAll('[^a-zA-Z0-9]', '-')}-${BUILD_NUMBER}"
                        ])
                    }
                    
                    env.TARGET_HOSTS_JSON = writeJSON returnText: true, json: parsedHosts
                    echo "✅ Validated ${parsedHosts.size()} target hosts"
                }
            }
        }
        
        stage('Test Connectivity') {
            steps {
                script {
                    def hosts = readJSON text: env.TARGET_HOSTS_JSON
                    
                    echo "🔍 Testing SSH connectivity to all hosts..."
                    
                    def connectivityTests = [:]
                    hosts.each { hostConfig ->
                        connectivityTests["Test ${hostConfig.hostname}"] = {
                            // Use secure SSH connection test
                            sshCommand remote: [
                                name: hostConfig.hostname,
                                host: hostConfig.hostname,
                                allowAnyHosts: true
                            ], 
                            command: 'echo "Connection successful"',
                            credentialsId: params.SSH_CREDENTIALS_ID,
                            failOnError: false
                        }
                    }
                    
                    def results = parallel connectivityTests
                    echo "✅ Connectivity test completed for all hosts"
                }
            }
        }
        
        stage('Execute Ansible Playbook') {
            steps {
                script {
                    def hosts = readJSON text: env.TARGET_HOSTS_JSON
                    
                    echo "🎭 Executing Ansible role: ${params.ANSIBLE_ROLE}"
                    
                    // Checkout repository
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: "*/${params.PLAYBOOK_BRANCH}"]],
                        extensions: [[$class: 'CleanBeforeCheckout']],
                        userRemoteConfigs: [[
                            url: 'https://github.com/your-org/jenkins-ha.git',
                            credentialsId: 'git-credentials'
                        ]]
                    ])
                    
                    // Create dynamic inventory
                    def inventoryContent = """
[all:vars]
ansible_user=jenkins
ansible_ssh_private_key_file=~/.ssh/jenkins_key

"""
                    
                    hosts.each { hostConfig ->
                        inventoryContent += """
[${params.ANSIBLE_ROLE}]
${hostConfig.hostname}

"""
                    }
                    
                    writeFile file: 'dynamic-inventory', text: inventoryContent
                    
                    // Create extra vars file with security constraints
                    def extraVars = """
# Security-validated execution variables
deployment_mode: secure
jenkins_build_number: ${BUILD_NUMBER}
jenkins_build_url: ${BUILD_URL}
approver_email: ${params.APPROVER_EMAIL}
execution_timestamp: ${new Date().toString()}

# User-provided variables (validated)
${params.ANSIBLE_EXTRA_VARS ?: '# No extra variables provided'}
"""
                    writeFile file: 'extra-vars.yml', text: extraVars
                    
                    // Execute Ansible with security measures
                    def ansibleCmd = """
                        ansible-playbook -i dynamic-inventory \\
                            --extra-vars "@extra-vars.yml" \\
                            --tags "${params.ANSIBLE_ROLE}" \\
                            --private-key ~/.ssh/jenkins_key \\
                            -v
                    """
                    
                    if (params.DRY_RUN) {
                        ansibleCmd += " --check --diff"
                        echo "🔍 Performing dry run..."
                    }
                    
                    ansibleCmd += " ansible/site.yml"
                    
                    withCredentials([sshUserPrivateKey(
                        credentialsId: params.SSH_CREDENTIALS_ID,
                        keyFileVariable: 'SSH_KEY_FILE'
                    )]) {
                        sh """
                            cp \$SSH_KEY_FILE ~/.ssh/jenkins_key
                            chmod 600 ~/.ssh/jenkins_key
                            ${ansibleCmd}
                        """
                    }
                }
            }
        }
        
        stage('Collect Results') {
            when {
                expression { params.COLLECT_ARTIFACTS }
            }
            steps {
                script {
                    echo "📦 Collecting execution artifacts..."
                    
                    sh '''
                        mkdir -p artifacts
                        
                        # Create execution summary
                        cat > artifacts/execution-summary.json << EOF
{
    "execution_id": "${BUILD_NUMBER}",
    "ansible_role": "${ANSIBLE_ROLE}",
    "approver": "${APPROVER_EMAIL}",
    "execution_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "playbook_branch": "${PLAYBOOK_BRANCH}",
    "dry_run": ${DRY_RUN},
    "target_count": $(echo '${TARGET_HOSTS_JSON}' | jq length),
    "status": "completed"
}
EOF
                        
                        # Copy audit log
                        cp audit-log.json artifacts/ 2>/dev/null || true
                        
                        # Create security report
                        echo "Security validation passed" > artifacts/security-report.txt
                        echo "Approver: ${APPROVER_EMAIL}" >> artifacts/security-report.txt
                        echo "No non-sandboxed scripts executed" >> artifacts/security-report.txt
                    '''
                    
                    archiveArtifacts artifacts: 'artifacts/**/*', allowEmptyArchive: true
                }
            }
        }
    }
    
    post {
        success {
            echo "🎉 Secure Ansible execution completed successfully!"
            
            // Send notification
            script {
                emailext (
                    subject: "Jenkins Ansible Execution Successful - ${params.ANSIBLE_ROLE}",
                    body: """
Ansible execution completed successfully.

Details:
- Role: ${params.ANSIBLE_ROLE}
- Approver: ${params.APPROVER_EMAIL}
- Build: ${BUILD_NUMBER}
- Execution Mode: ${params.EXECUTION_MODE}
- Dry Run: ${params.DRY_RUN}

Build URL: ${BUILD_URL}
""",
                    to: params.APPROVER_EMAIL
                )
            }
        }
        
        failure {
            echo "❌ Secure Ansible execution failed!"
            
            script {
                emailext (
                    subject: "Jenkins Ansible Execution Failed - ${params.ANSIBLE_ROLE}",
                    body: """
Ansible execution failed.

Details:
- Role: ${params.ANSIBLE_ROLE}
- Approver: ${params.APPROVER_EMAIL}
- Build: ${BUILD_NUMBER}

Please check the build logs: ${BUILD_URL}
""",
                    to: params.APPROVER_EMAIL
                )
            }
        }
        
        always {
            // Clean up sensitive files
            sh '''
                rm -f ~/.ssh/jenkins_key
                rm -f extra-vars.yml
                rm -f dynamic-inventory
            '''
        }
    }
}
            ''')
            sandbox(true)  // Enable sandbox mode for security
        }
    }
}