import jenkins.model.*
import org.jenkinsci.plugins.scriptsecurity.scripts.*
import org.jenkinsci.plugins.scriptsecurity.sandbox.groovy.SecureGroovyScript

/*
 * Jenkins DSL Script Approval Setup
 * This initialization script pre-approves safe DSL operations
 * to reduce manual approval requirements
 */

println "=== Configuring DSL Script Approvals ==="

def jenkins = Jenkins.instance
def scriptApproval = ScriptApproval.get()

// Pre-approved method signatures for DSL scripts
def approvedSignatures = [
    // Basic Groovy operations
    "method groovy.lang.GroovyObject getProperty java.lang.String",
    "method groovy.lang.GroovyObject setProperty java.lang.String java.lang.Object", 
    "method groovy.lang.GroovyObject invokeMethod java.lang.String java.lang.Object",
    "method java.lang.Object equals java.lang.Object",
    "method java.lang.Object toString",
    "method java.lang.String valueOf java.lang.Object",
    
    // Collections and data structures
    "method java.util.Collection size",
    "method java.util.Collection isEmpty", 
    "method java.util.Collection contains java.lang.Object",
    "method java.util.Map get java.lang.Object",
    "method java.util.Map put java.lang.Object java.lang.Object",
    "method java.util.Map containsKey java.lang.Object",
    "method java.util.Map keySet",
    "method java.util.Map values",
    "method java.util.List add java.lang.Object",
    "method java.util.List get int",
    "method java.util.Set add java.lang.Object",
    
    // String operations
    "method java.lang.String replace java.lang.CharSequence java.lang.CharSequence",
    "method java.lang.String replaceAll java.lang.String java.lang.String",
    "method java.lang.String split java.lang.String", 
    "method java.lang.String trim",
    "method java.lang.String toLowerCase",
    "method java.lang.String toUpperCase",
    "method java.lang.String substring int",
    "method java.lang.String substring int int",
    "method java.lang.String startsWith java.lang.String",
    "method java.lang.String endsWith java.lang.String",
    "method java.lang.String contains java.lang.CharSequence",
    "method java.lang.String matches java.lang.String",
    "method java.lang.String length",
    
    // Basic constructors 
    "new java.util.ArrayList",
    "new java.util.ArrayList int",
    "new java.util.LinkedList",
    "new java.util.HashMap", 
    "new java.util.LinkedHashMap",
    "new java.util.HashSet",
    "new java.lang.String java.lang.String",
    "new java.lang.StringBuilder",
    "new java.lang.StringBuilder java.lang.String",
    "new java.util.Date",
    "new java.text.SimpleDateFormat java.lang.String",
    
    // Date and time
    "method java.util.Date getTime",
    "method java.util.Date before java.util.Date", 
    "method java.util.Date after java.util.Date",
    "method java.text.SimpleDateFormat format java.util.Date",
    "method java.text.SimpleDateFormat parse java.lang.String",
    
    // Jenkins-specific safe operations
    "staticMethod jenkins.model.Jenkins getInstance",
    "method jenkins.model.Jenkins getItemByFullName java.lang.String",
    "method hudson.model.ItemGroup getItem java.lang.String", 
    "method hudson.model.Item getName",
    "method hudson.model.Item getFullName",
    "method hudson.model.Item getUrl",
    
    // System properties (limited safe ones)
    "staticMethod java.lang.System getProperty java.lang.String",
    "staticMethod java.lang.System getenv java.lang.String",
    
    // File operations (very limited)
    "method java.io.File exists", 
    "method java.io.File isDirectory",
    "method java.io.File isFile",
    "method java.io.File getName",
    "method java.io.File getPath",
    "method java.io.File getParent",
    
    // Math operations
    "method java.lang.Math max int int",
    "method java.lang.Math min int int", 
    "method java.lang.Math abs int",
    "method java.lang.Math round float",
    "method java.lang.Math ceil double",
    "method java.lang.Math floor double",
    
    // Regex operations
    "method java.util.regex.Pattern compile java.lang.String",
    "method java.util.regex.Pattern matcher java.lang.CharSequence",
    "method java.util.regex.Matcher matches",
    "method java.util.regex.Matcher find",
    "method java.util.regex.Matcher group",
    "method java.util.regex.Matcher group int",
    
    // Exception handling
    "method java.lang.Throwable getMessage",
    "method java.lang.Throwable getCause",
    "method java.lang.Throwable printStackTrace",
    
    // DSL-specific operations
    "method javaposse.jobdsl.dsl.DslFactory job java.lang.String",
    "method javaposse.jobdsl.dsl.DslFactory folder java.lang.String", 
    "method javaposse.jobdsl.dsl.DslFactory pipelineJob java.lang.String",
    "method javaposse.jobdsl.dsl.DslFactory multibranchPipelineJob java.lang.String",
    "method javaposse.jobdsl.dsl.DslFactory matrixJob java.lang.String",
    "method javaposse.jobdsl.dsl.DslFactory listView java.lang.String",
    "method javaposse.jobdsl.dsl.DslFactory buildPipelineView java.lang.String"
]

// Add approved signatures
def currentSignatures = scriptApproval.getApprovedSignatures()
approvedSignatures.each { signature ->
    if (!currentSignatures.contains(signature)) {
        try {
            scriptApproval.approveSignature(signature)
            println "✅ Approved signature: ${signature}"
        } catch (Exception e) {
            println "⚠️ Could not approve signature: ${signature} - ${e.message}"
        }
    }
}

// Configure Job DSL security settings
try {
    def globalJobDslSecurityConfig = jenkins.getDescriptor('javaposse.jobdsl.plugin.GlobalJobDslSecurityConfiguration')
    if (globalJobDslSecurityConfig != null) {
        // Enable script security but allow sandbox mode
        globalJobDslSecurityConfig.useScriptSecurity = true
        globalJobDslSecurityConfig.save()
        println "✅ Job DSL security configuration updated"
    }
} catch (Exception e) {
    println "⚠️ Could not configure Job DSL security: ${e.message}"
}

// Save Jenkins configuration
jenkins.save()

println "=== DSL Script Approval Setup Complete ===\n"
println "Configuration Summary:"
println "• Pre-approved ${approvedSignatures.size()} safe method signatures"  
println "• Enabled script security with sandbox mode"
println "• DSL jobs can now run with reduced approval requirements"
println ""
println "Note: Complex operations may still require manual approval"
println "Use sandbox mode in DSL scripts: sandbox(true)"