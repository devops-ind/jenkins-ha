# Multi-VM Blue-Green Architecture Design

**Status**: Planning & Design Phase
**Date**: December 2025
**Current State**: Single-VM multi-container implementation
**Target State**: Multi-VM infrastructure with true VM-level isolation

---

## Executive Summary

This document outlines the design considerations and options for migrating from the current single-VM, multi-container blue-green deployment to a multi-VM architecture that provides true infrastructure isolation.

### Current Architecture (Single VM)

```
┌─────────────────────────────────────────────┐
│         VM: 192.168.188.142                 │
├─────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐         │
│  │ Jenkins Blue │  │ Jenkins Green│         │
│  │  (Running)   │  │  (Stopped)   │         │
│  └──────────────┘  └──────────────┘         │
│  ┌──────────────┐  ┌──────────────┐         │
│  │   HAProxy    │  │  Monitoring  │         │
│  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────┘
```

**Characteristics:**
- All services containerized on single host
- Blue/green environments are Docker containers
- Fast switching (container start/stop)
- Shared VM resources (kernel, network, storage)
- Cost-efficient, simple networking

---

## Multi-VM Architecture Options

### Option 1: Separate VM Sets (Full Isolation)

**Architecture:**
```
BLUE ENVIRONMENT                    GREEN ENVIRONMENT
┌──────────────────────┐           ┌──────────────────────┐
│  VM-BLUE-1           │           │  VM-GREEN-1          │
│  ┌────────────────┐  │           │  ┌────────────────┐  │
│  │ Jenkins-DevOps │  │           │  │ Jenkins-DevOps │  │
│  │ Jenkins-Dev    │  │           │  │ Jenkins-Dev    │  │
│  └────────────────┘  │           │  └────────────────┘  │
└──────────────────────┘           └──────────────────────┘
          │                                    │
          └────────────────┬───────────────────┘
                           │
                    ┌──────────────┐
                    │   HAProxy    │
                    │ (VIP/Floating)│
                    └──────────────┘
                           │
                    ┌──────────────┐
                    │  Monitoring  │
                    │   Storage    │
                    └──────────────┘
```

**Benefits:**
- ✅ Complete infrastructure isolation (OS, kernel, network stack)
- ✅ Can test VM-level changes (OS upgrades, kernel patches)
- ✅ True disaster recovery capability
- ✅ Independent resource allocation
- ✅ Network-level isolation

**Challenges:**
- ❌ Higher cost (2x VMs for Jenkins)
- ❌ Network complexity (cross-VM communication)
- ❌ Storage synchronization needed
- ❌ More complex deployment
- ❌ Higher resource overhead

**Use Cases:**
- Production environments requiring DR capability
- Compliance requirements for environment isolation
- Testing infrastructure changes (kernel, OS patches)
- Large-scale deployments with dedicated resources

---

### Option 2: Hybrid - Shared Services + Separate Jenkins VMs

**Architecture:**
```
JENKINS BLUE           JENKINS GREEN          SHARED SERVICES
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│  VM-BLUE     │       │  VM-GREEN    │       │  VM-SHARED   │
│              │       │              │       │              │
│ Jenkins-     │       │ Jenkins-     │       │ ┌──────────┐ │
│  DevOps      │       │  DevOps      │       │ │ HAProxy  │ │
│ Jenkins-     │       │ Jenkins-     │       │ └──────────┘ │
│  Developer   │       │  Developer   │       │ ┌──────────┐ │
│              │       │              │       │ │Monitoring│ │
└──────────────┘       └──────────────┘       │ └──────────┘ │
                                              │ ┌──────────┐ │
                                              │ │ Storage  │ │
                                              │ │(GlusterFS│ │
                                              │ └──────────┘ │
                                              └──────────────┘
```

**Benefits:**
- ✅ Jenkins isolation only (most critical)
- ✅ Shared monitoring/storage (cost efficient)
- ✅ Simpler HAProxy configuration
- ✅ Easier to manage shared services
- ✅ Reduced VM count (3 VMs vs 8 VMs)

**Challenges:**
- ⚠️ HAProxy is single point of failure (can add HA later)
- ⚠️ Storage needs cross-VM mounting (NFS/GlusterFS)
- ⚠️ Monitoring/storage VM failure affects all environments

**Use Cases:**
- Development and staging environments
- Small to medium teams
- Cost-conscious deployments
- When Jenkins isolation is primary concern

---

### Option 3: Full Duplication (DR-Ready)

