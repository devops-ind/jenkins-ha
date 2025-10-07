# Cross-VM Individual Jenkins Master Monitoring & Failover

## Overview

Complete guide for monitoring and switching individual Jenkins masters across multiple VMs using HAProxy + Keepalived.

## Architecture: Two-Layer Monitoring

```
┌──────────────────────────────────────────────────────────────────┐
│                Layer 1: Keepalived (VIP Failover)                 │
│                Monitors: HAProxy process health                   │
│                Scope: Entire VM failover                          │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                Layer 2: HAProxy (Backend Failover)                │
│                Monitors: Individual Jenkins masters               │
│                Scope: Per-team failover                           │
└────────────────────────────┬─────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    ┌─────────┐         ┌─────────┐        ┌─────────┐
    │Team A   │         │Team B   │        │Team C   │
    │Jenkins  │         │Jenkins  │        │Jenkins  │
    │VM1:8080 │         │VM1:8081 │        │VM1:8082 │
    │VM2:8080 │         │VM2:8081 │        │VM2:8082 │
    └─────────┘         └─────────┘        └─────────┘
```

## Question: Can Keepalived Monitor Individual Jenkins Masters?

**Short Answer: NO, but HAProxy CAN!**

### What Keepalived Does

```
Keepalived:
├─ Monitors: HAProxy process (binary UP/DOWN)
├─ Decision: Move VIP to backup VM if HAProxy fails
├─ Scope: ENTIRE VM failover (all teams affected)
└─ Limitation: Cannot distinguish between team failures
```

**Keepalived Behavior**:
- Team A Jenkins fails → Keepalived does NOTHING (HAProxy still running)
- HAProxy container fails → Keepalived moves VIP (ALL teams failover)

### What HAProxy Does

```
HAProxy:
├─ Monitors: Each team's Jenkins individually
├─ Health check: GET /login every 5 seconds
├─ Decision: Route traffic to healthy backend
├─ Scope: PER-TEAM failover (isolated)
└─ Capability: Individual team monitoring and switching
```

**HAProxy Behavior**:
- Team A Jenkins fails on VM1 → HAProxy routes Team A to VM2
- Team B, C, D continue on VM1 (unaffected)

## Current vs New Configuration

### Current Configuration (Local-Only)

**Problem**: HAProxy only monitors Jenkins on the SAME VM

```
VM1 HAProxy:
└─ backend jenkins_backend_devops
    └─ server: devops-vm1:8080 (VM1 only)

VM2 HAProxy:
└─ backend jenkins_backend_devops
    └─ server: devops-vm2:8080 (VM2 only)

Result:
- HAProxy CAN detect local Jenkins failure ✓
- HAProxy CANNOT route to other VM ✗
- Returns 503 error when local Jenkins fails
```

### New Configuration (Cross-VM Active-Passive)

**Solution**: HAProxy monitors Jenkins on BOTH VMs

```
VM1 HAProxy:
└─ backend jenkins_backend_devops
    ├─ server: devops-vm1:8080 (PRIMARY)
    └─ server: devops-vm2:8080 (BACKUP)

VM2 HAProxy:
└─ backend jenkins_backend_devops
    ├─ server: devops-vm1:8080 (PRIMARY)
    └─ server: devops-vm2:8080 (BACKUP)

Result:
- HAProxy CAN detect individual Jenkins failures ✓
- HAProxy CAN route to backup VM ✓
- Automatic per-team failover ✓
```

## Three Failover Strategies

### Strategy 1: Active-Passive (RECOMMENDED)

**Configuration**:
```yaml
haproxy_backend_failover_strategy: "active-passive"
```

**Behavior**:
```
backend jenkins_backend_devops
    # VM1 is primary (handles all traffic)
    server devops-vm1 10.0.0.10:8080 check inter 5s fall 3 rise 2

    # VM2 is backup (only used if VM1 fails)
    server devops-vm2 10.0.0.11:8080 check inter 5s fall 3 rise 2 backup
```

**Characteristics**:
- ✅ Simple and predictable
- ✅ Clear primary/backup designation
- ✅ Minimal data sync requirements
- ✅ Better resource utilization
- ✅ Ideal for stateful applications like Jenkins

**Traffic Flow**:
```
Normal Operation:
All traffic → VM1 (100%)

Team A fails on VM1:
Team A → VM2 (100%)
Teams B, C, D → VM1 (100%)

VM1 completely fails:
All teams → VM2 (100%)
```

### Strategy 2: Active-Active (Load Balancing)

**Configuration**:
```yaml
haproxy_backend_failover_strategy: "active-active"
```

**Behavior**:
```
backend jenkins_backend_devops
    # Both VMs active, traffic distributed
    server devops-vm1 10.0.0.10:8080 check inter 5s fall 3 rise 2 weight 100
    server devops-vm2 10.0.0.11:8080 check inter 5s fall 3 rise 2 weight 100
```

