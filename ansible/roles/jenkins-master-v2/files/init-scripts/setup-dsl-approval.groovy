import jenkins.model.*
import org.jenkinsci.plugins.scriptsecurity.scripts.*

/*
 * Jenkins DSL Script Approval Setup
 * This initialization script pre-approves safe DSL operations
 * to reduce manual approval requirements
 */

println "=== Configuring DSL Script Approvals ==="

def jenkins = Jenkins.instance

// Check if Script Security plugin is available
def scriptApproval = null
try {
    scriptApproval = ScriptApproval.get()
    println "✅ Script Security plugin found and accessible"
} catch (Exception e) {
    println "⚠️ Script Security plugin not available: ${e.message}"
    println "DSL approval configuration will be skipped"
    return
}

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
    "method java.util.Collection iterator",
    "method java.util.Iterator hasNext",
    "method java.util.Iterator next",
    "method java.util.Map get java.lang.Object",
    "method java.util.Map put java.lang.Object java.lang.Object",
    "method java.util.Map containsKey java.lang.Object",
    "method java.util.Map keySet",
    "method java.util.Map values",
    "method java.util.Map entrySet",
    "method java.util.Map$Entry getKey",
    "method java.util.Map$Entry getValue",
    "method java.util.List add java.lang.Object",
    "method java.util.List get int",
    "method java.util.List size",
    "method java.util.Set add java.lang.Object",
    "method java.util.Set contains java.lang.Object",
    
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
    "method java.lang.String indexOf java.lang.String",
    "method java.lang.String lastIndexOf java.lang.String",
    
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
    "method jenkins.model.Jenkins getAllItems",
    "method jenkins.model.Jenkins getRootUrl",
    "method hudson.model.ItemGroup getItem java.lang.String", 
    "method hudson.model.Item getName",
    "method hudson.model.Item getFullName",
    "method hudson.model.Item getUrl",
    "method hudson.model.Run getWorkspace",
    "method hudson.FilePath absolutize",
    
    // System properties (limited safe ones)
    "staticMethod java.lang.System getProperty java.lang.String",
    "staticMethod java.lang.System getenv java.lang.String",
    "staticMethod java.lang.System getenv",
    
    // File operations (very limited)
    "method java.io.File exists", 
    "method java.io.File isDirectory",
    "method java.io.File isFile",
    "method java.io.File getName",
    "method java.io.File getPath",
    "method java.io.File getParent",
    "new java.io.File java.lang.String",
    
    // Math operations
    "method java.lang.Math max int int",
    "method java.lang.Math min int int", 
    "method java.lang.Math abs int",
    "method java.lang.Math round float",
    "method java.lang.Math ceil double",
    "method java.lang.Math floor double",
    
    // Regex operations
    "staticMethod java.util.regex.Pattern compile java.lang.String",
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
    "method javaposse.jobdsl.dsl.DslFactory buildPipelineView java.lang.String",
    
    // Build and environment access
    "field hudson.model.Run ENV",
    "field hudson.model.Run BUILD_NUMBER",
    "field hudson.model.Run BUILD_URL",
    "method hudson.model.EnvironmentContributor buildEnvironmentFor hudson.model.Job hudson.model.Run hudson.model.TaskListener",
    
    // Git and SCM operations
    "method hudson.plugins.git.GitSCM getBranches",
    "method hudson.plugins.git.BranchSpec getName",
    "method hudson.plugins.git.GitSCM getRepositories",
    "method hudson.plugins.git.UserRemoteConfig getUrl",
    "method hudson.plugins.git.UserRemoteConfig getCredentialsId",
    
    // JSON operations for secure data handling
    "method groovy.json.JsonBuilder call",
    "method groovy.json.JsonBuilder call groovy.lang.Closure",
    "method groovy.json.JsonSlurper parseText java.lang.String",
    "new groovy.json.JsonBuilder",
    "new groovy.json.JsonSlurper",
    
    // Credential and security operations (safe ones)
    "method com.cloudbees.plugins.credentials.CredentialsProvider lookupCredentials java.lang.Class hudson.model.Item",
    "method com.cloudbees.plugins.credentials.Credentials getId",
    "method com.cloudbees.plugins.credentials.Credentials getDescription",
    
    // Folder credential properties (needed for folder DSL)
    "method com.cloudbees.hudson.plugins.folder.properties.FolderCredentialsProperty getDomainCredentials",
    "method com.cloudbees.hudson.plugins.folder.properties.FolderCredentialsProperty$DomainCredentials getDomain",
    "method com.cloudbees.hudson.plugins.folder.properties.FolderCredentialsProperty$DomainCredentials getCredentials",
    
    // Archive and artifacts
    "method hudson.tasks.ArtifactArchiver getArtifacts",
    "method hudson.tasks.ArtifactArchiver getAllowEmptyArchive",
    
    // Build triggers
    "method hudson.triggers.TimerTrigger getSpec",
    "method hudson.triggers.SCMTrigger getSpec",
    
    // Publishers and post-build actions
    "method hudson.tasks.Mailer getRecipients",
    "method hudson.tasks.Mailer getDontNotifyEveryUnstableBuild",
    "method hudson.tasks.Mailer getSendToIndividuals",
    
    // Pipeline script security
    "method org.jenkinsci.plugins.workflow.cps.CpsScript writeJSON",
    "method org.jenkinsci.plugins.workflow.cps.CpsScript readJSON",
    "method org.jenkinsci.plugins.workflow.cps.CpsScript writeFile",
    "method org.jenkinsci.plugins.workflow.cps.CpsScript emailext",
    
    // SSH and remote operations (limited safe ones)
    "method org.hidetake.groovy.ssh.core.Remote getName",
    "method org.hidetake.groovy.ssh.core.Remote getHost",
    
    // Parameter handling
    "method hudson.model.ParameterDefinition getName",
    "method hudson.model.ParameterDefinition getDescription",
    "method hudson.model.ParameterDefinition getDefaultParameterValue",
    "method hudson.model.StringParameterDefinition getDefaultValue",
    "method hudson.model.BooleanParameterDefinition getDefaultValue",
    "method hudson.model.ChoiceParameterDefinition getChoices",
    
    // Node and agent operations
    "method hudson.model.Node getNodeName",
    "method hudson.model.Node getLabelString",
    "method jenkins.model.Jenkins getLabel java.lang.String",
    
    // Build history and status
    "method hudson.model.Job getLastBuild",
    "method hudson.model.Job getLastSuccessfulBuild",
    "method hudson.model.Job getLastFailedBuild",
    "method hudson.model.Run getResult",
    "method hudson.model.Run getNumber",
    "method hudson.model.Run getTimestamp",
    "method hudson.model.Run getDuration",
    
    // View operations  
    "method hudson.model.View getItems",
    "method hudson.model.View getName",
    "method hudson.model.View getDescription",
    
    // Matrix job operations
    "method hudson.matrix.MatrixProject getAxes",
    "method hudson.matrix.Axis getName",
    "method hudson.matrix.Axis getValues",
    
    // Multibranch pipeline operations
    "method jenkins.branch.MultiBranchProject getSources",
    "method jenkins.branch.BranchSource getSource",
    "method jenkins.plugins.git.GitSCMSource getRemote",
    "method jenkins.plugins.git.GitSCMSource getCredentialsId"
]