**Architecture:**
```
BLUE SITE                          GREEN SITE
┌─────────────────────────┐        ┌─────────────────────────┐
│ VM-BLUE-JENKINS         │        │ VM-GREEN-JENKINS        │
│  ├─ Jenkins (all teams) │        │  ├─ Jenkins (all teams)│
│                         │        │                         │
│ VM-BLUE-HAPROXY         │        │ VM-GREEN-HAPROXY        │
│  ├─ HAProxy             │        │  ├─ HAProxy             │
│                         │        │                         │
│ VM-BLUE-MONITOR         │        │ VM-GREEN-MONITOR        │
│  ├─ Prometheus          │        │  ├─ Prometheus          │
│  ├─ Grafana             │        │  ├─ Grafana             │
│                         │        │                         │
│ VM-BLUE-STORAGE         │        │ VM-GREEN-STORAGE        │
│  ├─ GlusterFS           │        │  ├─ GlusterFS           │
└─────────────────────────┘        └─────────────────────────┘
         │                                    │
         └──────── Floating VIP ──────────────┘
              (Keepalived/HAProxy)
```

**Benefits:**
- ✅ Complete DR capability
- ✅ Can test entire stack changes
- ✅ Maximum isolation (no shared components)
- ✅ Production-grade HA
- ✅ Geographic distribution possible

**Challenges:**
- ❌ Highest cost (8 VMs total)
- ❌ Most complex networking
- ❌ Storage replication overhead
- ❌ Complex orchestration
- ❌ Overkill for small teams

**Use Cases:**
- Mission-critical production environments
- Geographic redundancy requirements
- Compliance mandates for complete isolation
- Enterprise deployments with ample resources

---

## Design Considerations

### 1. Storage Strategy

#### Option A: Shared NFS/GlusterFS (Recommended)

```yaml
Storage VM: 192.168.188.150
├─ /shared/jenkins/devops/casc_configs
├─ /shared/jenkins/devops/jobs
├─ /shared/jenkins/developer/casc_configs
└─ /shared/jenkins/developer/jobs

Both Blue & Green VMs mount:
  - 192.168.188.150:/shared/jenkins/devops
  - 192.168.188.150:/shared/jenkins/developer
```

**Pros:**
- Centralized storage management
- No data synchronization needed
- Consistent view across environments
- Simplified backup strategy

**Cons:**
- Network dependency
- Storage VM is single point of failure
- NFS performance considerations

#### Option B: VM-Local Storage with Replication

```bash
Blue VM:  /var/jenkins/devops/
Green VM: /var/jenkins/devops/

Sync: rsync -avz blue:/var/jenkins/ green:/var/jenkins/
```

**Pros:**
- No network dependency
- Faster local I/O
- Independent failure domains

**Cons:**
- Data synchronization complexity
- Potential data inconsistency
- Replication lag
- Increased storage costs

---

### 2. HAProxy Strategy

#### Option A: External HAProxy with Floating VIP (Recommended)

```
VIP: 192.168.188.100 (Floating)
├─ HAProxy Primary:   192.168.188.110
└─ HAProxy Secondary: 192.168.188.111

Backend Configuration:
  Blue Environment:  192.168.188.142:8080
  Green Environment: 192.168.188.143:8080

Switching Mechanism:
  - Update backend weights via stats socket
  - Keepalived manages VIP failover
  - No DNS changes required
```

**Pros:**
- Fast switching (<1 second)
- HA capability with keepalived
- Centralized traffic management
- No DNS TTL delays

**Cons:**
- Additional VMs required
- Keepalived configuration complexity
- Network configuration changes

#### Option B: DNS-Based Switching

```bash
devops.jenkins.local → CNAME → jenkins-active.local

Switch Process:
  jenkins-active.local → 192.168.188.142 (blue)
  jenkins-active.local → 192.168.188.143 (green)

TTL: 60 seconds (configurable)
```

**Pros:**
- No additional infrastructure
- Simple configuration
- Works across network boundaries

**Cons:**
- DNS TTL delays (60-300 seconds)
- Client-side DNS caching issues
- Less control over traffic distribution

---

### 3. Inventory Structure

#### Current (Single VM):
```yaml
[jenkins_masters]
centos9-vm ansible_host=192.168.188.142

[load_balancers]
centos9-vm ansible_host=192.168.188.142

[monitoring]
centos9-vm ansible_host=192.168.188.142

[shared_storage]
centos9-vm ansible_host=192.168.188.142
```

