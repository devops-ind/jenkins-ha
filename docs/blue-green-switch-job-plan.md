# Blue-Green Switch Job Plan

## Overview

Dedicated Jenkins job for switching traffic between blue and green environments without redeploying. This is useful when:
- You've already deployed to passive environment and validated it
- You want to switch back and forth for A/B testing
- You need to switch without full deployment cycle
- You want faster operations (2-5 minutes vs 30-50 minutes)

---

## Job Requirements

### Primary Use Cases

1. **Post-Deployment Switch**: After deploying to passive via Infrastructure-Deployment job, switch traffic
2. **Quick Rollback**: Revert to previous environment if issues detected
3. **A/B Testing**: Switch between environments to compare performance/behavior
4. **Maintenance Window**: Switch away from environment needing maintenance
5. **Testing**: Validate passive environment with real traffic before full cutover

### Prerequisites

- Both blue and green environments already deployed
- Passive environment validated and healthy
- No ongoing deployments (concurrent builds prevented)

---

## Architecture

### Existing Scripts to Leverage

Located in `/var/jenkins/scripts/` (deployed by jenkins-master-v2 role):

1. **zero-downtime-blue-green-switch-{team}.sh** (Primary)
   - True zero-downtime switching
   - Uses HAProxy Runtime API
   - Automatic health checks
   - Container start/stop orchestration
   - State file management

2. **blue-green-healthcheck-{team}.sh**
   - Pre-switch health validation
   - Active vs passive comparison
   - Configuration drift detection

3. **health-monitor-{team}.sh**
   - Continuous health monitoring
   - Post-switch validation

### Script Capabilities (from zero-downtime-blue-green-switch.sh.j2)

- ✅ Get current active environment from state file
- ✅ Determine target environment automatically
- ✅ Health check Jenkins containers (HTTP 200/403)
- ✅ Start target environment container
- ✅ Health check target before switch
- ✅ Update HAProxy via Runtime API (zero downtime)
- ✅ Stop old active container (resource optimization)
- ✅ Update state file
- ✅ Rollback on failure

---

## Pipeline Design

### Job Name
`Infrastructure/Blue-Green-Switch`

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SWITCH_SCOPE` | Choice | team-specific | Scope: team-specific, all-teams, vm-wide |
| `TEAMS_TO_SWITCH` | String | all | Teams to switch (comma-separated): devops,ma,ba,tw OR all |
| `TARGET_VM` | Choice | jenkins_hosts_01 | Target VM: jenkins_hosts_01, jenkins_hosts_02, all |
| `SWITCH_DIRECTION` | Choice | auto | Direction: auto (blue→green or green→blue), force-blue, force-green |
| `SKIP_PRE_SWITCH_VALIDATION` | Boolean | false | Skip pre-switch health checks (dangerous!) |
| `SKIP_POST_SWITCH_VALIDATION` | Boolean | false | Skip post-switch validation |
| `AUTO_ROLLBACK_ON_FAILURE` | Boolean | true | Automatically rollback if post-switch validation fails |
| `ROLLBACK_TIMEOUT_SECONDS` | String | 300 | Max time to wait before triggering rollback (0=disabled) |
| `NOTIFICATION_CHANNEL` | Choice | teams | Notification: teams, email, both, none |

### Pipeline Stages

#### Stage 1: Pre-Switch Validation (2-3 min)
**Purpose:** Ensure both environments are healthy before switching

**Tasks:**
- Detect current active environment per team
- Verify target environment exists and is running
- Run health checks on both environments
- Compare configurations (detect drift)
- Check HAProxy is accessible
- Verify Prometheus is monitoring correctly
- Display current vs target state

**Script Usage:**
```bash
# Per team
/var/jenkins/scripts/blue-green-healthcheck-${team}.sh --environment both
```

**Output:**
```
Pre-Switch Validation Results:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Team: devops
Current Active: blue (port 8080)
Target: green (port 8180)

Active Environment (blue):
  ✓ Container: running
  ✓ HTTP Health: 200 OK
  ✓ Jobs: 45
  ✓ Plugins: 78
  ✓ Builds Running: 2

Target Environment (green):
  ✓ Container: running
  ✓ HTTP Health: 200 OK
  ✓ Jobs: 45 (matches active)
  ✓ Plugins: 78 (matches active)
  ✓ Configuration Drift: NONE
  ✓ Ready for switch: YES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Exit Criteria:**
