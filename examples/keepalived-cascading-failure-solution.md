# Keepalived Cascading Failure Solution

## Problem Overview

**Issue**: Single Jenkins container failure triggers full VIP failover affecting all teams, causing 2-5 minutes of downtime for healthy teams.

**Root Causes**:
1. Binary health check (UP/DOWN only)
2. Wrong check target (HAProxy process instead of backend health)
3. No threshold logic
4. No granularity between HAProxy vs backend failures

## Solution: Intelligent Backend Health Monitoring

### Architecture

The solution implements percentage-based backend health threshold logic that prevents cascading failures:

```
┌─────────────────────────────────────────────────────────────┐
│                    Keepalived VIP (Active)                   │
│                      192.168.1.100                           │
└───────────────────────┬─────────────────────────────────────┘
                        │
           ┌────────────┴─────────────┐
           │                          │
┌──────────▼──────────┐      ┌────────▼──────────┐
│  VM1 (Master)       │      │  VM2 (Backup)     │
│  Priority: 110      │      │  Priority: 100    │
│                     │      │                   │
│  HAProxy            │      │  HAProxy          │
│  ├─ devops (UP)     │      │  ├─ devops (UP)   │
│  ├─ ma (UP)         │      │  ├─ ma (UP)       │
│  ├─ ba (DOWN)       │      │  ├─ ba (UP)       │
│  └─ tw (UP)         │      │  └─ tw (UP)       │
│                     │      │                   │
│  Health: 75%        │      │  Health: 100%     │
│  Healthy teams: 3/4 │      │  Healthy teams: 4/4│
│                     │      │                   │
│  ✅ NO FAILOVER     │      │  ⏳ STANDBY       │
│  (Threshold: 50%)   │      │  (Waiting)        │
│  (Quorum: 2 teams)  │      │                   │
└─────────────────────┘      └───────────────────┘
```

**Result**: BA team failure does NOT trigger VIP failover because:
- Backend health = 75% (above 50% threshold)
- Healthy teams = 3 (above quorum of 2)
- Only BA team affected, other teams continue operating normally

### Implementation Components

#### 1. Intelligent Health Check Script

File: `ansible/roles/high-availability-v2/templates/keepalived-haproxy-check.sh.j2`

**Key Features**:
- **Per-Team Health Tracking**: Monitors each team's backend health individually
- **Percentage-Based Threshold**: Only triggers failover if < 50% backends are UP
- **Team Quorum Logic**: Requires minimum 2 teams unhealthy before failover
- **Grace Period**: 30-second grace period prevents flapping
- **Detailed Logging**: Per-team health status logged to `/var/log/keepalived-backend-health.log`

**Health Check Logic**:
```bash
# Phase 1: Container & Process Checks (Critical - Immediate Failover)
- HAProxy container running?
- HAProxy process responsive?
- HAProxy stats endpoint accessible?

# Phase 2: Intelligent Backend Health Check (Prevents Cascading Failures)
- Query HAProxy stats CSV API
- Parse per-team backend status:
  * devops: UP(1/1) or DOWN(0/1)
  * ma: UP(1/1) or DOWN(0/1)
  * ba: UP(1/1) or DOWN(0/1)
  * tw: UP(1/1) or DOWN(0/1)
- Calculate: backend_health_percentage = (UP_backends / total_backends) * 100
- Count healthy teams (teams with at least 1 UP backend)

# Failover Decision:
IF (backend_health_percentage < 50% AND healthy_teams < 2):
    IF grace_period_elapsed > 30s:
        TRIGGER FAILOVER
    ELSE:
        WAIT (no failover yet)
ELSE:
    NO FAILOVER (healthy enough)
```

#### 2. Configuration Variables

File: `ansible/roles/high-availability-v2/defaults/main.yml`

```yaml
# Intelligent failover thresholds (prevents cascading failures)
keepalived_backend_health_threshold: 50  # Percentage of backends that must be UP
keepalived_team_quorum: 2  # Minimum healthy teams to avoid failover
keepalived_failover_grace_period: 30  # Seconds grace period
```

**Tuning Guidelines**:

| Environment | Threshold | Quorum | Grace Period | Behavior |
|-------------|-----------|---------|--------------|----------|
| 4 teams     | 50%       | 2       | 30s          | 1 team failure = NO failover |
| 4 teams     | 25%       | 1       | 30s          | Up to 2 team failures = NO failover |
| 2 teams     | 50%       | 1       | 15s          | 1 team failure = NO failover |
| 8 teams     | 50%       | 4       | 45s          | Up to 3 team failures = NO failover |

