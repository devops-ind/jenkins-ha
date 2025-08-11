// Simple SSH Key Push Job DSL
// Pushes a Jenkins public key to remote hosts using a password.

pipelineJob('Utilities/Simple-SSH-Key-Push') {
    displayName('Simple SSH Key Push')
    description('A simple pipeline to add a Jenkins public key to the authorized_keys file on remote hosts using password authentication.')
    
    parameters {
        stringParam('TARGET_HOSTS', '', 'Comma-separated list of target host IPs or hostnames (e.g., 192.168.1.10,server1)')
        stringParam('REMOTE_USER', 'root', 'The username for the SSH connection (e.g., root, ec2-user)')
        credentialsParam('INITIAL_PASSWORD_ID') {
            type('com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl')
            description('Select the username/password credential for the initial connection to the hosts.')
            required(true)
        }
        credentialsParam('SSH_KEY_TO_DEPLOY_ID') {
            type('com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey')
            description('The Jenkins SSH key credential whose PUBLIC key will be deployed.')
            defaultValue('jenkins-ssh-key') // A sensible default
            required(true)
        }
    }
    
    properties {
        buildDiscarder { strategy { logRotator { numToKeepStr('10') } } }
        disableConcurrentBuilds()
    }
    
    definition {
        cps {
            script('''
pipeline {
    agent any

    options {
        timeout(time: 10, unit: 'MINUTES')
        timestamps()
    }

    stages {
        stage('Deploy Public Key') {
            steps {
                script {
                    // Extract the public key from the specified private key credential
                    def publicKey
                    withCredentials([sshUserPrivateKey(credentialsId: params.SSH_KEY_TO_DEPLOY_ID, keyFileVariable: 'JENKINS_PRIVATE_KEY')]) {
                        publicKey = sh(script: "ssh-keygen -y -f ${JENKINS_PRIVATE_KEY}", returnStdout: true).trim()
                    }

                    if (!publicKey) {
                        error "Could not extract public key from credential '${params.SSH_KEY_TO_DEPLOY_ID}'"
                    }

                    // Prepare parallel deployment tasks
                    def hosts = params.TARGET_HOSTS.split(',').collect { it.trim() }.findAll { it }
                    if (hosts.isEmpty()) {
                        error "TARGET_HOSTS parameter is empty or invalid."
                    }

                    def parallelTasks = [:]
                    hosts.each { host ->
                        parallelTasks[host] = {
                            echo "🚀 Deploying key to ${host}..."
                            try {
                                // Use the password credential for the initial connection
                                withCredentials([usernamePassword(credentialsId: params.INITIAL_PASSWORD_ID, passwordVariable: 'REMOTE_PASSWORD', usernameVariable: 'REMOTE_USERNAME')]) {
                                    
                                    // Ensure the remote username matches the parameter, not the one from the credential
                                    if (REMOTE_USERNAME != params.REMOTE_USER) {
                                        echo "Warning: Credential username '${REMOTE_USERNAME}' differs from specified user '${params.REMOTE_USER}'. Using '${params.REMOTE_USER}'."
                                    }

                                    // The remote script to add the key
                                    // It creates the .ssh dir, adds the key if not present, and sets permissions
                                    def remoteScript = """
                                        set -e
                                        mkdir -p ~/.ssh
                                        chmod 700 ~/.ssh
                                        if ! grep -qF '${publicKey}' ~/.ssh/authorized_keys 2>/dev/null; then
                                            echo '${publicKey}' >> ~/.ssh/authorized_keys
                                            chmod 600 ~/.ssh/authorized_keys
                                            echo '✅ Key successfully added to ${host}.'
                                        else
                                            echo 'ℹ️ Key already exists on ${host}. No changes made.'
                                        fi
                                    """
                                    
                                    // Use sshpass to provide the password for the SSH command
                                    sh "sshpass -p '${REMOTE_PASSWORD}' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${params.REMOTE_USER}@${host} '${remoteScript}'"
                                }
                            } catch (e) {
                                echo "❌ FAILED to deploy key to ${host}."
                                // This will mark the parallel stage as unstable but won't stop other deployments
                                unstable("Deployment failed for host: ${host}") 
                                error("Error on ${host}: ${e.message}")
                            }
                        }
                    }
                    
                    // Execute all deployments in parallel
                    parallel parallelTasks
                }
            }
        }
    }
    
    post {
        success {
            echo "🎉 All deployments completed successfully!"
        }
        unstable {
            echo "⚠️ Some deployments failed. Check logs for details."
        }
        failure {
            echo "💥 The pipeline failed. Please review the logs."
        }
    }
}
            ''')
            sandbox()
        }
    }
}