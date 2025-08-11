// Job DSL Seed Job Configuration
// This job will automatically create all jobs defined in the jenkins-dsl directory

pipelineJob('Infrastructure/Job-DSL-Seed') {
    displayName('Job DSL Seed Pipeline')
    description('''
        Git-based Job DSL Seed Pipeline with SCM integration.
        
        This seed job pulls from Git repository and processes Job DSL scripts:
        • folders.groovy - Creates folder structure
        • views.groovy - Creates Jenkins views
        • infrastructure/*.groovy - Infrastructure management jobs
        • applications/*.groovy - Application build/deploy jobs
        
        Features:
        • Git SCM integration with branch selection
        • Automatic polling for repository changes
        • Comprehensive Job DSL script processing
        • Build artifact generation and reporting
        
        Repository Structure:
        jenkins-dsl/
        ├── folders.groovy
        ├── views.groovy
        ├── seed-jobs.groovy
        ├── infrastructure/
        │   ├── ssh-key-exchange.groovy
        │   ├── ansible-image-builder.groovy
        │   └── dynamic-ansible-executor.groovy
        └── applications/
            └── *.groovy
    ''')
    
    parameters {
        stringParam('GIT_REPOSITORY', 'https://github.com/your-org/jenkins-ha.git', 'Git repository containing Job DSL scripts')
        stringParam('DSL_BRANCH', 'main', 'Git branch containing Job DSL scripts')
        credentialsParam('GIT_CREDENTIALS') {
            type('com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl')
            description('Git repository credentials')
            defaultValue('git-credentials')
        }
        stringParam('DSL_SCRIPTS_PATH', 'jenkins-dsl', 'Path to Job DSL scripts in repository')
        choiceParam('REMOVAL_ACTION', ['IGNORE', 'DELETE', 'DISABLE'], 'Action for removed jobs')
        booleanParam('DRY_RUN', false, 'Perform dry run without creating/updating jobs')
        choiceParam('LOG_LEVEL', ['INFO', 'DEBUG', 'WARN'], 'Job DSL processing log level')
        booleanParam('PROCESS_VIEWS', true, 'Process view definitions')
        booleanParam('VALIDATE_BEFORE_APPLY', true, 'Validate scripts before applying changes')
    }
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    numToKeepStr('25')
                    daysToKeepStr('30')
                    artifactDaysToKeepStr('14')
                    artifactNumToKeepStr('10')
                }
            }
        }
        pipelineTriggers {
            triggers {
                scm('H/10 * * * *')  // Poll SCM every 10 minutes
            }
        }
    }
    
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('${GIT_REPOSITORY}')
                        credentials('${GIT_CREDENTIALS}')
                    }
                    branches('*/${DSL_BRANCH}')
                    extensions {
                        cleanBeforeCheckout()
                        cloneOptions {
                            shallow(false)
                            noTags(false)
                            reference('')
                            timeout(10)
                        }
                    }
                }
            }
            scriptPath('pipelines/Jenkinsfile.job-dsl-seed')
        }
    }
}

println "Job DSL Seed pipeline job created successfully"