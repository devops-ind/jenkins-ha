// Sample Freestyle Job
// Demonstrates dynamic python-agent usage with freestyle job configuration

freeStyleProject('Applications/Freestyle-Sample') {
    displayName('Freestyle Sample Job')
    description('''
        Sample freestyle job that runs on dynamic python-agent.
        Demonstrates basic freestyle job configuration with Job DSL.
    ''')
    
    label('python')  // Runs on python-agent
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    daysToKeepStr('14')
                    numToKeepStr('10')
                }
            }
        }
        
        parameters {
            stringParam {
                name('MESSAGE')
                description('Custom message to display')
                defaultValue('Hello from Job DSL!')
                trim(true)
            }
        }
    }
    
    steps {
        shell('''
            echo "=== Freestyle Job Sample ==="
            echo "Running on: $(hostname)"
            echo "Agent: $NODE_NAME"
            echo "Labels: $NODE_LABELS"
            echo "Message: $MESSAGE"
            echo "Python version: $(python3 --version)"
            echo "Workspace: $WORKSPACE"
        ''')
    }
    
    publishers {
        buildDescription('', 'Sample job executed with message: $MESSAGE')
        
        wsCleanup {
            cleanWhenSuccess(true)
            cleanWhenAborted(true)
        }
    }
    
    wrappers {
        timeout {
            absolute(10)
            abortBuild()
        }
        
        timestamps()
        colorizeOutput()
    }
}

println "Freestyle Sample job created successfully"