// Jenkins Image Builder Pipeline Job
// References: pipelines/Jenkinsfile.image-builder

pipelineJob('Infrastructure/Image-Builder') {
    displayName('Jenkins Image Builder Pipeline')
    description('''
        Infrastructure Pipeline: Build and Push Jenkins Images to Harbor Registry
        
        This pipeline builds all Jenkins infrastructure images including:
        - Jenkins Master with pre-configured plugins and JCasC
        - DIND Agent for Docker operations
        - Maven Agent for Java builds
        - Python Agent for Python builds
        - Node.js Agent for frontend builds
        
        Images are pushed to Harbor registry
        Script: pipelines/Jenkinsfile.image-builder
    ''')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('30')
                    numToKeepStr('20')
                    artifactDaysToKeepStr('-1')
                    artifactNumToKeepStr('-1')
                }
            }
        }
        
        pipelineTriggers {
            triggers {
                cron {
                    spec('H 1 * * 0')  // Weekly on Sunday at 1 AM
                }
            }
        }
        
        parameters {
            booleanParam {
                name('FORCE_REBUILD')
                description('Force rebuild all images without cache')
                defaultValue(false)
            }
            booleanParam {
                name('PUSH_TO_HARBOR')
                description('Push built images to Harbor registry')
                defaultValue(true)
            }
            stringParam {
                name('IMAGE_TAG')
                description('Tag for built images (default: latest)')
                defaultValue('latest')
                trim(true)
            }
            choiceParam {
                name('IMAGES_TO_BUILD')
                description('Select which images to build')
                choices(['all', 'master', 'dind-agent', 'maven-agent', 'python-agent', 'nodejs-agent'])
            }
        }
    }
    
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(JENKINS_INFRASTRUCTURE_REPO_URL ?: 'https://github.com/company/jenkins-ha.git')
                        credentials(GIT_CREDENTIALS_ID ?: 'git-credentials')
                    }
                    branch('*/main')
                }
            }
            scriptPath('pipelines/Jenkinsfile.image-builder')
            lightweight(true)
        }
    }
}

println "Image Builder pipeline job created successfully"