**Characteristics**:
- ✅ True load balancing across VMs
- ✅ Better resource utilization (both VMs active)
- ⚠️ Requires data sync (GlusterFS handles this)
- ⚠️ Session affinity considerations
- ⚠️ More complex troubleshooting

**Traffic Flow**:
```
Normal Operation:
All traffic → VM1 (50%) + VM2 (50%)

Team A fails on VM1:
Team A → VM2 (100%)
Teams B, C, D → VM1 (50%) + VM2 (50%)
```

### Strategy 3: Local-Only (Current Behavior)

**Configuration**:
```yaml
haproxy_backend_failover_strategy: "local-only"
```

**Behavior**:
```
VM1 HAProxy:
backend jenkins_backend_devops
    server devops-vm1 127.0.0.1:8080 check  # Only local Jenkins

VM2 HAProxy:
backend jenkins_backend_devops
    server devops-vm2 127.0.0.1:8080 check  # Only local Jenkins
```

**Characteristics**:
- ✅ Simple configuration
- ❌ No cross-VM failover
- ❌ Returns 503 on local failure
- ❌ Not recommended for HA

## Complete Example: 4 Teams with Active-Passive

### Inventory Configuration

```yaml
# ansible/inventories/production/hosts.yml
all:
  children:
    jenkins_masters:
      hosts:
        jenkins-vm1:
          ansible_host: 10.0.0.10
        jenkins-vm2:
          ansible_host: 10.0.0.11
```

### HAProxy Configuration Generated

```haproxy
# Backend for DevOps Team
backend jenkins_backend_devops
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200

    # Active-Passive: jenkins-vm1 is PRIMARY
    server devops-jenkins-vm1 10.0.0.10:8080 check inter 5s fall 3 rise 2
    # Active-Passive: jenkins-vm2 is BACKUP
    server devops-jenkins-vm2 10.0.0.11:8080 check inter 5s fall 3 rise 2 backup

# Backend for MA Team
backend jenkins_backend_ma
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200

    server ma-jenkins-vm1 10.0.0.10:8081 check inter 5s fall 3 rise 2
    server ma-jenkins-vm2 10.0.0.11:8081 check inter 5s fall 3 rise 2 backup

# Backend for BA Team
backend jenkins_backend_ba
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200

    server ba-jenkins-vm1 10.0.0.10:8082 check inter 5s fall 3 rise 2
    server ba-jenkins-vm2 10.0.0.11:8082 check inter 5s fall 3 rise 2 backup

# Backend for TW Team
backend jenkins_backend_tw
    balance roundrobin
    option httpchk GET /login
    http-check expect status 200

    server tw-jenkins-vm1 10.0.0.10:8083 check inter 5s fall 3 rise 2
    server tw-jenkins-vm2 10.0.0.11:8083 check inter 5s fall 3 rise 2 backup
```

## Failure Scenarios Explained

### Scenario 1: Single Team Jenkins Fails (Team BA)

**Initial State**:
```
VM1 (Primary):
├─ HAProxy ✓
├─ DevOps Jenkins ✓ (8080)
├─ MA Jenkins ✓ (8081)
├─ BA Jenkins ✗ (8082) ← FAILED
└─ TW Jenkins ✓ (8083)

VM2 (Backup):
├─ HAProxy ✓
├─ DevOps Jenkins ✓ (8080)
├─ MA Jenkins ✓ (8081)
├─ BA Jenkins ✓ (8082) ← Healthy backup
└─ TW Jenkins ✓ (8083)
```

**What Happens**:

1. **HAProxy Health Checks** (every 5 seconds):
   ```
   T+0s:  BA Jenkins VM1 health check fails (HTTP error)
   T+5s:  BA Jenkins VM1 health check fails (2nd consecutive)
   T+10s: BA Jenkins VM1 health check fails (3rd consecutive)
   T+15s: HAProxy marks ba-jenkins-vm1 as DOWN
   ```

2. **HAProxy Backend Decision**:
   ```
   backend jenkins_backend_ba:
   ├─ ba-jenkins-vm1: DOWN (removed from pool)
   └─ ba-jenkins-vm2: UP (backup activated)

   Action: Route ALL Team BA traffic to VM2
   ```

3. **Other Teams Unaffected**:
   ```
   DevOps, MA, TW continue on VM1 (primary)
   No interruption, no downtime
   ```

4. **Keepalived Decision**:
   ```
   Backend health: 3/4 backends UP (75%)
   Healthy teams: 3 (DevOps, MA, TW)
   Decision: NO VIP FAILOVER
   Reason: Threshold (50%) not reached, quorum (2) satisfied
   ```

