// Dynamic Ansible Executor Pipeline Job DSL  
// Uses Jenkins SSH agents to execute Ansible roles on remote hosts

pipelineJob('Infrastructure/Dynamic-Ansible-Executor') {
    displayName('Dynamic Ansible Executor')
    description('''
        Executes Ansible roles on remote hosts using Jenkins SSH dynamic agents.
        
        This job provisions temporary Jenkins SSH agents on target hosts and executes
        Ansible playbooks directly on those hosts, providing true distributed execution.
        
        Features:
        • Real Jenkins SSH agent provisioning on remote hosts
        • Distributed Ansible execution
        • Automatic agent cleanup
        • Build artifact collection
        • Parallel execution support
        
        Prerequisites:
        • SSH keys exchanged with target hosts  
        • Java runtime available on target hosts
        • Git and Ansible tools on target hosts
    ''')
    
    parameters {
        textParam('TARGET_HOSTS', '', '''Target hosts for dynamic agent provisioning (one per line)
Format: hostname:label (label is optional)
Examples:
192.168.1.10
192.168.1.11:builder
build-server.example.com:docker-builder''')
        
        credentialsParam('SSH_CREDENTIALS_ID') {
            type('com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey')
            description('SSH credentials for agent connection')
            defaultValue('jenkins-ssh-key')
        }
        
        stringParam('SSH_USERNAME', 'jenkins', 'SSH username for agent connections')
        stringParam('SSH_PORT', '22', 'SSH port for connections')
        stringParam('JAVA_PATH', '/usr/bin/java', 'Path to Java on remote hosts')
        stringParam('AGENT_WORK_DIR', '/tmp/jenkins-agent', 'Working directory for agents')
        
        choiceParam('ANSIBLE_ROLE', [
            'jenkins-images',
            'harbor',
            'monitoring', 
            'backup',
            'security',
            'docker',
            'common'
        ], 'Ansible role to execute')
        
        stringParam('PLAYBOOK_REPO', 'https://github.com/your-org/jenkins-ha.git', 'Repository containing Ansible playbooks')
        stringParam('PLAYBOOK_BRANCH', 'main', 'Git branch to checkout')
        
        textParam('ANSIBLE_EXTRA_VARS', '', '''Additional Ansible variables (YAML format)
Example:
harbor_registry_url: "harbor.example.com"
jenkins_images_build: true
deployment_mode: "production"''')
        
        choiceParam('AGENT_CONNECTION_MODE', ['PARALLEL', 'SEQUENTIAL'], 'How to connect to agents')
        stringParam('AGENT_TIMEOUT', '300', 'Agent connection timeout (seconds)')
        booleanParam('KEEP_AGENTS_ONLINE', false, 'Keep agents online after execution')
        booleanParam('COLLECT_ARTIFACTS', true, 'Collect execution artifacts')
    }
    
    definition {
        cps {
            script('''
@Library('jenkins-shared-library') _

pipeline {
    agent {
        label 'master'
    }
    
    options {
        timeout(time: 3, unit: 'HOURS')
        timestamps()
        ansiColor('xterm')
    }
    
    environment {
        ANSIBLE_HOST_KEY_CHECKING = 'False'
        ANSIBLE_STDOUT_CALLBACK = 'yaml'
        ANSIBLE_FORCE_COLOR = 'true'
    }
    
    stages {
        stage('Parse Target Hosts') {
            steps {
                script {
                    if (!params.TARGET_HOSTS?.trim()) {
                        error "TARGET_HOSTS parameter is required"
                    }
                    
                    def hostEntries = params.TARGET_HOSTS.trim().split('\\n').collect { it.trim() }.findAll { it && !it.startsWith('#') }
                    
                    if (hostEntries.isEmpty()) {
                        error "No valid hosts found in TARGET_HOSTS"
                    }
                    
                    // Parse host entries (format: hostname or hostname:label)
                    def parsedHosts = []
                    hostEntries.each { entry ->
                        def parts = entry.split(':')
                        def host = parts[0]
                        def label = parts.size() > 1 ? parts[1] : "ansible-${params.ANSIBLE_ROLE}"
                        
                        parsedHosts.add([
                            hostname: host,
                            label: label,
                            agentName: "agent-${host.replaceAll('[^a-zA-Z0-9]', '-')}-${BUILD_NUMBER}"
                        ])
                    }
                    
                    env.TARGET_HOSTS_JSON = writeJSON returnText: true, json: parsedHosts
                    env.HOST_COUNT = parsedHosts.size().toString()
                    
                    echo "📋 Parsed ${env.HOST_COUNT} target hosts:"
                    parsedHosts.eachWithIndex { hostConfig, index ->
                        echo "  ${index + 1}. ${hostConfig.hostname} (label: ${hostConfig.label})"
                    }
                }
            }
        }
        
        stage('Provision SSH Agents') {
            steps {
                script {
                    def hosts = readJSON text: env.TARGET_HOSTS_JSON
                    def agentConfigs = []
                    
                    echo "🚀 Provisioning SSH agents on ${hosts.size()} hosts..."
                    
                    hosts.each { hostConfig ->
                        try {
                            echo "📡 Provisioning agent on ${hostConfig.hostname}..."
                            
                            // Create SSH agent configuration
                            def agentConfig = [
                                name: hostConfig.agentName,
                                host: hostConfig.hostname,
                                port: params.SSH_PORT as Integer,
                                credentialsId: params.SSH_CREDENTIALS_ID,
                                username: params.SSH_USERNAME,
                                javaPath: params.JAVA_PATH,
                                workDir: params.AGENT_WORK_DIR,
                                label: hostConfig.label,
                                retentionStrategy: params.KEEP_AGENTS_ONLINE ? 'always' : 'demand',
                                nodeProperties: [
                                    [
                                        $class: 'EnvironmentVariablesNodeProperty',
                                        envVars: [
                                            [key: 'ANSIBLE_HOST_KEY_CHECKING', value: 'False'],
                                            [key: 'ANSIBLE_FORCE_COLOR', value: 'true'],
                                            [key: 'TARGET_HOSTNAME', value: hostConfig.hostname]
                                        ]
                                    ]
                                ]
                            ]
                            
                            // Provision the SSH agent using Jenkins SSH Build Agent Plugin
                            def agentXml = """
<hudson.plugins.sshslaves.SSHLauncher plugin="ssh-slaves@1.31.2">
  <host>${hostConfig.hostname}</host>
  <port>${params.SSH_PORT}</port>
  <credentialsId>${params.SSH_CREDENTIALS_ID}</credentialsId>
  <javaPath>${params.JAVA_PATH}</javaPath>
  <jvmOptions></jvmOptions>
  <prefixStartSlaveCmd></prefixStartSlaveCmd>
  <suffixStartSlaveCmd></suffixStartSlaveCmd>
  <launchTimeoutSeconds>${params.AGENT_TIMEOUT}</launchTimeoutSeconds>
  <maxNumRetries>3</maxNumRetries>
  <retryWaitTime>15</retryWaitTime>
  <sshHostKeyVerificationStrategy class="hudson.plugins.sshslaves.verifiers.NonVerifyingKeyVerificationStrategy"/>
  <tcpNoDelay>true</tcpNoDelay>
  <trackCredentials>true</trackCredentials>
</hudson.plugins.sshslaves.SSHLauncher>
"""
                            
                            // Add agent to Jenkins using Groovy script
                            def addAgentScript = """
import jenkins.model.*
import hudson.model.*
import hudson.plugins.sshslaves.*
import hudson.slaves.*
import hudson.slaves.EnvironmentVariablesNodeProperty.Entry

def jenkins = Jenkins.instance

def launcher = new SSHLauncher(
    '${hostConfig.hostname}',
    ${params.SSH_PORT} as Integer,
    '${params.SSH_CREDENTIALS_ID}',
    '${params.JAVA_PATH}',
    null, null, null,
    ${params.AGENT_TIMEOUT} as Integer,
    3, 15,
    new hudson.plugins.sshslaves.verifiers.NonVerifyingKeyVerificationStrategy()
)

def retentionStrategy = new RetentionStrategy.Demand(1, 1)
if ('${params.KEEP_AGENTS_ONLINE}' == 'true') {
    retentionStrategy = new RetentionStrategy.Always()
}

def nodeProperties = []
def envVars = []
envVars.add(new Entry('ANSIBLE_HOST_KEY_CHECKING', 'False'))
envVars.add(new Entry('ANSIBLE_FORCE_COLOR', 'true'))
envVars.add(new Entry('TARGET_HOSTNAME', '${hostConfig.hostname}'))
nodeProperties.add(new EnvironmentVariablesNodeProperty(envVars))

def agent = new DumbSlave(
    '${hostConfig.agentName}',
    'Dynamic SSH agent for ${hostConfig.hostname}',
    '${params.AGENT_WORK_DIR}',
    '2',
    Node.Mode.NORMAL,
    '${hostConfig.label}',
    launcher,
    retentionStrategy,
    nodeProperties
)

jenkins.addNode(agent)
println "Agent ${hostConfig.agentName} added successfully"

// Wait for agent to come online
def maxWaitTime = 120 // 2 minutes
def waitInterval = 5 // 5 seconds
def waitCount = 0

while (waitCount < (maxWaitTime / waitInterval)) {
    def computer = jenkins.getComputer('${hostConfig.agentName}')
    if (computer?.isOnline()) {
        println "Agent ${hostConfig.agentName} is online"
        break
    }
    Thread.sleep(waitInterval * 1000)
    waitCount++
}

def computer = jenkins.getComputer('${hostConfig.agentName}')
if (!computer?.isOnline()) {
    throw new Exception("Agent ${hostConfig.agentName} failed to come online within \${maxWaitTime} seconds")
}

return "success"
"""
                            
                            // Execute the agent provisioning script
                            def result = build job: '/manage/scriptText', parameters: [
                                text(name: 'script', value: addAgentScript)
                            ]
                            
                            echo "✅ Agent ${hostConfig.agentName} provisioned successfully"
                            agentConfigs.add(hostConfig)
                            
                        } catch (Exception e) {
                            echo "❌ Failed to provision agent on ${hostConfig.hostname}: ${e.message}"
                            if (params.AGENT_CONNECTION_MODE == 'SEQUENTIAL') {
                                error "Agent provisioning failed for ${hostConfig.hostname}"
                            }
                        }
                    }
                    
                    if (agentConfigs.isEmpty()) {
                        error "No agents were successfully provisioned"
                    }
                    
                    env.ACTIVE_AGENTS_JSON = writeJSON returnText: true, json: agentConfigs
                    echo "📊 Successfully provisioned ${agentConfigs.size()} agents"
                }
            }
        }
        
        stage('Execute Ansible on Dynamic Agents') {
            steps {
                script {
                    def activeAgents = readJSON text: env.ACTIVE_AGENTS_JSON
                    def executionResults = [:]
                    
                    echo "🎭 Executing Ansible role '${params.ANSIBLE_ROLE}' on ${activeAgents.size()} agents..."
                    
                    def executeOnAgent = { agentConfig ->
                        return {
                            try {
                                // Execute on the specific dynamic agent
                                node(agentConfig.agentName) {
                                    stage("Setup on ${agentConfig.hostname}") {
                                        echo "🏗️ Setting up Ansible environment on ${agentConfig.hostname}..."
                                        
                                        // Install required tools if not present
                                        sh '''
                                            # Check and install Git
                                            if ! command -v git &> /dev/null; then
                                                echo "Installing Git..."
                                                if command -v yum &> /dev/null; then
                                                    sudo yum install -y git
                                                elif command -v apt-get &> /dev/null; then
                                                    sudo apt-get update && sudo apt-get install -y git
                                                else
                                                    echo "Package manager not supported"
                                                    exit 1
                                                fi
                                            fi
                                            
                                            # Check and install Python3/pip
                                            if ! command -v python3 &> /dev/null; then
                                                echo "Installing Python3..."
                                                if command -v yum &> /dev/null; then
                                                    sudo yum install -y python3 python3-pip
                                                elif command -v apt-get &> /dev/null; then
                                                    sudo apt-get install -y python3 python3-pip
                                                fi
                                            fi
                                            
                                            # Install Ansible
                                            if ! command -v ansible-playbook &> /dev/null; then
                                                echo "Installing Ansible..."
                                                pip3 install --user ansible
                                                export PATH=$PATH:~/.local/bin
                                            fi
                                            
                                            echo "✅ Prerequisites installed"
                                        '''
                                    }
                                    
                                    stage("Checkout Playbooks on ${agentConfig.hostname}") {
                                        echo "📥 Checking out Ansible playbooks..."
                                        
                                        checkout([
                                            $class: 'GitSCM',
                                            branches: [[name: "*/${params.PLAYBOOK_BRANCH}"]],
                                            extensions: [[$class: 'CleanBeforeCheckout']],
                                            userRemoteConfigs: [[
                                                url: params.PLAYBOOK_REPO,
                                                credentialsId: 'git-credentials'
                                            ]]
                                        ])
                                    }
                                    
                                    stage("Execute Ansible on ${agentConfig.hostname}") {
                                        echo "🎭 Running Ansible role: ${params.ANSIBLE_ROLE}"
                                        
                                        // Create localhost inventory
                                        writeFile file: 'localhost-inventory', text: '''
[all]
localhost ansible_connection=local

[jenkins_masters]
localhost

[monitoring]
localhost

[harbor]
localhost

[shared_storage]
localhost
'''
                                        
                                        // Create extra variables file
                                        def extraVars = """
# Dynamic agent execution variables
ansible_host: localhost
ansible_connection: local
deployment_mode: localhost
target_hostname: ${agentConfig.hostname}

# Build information
jenkins_build_number: ${BUILD_NUMBER}
jenkins_build_url: ${BUILD_URL}
jenkins_agent_name: ${agentConfig.agentName}

# User-provided variables
${params.ANSIBLE_EXTRA_VARS ?: '# No extra variables provided'}
"""
                                        writeFile file: 'extra-vars.yml', text: extraVars
                                        
                                        // Execute Ansible playbook
                                        sh """
                                            export PATH=\$PATH:~/.local/bin
                                            
                                            echo "📋 Ansible version:"
                                            ansible --version
                                            
                                            echo "🎯 Executing role: ${params.ANSIBLE_ROLE}"
                                            ansible-playbook -i localhost-inventory \\
                                                --extra-vars "@extra-vars.yml" \\
                                                --tags "${params.ANSIBLE_ROLE}" \\
                                                -vv \\
                                                ansible/site.yml
                                        """
                                    }
                                    
                                    stage("Collect Artifacts from ${agentConfig.hostname}") {
                                        if (params.COLLECT_ARTIFACTS) {
                                            echo "📦 Collecting build artifacts..."
                                            
                                            sh '''
                                                mkdir -p artifacts
                                                
                                                # Collect system information
                                                echo "=== System Information ===" > artifacts/system-info.txt
                                                uname -a >> artifacts/system-info.txt
                                                echo "\\n=== Disk Usage ===" >> artifacts/system-info.txt
                                                df -h >> artifacts/system-info.txt
                                                echo "\\n=== Memory Usage ===" >> artifacts/system-info.txt
                                                free -h >> artifacts/system-info.txt
                                                
                                                # Role-specific artifacts
                                                case "${params.ANSIBLE_ROLE}" in
                                                    "jenkins-images")
                                                        if command -v docker &> /dev/null; then
                                                            docker images --format "table {{.Repository}}:{{.Tag}}\\t{{.Size}}\\t{{.CreatedAt}}" > artifacts/docker-images.txt 2>/dev/null || true
                                                        fi
                                                        if command -v podman &> /dev/null; then
                                                            podman images --format "table {{.Repository}}:{{.Tag}}\\t{{.Size}}\\t{{.CreatedAt}}" > artifacts/podman-images.txt 2>/dev/null || true
                                                        fi
                                                        ;;
                                                    "harbor")
                                                        curl -s http://localhost/api/v2.0/projects 2>/dev/null > artifacts/harbor-projects.json || true
                                                        ;;
                                                    "monitoring")
                                                        curl -s http://localhost:9090/api/v1/targets 2>/dev/null > artifacts/prometheus-targets.json || true
                                                        curl -s http://localhost:3000/api/health 2>/dev/null > artifacts/grafana-health.json || true
                                                        ;;
                                                esac
                                                
                                                # Collect logs
                                                find /var/log -name "*.log" -newermt "1 hour ago" -exec basename {} \\; | head -10 | while read log; do
                                                    sudo tail -100 /var/log/$log > artifacts/log-$log 2>/dev/null || true
                                                done
                                                
                                                # Create execution summary
                                                cat > artifacts/execution-summary.json << EOF
{
    "hostname": "${agentConfig.hostname}",
    "agent_name": "${agentConfig.agentName}",
    "ansible_role": "${params.ANSIBLE_ROLE}",
    "execution_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "jenkins_build": "${BUILD_NUMBER}",
    "playbook_branch": "${params.PLAYBOOK_BRANCH}",
    "status": "completed"
}
EOF
                                            '''
                                            
                                            // Archive artifacts
                                            archiveArtifacts artifacts: 'artifacts/**/*', allowEmptyArchive: true
                                        }
                                    }
                                }
                                
                                return [status: 'success', agent: agentConfig.agentName, hostname: agentConfig.hostname]
                                
                            } catch (Exception e) {
                                echo "❌ Execution failed on ${agentConfig.hostname}: ${e.message}"
                                return [status: 'failed', agent: agentConfig.agentName, hostname: agentConfig.hostname, error: e.message]
                            }
                        }
                    }
                    
                    // Execute on agents
                    if (params.AGENT_CONNECTION_MODE == 'PARALLEL') {
                        def parallelExecutions = [:]
                        activeAgents.each { agentConfig ->
                            parallelExecutions["Execute on ${agentConfig.hostname}"] = executeOnAgent(agentConfig)
                        }
                        def results = parallel parallelExecutions
                        
                        results.each { name, result ->
                            executionResults[result.hostname] = result
                        }
                    } else {
                        activeAgents.each { agentConfig ->
                            def result = executeOnAgent(agentConfig).call()
                            executionResults[agentConfig.hostname] = result
                        }
                    }
                    
                    // Report results
                    echo "\\n📊 Execution Results:"
                    echo "=" * 50
                    
                    def successCount = 0
                    def failCount = 0
                    
                    executionResults.each { hostname, result ->
                        if (result.status == 'success') {
                            echo "✅ ${hostname}: Ansible execution successful"
                            successCount++
                        } else {
                            echo "❌ ${hostname}: Ansible execution failed - ${result.error}"
                            failCount++
                        }
                    }
                    
                    echo "\\nSummary: ${successCount} successful, ${failCount} failed"
                    env.EXECUTION_RESULTS = writeJSON returnText: true, json: executionResults
                    
                    if (successCount == 0) {
                        error "Ansible execution failed on all agents"
                    } else if (failCount > 0) {
                        unstable "Ansible execution failed on some agents"
                    }
                }
            }
        }
    }
    
    post {
        always {
            script {
                // Clean up dynamic agents if not keeping them online
                if (!params.KEEP_AGENTS_ONLINE) {
                    try {
                        def activeAgents = readJSON text: env.ACTIVE_AGENTS_JSON
                        
                        echo "🧹 Cleaning up dynamic agents..."
                        
                        def cleanupScript = """
import jenkins.model.*

def jenkins = Jenkins.instance
def agentsToRemove = []
"""
                        
                        activeAgents.each { agentConfig ->
                            cleanupScript += """
agentsToRemove.add('${agentConfig.agentName}')
"""
                        }
                        
                        cleanupScript += """
agentsToRemove.each { agentName ->
    def node = jenkins.getNode(agentName)
    if (node != null) {
        jenkins.removeNode(node)
        println "Removed agent: \${agentName}"
    }
}
"""
                        
                        build job: '/manage/scriptText', parameters: [
                            text(name: 'script', value: cleanupScript)
                        ]
                        
                        echo "✅ Dynamic agents cleaned up"
                        
                    } catch (Exception e) {
                        echo "⚠️ Failed to cleanup some agents: ${e.message}"
                    }
                }
            }
        }
        
        success {
            echo "🎉 Dynamic Ansible execution completed successfully!"
        }
        
        failure {
            echo "❌ Dynamic Ansible execution failed!"
        }
        
        unstable {
            echo "⚠️ Dynamic Ansible execution completed with warnings!"
        }
    }
}
            ''')
            sandbox()
        }
    }
}