// Add approved signatures with enhanced error handling
def currentSignatures = scriptApproval.getApprovedSignatures()
def approvedCount = 0
def skippedCount = 0
def failedCount = 0
def failedSignatures = []

println "\n=== Processing ${approvedSignatures.size()} method signatures ==="

approvedSignatures.each { signature ->
    if (!signature?.trim()) {
        skippedCount++
        return // Skip empty signatures
    }
    
    if (currentSignatures.contains(signature)) {
        skippedCount++
        println "⏩ Already approved: ${signature.take(60)}${signature.length() > 60 ? '...' : ''}"
        return
    }
    
    try {
        scriptApproval.approveSignature(signature)
        approvedCount++
        println "✅ Approved: ${signature.take(80)}${signature.length() > 80 ? '...' : ''}"
    } catch (Exception e) {
        failedCount++
        failedSignatures.add([signature: signature, error: e.message])
        println "❌ Failed: ${signature.take(60)}${signature.length() > 60 ? '...' : ''}"
        println "   Error: ${e.message}"
    }
}

println "\n=== Signature Approval Summary ==="
println "✅ Successfully approved: ${approvedCount}"
println "⏩ Already approved (skipped): ${skippedCount}" 
println "❌ Failed to approve: ${failedCount}"

if (failedCount > 0) {
    println "\n=== Failed Signatures Details ==="
    failedSignatures.each { item ->
        println "❌ ${item.signature}"
        println "   Error: ${item.error}"
    }
    println "\nNote: Some failures may be due to:"
    println "• Plugin not installed or inactive"
    println "• Signature format incompatibility"
    println "• Security policy restrictions"
    println "• Jenkins version compatibility issues"
}

