// DSL Sandbox Test Script
// This script validates that common DSL operations work in sandbox mode

println "=== Testing DSL Sandbox Compatibility ==="

try {
    // Test 1: Basic folder creation
    folder('Test/Sandbox-Tests') {
        displayName('Sandbox Test Folder')
        description('Testing sandbox-compatible operations')
    }
    println "✅ Test 1: Folder creation - PASSED"
    
    // Test 2: Simple pipeline job
    pipelineJob('Test/Sandbox-Tests/Simple-Pipeline') {
        displayName('Sandbox Test Pipeline')
        description('Testing pipeline creation in sandbox')
        
        parameters {
            stringParam('TEST_PARAM', 'default', 'Test parameter')
            booleanParam('ENABLE_FEATURE', false, 'Feature flag')
        }
        
        definition {
            cps {
                script('''
                    pipeline {
                        agent any
                        options {
                            buildDiscarder(logRotator(numToKeepStr: '5'))
                            timeout(time: 30, unit: 'MINUTES')
                        }
                        stages {
                            stage('Test') {
                                steps {
                                    echo "Testing with parameter: ${params.TEST_PARAM}"
                                    echo "Feature enabled: ${params.ENABLE_FEATURE}"
                                }
                            }
                        }
                    }
                ''')
                sandbox(true)
            }
        }
    }
    println "✅ Test 2: Pipeline job creation - PASSED"
    
    // Test 3: Freestyle job
    job('Test/Sandbox-Tests/Simple-Freestyle') {
        displayName('Sandbox Test Freestyle')
        description('Testing freestyle job creation')
        
        parameters {
            choiceParam('ENVIRONMENT', ['dev', 'staging', 'prod'], 'Target environment')
        }
        
        steps {
            shell('''
                echo "Environment: $ENVIRONMENT"
                echo "Build number: $BUILD_NUMBER"
                echo "Job name: $JOB_NAME"
            ''')
        }
        
        publishers {
            archiveArtifacts {
                pattern('*.log')
                allowEmpty(true)
            }
        }
    }
    println "✅ Test 3: Freestyle job creation - PASSED"
    
    // Test 4: List view
    listView('Test/Sandbox-Tests-View') {
        description('View for sandbox test jobs')
        
        jobs {
            regex('Test/Sandbox-Tests/.*')
        }
        
        columns {
            status()
            weather()
            name()
            lastSuccess()
            lastFailure()
            buildButton()
        }
        
        jobFilters {
            status {
                matchType(MatchType.INCLUDE_MATCHED)
                status(Status.BLUE, Status.RED, Status.YELLOW)
            }
        }
    }
    println "✅ Test 4: List view creation - PASSED"
    
    // Test 5: Matrix job
    matrixJob('Test/Sandbox-Tests/Matrix-Build') {
        displayName('Sandbox Matrix Test')
        description('Testing matrix job in sandbox')
        
        axes {
            textAxis('OS', ['ubuntu', 'centos'])
            textAxis('VERSION', ['java11', 'java17'])
        }
        
        steps {
            shell('''
                echo "Building on $OS with $VERSION"
                echo "Matrix combination: $OS-$VERSION"
            ''')
        }
    }
    println "✅ Test 5: Matrix job creation - PASSED"
    
    // Test 6: String operations (should be pre-approved)
    def testString = "Hello World"
    def result = testString.toLowerCase().replace(" ", "-")
    println "✅ Test 6: String operations (${result}) - PASSED"
    
    // Test 7: Collection operations
    def testList = []
    testList.add("item1")
    testList.add("item2")
    def testMap = [:]
    testMap.put("key1", "value1")
    println "✅ Test 7: Collection operations (list size: ${testList.size()}, map size: ${testMap.size()}) - PASSED"
    
    // Test 8: Date operations
    def currentDate = new Date()
    def timeString = currentDate.toString()
    println "✅ Test 8: Date operations (${timeString}) - PASSED"
    
    println "\n=== All Sandbox Tests Completed Successfully ==="
    println "Summary:"
    println "• Folder creation: Working"
    println "• Pipeline jobs: Working"  
    println "• Freestyle jobs: Working"
    println "• Views: Working"
    println "• Matrix jobs: Working"
    println "• String operations: Working"
    println "• Collection operations: Working"
    println "• Date operations: Working"
    println ""
    println "🎉 DSL Sandbox implementation is functioning correctly!"
    
} catch (Exception e) {
    println "❌ Sandbox test failed: ${e.message}"
    e.printStackTrace()
    throw e
}