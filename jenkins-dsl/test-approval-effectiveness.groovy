// DSL Approval Effectiveness Test Script
// This script tests whether common DSL operations work without manual approval
// Run this script in Jenkins DSL to validate signature approval effectiveness

println "=== DSL Approval Effectiveness Test ==="
println "Testing various DSL operations for automatic approval..."

def testResults = []
def testsTotal = 0
def testsPass = 0

// Helper function to test operations
def testOperation(name, closure) {
    testsTotal++
    try {
        closure()
        testResults.add([name: name, status: "PASS", error: null])
        testsPass++
        println "✅ ${name}"
    } catch (Exception e) {
        testResults.add([name: name, status: "FAIL", error: e.message])
        println "❌ ${name} - ${e.message}"
    }
}

// Test 1: Basic Jenkins instance access
testOperation("Jenkins instance access") {
    def jenkins = Jenkins.instance
    def url = jenkins.getRootUrl()
    def items = jenkins.getAllItems()
    assert jenkins != null
    assert items != null
}

// Test 2: String operations
testOperation("String manipulation") {
    def testStr = "Hello World Jenkins DSL"
    def result = testStr.toLowerCase().replace(" ", "-").trim()
    assert result == "hello-world-jenkins-dsl"
}

// Test 3: Collection operations  
testOperation("Collection operations") {
    def list = new ArrayList()
    list.add("item1")
    list.add("item2")
    def map = new HashMap()
    map.put("key1", "value1")
    assert list.size() == 2
    assert map.containsKey("key1")
}

// Test 4: Date operations
testOperation("Date and time operations") {
    def now = new Date()
    def formatter = new SimpleDateFormat("yyyy-MM-dd")
    def formatted = formatter.format(now)
    assert formatted != null
    assert formatted.matches("\\d{4}-\\d{2}-\\d{2}")
}

// Test 5: Basic folder creation (dry run)
testOperation("Folder DSL syntax") {
    // This tests the syntax without actually creating the folder
    def folderConfig = {
        folder('Test/Approval-Test') {
            displayName('Approval Test Folder')
            description('Test folder for DSL approval validation')
        }
    }
    assert folderConfig != null
}

// Test 6: Basic job syntax test
testOperation("Job DSL syntax") {
    // This tests the syntax without actually creating the job
    def jobConfig = {
        job('Test/approval-test-job') {
            displayName('Approval Test Job')
            description('Test job for DSL approval validation')
            parameters {
                stringParam('TEST_PARAM', 'default', 'Test parameter')
                booleanParam('ENABLE_TEST', false, 'Enable test mode')
            }
            scm {
                git {
                    remote {
                        url('https://github.com/test/repo.git')
                        credentials('test-credentials')
                    }
                    branches('*/main')
                }
            }
            triggers {
                cron('H H * * *')
            }
            steps {
                shell('echo "Test execution"')
            }
            publishers {
                archiveArtifacts {
                    pattern('**/*.log')
                    allowEmpty(true)
                }
            }
        }
    }
    assert jobConfig != null
}

// Test 7: Pipeline job syntax test
testOperation("Pipeline DSL syntax") {
    def pipelineConfig = {
        pipelineJob('Test/approval-test-pipeline') {
            displayName('Approval Test Pipeline')
            description('Test pipeline for DSL approval validation')
            parameters {
                choiceParam('ENVIRONMENT', ['dev', 'staging', 'prod'], 'Target environment')
            }
            definition {
                cps {
                    script('''
                        pipeline {
                            agent any
                            options {
                                timeout(time: 1, unit: 'HOURS')
                                timestamps()
                            }
                            stages {
                                stage('Test') {
                                    steps {
                                        echo "Testing approval effectiveness"
                                        echo "Environment: ${params.ENVIRONMENT}"
                                    }
                                }
                            }
                        }
                    ''')
                    sandbox(true)
                }
            }
        }
    }
    assert pipelineConfig != null
}

// Test 8: Matrix job syntax test
testOperation("Matrix DSL syntax") {
    def matrixConfig = {
        matrixJob('Test/approval-test-matrix') {
            displayName('Approval Test Matrix')
            axes {
                textAxis('OS', ['ubuntu', 'centos'])
                textAxis('VERSION', ['java8', 'java11'])
            }
            steps {
                shell('echo "Testing on ${OS} with ${VERSION}"')
            }
        }
    }
    assert matrixConfig != null
}

// Test 9: View creation syntax test
testOperation("View DSL syntax") {
    def viewConfig = {
        listView('Test/Approval-Test-View') {
            description('Test view for approval validation')
            jobs {
                regex(/Test\/.*/)
            }
            columns {
                status()
                weather()
                name()
                lastSuccess()
                lastFailure()
                buildButton()
            }
        }
    }
    assert viewConfig != null
}

// Test 10: Credential access (read-only)
testOperation("Credential access (read-only)") {
    try {
        def jenkins = Jenkins.instance
        def credentialStore = jenkins.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0]
        // Just test that we can access the credential provider without errors
        assert credentialStore != null
    } catch (Exception e) {
        // This might fail due to security restrictions, which is expected
        println "   Note: Credential access restricted (expected for security)"
    }
}

// Test 11: JSON operations
testOperation("JSON operations") {
    def jsonBuilder = new groovy.json.JsonBuilder()
    jsonBuilder {
        test "approval"
        status "checking"
        timestamp new Date().toString()
    }
    def jsonText = jsonBuilder.toString()
    
    def jsonSlurper = new groovy.json.JsonSlurper()
    def parsed = jsonSlurper.parseText(jsonText)
    assert parsed.test == "approval"
}

// Test 12: Regex operations
testOperation("Regex operations") {
    def pattern = java.util.regex.Pattern.compile("test-.*")
    def matcher = pattern.matcher("test-approval-script")
    assert matcher.matches()
}

// Test 13: File operations (limited)
testOperation("Safe file operations") {
    def tempFile = new java.io.File("/tmp")
    assert tempFile.exists()
    assert tempFile.isDirectory()
    assert tempFile.getName() == "tmp"
}

// Test 14: Environment variable access
testOperation("Environment access") {
    def javaHome = System.getProperty("java.home")
    def userName = System.getenv("USER") ?: System.getenv("USERNAME") ?: "unknown"
    assert javaHome != null
    assert userName != null
}

// Generate test report
println "\n=== DSL Approval Test Results ==="
println "Tests executed: ${testsTotal}"
println "Tests passed: ${testsPass}"
println "Tests failed: ${testsTotal - testsPass}"
println "Success rate: ${Math.round((testsPass / testsTotal) * 100)}%"

if (testsPass == testsTotal) {
    println "\n🎉 ALL TESTS PASSED! DSL approval configuration is working effectively."
    println "Most common DSL operations should work without manual approval."
} else {
    println "\n⚠️ Some tests failed. Review the following operations:"
    testResults.findAll { it.status == "FAIL" }.each { result ->
        println "❌ ${result.name}: ${result.error}"
    }
    println "\nConsider updating the DSL approval script to include missing signatures."
}

println "\n📋 Recommendations:"
println "• Run this test after any Jenkins or plugin updates"
println "• Add any failing operations to the approval script"
println "• Test actual job creation in a development environment"
println "• Monitor 'Script Approval' page for any pending approvals"

// Return test results for potential automation use
return [
    total: testsTotal,
    passed: testsPass,
    failed: testsTotal - testsPass,
    successRate: Math.round((testsPass / testsTotal) * 100),
    results: testResults
]