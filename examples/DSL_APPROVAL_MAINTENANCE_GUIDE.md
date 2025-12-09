# Jenkins DSL Script Approval - Maintenance Guide

## Overview

This guide provides comprehensive information for maintaining and troubleshooting the Jenkins DSL Script Approval system in the Jenkins HA infrastructure. The system pre-approves safe method signatures to reduce manual intervention while maintaining security.

## Architecture Components

### 1. DSL Approval Script
**Location:** `ansible/roles/jenkins-master-v2/files/init-scripts/setup-dsl-approval.groovy`

**Purpose:** Automatically approves safe method signatures during Jenkins initialization to enable DSL scripts to run without manual approval.

**Key Features:**
- **200+ Pre-approved Signatures** covering common DSL operations
- **Enhanced Error Handling** with detailed diagnostics
- **Plugin Compatibility Checks** for Job DSL plugin availability
- **Comprehensive Logging** for troubleshooting
- **Security-focused** - only safe operations are approved

### 2. Testing Framework
**Files:**
- `jenkins-dsl/test-approval-effectiveness.groovy` - Validates approval effectiveness
- `scripts/validate-dsl-signatures.sh` - Analyzes DSL files for missing signatures

### 3. DSL Security Configuration
- **Sandbox Mode:** Enabled by default for all DSL scripts
- **Script Security:** Configured to allow approved operations while blocking dangerous ones
- **Audit Logging:** Tracks all approval activities and failures

## Approved Method Categories

### Core Java Operations
```groovy
// String manipulation
"method java.lang.String trim"
"method java.lang.String toLowerCase"
"method java.lang.String replace java.lang.CharSequence java.lang.CharSequence"

// Collections
"method java.util.List add java.lang.Object"
"method java.util.Map get java.lang.Object"
"method java.util.Collection size"

// Date/Time
"method java.util.Date getTime"
"new java.text.SimpleDateFormat java.lang.String"
```

### Jenkins API Operations
```groovy
// Jenkins instance access
"staticMethod jenkins.model.Jenkins getInstance"
"method jenkins.model.Jenkins getRootUrl"
"method jenkins.model.Jenkins getAllItems"

// Item operations
"method hudson.model.Item getName"
"method hudson.model.Item getFullName"
"method hudson.model.ItemGroup getItem java.lang.String"
```

### DSL-Specific Operations
```groovy
// Job creation
"method javaposse.jobdsl.dsl.DslFactory job java.lang.String"
"method javaposse.jobdsl.dsl.DslFactory pipelineJob java.lang.String"
"method javaposse.jobdsl.dsl.DslFactory folder java.lang.String"

// Views and organization
"method javaposse.jobdsl.dsl.DslFactory listView java.lang.String"
"method javaposse.jobdsl.dsl.DslFactory matrixJob java.lang.String"
```

### Git and SCM Operations
```groovy
// Git operations
"method hudson.plugins.git.GitSCM getBranches"
"method hudson.plugins.git.UserRemoteConfig getUrl"
"method hudson.plugins.git.UserRemoteConfig getCredentialsId"
```

### Build and Pipeline Operations
```groovy
// Build environment
"field hudson.model.Run BUILD_NUMBER"
"field hudson.model.Run BUILD_URL"
"method hudson.model.Run getWorkspace"

// Pipeline scripts
"method org.jenkinsci.plugins.workflow.cps.CpsScript writeJSON"
"method org.jenkinsci.plugins.workflow.cps.CpsScript readJSON"
```

## Maintenance Procedures

### 1. Regular Testing

**Monthly Testing:**
```bash
# Run the effectiveness test in Jenkins DSL job
# Navigate to Jenkins > New Item > Pipeline
# Paste the content of test-approval-effectiveness.groovy
# Run and review results
```

**Automated Validation:**
```bash
# Run signature analysis
cd /path/to/jenkins-ha
./scripts/validate-dsl-signatures.sh

# Review output for missing signatures
# Update approval script as needed
```

### 2. Adding New Signatures

**When to Add:**
- New DSL patterns fail with approval requests
- Jenkins/plugin upgrades introduce new APIs
- New DSL files require additional operations

**How to Add:**
1. **Identify Required Signature:**
   ```bash
   # Check Jenkins logs or Script Approval page
   # Format: "method package.Class methodName parameter.Type"
   ```

2. **Validate Safety:**
   - Ensure the method doesn't compromise security
   - Check if it accesses sensitive data or system functions
   - Verify it's used for legitimate DSL operations