**Result**:
- ✅ Only Team BA affected (switches to VM2)
- ✅ Other teams continue on VM1
- ✅ Failover time: ~15 seconds (3 health checks)
- ✅ No VIP movement, no cascading failure

### Scenario 2: HAProxy Fails on VM1

**Initial State**:
```
VM1 (Primary):
├─ HAProxy ✗ ← CRASHED
└─ All Jenkins ✓ (Running but unreachable)

VM2 (Backup):
├─ HAProxy ✓
└─ All Jenkins ✓
```

**What Happens**:

1. **Keepalived Health Check**:
   ```
   T+0s:  HAProxy container check fails
   T+3s:  HAProxy container check fails (2nd)
   T+6s:  HAProxy container check fails (3rd)
   T+9s:  Keepalived triggers VIP failover
   ```

2. **VIP Movement**:
   ```
   VIP 192.168.1.100 moves from VM1 to VM2
   All DNS/traffic now points to VM2
   ```

3. **HAProxy on VM2**:
   ```
   All teams route to their backends on VM2:
   ├─ DevOps → devops-jenkins-vm2:8080
   ├─ MA → ma-jenkins-vm2:8081
   ├─ BA → ba-jenkins-vm2:8082
   └─ TW → tw-jenkins-vm2:8083
   ```

**Result**:
- ✅ All teams failover to VM2
- ✅ Failover time: ~10-15 seconds
- ✅ This is CORRECT behavior (infrastructure failure)

### Scenario 3: Multiple Teams Fail (BA + TW)

**Initial State**:
```
VM1 (Primary):
├─ HAProxy ✓
├─ DevOps Jenkins ✓
├─ MA Jenkins ✓
├─ BA Jenkins ✗ ← FAILED
└─ TW Jenkins ✗ ← FAILED

VM2 (Backup):
├─ All Jenkins ✓
```

**What Happens**:

1. **HAProxy Per-Team Failover**:
   ```
   T+15s: BA Jenkins fails → routes to VM2
   T+20s: TW Jenkins fails → routes to VM2
   ```

2. **Traffic Distribution**:
   ```
   DevOps → VM1 (primary)
   MA → VM1 (primary)
   BA → VM2 (backup activated)
   TW → VM2 (backup activated)
   ```

3. **Keepalived Decision**:
   ```
   Backend health: 2/4 backends UP (50%)
   Healthy teams: 2 (DevOps, MA)
   Decision: NO VIP FAILOVER (exactly at threshold)
   Reason: Quorum (2) still satisfied
   ```

**Result**:
- ✅ BA and TW failover to VM2
- ✅ DevOps and MA continue on VM1
- ✅ No full VIP failover
- ✅ Selective per-team failover working correctly

## Deployment

### Step 1: Configure Failover Strategy

```yaml
# ansible/roles/high-availability-v2/defaults/main.yml
haproxy_backend_failover_strategy: "active-passive"  # or "active-active", "local-only"
```

### Step 2: Deploy HAProxy Configuration

```bash
# Deploy to both VMs
ansible-playbook ansible/site.yml --tags high-availability,haproxy

# Verify configuration
ansible jenkins_masters -m command -a "docker exec jenkins-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg"
```

### Step 3: Verify Cross-VM Backends

```bash
# Check HAProxy stats page
curl -u admin:admin123 http://localhost:8404/stats

# Or access via browser:
# http://192.168.1.100:8404/stats
```

### Step 4: Test Individual Failover

```bash
# Test script
cat > test-individual-failover.sh <<'EOF'
#!/bin/bash
set -e

echo "=== Testing Individual Team Failover ==="
echo ""

# Step 1: Check all teams healthy
echo "Step 1: Verifying all teams healthy..."
for team in devops ma ba tw; do
    if curl -f -s http://192.168.1.100/${team}jenkins.example.com/login > /dev/null; then
        echo "✓ $team: Healthy"
    else
        echo "✗ $team: Unhealthy"
    fi
done
echo ""

# Step 2: Stop BA team Jenkins on VM1
echo "Step 2: Stopping BA team Jenkins on VM1..."
ssh jenkins-vm1 "docker stop jenkins-ba-blue"
sleep 20  # Wait for health checks to detect failure

# Step 3: Verify BA failed over to VM2
echo "Step 3: Verifying BA failover to VM2..."
if curl -f -s http://192.168.1.100/bajenkins.example.com/login > /dev/null; then
    echo "✓ BA team: Accessible (failed over to VM2)"
else
    echo "✗ BA team: Still unavailable"
    exit 1
fi

# Step 4: Verify other teams still on VM1
echo "Step 4: Verifying other teams still on VM1..."
for team in devops ma tw; do
    if curl -f -s http://192.168.1.100/${team}jenkins.example.com/login > /dev/null; then
        echo "✓ $team: Still healthy on VM1"
    else
        echo "✗ $team: Affected by BA failure (SHOULD NOT HAPPEN)"
        exit 1
    fi
done
echo ""

# Step 5: Check HAProxy backend status
echo "Step 5: HAProxy backend status:"
curl -s -u admin:admin123 http://192.168.1.100:8404/stats | grep jenkins_backend_ba

# Step 6: Verify VIP did not move
echo "Step 6: Verifying VIP remained on VM1..."
if ssh jenkins-vm1 "ip addr show | grep 192.168.1.100" > /dev/null; then
    echo "✓ VIP still on VM1 (NO cascading failure)"
else
    echo "✗ VIP moved to VM2 (cascading failure occurred)"
    exit 1
fi

echo ""
echo "=== Test PASSED: Individual failover working correctly ==="
EOF

chmod +x test-individual-failover.sh
./test-individual-failover.sh
```

