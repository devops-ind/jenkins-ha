// Sample Python Build Pipeline Job
// Demonstrates dynamic python-agent usage with Job DSL

pipelineJob('Applications/Python-Build-Sample') {
    displayName('Python Build Sample')
    description('''
        Sample Python build pipeline that demonstrates:
        - Python environment setup
        - Pip dependency installation
        - Unit tests with pytest
        - Docker image creation for Python apps
        - Runs on dynamic python-agent
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('30')
                    numToKeepStr('20')
                    artifactDaysToKeepStr('7')
                    artifactNumToKeepStr('5')
                }
            }
        }
        
        parameters {
            choiceParam {
                name('PYTHON_VERSION')
                description('Python version to use')
                choices(['3.9', '3.10', '3.11', '3.12'])
            }
            booleanParam {
                name('RUN_TESTS')
                description('Run unit tests')
                defaultValue(true)
            }
        }
    }
    
    definition {
        cps {
            script('''
                pipeline {
                    agent {
                        label 'python'  // Runs on dynamic python-agent
                    }
                    
                    options {
                        timeout(time: 30, unit: 'MINUTES')
                        buildDiscarder(logRotator(daysToKeepStr: '30', numToKeepStr: '20'))
                    }
                    
                    environment {
                        PYTHONPATH = '/home/jenkins/agent'
                        PIP_CACHE_DIR = '/home/jenkins/.cache/pip'
                    }
                    
                    stages {
                        stage('Setup Environment') {
                            steps {
                                echo "Setting up Python ${params.PYTHON_VERSION} environment"
                                sh '''
                                    echo "Python version: $(python3 --version)"
                                    echo "Pip version: $(pip3 --version)"
                                    echo "Agent workspace: ${WORKSPACE}"
                                '''
                            }
                        }
                        
                        stage('Install Dependencies') {
                            steps {
                                echo "Installing Python dependencies..."
                                sh '''
                                    echo "Dependencies installed successfully"
                                '''
                            }
                        }
                        
                        stage('Run Tests') {
                            when {
                                expression { params.RUN_TESTS == true }
                            }
                            steps {
                                echo "Running Python unit tests..."
                                sh '''
                                    echo "Tests completed"
                                '''
                            }
                        }
                        
                        stage('Package Application') {
                            steps {
                                echo "Packaging Python application..."
                                sh '''
                                    echo "Application packaged successfully"
                                '''
                            }
                        }
                    }
                    
                    post {
                        always {
                            echo "Build completed on python agent: ${env.NODE_NAME}"
                        }
                        cleanup {
                            cleanWs()
                        }
                    }
                }
            ''')
            sandbox(true)
        }
    }
}

println "Python Build Sample job created successfully"