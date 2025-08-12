#!/usr/bin/env groovy

/**
 * Jenkins DSL Seed Script
 * This script creates all jobs, folders, and views from DSL definitions
 * 
 * This script runs in sandbox mode for security
 */

// Import necessary classes
import jenkins.model.Jenkins
import groovy.io.FileType

def jenkins = Jenkins.instance
def workspace = build.workspace.absolutize()

println "=== Jenkins DSL Seed Job ==="
println "Workspace: ${workspace}"
println "Jenkins URL: ${jenkins.getRootUrl()}"

try {
    // Create folders first
    println "\n=== Creating Folders ==="
    
    folder('Infrastructure') {
        displayName('Infrastructure Management')
        description('''
            Infrastructure jobs for managing Jenkins deployment, 
            maintenance, monitoring, and automation tasks.
        ''')
    }

    folder('Applications') {
        displayName('Application Jobs') 
        description('''
            Application build, test, and deployment jobs.
            Organized by application or team.
        ''')
    }

    folder('Utilities') {
        displayName('Utility Jobs')
        description('''
            Utility and maintenance jobs including backups,
            health checks, and system administration tasks.
        ''')
    }
    
    println "✅ Folders created successfully"

    // Create views
    println "\n=== Creating Views ==="
    
    listView('All Infrastructure') {
        description('All infrastructure-related jobs')
        jobs {
            regex(/Infrastructure\/.*/)
        }
        columns {
            status()
            weather()
            name()
            lastSuccess()
            lastFailure()
            lastDuration()
            buildButton()
        }
    }

    listView('All Applications') {
        description('All application build and deployment jobs')
        jobs {
            regex(/Applications\/.*/)
        }
        columns {
            status()
            weather()
            name()
            lastSuccess()
            lastFailure()
            lastDuration()
            buildButton()
        }
    }
    
    println "✅ Views created successfully"

    // Create infrastructure jobs
    println "\n=== Creating Infrastructure Jobs ==="
    
    pipelineJob('Infrastructure/Image-Builder') {
        displayName('Jenkins Image Builder')
        description('''
            Builds and manages Jenkins Docker images including:
            • Jenkins master images
            • Jenkins agent images (Maven, Python, Node.js, DIND)
            • Pushes to Docker registry
        ''')
        
        parameters {
            choiceParam('IMAGES_TO_BUILD', ['all', 'master', 'agents', 'maven', 'python', 'nodejs', 'dind'], 'Images to build')
            stringParam('IMAGE_TAG', 'latest', 'Tag for built images')
            booleanParam('FORCE_REBUILD', false, 'Force rebuild even if images exist')
            booleanParam('PUSH_TO_REGISTRY', true, 'Push built images to registry')
        }
        
        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url('${GIT_REPO_URL}')
                            credentials('git-credentials')
                        }
                        branches('*/main')
                        scriptPath('pipelines/Jenkinsfile.image-builder')
                    }
                }
            }
        }
        
        triggers {
            cron('H 2 * * 0')  // Weekly on Sunday at 2 AM
        }
    }

    pipelineJob('Infrastructure/Health-Check') {
        displayName('Infrastructure Health Check')
        description('''
            Comprehensive health checks for Jenkins infrastructure:
            • Jenkins master and agents connectivity
            • Service health monitoring
            • Resource usage verification
        ''')
        
        parameters {
            choiceParam('CHECK_TYPE', ['full', 'basic', 'connectivity', 'resources'], 'Type of health check')
            booleanParam('SEND_NOTIFICATIONS', true, 'Send notifications on issues')
        }
        
        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url('${GIT_REPO_URL}')
                            credentials('git-credentials')
                        }
                        branches('*/main')
                        scriptPath('pipelines/Jenkinsfile.health-check')
                    }
                }
            }
        }
        
        triggers {
            cron('H/15 * * * *')  // Every 15 minutes
        }
    }

    pipelineJob('Infrastructure/Security-Scan') {
        displayName('Security Vulnerability Scan')
        description('''
            Security scanning for Jenkins infrastructure:
            • Container vulnerability scanning with Trivy
            • Dependency security analysis
            • Configuration security assessment
        ''')
        
        parameters {
            choiceParam('SCAN_TYPE', ['all', 'containers', 'dependencies', 'config'], 'Type of security scan')
            stringParam('SEVERITY_THRESHOLD', 'HIGH', 'Minimum severity to report (LOW, MEDIUM, HIGH, CRITICAL)')
            booleanParam('FAIL_ON_CRITICAL', true, 'Fail build on critical vulnerabilities')
        }
        
        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url('${GIT_REPO_URL}')
                            credentials('git-credentials')
                        }
                        branches('*/main')
                        scriptPath('pipelines/Jenkinsfile.security-scan')
                    }
                }
            }
        }
        
        triggers {
            cron('H 1 * * *')  // Daily at 1 AM
        }
    }

    pipelineJob('Utilities/Backup-Job') {
        displayName('Jenkins Backup')
        description('''
            Automated backup of Jenkins configuration and data:
            • Jenkins configuration backup
            • Job definitions and history
            • User data and credentials (encrypted)
        ''')
        
        parameters {
            choiceParam('BACKUP_TYPE', ['full', 'config', 'jobs'], 'Type of backup')
            stringParam('RETENTION_DAYS', '30', 'Days to retain backups')
            booleanParam('COMPRESS_BACKUP', true, 'Compress backup files')
        }
        
        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url('${GIT_REPO_URL}')
                            credentials('git-credentials')
                        }
                        branches('*/main')
                        scriptPath('pipelines/Jenkinsfile.backup')
                    }
                }
            }
        }
        
        triggers {
            cron('H 3 * * *')  // Daily at 3 AM
        }
    }

    println "✅ Infrastructure jobs created successfully"

    // Create sample application jobs
    println "\n=== Creating Sample Application Jobs ==="

    pipelineJob('Applications/Maven-Build-Sample') {
        displayName('Maven Build Sample')
        description('''
            Sample Maven application build pipeline demonstrating:
            • Multi-stage build process
            • Testing and quality gates
            • Docker image creation
        ''')
        
        parameters {
            stringParam('GIT_BRANCH', 'main', 'Git branch to build')
            booleanParam('RUN_TESTS', true, 'Execute unit tests')
            booleanParam('BUILD_DOCKER_IMAGE', false, 'Build Docker image')
        }
        
        definition {
            cps {
                script('''
                    pipeline {
                        agent { label 'maven' }
                        
                        options {
                            buildDiscarder(logRotator(daysToKeepStr: '30', numToKeepStr: '10'))
                            timeout(time: 1, unit: 'HOURS')
                            timestamps()
                        }
                        
                        stages {
                            stage('Checkout') {
                                steps {
                                    echo "Checking out code from branch: ${params.GIT_BRANCH}"
                                    // Add actual git checkout here
                                }
                            }
                            
                            stage('Build') {
                                steps {
                                    echo "Building Maven project..."
                                    // sh 'mvn clean compile'
                                }
                            }
                            
                            stage('Test') {
                                when { 
                                    expression { params.RUN_TESTS } 
                                }
                                steps {
                                    echo "Running tests..."
                                    // sh 'mvn test'
                                }
                            }
                            
                            stage('Package') {
                                steps {
                                    echo "Packaging application..."
                                    // sh 'mvn package -DskipTests'
                                }
                            }
                            
                            stage('Docker Build') {
                                when { 
                                    expression { params.BUILD_DOCKER_IMAGE } 
                                }
                                steps {
                                    echo "Building Docker image..."
                                    // docker.build("app:${env.BUILD_NUMBER}")
                                }
                            }
                        }
                        
                        post {
                            always {
                                echo "Build completed"
                            }
                        }
                    }
                ''')
                sandbox(true)
            }
        }
    }

    println "✅ Sample application jobs created successfully"

    println "\n=== DSL Seed Job Completed Successfully ==="
    println "Total jobs created: ${jenkins.getAllItems().size()}"
    
} catch (Exception e) {
    println "❌ Error in DSL seed job: ${e.message}"
    e.printStackTrace()
    throw e
}