3. **Add to Approval Script:**
   ```groovy
   // Add to appropriate category in approvedSignatures list
   "method com.example.Class newMethod java.lang.String",
   ```

4. **Test Addition:**
   - Deploy updated script
   - Test the failing DSL operation
   - Verify no new approval requests

### 3. Plugin Compatibility

**Job DSL Plugin Updates:**
```bash
# Check plugin compatibility after updates
# Verify GlobalJobDslSecurityConfiguration access
# Update class references if needed
```

**Common Plugin Issues:**
- **Plugin Class Changes:** Update class references in approval script
- **API Deprecations:** Replace deprecated method signatures
- **Security Policy Changes:** Adjust approval logic accordingly

### 4. Troubleshooting Common Issues

#### Issue: DSL Scripts Still Require Approval
**Symptoms:**
- Manual approval requests appear
- DSL jobs fail with security errors
- "Script not yet approved" messages

**Solutions:**
1. **Check Approval Script Execution:**
   ```bash
   # Check Jenkins startup logs
   grep -i "dsl.*approval" /var/log/jenkins/jenkins.log
   ```

2. **Verify Missing Signatures:**
   ```bash
   # Run signature validation
   ./scripts/validate-dsl-signatures.sh
   ```

3. **Manual Approval Check:**
   - Navigate to "Manage Jenkins > Script Approval"
   - Review pending approvals
   - Add missing signatures to approval script

#### Issue: Approval Script Fails During Startup
**Symptoms:**
- Script approval setup errors in logs
- Job DSL security not configured
- High approval script failure count

**Solutions:**
1. **Check Plugin Availability:**
   ```groovy
   // Add to init script for debugging
   def jobDslPlugin = Jenkins.instance.getPluginManager().getPlugin('job-dsl')
   println "Job DSL Plugin: ${jobDslPlugin?.isActive()} (${jobDslPlugin?.getVersion()})"
   ```

2. **Verify Script Security Service:**
   ```groovy
   // Check if script approval service is available
   def scriptApproval = ScriptApproval.get()
   println "Script Approval Service: ${scriptApproval != null}"
   ```

3. **Review Error Messages:**
   - Check init script output in Jenkins logs
   - Look for class not found or permission errors
   - Update script for compatibility

#### Issue: High Security Risk Warnings
**Symptoms:**
- Security scanners flag approved signatures
- Audit findings about excessive permissions
- Security policy violations

**Solutions:**
1. **Review Approved Signatures:**
   ```bash
   # Analyze current approvals
   grep "method.*" setup-dsl-approval.groovy | sort
   ```

2. **Remove Risky Signatures:**
   - Remove signatures that access file system unsafely
   - Remove system property access beyond safe ones
   - Limit reflection and dynamic class loading

3. **Implement Principle of Least Privilege:**
   - Only approve signatures actually used
   - Regular cleanup of unused approvals
   - Document justification for each signature

### 5. Security Best Practices

#### Safe Signature Categories
✅ **Always Safe:**
- String manipulation methods
- Collection operations (read-only)
- Date/time operations
- Basic mathematical operations
- Jenkins item metadata access

✅ **Generally Safe:**
- Jenkins API read operations
- SCM metadata access
- Build information access
- DSL factory methods

⚠️ **Requires Careful Review:**
- File system access
- System property access
- Credential access (even read-only)
- Network operations
- Process execution

❌ **Never Approve:**
- System.exit() or Runtime.halt()
- Process execution methods
- File write operations outside workspace
- Network socket operations
- Reflection methods for class loading
- Credential modification operations

#### Signature Validation Checklist
Before approving any new signature:

1. **Purpose Justification:**
   - [ ] Signature is required for legitimate DSL operation
   - [ ] No safer alternative exists
   - [ ] Usage is documented and understood

2. **Security Assessment:**
   - [ ] Method doesn't access sensitive system resources
   - [ ] Method doesn't modify security settings
   - [ ] Method doesn't enable privilege escalation

3. **Testing Validation:**
   - [ ] Signature tested in development environment
   - [ ] DSL operation works as expected
   - [ ] No unintended side effects observed

4. **Documentation:**
   - [ ] Signature purpose documented in script
   - [ ] Review date and reviewer recorded
   - [ ] Removal criteria established

## Monitoring and Alerting

### 1. Key Metrics to Monitor

