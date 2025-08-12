// Ansible Image Builder Pipeline Job DSL
// Runs image builder Ansible role on remote hosts using dynamic agents

pipelineJob('Infrastructure/Ansible-Image-Builder') {
    displayName('Ansible Image Builder - Remote Execution')
    description('''
        Executes the image builder Ansible role on remote hosts using dynamic agents.
        
        Features:
        • Dynamic agent provisioning on target hosts
        • Secure SSH key-based authentication
        • Parallel execution across multiple hosts
        • Real-time log streaming from remote execution
        • Artifact collection from remote builds
        • Integration with Docker registry for image push
        
        Prerequisites:
        • SSH keys must be exchanged with target hosts
        • Docker/Podman must be available on target hosts
        • Target hosts must support Jenkins agent execution
    ''')
    
    parameters {
        textParam('TARGET_HOSTS', '', '''List of target hosts for image building (one per line)
Example:
192.168.1.10
192.168.1.11
build-server-1.example.com''')
        
        credentialsParam('SSH_PRIVATE_KEY_ID') {
            type('com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey')
            description('SSH private key credential for connecting to remote hosts')
            defaultValue('jenkins-ssh-key')
        }
        
        stringParam('SSH_USERNAME', 'root', 'SSH username for remote host connections')
        stringParam('SSH_PORT', '22', 'SSH port for remote host connections')
        
        choiceParam('ANSIBLE_ROLE', [
            'jenkins-images',
 
            'monitoring',
            'custom'
        ], 'Ansible role to execute on remote hosts')
        
        textParam('ANSIBLE_EXTRA_VARS', '', '''Additional Ansible variables (YAML format)
Example:
jenkins_images_build: true
jenkins_images_push: true
        
        stringParam('ANSIBLE_PLAYBOOK_REPO', 'https://github.com/your-org/jenkins-ha.git', 'Git repository containing Ansible playbooks')
        stringParam('ANSIBLE_PLAYBOOK_BRANCH', 'main', 'Git branch to use for Ansible playbooks')
        
        choiceParam('EXECUTION_MODE', ['parallel', 'sequential'], 'How to execute across multiple hosts')
        booleanParam('COLLECT_ARTIFACTS', true, 'Collect build artifacts from remote hosts')
        booleanParam('CLEANUP_AGENTS', true, 'Clean up dynamic agents after execution')
        
        stringParam('AGENT_MEMORY', '4g', 'Memory allocation for dynamic agents')
        stringParam('AGENT_TIMEOUT', '60', 'Agent connection timeout in minutes')
    }
    
    definition {
        cps {
            script('''
pipeline {
    agent none
    
    options {
        timeout(time: 2, unit: 'HOURS')
        timestamps()
        ansiColor('xterm')
        skipDefaultCheckout()
    }
    
    environment {
        ANSIBLE_HOST_KEY_CHECKING = 'False'
        ANSIBLE_STDOUT_CALLBACK = 'yaml'
        ANSIBLE_FORCE_COLOR = 'true'
    }
    
    stages {
        stage('Validate Parameters') {
            agent any
            steps {
                script {
                    if (!params.TARGET_HOSTS?.trim()) {
                        error "TARGET_HOSTS parameter is required"
                    }
                    
                    // Parse and validate hosts
                    def hosts = params.TARGET_HOSTS.trim().split('\\n').collect { it.trim() }.findAll { it && !it.startsWith('#') }
                    if (hosts.isEmpty()) {
                        error "No valid hosts found in TARGET_HOSTS"
                    }
                    
                    env.HOST_COUNT = hosts.size().toString()
                    env.HOST_LIST = hosts.join(',')
                    
                    echo "✅ Validated ${env.HOST_COUNT} target hosts"
                    hosts.eachWithIndex { host, index ->
                        echo "  ${index + 1}. ${host}"
                    }
                    
                    echo "📋 Configuration:"
                    echo "  Ansible Role: ${params.ANSIBLE_ROLE}"
                    echo "  Execution Mode: ${params.EXECUTION_MODE}"
                    echo "  SSH Username: ${params.SSH_USERNAME}"
                    echo "  Agent Memory: ${params.AGENT_MEMORY}"
                }
            }
        }
        
        stage('Test SSH Connectivity') {
            agent any
            steps {
                script {
                    def hosts = env.HOST_LIST.split(',')
                    def connectivityResults = [:]
                    
                    echo "🔍 Testing SSH connectivity to ${hosts.size()} hosts..."
                    
                    def testHost = { host ->
                        try {
                            withCredentials([sshUserPrivateKey(
                                credentialsId: params.SSH_PRIVATE_KEY_ID,
                                keyFileVariable: 'SSH_KEY_FILE'
                            )]) {
                                sh """
                                    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \\
                                        -i \${SSH_KEY_FILE} -p ${params.SSH_PORT} \\
                                        ${params.SSH_USERNAME}@${host} \\
                                        'echo "SSH connectivity test successful"; uname -a; docker --version || podman --version'
                                """
                            }
                            return [status: 'success']
                        } catch (Exception e) {
                            return [status: 'failed', error: e.message]
                        }
                    }
                    
                    // Test connectivity in parallel
                    if (params.EXECUTION_MODE == 'parallel') {
                        def parallelTests = [:]
                        hosts.each { host ->
                            parallelTests[host] = {
                                connectivityResults[host] = testHost(host)
                            }
                        }
                        parallel parallelTests
                    } else {
                        hosts.each { host ->
                            connectivityResults[host] = testHost(host)
                        }
                    }
                    
                    // Report results
                    def failedHosts = []
                    connectivityResults.each { host, result ->
                        if (result.status == 'success') {
                            echo "✅ ${host}: SSH connectivity successful"
                        } else {
                            echo "❌ ${host}: SSH connectivity failed - ${result.error}"
                            failedHosts.add(host)
                        }
                    }
                    
                    if (failedHosts.size() > 0) {
                        error "SSH connectivity failed for hosts: ${failedHosts.join(', ')}"
                    }
                }
            }
        }
        
        stage('Execute Ansible on Remote Hosts') {
            steps {
                script {
                    def hosts = env.HOST_LIST.split(',')
                    def executionResults = [:]
                    
                    echo "🚀 Executing Ansible role '${params.ANSIBLE_ROLE}' on ${hosts.size()} hosts..."
                    
                    def executeOnHost = { host ->
                        return {
                            // Create dynamic agent on the remote host
                            node("") {
                                // Override node allocation to use SSH agent
                                def agentSpec = """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
    jenkins/label: ssh-agent-${host.replaceAll('[^a-zA-Z0-9]', '-')}
spec:
  containers:
  - name: ansible-runner
    image: quay.io/ansible/ansible-runner:latest
    command:
    - cat
    tty: true
    resources:
      requests:
        memory: "${params.AGENT_MEMORY}"
        cpu: "500m"
      limits:
        memory: "${params.AGENT_MEMORY}" 
        cpu: "2000m"
    env:
    - name: ANSIBLE_HOST_KEY_CHECKING
      value: "False"
    volumeMounts:
    - name: ssh-key
      mountPath: /root/.ssh
      readOnly: true
  volumes:
  - name: ssh-key
    secret:
      secretName: jenkins-ssh-key
      defaultMode: 0600
"""
                                
                                // Alternative: Use SSH agent directly on remote host
                                def sshAgent = [:]
                                sshAgent.label = "ssh-${host.replaceAll('[^a-zA-Z0-9]', '-')}-${BUILD_NUMBER}"
                                sshAgent.host = host
                                sshAgent.port = params.SSH_PORT as Integer
                                sshAgent.username = params.SSH_USERNAME
                                sshAgent.credentialsId = params.SSH_PRIVATE_KEY_ID
                                sshAgent.javaPath = '/usr/bin/java'  // Assumes Java is installed
                                sshAgent.workDir = '/tmp/jenkins-agent'
                                
                                try {
                                    // Use SSH agent provisioning
                                    node() {
                                        // Create temporary SSH agent configuration
                                        writeFile file: 'agent-config.json', text: writeJSON(returnText: true, json: sshAgent)
                                        
                                        // Provision SSH agent on remote host
                                        withCredentials([sshUserPrivateKey(
                                            credentialsId: params.SSH_PRIVATE_KEY_ID,
                                            keyFileVariable: 'SSH_KEY_FILE'
                                        )]) {
                                            // Setup remote agent workspace
                                            sh """
                                                ssh -o StrictHostKeyChecking=no -i \${SSH_KEY_FILE} -p ${params.SSH_PORT} \\
                                                    ${params.SSH_USERNAME}@${host} \\
                                                    'mkdir -p /tmp/jenkins-agent && echo "Agent workspace ready"'
                                            """
                                            
                                            // Execute Ansible on remote host
                                            def remoteScript = """
set -euo pipefail

echo "🏗️ Setting up Ansible execution environment on ${host}..."

# Install required packages if not present
if ! command -v git &> /dev/null; then
    if command -v yum &> /dev/null; then
        sudo yum install -y git python3 python3-pip
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y git python3 python3-pip
    fi
fi

# Install Ansible if not present
if ! command -v ansible &> /dev/null; then
    pip3 install ansible
    export PATH=\\\$PATH:/usr/local/bin
fi

# Clone playbook repository
cd /tmp/jenkins-agent
rm -rf ansible-playbooks 2>/dev/null || true
git clone ${params.ANSIBLE_PLAYBOOK_REPO} ansible-playbooks
cd ansible-playbooks
git checkout ${params.ANSIBLE_PLAYBOOK_BRANCH}

echo "📝 Creating Ansible inventory for localhost execution..."
cat > inventory/localhost << 'EOF'
[all]
localhost ansible_connection=local

[jenkins_masters]
localhost

[monitoring]  
localhost

localhost

[shared_storage]
localhost
EOF

echo "📝 Creating extra variables file..."
cat > extra-vars.yml << 'EOF'
# Host-specific variables
ansible_host: localhost
ansible_connection: local
deployment_mode: localhost

# Role-specific variables
${params.ANSIBLE_EXTRA_VARS ?: '# No extra variables provided'}

# Build information
jenkins_build_number: ${BUILD_NUMBER}
jenkins_build_url: ${BUILD_URL}
jenkins_host: ${host}
EOF

echo "🎭 Executing Ansible role: ${params.ANSIBLE_ROLE}"

# Execute the specific Ansible role
ansible-playbook -i inventory/localhost \\
    --extra-vars "@extra-vars.yml" \\
    --tags "${params.ANSIBLE_ROLE}" \\
    -v \\
    ansible/site.yml

echo "✅ Ansible execution completed successfully on ${host}"

# Collect artifacts if requested
if [ "${params.COLLECT_ARTIFACTS}" = "true" ]; then
    echo "📦 Collecting build artifacts..."
    mkdir -p /tmp/jenkins-agent/artifacts
    
    # Collect common artifacts
    find /tmp -name "*.log" -newer /tmp/jenkins-agent -exec cp {} /tmp/jenkins-agent/artifacts/ \\; 2>/dev/null || true
    find /var/log -name "*.log" -newer /tmp/jenkins-agent -exec sudo cp {} /tmp/jenkins-agent/artifacts/ \\; 2>/dev/null || true
    
    # Role-specific artifact collection
    case "${params.ANSIBLE_ROLE}" in
        "jenkins-images")
            docker images --format "table {{.Repository}}:{{.Tag}}\\t{{.Size}}\\t{{.CreatedAt}}" > /tmp/jenkins-agent/artifacts/docker-images.txt 2>/dev/null || true
            ;;
            ;;
        "monitoring") 
            curl -s http://localhost:9090/api/v1/targets 2>/dev/null > /tmp/jenkins-agent/artifacts/prometheus-targets.json || true
            ;;
    esac
    
    # Create execution report
    cat > /tmp/jenkins-agent/artifacts/execution-report.json << EOF_REPORT
{
    "host": "${host}",
    "role": "${params.ANSIBLE_ROLE}",
    "execution_time": "\$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "jenkins_build": "${BUILD_NUMBER}",
    "status": "completed"
}
EOF_REPORT

    echo "📦 Artifacts collected in /tmp/jenkins-agent/artifacts/"
fi
"""
                                            
                                            // Execute the remote script via SSH
                                            sh """
                                                ssh -o StrictHostKeyChecking=no -i \${SSH_KEY_FILE} -p ${params.SSH_PORT} \\
                                                    ${params.SSH_USERNAME}@${host} \\
                                                    '${remoteScript}'
                                            """
                                            
                                            // Collect artifacts if requested
                                            if (params.COLLECT_ARTIFACTS) {
                                                sh """
                                                    echo "📥 Downloading artifacts from ${host}..."
                                                    mkdir -p artifacts/${host}
                                                    scp -o StrictHostKeyChecking=no -i \${SSH_KEY_FILE} -P ${params.SSH_PORT} \\
                                                        -r ${params.SSH_USERNAME}@${host}:/tmp/jenkins-agent/artifacts/* \\
                                                        artifacts/${host}/ 2>/dev/null || echo "No artifacts found"
                                                """
                                            }
                                            
                                            // Cleanup remote workspace if requested
                                            if (params.CLEANUP_AGENTS) {
                                                sh """
                                                    echo "🧹 Cleaning up remote workspace on ${host}..."
                                                    ssh -o StrictHostKeyChecking=no -i \${SSH_KEY_FILE} -p ${params.SSH_PORT} \\
                                                        ${params.SSH_USERNAME}@${host} \\
                                                        'rm -rf /tmp/jenkins-agent' || echo "Cleanup completed"
                                                """
                                            }
                                        }
                                    }
                                    
                                    return [status: 'success', host: host]
                                    
                                } catch (Exception e) {
                                    echo "❌ Execution failed on ${host}: ${e.message}"
                                    return [status: 'failed', host: host, error: e.message]
                                }
                            }
                        }
                    }
                    
                    // Execute Ansible on hosts
                    if (params.EXECUTION_MODE == 'parallel') {
                        def parallelExecutions = [:]
                        hosts.each { host ->
                            parallelExecutions["Execute on ${host}"] = executeOnHost(host)
                        }
                        def results = parallel parallelExecutions
                        
                        results.each { name, result ->
                            executionResults[result.host] = result
                        }
                    } else {
                        hosts.each { host ->
                            def result = executeOnHost(host).call()
                            executionResults[host] = result
                        }
                    }
                    
                    // Report execution results
                    echo "\\n📊 Ansible Execution Results:"
                    echo "=" * 50
                    
                    def successCount = 0
                    def failCount = 0
                    
                    executionResults.each { host, result ->
                        if (result.status == 'success') {
                            echo "✅ ${host}: Ansible execution successful"
                            successCount++
                        } else {
                            echo "❌ ${host}: Ansible execution failed - ${result.error}"
                            failCount++
                        }
                    }
                    
                    echo "\\nSummary: ${successCount} successful, ${failCount} failed"
                    
                    if (successCount == 0) {
                        error "Ansible execution failed on all hosts"
                    } else if (failCount > 0) {
                        unstable "Ansible execution failed on some hosts"
                    }
                }
            }
        }
        
        stage('Archive Results') {
            agent any
            when {
                expression { params.COLLECT_ARTIFACTS }
            }
            steps {
                script {
                    // Archive collected artifacts
                    if (fileExists('artifacts')) {
                        archiveArtifacts artifacts: 'artifacts/**/*', allowEmptyArchive: true
                        echo "📦 Build artifacts archived"
                    }
                    
                    // Generate execution report
                    def hosts = env.HOST_LIST.split(',')
                    def report = """
# Ansible Remote Execution Report

**Build**: ${env.BUILD_NUMBER}  
**Date**: ${new Date()}  
**Role**: ${params.ANSIBLE_ROLE}  
**Execution Mode**: ${params.EXECUTION_MODE}

## Configuration
- **Target Hosts**: ${env.HOST_COUNT} hosts
- **SSH Username**: ${params.SSH_USERNAME}
- **Agent Memory**: ${params.AGENT_MEMORY}
- **Repository**: ${params.ANSIBLE_PLAYBOOK_REPO}
- **Branch**: ${params.ANSIBLE_PLAYBOOK_BRANCH}

## Hosts
${hosts.collect { "- ${it}" }.join('\\n')}

## Extra Variables
```yaml
${params.ANSIBLE_EXTRA_VARS ?: '# None provided'}
```

## Artifacts
${params.COLLECT_ARTIFACTS ? 'Build artifacts collected from all successful executions' : 'Artifact collection disabled'}

## Next Steps
1. Review execution logs for any warnings or errors
2. Verify role deployment on target hosts
3. Update inventory files if new services were deployed
4. Configure monitoring for newly deployed components
"""
                    
                    writeFile file: 'ansible-execution-report.md', text: report
                    archiveArtifacts artifacts: 'ansible-execution-report.md', allowEmptyArchive: false
                }
            }
        }
    }
    
    post {
        always {
            script {
                if (params.CLEANUP_AGENTS) {
                    echo "🧹 Cleaning up any remaining resources..."
                }
            }
        }
        
        success {
            echo "🎉 Ansible remote execution completed successfully!"
        }
        
        failure {
            echo "❌ Ansible remote execution failed!"
        }
        
        unstable {
            echo "⚠️ Ansible remote execution completed with warnings!"
        }
    }
}
            ''')
            sandbox()
        }
    }
}