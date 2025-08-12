// Sandbox-Safe DSL Examples
// These examples demonstrate how to create Jenkins jobs that work within the DSL sandbox

// Simple pipeline job without external dependencies
pipelineJob('Examples/Simple-Pipeline') {
    displayName('Simple Sandbox-Safe Pipeline')
    description('Example of a pipeline that runs in sandbox mode without approval')
    
    parameters {
        stringParam('BUILD_VERSION', '1.0.0', 'Version to build')
        booleanParam('SKIP_TESTS', false, 'Skip test execution')
        choiceParam('ENVIRONMENT', ['dev', 'staging', 'prod'], 'Target environment')
    }
    
    definition {
        cps {
            script('''
                pipeline {
                    agent any
                    
                    options {
                        buildDiscarder(logRotator(numToKeepStr: '10'))
                        timeout(time: 1, unit: 'HOURS')
                        timestamps()
                    }
                    
                    environment {
                        BUILD_VERSION = "${params.BUILD_VERSION}"
                        TARGET_ENV = "${params.ENVIRONMENT}"
                    }
                    
                    stages {
                        stage('Preparation') {
                            steps {
                                echo "Building version: ${env.BUILD_VERSION}"
                                echo "Target environment: ${env.TARGET_ENV}"
                            }
                        }
                        
                        stage('Build') {
                            steps {
                                echo 'Building application...'
                                // sh 'make build'  // Uncomment for real build
                            }
                        }
                        
                        stage('Test') {
                            when { 
                                not { params.SKIP_TESTS }
                            }
                            steps {
                                echo 'Running tests...'
                                // sh 'make test'  // Uncomment for real tests
                            }
                        }
                        
                        stage('Deploy') {
                            when {
                                anyOf {
                                    branch 'main'
                                    expression { params.ENVIRONMENT == 'prod' }
                                }
                            }
                            steps {
                                echo "Deploying to ${env.TARGET_ENV}..."
                                // Add deployment steps here
                            }
                        }
                    }
                    
                    post {
                        always {
                            echo 'Pipeline completed'
                        }
                        success {
                            echo 'Pipeline succeeded!'
                        }
                        failure {
                            echo 'Pipeline failed!'
                        }
                    }
                }
            ''')
            sandbox(true)  // Enable sandbox for security
        }
    }
    
    triggers {
        cron('H H(0-7) * * 1-5')  // Weekdays between midnight and 7 AM
    }
}

// Freestyle job with basic configuration
job('Examples/Simple-Freestyle') {
    displayName('Simple Freestyle Job')
    description('Example of a basic freestyle job that works in sandbox')
    
    parameters {
        stringParam('MESSAGE', 'Hello World', 'Message to display')
        booleanParam('VERBOSE', false, 'Enable verbose output')
    }
    
    scm {
        git {
            remote {
                url('https://github.com/your-org/sample-repo.git')
                credentials('git-credentials')
            }
            branches('*/main')
        }
    }
    
    triggers {
        scm('H/15 * * * *')  // Poll every 15 minutes
    }
    
    wrappers {
        timestamps()
        timeout {
            absolute(30)  // 30 minute timeout
        }
    }
    
    steps {
        shell('''
            echo "Message: ${MESSAGE}"
            if [ "${VERBOSE}" = "true" ]; then
                echo "Verbose mode enabled"
                env | sort
            fi
            echo "Build completed successfully"
        ''')
    }
    
    publishers {
        archiveArtifacts {
            pattern('logs/*.log')
            allowEmpty(true)
        }
        
        mailer('devops@company.com', false, true)
    }
}

// Matrix job for multi-configuration builds
matrixJob('Examples/Matrix-Build') {
    displayName('Matrix Build Example')
    description('Multi-configuration build example')
    
    axes {
        textAxis('OS', ['ubuntu', 'centos', 'alpine'])
        textAxis('VERSION', ['java8', 'java11', 'java17'])
    }
    
    combinationFilter('!(OS=="alpine" && VERSION=="java8")')
    
    steps {
        shell('''
            echo "Building on OS: ${OS} with ${VERSION}"
            echo "Matrix configuration: ${OS}-${VERSION}"
        ''')
    }
    
    publishers {
        archiveArtifacts {
            pattern('build-${OS}-${VERSION}.log')
            allowEmpty(true)
        }
    }
}

// Multibranch pipeline job
multibranchPipelineJob('Examples/Multibranch-Pipeline') {
    displayName('Multibranch Pipeline Example')
    description('Multibranch pipeline for feature branches')
    
    branchSources {
        git {
            id('example-repo')
            remote('https://github.com/your-org/example-app.git')
            credentialsId('git-credentials')
            includes('*')
            excludes('archive/*')
        }
    }
    
    configure { node ->
        node / sources / 'data' / 'jenkins.branch.BranchSource' / source / traits << 'jenkins.plugins.git.traits.BranchDiscoveryTrait' {
            strategyId(3)  // Detect all branches
        }
    }
    
    factory {
        workflowBranchProjectFactory {
            scriptPath('Jenkinsfile')
        }
    }
    
    triggers {
        periodic(5)  // Scan for new branches every 5 minutes
    }
    
    orphanedItemStrategy {
        discardOldItems {
            daysToKeep(7)
            numToKeep(10)
        }
    }
}

out.println('✅ Sandbox-safe example jobs created successfully')