#### Multi-VM Option A (Separate Blue/Green):
```yaml
[jenkins_masters_blue]
jenkins-blue-vm ansible_host=192.168.188.142
  environment=blue
  jenkins_teams=['devops', 'developer']

[jenkins_masters_green]
jenkins-green-vm ansible_host=192.168.188.143
  environment=green
  jenkins_teams=['devops', 'developer']

[load_balancers]
haproxy-primary ansible_host=192.168.188.110 priority=100
haproxy-secondary ansible_host=192.168.188.111 priority=50

[monitoring]
monitor-vm ansible_host=192.168.188.150

[shared_storage]
storage-vm ansible_host=192.168.188.150
```

#### Multi-VM Option B (Team-Based Allocation):
```yaml
[jenkins_masters:children]
jenkins_blue
jenkins_green

[jenkins_blue]
blue-devops-vm ansible_host=192.168.188.142
  jenkins_teams=['devops']
  environment=blue

blue-dev-vm ansible_host=192.168.188.144
  jenkins_teams=['developer']
  environment=blue

[jenkins_green]
green-devops-vm ansible_host=192.168.188.143
  jenkins_teams=['devops']
  environment=green

green-dev-vm ansible_host=192.168.188.145
  jenkins_teams=['developer']
  environment=green
```

---

### 4. Switching Mechanism

#### Current (Container Switch):
```bash
# Stop blue container, start green container
docker stop jenkins-devops-blue
docker start jenkins-devops-green

# Update HAProxy stats socket
echo "set server backend_devops/blue-server state maint" | \
  socat /run/haproxy/admin.sock -

echo "set server backend_devops/green-server state ready" | \
  socat /run/haproxy/admin.sock -
```

**Speed:** < 1 second
**Scope:** Container lifecycle only

#### Multi-VM (HAProxy Backend Switch):
```bash
# Update HAProxy backend weights (graceful)
echo "set weight backend_devops/blue-server 0" | \
  socat /run/haproxy/admin.sock -

echo "set weight backend_devops/green-server 100" | \
  socat /run/haproxy/admin.sock -

# OR disable/enable servers (immediate)
echo "disable server backend_devops/blue-server" | \
  socat /run/haproxy/admin.sock -

echo "enable server backend_devops/green-server" | \
  socat /run/haproxy/admin.sock -
```

**Speed:** < 1 second
**Scope:** Traffic routing only (VMs remain running)

#### Multi-VM (DNS Update):
```bash
# Update DNS record
nsupdate <<EOF
  server ${DNS_SERVER}
  zone jenkins.local
  update delete jenkins-active.local A
  update add jenkins-active.local 60 A 192.168.188.143
  send
EOF
```

**Speed:** 60-300 seconds (TTL dependent)
**Scope:** DNS resolution

---

## Network Architecture

### Same Subnet (Simple)
```
Subnet: 192.168.188.0/24
├─ Blue Jenkins:   192.168.188.142
├─ Green Jenkins:  192.168.188.143
├─ HAProxy VIP:    192.168.188.100
├─ HAProxy-1:      192.168.188.110
├─ HAProxy-2:      192.168.188.111
├─ Monitoring:     192.168.188.150
└─ Storage:        192.168.188.151

Routing: Direct layer 2 communication
Firewall: Optional host-based firewall
```

### Separate Subnets (Isolated)
```
Blue Network:  192.168.100.0/24
  └─ Blue Jenkins: 192.168.100.10

Green Network: 192.168.200.0/24
  └─ Green Jenkins: 192.168.200.10

Shared Network: 192.168.188.0/24
  ├─ HAProxy:    192.168.188.100
  ├─ Monitoring: 192.168.188.150
  └─ Storage:    192.168.188.151

Routing: Layer 3 routing required
Firewall: Network-level isolation
```

---

## Migration Strategy

### Phase 1: Planning & Preparation (Week 1-2)
- [ ] Finalize architecture option
- [ ] IP address allocation
- [ ] Network configuration planning
- [ ] Storage strategy decision
- [ ] VM provisioning

### Phase 2: Infrastructure Setup (Week 3-4)
- [ ] Deploy storage VM (if using centralized storage)
- [ ] Deploy HAProxy VM(s)
- [ ] Deploy monitoring VM
- [ ] Network configuration (VLANs, routes, firewall)
- [ ] DNS configuration

### Phase 3: Jenkins VM Deployment (Week 5-6)
- [ ] Deploy Blue Jenkins VM
- [ ] Deploy Green Jenkins VM
- [ ] Storage mounting configuration
- [ ] Team configuration deployment
- [ ] Health check validation

### Phase 4: Testing & Validation (Week 7-8)
- [ ] Functional testing (all teams)
- [ ] Blue-green switching tests
- [ ] Performance testing
- [ ] Disaster recovery testing
- [ ] Security validation