## Monitoring

### HAProxy Stats Dashboard

Access at: `http://192.168.1.100:8404/stats`

**Key Metrics to Monitor**:
- Backend status (UP/DOWN/backup)
- Session count per backend
- Queue length
- Response time
- Health check failures

### Log Monitoring

```bash
# Keepalived backend health log
tail -f /var/log/keepalived-backend-health.log

# Expected output:
# Overall: 3/4 (75%) | Teams: devops:UP(1/1) ma:UP(1/1) ba:DOWN(0/1) tw:UP(1/1)

# HAProxy logs
docker logs -f jenkins-haproxy --tail 100

# Individual team failover events
grep "jenkins_backend_ba" /var/log/haproxy.log
```

## Comparison Matrix

| Feature | Local-Only | Active-Passive | Active-Active |
|---------|-----------|----------------|---------------|
| **Individual monitoring** | ✓ | ✓ | ✓ |
| **Cross-VM failover** | ✗ | ✓ | ✓ |
| **Per-team failover** | ✗ | ✓ | ✓ |
| **Resource efficiency** | ✓✓ | ✓✓ | ✓ |
| **Configuration complexity** | Low | Medium | Medium |
| **Data sync required** | No | Optional | Required |
| **Predictable behavior** | ✓✓ | ✓✓ | ✓ |
| **Recommended for HA** | ✗ | ✓✓ | ✓ |

## Best Practices

1. **Use Active-Passive for Stateful Apps**: Jenkins state makes active-passive ideal
2. **Monitor Both Layers**: Track both HAProxy backend health and Keepalived decisions
3. **Test Failover Regularly**: Automate failover testing for each team
4. **Configure Proper Health Checks**: Ensure `/login` endpoint is reliable
5. **Set Appropriate Timeouts**: Balance between quick failover and false positives
6. **Enable GlusterFS**: Required for seamless data access across VMs
7. **Log Analysis**: Review logs to understand failover patterns

## Troubleshooting

### Issue: Team Shows as DOWN but Jenkins is Running

**Cause**: Health check failing

**Solution**:
```bash
# Check health check endpoint
curl -v http://vm1:8080/login

# Check HAProxy backend config
docker exec jenkins-haproxy cat /usr/local/etc/haproxy/haproxy.cfg | grep -A 5 "backend jenkins_backend_devops"

# Check health check logs
docker exec jenkins-haproxy cat /var/log/haproxy.log | grep health_check
```

### Issue: Backup Not Activating When Primary Fails

**Cause**: Both backends marked as DOWN

**Solution**:
```bash
# Verify both Jenkins are accessible
curl -f http://vm1:8080/login
curl -f http://vm2:8080/login

# Check HAProxy can reach both
docker exec jenkins-haproxy curl -f http://vm1:8080/login
docker exec jenkins-haproxy curl -f http://vm2:8080/login

# Verify network connectivity
ansible jenkins_masters -m ping
```

### Issue: All Traffic Going to Backup Instead of Primary

**Cause**: Primary marked as DOWN incorrectly

**Solution**:
```bash
# Check HAProxy stats
curl -u admin:admin123 http://localhost:8404/stats | grep jenkins_backend

# Force backend UP
echo "set server jenkins_backend_devops/devops-vm1 state ready" | \
  socat stdio /run/haproxy/admin.sock

# Restart HAProxy if needed
docker restart jenkins-haproxy
```

## Related Documentation

- **Intelligent Keepalived**: [keepalived-cascading-failure-solution.md](keepalived-cascading-failure-solution.md)
- **GlusterFS Setup**: [glusterfs-implementation-guide.md](glusterfs-implementation-guide.md)
- **Blue-Green Deployment**: [blue-green-data-sync-guide.md](blue-green-data-sync-guide.md)
