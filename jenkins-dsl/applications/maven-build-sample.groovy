// Sample Maven Build Pipeline Job
// Demonstrates dynamic maven-agent usage with Job DSL

pipelineJob('Applications/Maven-Build-Sample') {
    displayName('Maven Build Sample')
    description('''
        Sample Maven build pipeline that demonstrates:
        - Git SCM checkout
        - Maven build and test
        - Docker image creation
        - Harbor registry push
        - Runs on dynamic maven-agent
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('30')
                    numToKeepStr('25')
                    artifactDaysToKeepStr('14')
                    artifactNumToKeepStr('10')
                }
            }
        }
        
        parameters {
            stringParam {
                name('BRANCH')
                description('Git branch to build')
                defaultValue('main')
                trim(true)
            }
            booleanParam {
                name('PUSH_TO_REGISTRY')
                description('Push built image to Harbor registry')
                defaultValue(true)
            }
            choiceParam {
                name('BUILD_TYPE')
                description('Type of build to perform')
                choices(['snapshot', 'release', 'hotfix'])
            }
        }
    }
    
    definition {
        cps {
            script('''
                pipeline {
                    agent {
                        label 'maven'  // Runs on dynamic maven-agent
                    }
                    
                    options {
                        timeout(time: 45, unit: 'MINUTES')
                        skipStagesAfterUnstable()
                        buildDiscarder(logRotator(daysToKeepStr: '30', numToKeepStr: '25'))
                    }
                    
                    environment {
                        MAVEN_OPTS = '-Xmx1024m -Xms512m'
                        HARBOR_REGISTRY = ''' + "'${HARBOR_REGISTRY}'" + '''
                        HARBOR_PROJECT = ''' + "'${HARBOR_PROJECT}'" + '''
                    }
                    
                    stages {
                        stage('Checkout') {
                            steps {
                                echo "Checking out branch: ${params.BRANCH}"
                                echo "Maven agent workspace: ${env.WORKSPACE}"
                            }
                        }
                        
                        stage('Maven Build') {
                            steps {
                                echo "Starting Maven build..."
                                sh '''
                                    echo "Maven version: $(mvn --version)"
                                    echo "Java version: $(java -version)"
                                '''
                            }
                        }
                        
                        stage('Docker Build') {
                            when {
                                expression { params.PUSH_TO_REGISTRY == true }
                            }
                            steps {
                                script {
                                    echo "Building Docker image for ${params.BUILD_TYPE} build"
                                }
                            }
                        }
                        
                        stage('Push to Harbor') {
                            when {
                                expression { params.PUSH_TO_REGISTRY == true }
                            }
                            steps {
                                echo "Pushing to Harbor registry: ${HARBOR_REGISTRY}/${HARBOR_PROJECT}"
                            }
                        }
                    }
                    
                    post {
                        always {
                            echo "Build completed on maven agent: ${env.NODE_NAME}"
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

println "Maven Build Sample job created successfully"