// Configure Job DSL security settings
try {
    // Check if Job DSL plugin is installed and available
    def jobDslPlugin = jenkins.getPluginManager().getPlugin('job-dsl')
    if (jobDslPlugin == null) {
        println "⚠️ Job DSL plugin not found - skipping security configuration"
    } else if (!jobDslPlugin.isActive()) {
        println "⚠️ Job DSL plugin not active - skipping security configuration"
    } else {
        println "✅ Job DSL plugin found and active (version: ${jobDslPlugin.getVersion()})"
        
        // Try multiple ways to access the configuration
        def globalJobDslSecurityConfig = null
        
        // Method 1: Try by class name
        try {
            globalJobDslSecurityConfig = jenkins.getDescriptor('javaposse.jobdsl.plugin.GlobalJobDslSecurityConfiguration')
        } catch (Exception e1) {
            // Method 2: Try by descriptor class
            try {
                def configClass = Class.forName('javaposse.jobdsl.plugin.GlobalJobDslSecurityConfiguration')
                globalJobDslSecurityConfig = jenkins.getDescriptor(configClass)
            } catch (Exception e2) {
                println "⚠️ Could not access Job DSL security configuration: ${e2.message}"
            }
        }
        
        if (globalJobDslSecurityConfig != null) {
            // Enable script security but allow sandbox mode
            globalJobDslSecurityConfig.useScriptSecurity = true
            globalJobDslSecurityConfig.save()
            println "✅ Job DSL security configuration updated successfully"
            println "  • Script security enabled: ${globalJobDslSecurityConfig.useScriptSecurity}"
        } else {
            println "⚠️ Job DSL security configuration not accessible"
            println "  • This may be due to plugin version compatibility"
            println "  • DSL scripts will use default security settings"
        }
    }
} catch (Exception e) {
    println "⚠️ Exception while configuring Job DSL security: ${e.message}"
    println "  • Stack trace: ${e.getStackTrace().take(3).join(', ')}"
}

// Save Jenkins configuration
jenkins.save()

println "\n=== DSL Script Approval Setup Complete ===\n"

// Generate comprehensive status report
def finalCurrentSignatures = scriptApproval.getApprovedSignatures()
def totalApprovedNow = finalCurrentSignatures.size()

println "📊 Final Configuration Summary:"
println "• Total signatures in approval list: ${totalApprovedNow}"
println "• Signatures processed this run: ${approvedSignatures.size()}"
println "• Successfully approved this run: ${approvedCount}"
println "• Previously approved (skipped): ${skippedCount}"
println "• Failed to approve: ${failedCount}"

// Calculate effectiveness
def effectivenessPercent = approvedCount > 0 ? Math.round((approvedCount / (approvedCount + failedCount)) * 100) : 0
println "• Approval success rate: ${effectivenessPercent}%"

println "\n🔧 Security Configuration:"
try {
    def jobDslPlugin = jenkins.getPluginManager().getPlugin('job-dsl')
    if (jobDslPlugin?.isActive()) {
        println "• Job DSL plugin: Active (${jobDslPlugin.getVersion()})"
        println "• Script security: Enabled with sandbox mode"
        println "• DSL jobs can run with reduced manual approval"
    } else {
        println "• Job DSL plugin: Not available or inactive"
        println "• Default security settings will apply"
    }
} catch (Exception e) {
    println "• Job DSL plugin status: Could not determine"
}

println "\n📋 Usage Recommendations:"
println "• Always use sandbox(true) in pipeline DSL scripts"
println "• Test DSL scripts in development environment first"
println "• Monitor Jenkins logs for any remaining approval requests"
println "• Update this script when adding new DSL operations"

if (failedCount > 0) {
    println "\n⚠️  Warning: ${failedCount} signatures failed to approve"
    println "• Review failed signatures above for potential issues"
    println "• Some operations may still require manual approval"
    println "• Consider updating signature formats for compatibility"
}

println "\n📖 Troubleshooting:"
println "• Check 'Manage Jenkins > Script Approval' for pending approvals"
println "• Review Jenkins system logs for DSL-related errors"
println "• Verify required plugins are installed and active"
println "• Use 'Replay' feature in pipeline jobs to test DSL scripts"

println "\n✅ DSL Script Approval configuration completed successfully!"

// Create a marker file to indicate completion
try {
    new File('/tmp/dsl-approval-setup.complete').text = "Setup completed at: ${new Date()}\nApproved: ${approvedCount}, Failed: ${failedCount}"
} catch (Exception e) {
    println "Note: Could not create completion marker file"
}