**Approval Effectiveness:**
```bash
# Track approval success rate
# Monitor manual approval requests
# Measure DSL job failure rates
```

**Security Indicators:**
```bash
# Monitor failed signature approvals
# Track security-related errors
# Review audit logs regularly
```

### 2. Automated Monitoring

**Script Integration:**
```yaml
# Add to monitoring playbook
- name: Check DSL approval effectiveness
  shell: |
    if [ -f /tmp/dsl-approval-setup.complete ]; then
      cat /tmp/dsl-approval-setup.complete
    else
      echo "DSL approval setup not completed"
    fi
  register: dsl_status

- name: Validate DSL signatures
  shell: ./scripts/validate-dsl-signatures.sh
  register: dsl_validation
  changed_when: false
```

**Alerting Rules:**
- Alert on approval script failures
- Monitor excessive manual approvals
- Track DSL job security errors

### 3. Reporting

**Weekly Reports:**
- DSL approval effectiveness metrics
- New signature requirements
- Security review findings
- Plugin compatibility status

**Monthly Reviews:**
- Signature cleanup opportunities
- Security policy compliance
- Performance impact analysis
- Documentation updates

## Version Compatibility

### Jenkins Core Versions
- **Jenkins 2.400+:** Full compatibility
- **Jenkins 2.300-2.399:** Compatible with minor limitations
- **Jenkins < 2.300:** May require signature adjustments

### Job DSL Plugin Versions
- **1.80+:** Fully supported with all features
- **1.70-1.79:** Compatible with basic functionality
- **< 1.70:** May require manual configuration adjustments

### Plugin Dependencies
- **Script Security Plugin:** Required for approval functionality
- **Credentials Plugin:** Required for credential-related signatures
- **Git Plugin:** Required for SCM-related signatures
- **Pipeline Plugin:** Required for pipeline-related signatures

## Migration and Upgrades

### Upgrading Jenkins
1. **Pre-upgrade:**
   - Backup current approval configuration
   - Document custom signatures
   - Test DSL operations

2. **Post-upgrade:**
   - Verify approval script execution
   - Test DSL effectiveness
   - Update signatures if needed

### Upgrading Job DSL Plugin
1. **Review Release Notes:**
   - Check for API changes
   - Note deprecated methods
   - Identify new features

2. **Update Signatures:**
   - Remove deprecated signatures
   - Add new method signatures
   - Test compatibility

3. **Validate Configuration:**
   - Run effectiveness tests
   - Check security settings
   - Verify documentation

## Troubleshooting Tools

### 1. Diagnostic Scripts
```bash
# Check approval script status
./scripts/validate-dsl-signatures.sh

# Test DSL effectiveness
# Run test-approval-effectiveness.groovy in Jenkins

# Check Jenkins logs
tail -f /var/log/jenkins/jenkins.log | grep -i "dsl\|approval"
```

### 2. Manual Verification
```groovy
// Check current approvals in Jenkins console
def scriptApproval = org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval.get()
println "Total approved signatures: ${scriptApproval.getApprovedSignatures().size()}"
scriptApproval.getApprovedSignatures().each { sig ->
    if (sig.contains("jenkins") || sig.contains("hudson")) {
        println sig
    }
}
```

### 3. Emergency Procedures

**Complete Approval Reset:**
```groovy
// Use only in emergency - removes all approvals
def scriptApproval = org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval.get()
scriptApproval.getApprovedSignatures().clear()
scriptApproval.save()
```

**Manual Signature Addition:**
```groovy
// Add single signature manually
def scriptApproval = org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval.get()
scriptApproval.approveSignature("method java.lang.String newMethod")
scriptApproval.save()
```

## Best Practices Summary

### 1. Development
- Always test DSL scripts in development environment first
- Use `sandbox(true)` in all pipeline DSL definitions
- Review and approve signatures through code review process
- Document the purpose of custom signatures

### 2. Production
- Monitor approval requests and update scripts accordingly
- Implement automated testing for DSL effectiveness
- Regular security reviews of approved signatures
- Maintain documentation and change logs

### 3. Security
- Follow principle of least privilege for approvals
- Regular audit of approved signatures
- Remove unused or risky signatures
- Keep approval scripts under version control

### 4. Maintenance
- Monthly effectiveness testing
- Quarterly security reviews
- Update signatures after plugin upgrades
- Keep compatibility documentation current

This maintenance guide provides the foundation for reliable, secure, and effective DSL script approval management in your Jenkins HA infrastructure.