### Phase 5: Production Migration (Week 9-10)
- [ ] Gradual traffic migration
- [ ] Monitoring and alerting setup
- [ ] Documentation updates
- [ ] Team training
- [ ] Post-migration validation

---

## Resource Requirements

### Option 1: Separate VM Sets
| Component | VMs | vCPU | RAM | Storage | Network |
|-----------|-----|------|-----|---------|---------|
| Jenkins Blue | 1 | 8 | 16GB | 500GB | 10Gbps |
| Jenkins Green | 1 | 8 | 16GB | 500GB | 10Gbps |
| HAProxy (HA) | 2 | 2 | 4GB | 50GB | 10Gbps |
| Monitoring | 1 | 4 | 8GB | 200GB | 1Gbps |
| Storage | 1 | 2 | 4GB | 2TB | 10Gbps |
| **Total** | **6** | **26** | **52GB** | **3.75TB** | - |

### Option 2: Hybrid
| Component | VMs | vCPU | RAM | Storage | Network |
|-----------|-----|------|-----|---------|---------|
| Jenkins Blue | 1 | 8 | 16GB | 500GB | 10Gbps |
| Jenkins Green | 1 | 8 | 16GB | 500GB | 10Gbps |
| Shared Services | 1 | 6 | 12GB | 500GB | 10Gbps |
| **Total** | **3** | **22** | **44GB** | **1.5TB** | - |

### Option 3: Full Duplication
| Component | VMs | vCPU | RAM | Storage | Network |
|-----------|-----|------|-----|---------|---------|
| Blue Site (All) | 4 | 16 | 32GB | 3TB | 10Gbps |
| Green Site (All) | 4 | 16 | 32GB | 3TB | 10Gbps |
| **Total** | **8** | **32** | **64GB** | **6TB** | - |

---

## Cost Analysis

### Monthly Cloud Cost Estimates (AWS us-east-1)

| Architecture | EC2 Cost | EBS Cost | Network | Total/Month |
|--------------|----------|----------|---------|-------------|
| Current (Single VM) | $150 | $100 | $20 | **$270** |
| Option 1 (Separate VMs) | $900 | $600 | $100 | **$1,600** |
| Option 2 (Hybrid) | $450 | $300 | $50 | **$800** |
| Option 3 (Full Duplication) | $1,600 | $1,200 | $200 | **$3,000** |

*Estimates based on t3.xlarge instances, gp3 storage, and standard data transfer*

---

## Recommendations

### For Small Teams (1-5 developers):
- **Current architecture** (single VM) is sufficient
- Consider multi-VM only for DR requirements
- Focus on dynamic config updates instead

### For Medium Teams (5-20 developers):
- **Option 2 (Hybrid)** provides good balance
- Jenkins isolation with shared services
- Cost-effective scaling path

### For Large Teams (20+ developers):
- **Option 1 (Separate VMs)** for production
- Full isolation with manageable complexity
- Can scale to Option 3 if DR needed

### For Enterprise:
- **Option 3 (Full Duplication)** for mission-critical
- Complete DR capability
- Geographic distribution support

---

## Open Questions

1. **VM Allocation Model**: Which architecture option (1, 2, 3, or custom)?
2. **Jenkins VMs Count**: How many VMs for Jenkins (2, 4, or variable)?
3. **Storage Strategy**: Centralized NFS/GlusterFS or VM-local with replication?
4. **HAProxy Placement**: Separate VM with VIP, or integrated approach?
5. **Switching Priority**: Fast (HAProxy) vs Safe (DNS)?
6. **Backward Compatibility**: Support both single-VM and multi-VM modes?
7. **Monitoring Placement**: Separate VM, on HAProxy VM, or duplicated?
8. **IP Address Allocation**: Specific ranges available?
9. **Network Requirements**: Same subnet or separate subnets?
10. **Migration Strategy**: Big bang, gradual, parallel, or testing first?

---

## Next Steps

1. ✅ Document architecture options (this document)
2. ⏳ Answer open questions with stakeholders
3. ⏳ Finalize architecture design based on requirements
4. ⏳ Create detailed implementation plan
5. ⏳ Update Ansible playbooks and roles
6. ⏳ Test in non-production environment
7. ⏳ Production migration

---

## References

- Current implementation: `docs/BLUE-GREEN-DEPLOYMENT.md`
- Ansible playbooks: `ansible/playbooks/blue-green-operations.yml`
- HAProxy configuration: `ansible/roles/high-availability/templates/haproxy.cfg.j2`
- Jenkins teams config: `ansible/group_vars/all/jenkins_teams.yml`

---

**Document Status**: Draft for Review
**Last Updated**: December 2025
**Owner**: DevOps Team
**Review Cycle**: Quarterly