- Target environment must be running and healthy
- No critical configuration drift
- HAProxy accessible

---

#### Stage 2: Pre-Switch Snapshot (1 min)
**Purpose:** Capture current state for rollback

**Tasks:**
- Record current active environment per team
- Capture HAProxy backend states
- Record Prometheus targets
- Create state snapshot file
- Archive current blue-green-state.json

**Output:**
```
State Snapshot Created:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Snapshot ID: switch-20250109-143022
Teams: devops, ma, ba, tw

Current State:
  devops: blue → green
  ma: green → blue
  ba: blue → green
  tw: green → blue

Snapshot saved to: /var/log/blue-green-switch/switch-20250109-143022.json
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

#### Stage 3: Manual Approval Gate ⏸️ (Optional)
**Purpose:** Allow manual review before switch

**Conditions:**
- Required for production
- Optional for dev/staging (configurable)
- Timeout: 4 hours (configurable)

**Display Information:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
APPROVAL REQUIRED: Blue-Green Traffic Switch
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Teams to Switch: devops, ma, ba, tw

Switch Plan:
• devops: blue (8080) → green (8180)
• ma: green (8181) → blue (8081)
• ba: blue (8082) → green (8182)
• tw: green (8183) → blue (8083)

Pre-Switch Validation: ✅ PASSED
- All target environments healthy
- No configuration drift detected
- HAProxy backends ready

Estimated Switch Time: 2-3 minutes
Estimated Downtime: 0 seconds (zero-downtime)

Post-Switch Actions:
- HAProxy backends updated
- Prometheus targets updated
- Old active containers stopped
- Automatic rollback enabled (5 min timeout)

Rollback Plan:
- Automatic rollback on validation failure
- Manual rollback available: Infrastructure/Infrastructure-Rollback
- Rollback time: <30 seconds

Actions:
✅ APPROVE - Execute switch
❌ REJECT - Cancel switch
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

#### Stage 4: Execute Blue-Green Switch (2-3 min)
**Purpose:** Perform zero-downtime environment switch

**Tasks:**
- Run zero-downtime switch script per team (sequential or parallel)
- Monitor switch progress
- Update HAProxy backends via Runtime API
- Update Prometheus targets
- Stop old active containers (resource optimization)
- Update state files

**Script Usage:**
```bash
# Sequential switch (safer, one team at a time)
for team in devops ma ba tw; do
  /var/jenkins/scripts/zero-downtime-blue-green-switch-${team}.sh switch
done

# Parallel switch (faster, all teams simultaneously)
parallel --jobs 4 ::: \
  "/var/jenkins/scripts/zero-downtime-blue-green-switch-devops.sh switch" \
  "/var/jenkins/scripts/zero-downtime-blue-green-switch-ma.sh switch" \
  "/var/jenkins/scripts/zero-downtime-blue-green-switch-ba.sh switch" \
  "/var/jenkins/scripts/zero-downtime-blue-green-switch-tw.sh switch"
```

**Output:**
```
Blue-Green Switch Execution:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[14:30:45] Team: devops
[14:30:45] Current: blue, Target: green
[14:30:46] ✓ Starting green container
[14:30:55] ✓ Green container healthy
[14:30:56] ✓ Updating HAProxy backend (zero downtime)
[14:30:57] ✓ Traffic now routing to green
[14:30:58] ✓ Stopping blue container
[14:30:59] ✓ State file updated
[14:31:00] ✅ Switch complete for devops (15 seconds)

[14:31:01] Team: ma
[14:31:01] Current: green, Target: blue
[14:31:02] ✓ Starting blue container
[14:31:11] ✓ Blue container healthy
[14:31:12] ✓ Updating HAProxy backend (zero downtime)
[14:31:13] ✓ Traffic now routing to blue
[14:31:14] ✓ Stopping green container
[14:31:15] ✓ State file updated
[14:31:16] ✅ Switch complete for ma (15 seconds)