#### 3. Deployment

```bash
# Deploy intelligent health check script
ansible-playbook ansible/site.yml --tags high-availability,keepalived

# Verify keepalived is using new health check
ansible all -m command -a "systemctl status keepalived" -i ansible/inventories/production/hosts.yml

# Monitor backend health logs
tail -f /var/log/keepalived-backend-health.log

# Expected output:
# 2025-01-07 10:15:00 Overall: 3/4 (75%) | Teams: devops:UP(1/1) ma:UP(1/1) ba:DOWN(0/1) tw:UP(1/1)
# 2025-01-07 10:15:05 INFO: Backend health 75% below threshold but 3 teams healthy - NO FAILOVER (prevents cascading failure)
```

### Testing Scenarios

#### Test 1: Single Team Failure (NO Failover Expected)

```bash
# Simulate BA team Jenkins failure
docker stop jenkins-ba-blue

# Monitor keepalived logs
tail -f /var/log/keepalived-haproxy-check.log

# Expected behavior:
# - Backend health drops to 75% (3/4 backends UP)
# - Healthy teams: 3 (devops, ma, tw still UP)
# - Decision: NO FAILOVER (above threshold and quorum met)
# - Result: Only BA team affected, others continue operating

# Verify VIP remains on current master
ip addr show | grep 192.168.1.100

# Verify other teams still accessible
curl -f http://192.168.1.100/  # devops (default)
curl -f http://majenkins.192.168.1.100/  # ma team
curl -f http://twjenkins.192.168.1.100/  # tw team
curl -f http://bajenkins.192.168.1.100/  # ba team (should fail)
```

#### Test 2: Multiple Team Failures (Failover Expected)

```bash
# Simulate 3 team failures (BA, TW, MA)
docker stop jenkins-ba-blue jenkins-tw-blue jenkins-ma-blue

# Monitor keepalived logs
tail -f /var/log/keepalived-haproxy-check.log

# Expected behavior after 30s grace period:
# - Backend health drops to 25% (1/4 backends UP)
# - Healthy teams: 1 (only devops UP)
# - Decision: TRIGGER FAILOVER (below threshold AND below quorum)
# - Result: VIP moves to backup node

# Verify VIP moved to backup
ip addr show | grep 192.168.1.100  # Should be on backup node now
```

#### Test 3: HAProxy Process Failure (Immediate Failover)

```bash
# Simulate HAProxy container failure
docker stop jenkins-haproxy

# Expected behavior (IMMEDIATE):
# - Container check fails
# - Decision: IMMEDIATE FAILOVER (no grace period)
# - Result: VIP moves to backup node immediately

# Verify VIP moved
ip addr show | grep 192.168.1.100
```

### Monitoring & Alerting

#### Log Files

```bash
# Keepalived main log
/var/log/keepalived-haproxy-check.log

# Per-team backend health log
/var/log/keepalived-backend-health.log

# Keepalived service log
journalctl -u keepalived -f
```

#### Prometheus Metrics (Future Enhancement)

```prometheus
# keepalived_backend_health_percentage
# keepalived_healthy_teams_count
# keepalived_failover_triggered_total
# keepalived_grace_period_active
```

### Benefits

| Aspect | Before | After |
|--------|--------|-------|
| **Single Team Failure** | 2-5 min downtime for ALL teams | NO downtime for healthy teams |
| **Failover Frequency** | High (false positives) | Low (only critical failures) |
| **RTO for Healthy Teams** | 2-5 minutes | 0 seconds (no impact) |
| **Operational Complexity** | Manual investigation required | Automatic intelligent decision |

### Rollback Plan

If issues occur with intelligent health check:

```bash
# Revert to simple container check (emergency)
cat > /usr/local/bin/keepalived-haproxy-check.sh <<'EOF'
#!/bin/bash
if docker ps | grep -q jenkins-haproxy; then
    exit 0
else
    exit 1
fi
EOF

chmod +x /usr/local/bin/keepalived-haproxy-check.sh
systemctl restart keepalived
```

### Related Solutions

- **Workspace Retention**: See [workspace-retention-implementation.md](workspace-retention-implementation.md)
- **Blue-Green Data Sync**: See [blue-green-data-sync-guide.md](blue-green-data-sync-guide.md)
- **Multi-Team Monitoring**: See [multi-team-monitoring-dashboard.md](multi-team-monitoring-dashboard.md)