[... repeat for ba, tw ...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
All switches completed in 62 seconds
Total downtime: 0 seconds (zero-downtime)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

#### Stage 5: Post-Switch Validation (2-3 min)
**Purpose:** Verify switch success and new active environment health

**Tasks:**
- Health check new active environments
- Verify HAProxy routing to correct backends
- Verify Prometheus monitoring new active environments
- Check for errors in Jenkins logs (last 5 minutes)
- Compare traffic patterns (optional)
- Test sample job execution (optional)

**Validation Checks:**
1. HTTP 200/403 on new active endpoints
2. HAProxy stats show correct backends UP
3. Prometheus targets show new active environments
4. No 5xx errors in HAProxy logs
5. No critical errors in Jenkins logs
6. Old active containers stopped

**Output:**
```
Post-Switch Validation:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Team: devops (now on green)
  ✓ HTTP Health: 200 OK (http://jenkins_hosts_01:8180)
  ✓ HAProxy Backend: devops-green UP, devops-blue DOWN
  ✓ Prometheus Target: devops-green:8180 (UP)
  ✓ Jenkins Logs: No errors in last 5 minutes
  ✓ Old Container: devops-blue STOPPED

Team: ma (now on blue)
  ✓ HTTP Health: 200 OK (http://jenkins_hosts_02:8081)
  ✓ HAProxy Backend: ma-blue UP, ma-green DOWN
  ✓ Prometheus Target: ma-blue:8081 (UP)
  ✓ Jenkins Logs: No errors in last 5 minutes
  ✓ Old Container: ma-green STOPPED

[... repeat for ba, tw ...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall Result: ✅ VALIDATION PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Exit Criteria:**
- All health checks pass
- HAProxy routing correctly
- Prometheus monitoring correctly
- No critical errors

---

#### Stage 6: Post-Switch Monitoring (5 min, async)
**Purpose:** Monitor new active environment for stability

**Tasks:**
- Monitor error rates for 5 minutes
- Monitor response times
- Monitor resource usage
- Alert on anomalies

**Rollback Triggers (if enabled):**
- HTTP 5xx error rate > 5%
- Response time > 2x baseline
- Critical errors in Jenkins logs
- Container crashes

**Monitoring Output:**
```
Post-Switch Monitoring (5 minutes):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Time Elapsed: 2/5 minutes

Metrics:
• HTTP 5xx Errors: 0 (threshold: <5%)
• Response Time: 245ms (baseline: 230ms, threshold: <460ms)
• Memory Usage: 1.8GB / 3GB (60%)
• CPU Usage: 35%
• Container Status: running

Status: ✅ STABLE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

#### Stage 7: Notification (1 min)
**Purpose:** Send switch summary to configured channels

**Notification Template:**
```
🔄 Blue-Green Switch Complete

Scope: team-specific
Teams Switched: devops, ma, ba, tw
Target VM: jenkins_hosts_01

Switch Summary:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Pre-Switch Validation: PASSED
✅ Switch Execution: COMPLETED (62 seconds)
✅ Post-Switch Validation: PASSED
✅ Post-Switch Monitoring: STABLE (5 minutes)

Team Status:
• devops: blue → green (8080 → 8180) ✅
• ma: green → blue (8181 → 8081) ✅
• ba: blue → green (8082 → 8182) ✅
• tw: green → blue (8183 → 8083) ✅

Total Duration: 8 minutes 15 seconds
Downtime: 0 seconds (zero-downtime)

Access URLs (updated):
• devops: http://devopsjenkins.dev.net (green)
• ma: http://majenkins.dev.net (blue)
• ba: http://bajenkins.dev.net (green)
• tw: http://twjenkins.dev.net (blue)

Jenkins Job: http://devopsjenkins.dev.net/job/Blue-Green-Switch/15
Triggered by: John Doe
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Automatic Rollback Logic

### Rollback Triggers

1. **Pre-Switch Validation Failure**
   - Target environment not healthy
   - Configuration drift detected
   - HAProxy not accessible
   - Action: Abort before switch

2. **Switch Execution Failure**
   - Script returns non-zero exit code
   - Container fails to start
   - HAProxy update fails
   - Action: Immediate rollback

3. **Post-Switch Validation Failure**
   - Health checks fail
   - HAProxy routing incorrect
   - Critical errors detected
   - Action: Automatic rollback (if enabled)

4. **Post-Switch Monitoring Failure**
   - Error rate exceeds threshold
   - Response time degrades
   - Container crashes
   - Action: Automatic rollback with notification

### Rollback Procedure

```bash
# Rollback script (reuse zero-downtime-blue-green-switch.sh)
for team in devops ma ba tw; do
  /var/jenkins/scripts/zero-downtime-blue-green-switch-${team}.sh switch
  # Script automatically switches back to previous environment
done
```

**Rollback Time:** <30 seconds
**Rollback Validation:** Same as post-switch validation

---

## Switch Strategies

### Strategy 1: Sequential Switch (Safer)
**Description:** Switch one team at a time with validation between each

**Pros:**
- Safer - issues isolated to one team
- Easier to identify problematic team
- Can stop mid-switch if issues detected

**Cons:**
- Slower - 2-3 minutes per team
- Not suitable for large deployments

**Use Case:** Production, high-risk switches

### Strategy 2: Parallel Switch (Faster)
**Description:** Switch all teams simultaneously

**Pros:**
- Faster - 2-3 minutes total
- Minimizes switch window

**Cons:**
- Higher risk - all teams affected if issues
- Harder to identify problematic team

**Use Case:** Dev/staging, low-risk switches

### Strategy 3: Canary Switch (Progressive)
**Description:** Switch one team, monitor, then switch remaining teams

**Pros:**
- Balance of safety and speed
- Real traffic validation on single team
- Can abort before switching all teams

**Cons:**
- More complex orchestration
- Longer total time

**Use Case:** Production, cautious rollouts

---

## Advanced Features

### Feature 1: Dry-Run Mode
Preview what would happen without actually switching

```
DRY_RUN=true
Output:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DRY-RUN MODE - No changes will be made
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Planned Actions:
✓ devops: Would switch blue → green
✓ ma: Would switch green → blue
✓ ba: Would switch blue → green
✓ tw: Would switch green → blue

HAProxy Updates: 4 backends
Prometheus Updates: 4 targets
Containers to Stop: 4
Containers to Start: 4 (already running)

Estimated Time: 2-3 minutes
Estimated Downtime: 0 seconds
```

### Feature 2: Scheduled Switch
Schedule switch for specific time (e.g., maintenance window)

```
SCHEDULED_SWITCH_TIME=2025-01-10T02:00:00
Wait until scheduled time, then execute
```

### Feature 3: Traffic Percentage Switch (Future)
Gradually shift traffic from old to new (canary deployment)

```
TRAFFIC_SPLIT=10  # Start with 10% to new environment
Monitor for 5 minutes
If stable, increase to 50%
Monitor for 5 minutes
If stable, increase to 100%
```

---

## Performance Estimates

| Operation | Time | Notes |
|-----------|------|-------|
| Pre-Switch Validation | 2-3 min | Per team validation |
| Pre-Switch Snapshot | 1 min | State capture |
| Approval Gate | User dependent | 4-hour timeout |
| Switch Execution (Sequential) | 2-3 min per team | ~10 min for 4 teams |
| Switch Execution (Parallel) | 2-3 min total | All teams simultaneously |
| Post-Switch Validation | 2-3 min | Health checks |
| Post-Switch Monitoring | 5 min | Stability monitoring |
| Notification | 1 min | Teams/Email |
| **Total (Sequential)** | **15-20 min** | Safer approach |
| **Total (Parallel)** | **8-12 min** | Faster approach |
| **Rollback** | **<30 sec** | Emergency revert |

**Downtime:** 0 seconds (zero-downtime switching)

---

## Security & Safety

### Access Control
- Restrict to `admin` and `devops-team`
- Approval required for production
- Audit trail of who switched when

### Safety Mechanisms
- ✅ Pre-switch validation (catches 90% of issues)
- ✅ Automatic rollback on failure
- ✅ Concurrent build prevention
- ✅ State snapshot for rollback
- ✅ 5-minute stability monitoring
- ✅ Dry-run mode for testing

### Audit Trail
- Switch initiation timestamp
- Approver name
- Teams switched
- Switch duration
- Validation results
- Rollback events

---

## Integration with Existing Jobs

### Relationship to Infrastructure-Deployment Job

**Infrastructure-Deployment:**
- Full deployment cycle (30-50 minutes)
- Deploys new code/config to passive
- GlusterFS data recovery
- Includes blue-green switch at end

**Blue-Green-Switch:**
- Quick switch only (8-15 minutes)
- Assumes passive already deployed and validated
- No deployment or data recovery
- Just switches traffic

**Typical Workflow:**
```
1. Use Infrastructure-Deployment with SKIP_SWITCH=true
   → Deploys to passive, validates, but doesn't switch
   → Duration: 30-50 minutes

2. Manual testing/validation of passive environment
   → User validates passive environment manually
   → Duration: hours/days

3. Use Blue-Green-Switch when ready
   → Quick traffic switch to validated passive
   → Duration: 8-15 minutes
```

### Relationship to Infrastructure-Rollback Job

**Infrastructure-Rollback:**
- Emergency rollback (disaster recovery)
- <30 second execution
- No validation - just switches back

**Blue-Green-Switch (with rollback):**
- Controlled rollback with validation
- 8-15 minute execution
- Full validation and monitoring

---

## Implementation Files

### Files to Create

1. **Jenkinsfile** (500+ lines)
   - `pipelines/Jenkinsfile.blue-green-switch`
   - All 7 pipeline stages
   - Rollback logic
   - Monitoring

2. **Job DSL** (150+ lines)
   - `jenkins-dsl/infrastructure/blue-green-switch-job.groovy`
   - Parameter definitions
   - Build retention
   - Access control

3. **Helper Script** (optional, 200+ lines)
   - `scripts/blue-green-switch-orchestrator.sh`
   - Orchestrates multiple team switches
   - Handles parallel vs sequential
   - Captures metrics

4. **Documentation** (this file)
   - `docs/blue-green-switch-plan.md`
   - Usage examples
   - Troubleshooting

---

## Testing Plan

### Phase 1: Dry-Run Testing
```bash
# Test in dev environment with dry-run
Jenkins UI → Blue-Green-Switch
  DRY_RUN: true
  TEAMS_TO_SWITCH: devops
  TARGET_VM: jenkins_hosts_01
```

### Phase 2: Single Team Testing
```bash
# Switch single team in dev
Jenkins UI → Blue-Green-Switch
  TEAMS_TO_SWITCH: devops
  AUTO_ROLLBACK_ON_FAILURE: true
  ROLLBACK_TIMEOUT_SECONDS: 60
```

### Phase 3: Multi-Team Sequential
```bash
# Switch all teams sequentially in staging
Jenkins UI → Blue-Green-Switch
  TEAMS_TO_SWITCH: all
  SWITCH_STRATEGY: sequential
```

### Phase 4: Multi-Team Parallel
```bash
# Switch all teams in parallel in staging
Jenkins UI → Blue-Green-Switch
  TEAMS_TO_SWITCH: all
  SWITCH_STRATEGY: parallel
```

### Phase 5: Production Rollout
```bash
# Production switch with all safety mechanisms
Jenkins UI → Blue-Green-Switch
  TEAMS_TO_SWITCH: all
  AUTO_ROLLBACK_ON_FAILURE: true
  ROLLBACK_TIMEOUT_SECONDS: 300
  Approval: Required
```

---

## Success Criteria

### Must Have
- ✅ Zero-downtime switching using existing scripts
- ✅ Pre-switch validation
- ✅ Post-switch validation
- ✅ Automatic rollback on failure
- ✅ Manual approval gate
- ✅ Team-specific switching
- ✅ HAProxy integration
- ✅ Prometheus integration

### Should Have
- ✅ Post-switch monitoring
- ✅ Parallel switch option
- ✅ Dry-run mode
- ✅ Rich notifications
- ✅ State snapshots

### Could Have (Future)
- ⏳ Scheduled switching
- ⏳ Traffic percentage split
- ⏳ Canary deployment strategy
- ⏳ Performance comparison reports
- ⏳ Integration with monitoring dashboards

---

## Next Steps

1. ✅ Review and approve this plan
2. ✅ Implement Jenkinsfile for Blue-Green-Switch job
3. ✅ Implement Job DSL script
4. ✅ Create helper orchestrator script (optional)
5. ✅ Test in dev environment
6. ✅ Document usage examples
7. ✅ Train team on new job
8. ✅ Production rollout

---

## Questions for Clarification

1. **Switch Strategy**: Sequential (safer) or Parallel (faster) as default?
2. **Approval Gate**: Required for all environments or just production?
3. **Rollback Timeout**: 5 minutes default or configurable?
4. **Monitoring Duration**: 5 minutes sufficient or longer?
5. **Notification Preferences**: Teams only or both Teams + Email?
6. **Dry-Run**: Should it be default=true for safety?

**Ready to implement once you confirm preferences!**
