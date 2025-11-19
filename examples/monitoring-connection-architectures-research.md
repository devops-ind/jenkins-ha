# Monitoring Connection Architectures for Large-Scale Multi-Product Environments

**Date**: 2025-10-21
**Status**: Research & Recommendations
**Context**: Expanding from Jenkins HA monitoring to multi-product, multi-VM infrastructure

---

## Executive Summary

This document analyzes different monitoring infrastructure connection patterns for scaling from a Jenkins HA setup to enterprise-wide monitoring covering multiple products and VMs. The research compares 5 major architectural approaches with specific recommendations based on infrastructure scale and requirements.

### Current State Analysis

**Existing Architecture** (Jenkins HA Monitoring):
- **Connection Method**: Static FQDN-based configuration with DNS resolution
- **Discovery**: Ansible inventory-driven target generation
- **Scale**: 2-10 VMs, single product (Jenkins)
- **Components**: Prometheus, Grafana, Loki, cAdvisor, Node Exporter, Promtail
- **Deployment**: Phase-based Ansible automation with unified agent deployment

**Target State Requirements**:
- Support 100+ VMs across multiple products
- Dynamic environments (auto-scaling, blue-green deployments)
- Multi-product monitoring (Jenkins, databases, applications, middleware)
- Mixed infrastructure (VMs, containers, bare metal)
- Enterprise security, reliability, and compliance

---

## Table of Contents

1. [FQDN/DNS-Based Connections (Current)](#1-fqdndns-based-connections-current)
2. [Service Discovery Approaches](#2-service-discovery-approaches)
3. [Pull vs Push Models](#3-pull-vs-push-models)
4. [Network Mesh/Relay Patterns](#4-network-meshrelay-patterns)
5. [Modern Observability Platforms](#5-modern-observability-platforms)
6. [Comparison Matrix](#comparison-matrix)
7. [Recommendations by Scale](#recommendations-by-scale)
8. [Migration Path](#migration-path)

---

## 1. FQDN/DNS-Based Connections (Current)

### Architecture Overview

Static or semi-static configuration files with FQDN-based targets, leveraging DNS for service resolution.

```yaml
# Current Prometheus Configuration Pattern
scrape_configs:
  - job_name: 'jenkins-devops'
    static_configs:
      - targets: ['centos9-vm.internal.local:8080']
        labels:
          team: 'devops'
          environment: 'production'

  - job_name: 'node-exporter'
    static_configs:
      - targets:
        - 'centos9-vm.internal.local:9100'
        - 'centos9-vm2.internal.local:9100'
```

### Connection Mechanism

1. **Target Definition**: Static FQDN targets in configuration files
2. **Resolution**: DNS A/AAAA records resolve FQDNs to IPs
3. **Discovery**: Ansible generates targets from inventory
4. **Updates**: Configuration redeployment via Ansible playbooks

### Current Implementation Strengths

✅ **Production-Ready**: Fully implemented and tested
✅ **DNS Flexibility**: Supports failover via DNS changes
✅ **Team Isolation**: Team-based FQDN patterns
✅ **Ansible Integration**: Automated target generation from inventory
✅ **Rollback Support**: Easy toggle between FQDN/IP modes
✅ **Clear Debugging**: FQDNs more readable than IPs

### Limitations for Scale

❌ **Static Configuration**: Requires redeployment for new targets
❌ **Inventory Maintenance**: Manual inventory updates for new VMs
❌ **Auto-scaling Friction**: Can't discover dynamically created VMs
❌ **Product Heterogeneity**: Different products need different scrape configs
❌ **Configuration Drift**: Risk of inventory vs reality mismatch

### Scalability Analysis

| Scale | Suitability | Notes |
|-------|-------------|-------|
| **2-20 VMs** | ⭐⭐⭐⭐⭐ Excellent | Current implementation perfect |
| **20-100 VMs** | ⭐⭐⭐ Good | Manageable with automation, but friction increasing |
| **100-500 VMs** | ⭐⭐ Poor | Manual inventory maintenance becomes bottleneck |
| **500+ VMs** | ⭐ Very Poor | Not feasible without significant automation |

### Enhancement Path (Keeping Current Pattern)

To extend FQDN-based approach for larger scale:

```yaml
# Option 1: DNS-SD (DNS Service Discovery)
scrape_configs:
  - job_name: 'jenkins-all'
    dns_sd_configs:
      - names:
        - '_jenkins._tcp.internal.local'
        type: 'SRV'
        refresh_interval: 30s

# Option 2: File-based service discovery
scrape_configs:
  - job_name: 'dynamic-targets'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets/*.json'
        refresh_interval: 30s
```

**DNS-SD SRV Record Example**:
```dns
_jenkins._tcp.internal.local. 300 IN SRV 10 10 8080 jenkins1.internal.local.
_jenkins._tcp.internal.local. 300 IN SRV 10 10 8080 jenkins2.internal.local.
```

**File-based Discovery JSON**:
```json
[
  {
    "targets": ["centos9-vm.internal.local:8080"],
    "labels": {
      "team": "devops",
      "product": "jenkins",
      "environment": "production"
    }
  }
]
```

### Operational Complexity

- **Initial Setup**: ⭐⭐⭐⭐⭐ Very Low (already done)
- **Day-2 Operations**: ⭐⭐⭐ Medium (Ansible redeploys)
- **Troubleshooting**: ⭐⭐⭐⭐ Easy (clear DNS/FQDN issues)
- **Learning Curve**: ⭐⭐⭐⭐⭐ Very Low (standard DNS)

### Best Use Cases

✅ Stable infrastructure with infrequent changes
✅ Team-based isolation with predictable naming
✅ HA deployments with DNS-based failover
✅ Environments where DNS is well-managed
✅ Small to medium scale (< 50 VMs)

### Integration with Current Stack

**Existing Integration**: Seamless (current implementation)

**Enhancement Integration**:
```yaml
# Add to ansible/roles/monitoring/templates/prometheus.yml.j2
{% if prometheus_dns_sd_enabled | default(false) %}
  - job_name: 'dns-discovered-services'
    dns_sd_configs:
{% for dns_sd_config in prometheus_dns_sd_configs | default([]) %}
      - names: ['{{ dns_sd_config.name }}']
        type: '{{ dns_sd_config.type | default("SRV") }}'
        refresh_interval: {{ dns_sd_config.refresh_interval | default("30s") }}
{% endfor %}
{% endif %}
```

---

## 2. Service Discovery Approaches

### 2.1 Consul-Based Service Discovery

#### Architecture Overview

Consul provides distributed service discovery with health checking, KV store, and multi-datacenter support.

```
┌─────────────────────────────────────────────────────┐
│                 Consul Cluster                      │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐     │
│  │ Consul     │ │ Consul     │ │ Consul     │     │
│  │ Server 1   │ │ Server 2   │ │ Server 3   │     │
│  └────────────┘ └────────────┘ └────────────┘     │
└─────────────────────────────────────────────────────┘
           ↑                  ↑                  ↑
           │ Service          │ Health           │ Discovery
           │ Registration     │ Checks           │ Queries
           ↓                  ↓                  ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ VM1          │  │ VM2          │  │ Prometheus   │
│ - Consul     │  │ - Consul     │  │ - consul_sd  │
│   Agent      │  │   Agent      │  │   config     │
│ - Jenkins    │  │ - Database   │  │              │
│ - Exporters  │  │ - Exporters  │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
```

#### Connection Mechanism

1. **Service Registration**: Consul agents register services with metadata
2. **Health Monitoring**: Consul performs health checks (HTTP/TCP/Script)
3. **Discovery**: Prometheus queries Consul HTTP API for service catalog
4. **Auto-Update**: Prometheus refreshes targets automatically

**Consul Service Registration** (via systemd or config):
```json
{
  "service": {
    "name": "jenkins",
    "tags": ["team:devops", "environment:production", "blue-green:blue"],
    "port": 8080,
    "check": {
      "http": "http://localhost:8080/login",
      "interval": "30s",
      "timeout": "5s"
    },
    "meta": {
      "team": "devops",
      "product": "jenkins",
      "version": "2.401.1"
    }
  }
}
```

**Prometheus Consul SD Configuration**:
```yaml
scrape_configs:
  - job_name: 'consul-discovered-jenkins'
    consul_sd_configs:
      - server: 'consul.internal.local:8500'
        services: ['jenkins']
        tags: ['environment:production']
        refresh_interval: 30s

    relabel_configs:
      # Extract team from Consul metadata
      - source_labels: [__meta_consul_service_metadata_team]
        target_label: team

      # Extract environment
      - source_labels: [__meta_consul_tags]
        regex: '.*,environment:([^,]+),.*'
        target_label: environment

      # Only scrape healthy instances
      - source_labels: [__meta_consul_health]
        regex: 'passing'
        action: keep
```

#### Pros and Cons

**Advantages**:
✅ **True Dynamic Discovery**: Automatically discovers new services
✅ **Health-Aware**: Only scrapes healthy instances
✅ **Rich Metadata**: Tags and KV store for complex labeling
✅ **Multi-DC Support**: Supports geographically distributed infrastructure
✅ **Mature Ecosystem**: Battle-tested, large community
✅ **DNS Interface**: Can serve as DNS server for backward compatibility

**Disadvantages**:
❌ **Infrastructure Overhead**: Requires Consul cluster (3-5 servers for HA)
❌ **Operational Complexity**: Another distributed system to manage
❌ **Agent Deployment**: Need Consul agent on every VM
❌ **Learning Curve**: Team needs Consul expertise
❌ **Cost**: Resource overhead for Consul cluster + agents

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **10-100 VMs** | ⭐⭐⭐⭐ Excellent | Light cluster can handle easily |
| **100-1000 VMs** | ⭐⭐⭐⭐⭐ Excellent | Designed for this scale |
| **1000-10,000 VMs** | ⭐⭐⭐⭐ Very Good | Needs cluster tuning |
| **10,000+ VMs** | ⭐⭐⭐ Good | Multi-DC federation required |

#### Operational Complexity

- **Initial Setup**: ⭐⭐ Medium-High (cluster setup, agent deployment)
- **Day-2 Operations**: ⭐⭐⭐⭐ Easy (auto-discovery, self-healing)
- **Troubleshooting**: ⭐⭐⭐ Medium (Consul UI helpful, but complexity)
- **Learning Curve**: ⭐⭐ Medium-High (Consul concepts required)

#### Best Use Cases

✅ Large-scale dynamic infrastructure (100+ VMs)
✅ Multi-datacenter deployments
✅ Microservices architectures
✅ Auto-scaling environments
✅ When you need service mesh capabilities
✅ Organizations already using HashiCorp stack

#### Integration with Current Stack

**Ansible Role Extension**:
```yaml
# ansible/roles/consul-agent/tasks/main.yml
- name: Deploy Consul Agent
  community.docker.docker_container:
    name: consul-agent
    image: "consul:{{ consul_version }}"
    network_mode: host
    volumes:
      - /etc/consul.d:/consul/config:ro
      - consul-data:/consul/data
    command: agent -retry-join consul-server.internal.local

- name: Register Jenkins Service
  consul.io.consul_service:
    name: jenkins
    port: 8080
    tags:
      - "team:{{ team_name }}"
      - "environment:{{ deployment_environment }}"
    check:
      http: "http://localhost:8080/login"
      interval: "30s"
```

**Prometheus Configuration Update**:
```yaml
# Add consul_sd_configs to prometheus.yml.j2
{% if prometheus_consul_sd_enabled | default(false) %}
  - job_name: 'consul-services'
    consul_sd_configs:
      - server: '{{ consul_server_url }}'
        datacenter: '{{ consul_datacenter | default("dc1") }}'
        services: {{ prometheus_consul_services | default(['jenkins', 'database']) | to_json }}
{% endif %}
```

---

### 2.2 etcd-Based Service Discovery

#### Architecture Overview

etcd is a distributed key-value store often used for Kubernetes but can serve as generic service discovery.

```
┌─────────────────────────────────────┐
│        etcd Cluster (Raft)          │
│  ┌────────┐ ┌────────┐ ┌────────┐  │
│  │ etcd-1 │ │ etcd-2 │ │ etcd-3 │  │
│  └────────┘ └────────┘ └────────┘  │
└─────────────────────────────────────┘
           ↑ Write             ↓ Read
           │ /services/        │ Watch
┌──────────────────┐    ┌──────────────────┐
│ Registration     │    │ Prometheus       │
│ Script/Tool      │    │ (custom SD)      │
│ - Consul-Template│    │ - HTTP API poll  │
│ - confd          │    │ - File generator │
│ - Registrator    │    │                  │
└──────────────────┘    └──────────────────┘
```

#### Connection Mechanism

1. **Service Registration**: Services write to etcd KV (manual or via Registrator)
2. **Storage Format**: Hierarchical key structure (`/services/jenkins/vm1`)
3. **Discovery**: Prometheus uses file_sd with external etcd watcher
4. **Updates**: etcd watch triggers file regeneration

**etcd Service Registration**:
```bash
# Register service
etcdctl put /services/jenkins/devops-vm1 '{
  "host": "centos9-vm.internal.local",
  "port": 8080,
  "team": "devops",
  "environment": "production",
  "health": "healthy"
}'

# List services
etcdctl get /services/jenkins --prefix
```

**etcd to Prometheus File SD Bridge** (custom tool):
```python
# /usr/local/bin/etcd-prometheus-sd.py
import etcd3
import json
import time

def generate_targets():
    etcd = etcd3.client(host='etcd.internal.local')
    services = etcd.get_prefix('/services/jenkins')

    targets = []
    for value, metadata in services:
        service = json.loads(value)
        targets.append({
            "targets": [f"{service['host']}:{service['port']}"],
            "labels": {
                "team": service['team'],
                "environment": service['environment']
            }
        })

    with open('/etc/prometheus/targets/etcd-jenkins.json', 'w') as f:
        json.dump(targets, f, indent=2)

# Watch for changes
while True:
    generate_targets()
    time.sleep(30)
```

**Prometheus Configuration**:
```yaml
scrape_configs:
  - job_name: 'etcd-discovered-services'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets/etcd-*.json'
        refresh_interval: 30s
```

#### Pros and Cons

**Advantages**:
✅ **Lightweight**: Simpler than Consul, focused on KV storage
✅ **Strong Consistency**: Raft consensus guarantees
✅ **Kubernetes Native**: If using K8s, already available
✅ **Watch API**: Efficient change notifications
✅ **Low Resource**: Smaller footprint than Consul

**Disadvantages**:
❌ **No Native Health Checks**: Need external health monitoring
❌ **No Built-in Prometheus SD**: Requires custom bridge/exporter
❌ **Less Feature-Rich**: No DNS, service mesh, etc.
❌ **Registration Complexity**: Manual registration or custom tooling
❌ **Limited Metadata**: Flat KV vs Consul's rich service model

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **10-100 VMs** | ⭐⭐⭐⭐ Excellent | Overkill but works well |
| **100-1000 VMs** | ⭐⭐⭐⭐ Excellent | Good performance |
| **1000-10,000 VMs** | ⭐⭐⭐ Good | Watch API scales well |
| **10,000+ VMs** | ⭐⭐ Fair | May need partitioning |

#### Operational Complexity

- **Initial Setup**: ⭐⭐⭐ Medium (cluster setup, custom bridge)
- **Day-2 Operations**: ⭐⭐⭐ Medium (bridge maintenance)
- **Troubleshooting**: ⭐⭐⭐ Medium (etcdctl for debugging)
- **Learning Curve**: ⭐⭐⭐ Medium (simpler than Consul)

#### Best Use Cases

✅ Kubernetes environments (already have etcd)
✅ Organizations wanting simpler than Consul
✅ When you need strong consistency guarantees
✅ Custom service discovery requirements
✅ Integration with existing etcd infrastructure

#### Integration with Current Stack

**Less Recommended** unless already using Kubernetes or etcd for other purposes. Consul provides better out-of-box Prometheus integration.

---

### 2.3 Kubernetes Service Discovery

#### Architecture Overview

Kubernetes native service discovery using API server queries.

```
┌─────────────────────────────────────────────┐
│          Kubernetes Cluster                 │
│  ┌──────────────────────────────────────┐  │
│  │     Kubernetes API Server            │  │
│  │  - Service Registry                  │  │
│  │  - Endpoints                         │  │
│  │  - Pod Metadata                      │  │
│  └──────────────────────────────────────┘  │
│           ↑ API Queries                     │
└───────────┼─────────────────────────────────┘
            │
     ┌──────┴──────┐
     │ Prometheus  │ kubernetes_sd_configs
     │ (in-cluster │ - API discovery
     │  or remote) │ - Auto labeling
     └─────────────┘
```

#### Connection Mechanism

1. **Service Registration**: Kubernetes Services/Endpoints (automatic)
2. **Discovery**: Prometheus queries K8s API server
3. **Labeling**: Pod labels, annotations, namespaces auto-applied
4. **Updates**: Real-time via API watch

**Prometheus Kubernetes SD Configuration**:
```yaml
scrape_configs:
  # Discover pods with prometheus.io/scrape annotation
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
        api_server: https://kubernetes.default.svc

    relabel_configs:
      # Only scrape pods with prometheus.io/scrape=true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true

      # Extract port from annotation
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2

      # Use namespace as team label
      - source_labels: [__meta_kubernetes_namespace]
        target_label: team

      # Add pod labels as metric labels
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)

  # Discover services
  - job_name: 'kubernetes-services'
    kubernetes_sd_configs:
      - role: service

    relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
```

**Pod Annotation for Discovery**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: jenkins-master
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/prometheus"
  labels:
    app: jenkins
    team: devops
    environment: production
```

#### Pros and Cons

**Advantages**:
✅ **Zero Configuration**: If on Kubernetes, automatic discovery
✅ **Native Integration**: Perfect for containerized workloads
✅ **Real-time Updates**: Instant pod/service discovery
✅ **Rich Metadata**: Namespaces, labels, annotations
✅ **No Extra Infrastructure**: Uses existing K8s API
✅ **Security**: RBAC integration

**Disadvantages**:
❌ **Kubernetes Required**: Only works in K8s environments
❌ **No VM Support**: Can't discover non-K8s VMs
❌ **Complexity**: Kubernetes operational overhead
❌ **Limited to Cluster**: Can't discover external services easily
❌ **Network Overhead**: API queries can be high at scale

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **10-100 Pods** | ⭐⭐⭐⭐⭐ Excellent | Native K8s performance |
| **100-1000 Pods** | ⭐⭐⭐⭐⭐ Excellent | Designed for this |
| **1000-10,000 Pods** | ⭐⭐⭐⭐ Very Good | May need federation |
| **10,000+ Pods** | ⭐⭐⭐ Good | Multi-cluster required |

#### Operational Complexity

- **Initial Setup**: ⭐⭐⭐⭐⭐ Very Low (if K8s exists)
- **Day-2 Operations**: ⭐⭐⭐⭐⭐ Very Low (automatic)
- **Troubleshooting**: ⭐⭐⭐ Medium (K8s knowledge required)
- **Learning Curve**: ⭐⭐⭐ Medium (K8s knowledge)

#### Best Use Cases

✅ **Containerized workloads on Kubernetes**
✅ Cloud-native applications
✅ Microservices architectures
✅ Organizations with K8s expertise
✅ When you want zero-config discovery

#### Integration with Current Stack

**NOT RECOMMENDED** for your current Jenkins HA use case because:
- Jenkins runs on VMs, not Kubernetes
- Adds significant infrastructure overhead
- Overkill for VM-based deployment

**FUTURE CONSIDERATION** if migrating Jenkins to Kubernetes (containerized masters).

---

### 2.4 DNS-SD (DNS Service Discovery)

#### Architecture Overview

RFC 6763 DNS-based service discovery using SRV and TXT records.

```
┌──────────────────────────────────────┐
│         DNS Server (Bind9,           │
│         PowerDNS, dnsmasq)           │
│                                      │
│  SRV Records:                        │
│  _jenkins._tcp.internal.local        │
│    → jenkins1.internal.local:8080    │
│    → jenkins2.internal.local:8080    │
│                                      │
│  TXT Records (metadata):             │
│  _jenkins._tcp.internal.local        │
│    → "team=devops"                   │
│    → "environment=production"        │
└──────────────────────────────────────┘
            ↑ DNS Query
            │ SRV lookup
     ┌──────┴──────┐
     │ Prometheus  │ dns_sd_configs
     │ - SRV query │ - Periodic refresh
     │ - A record  │ - Label extraction
     └─────────────┘
```

#### Connection Mechanism

1. **Service Registration**: DNS SRV records created (manual or automation)
2. **Discovery**: Prometheus queries DNS SRV records
3. **Resolution**: SRV returns target + port, A record returns IP
4. **Updates**: DNS TTL-based refresh

**DNS Zone File Example** (BIND9):
```dns
; SRV records for Jenkins discovery
; Format: _service._proto.domain. TTL IN SRV priority weight port target.

_jenkins._tcp.internal.local. 300 IN SRV 10 10 8080 centos9-vm.internal.local.
_jenkins._tcp.internal.local. 300 IN SRV 10 10 8080 centos9-vm2.internal.local.

; Node exporter discovery
_node-exporter._tcp.internal.local. 300 IN SRV 10 10 9100 centos9-vm.internal.local.
_node-exporter._tcp.internal.local. 300 IN SRV 10 10 9100 centos9-vm2.internal.local.

; TXT records for metadata (optional, limited support)
_jenkins._tcp.internal.local. 300 IN TXT "team=devops"
_jenkins._tcp.internal.local. 300 IN TXT "environment=production"

; A records for target resolution
centos9-vm.internal.local. 300 IN A 192.168.188.142
centos9-vm2.internal.local. 300 IN A 192.168.188.143
```

**Prometheus DNS-SD Configuration**:
```yaml
scrape_configs:
  - job_name: 'dns-sd-jenkins'
    dns_sd_configs:
      - names:
        - '_jenkins._tcp.internal.local'
        type: 'SRV'
        refresh_interval: 30s

    relabel_configs:
      # SRV records provide hostname and port automatically
      # Add custom labels (must be in separate config or static)
      - target_label: 'product'
        replacement: 'jenkins'

  - job_name: 'dns-sd-node-exporter'
    dns_sd_configs:
      - names:
        - '_node-exporter._tcp.internal.local'
        type: 'SRV'
        refresh_interval: 30s
```

**Automated SRV Record Management** (Ansible):
```yaml
# ansible/roles/dns-sd/tasks/register-service.yml
- name: Add SRV record for Jenkins
  nsupdate:
    server: "{{ dns_server }}"
    zone: "internal.local"
    record: "_jenkins._tcp.internal.local"
    type: "SRV"
    ttl: 300
    value: "10 10 8080 {{ inventory_hostname }}.internal.local."
    state: present
```

#### Pros and Cons

**Advantages**:
✅ **Standardized**: RFC 6763 standard protocol
✅ **No Extra Agents**: Just DNS server
✅ **Simple**: Easy to understand and debug
✅ **Low Overhead**: Lightweight discovery
✅ **Built-in Prometheus**: Native dns_sd_configs
✅ **Multi-Platform**: Works everywhere with DNS

**Disadvantages**:
❌ **Limited Metadata**: TXT records limited, not well-supported
❌ **No Health Checks**: DNS doesn't know service health
❌ **Manual Management**: SRV records need automation
❌ **DNS Caching**: TTL can delay updates
❌ **Limited Flexibility**: Can't do complex filtering

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **10-100 VMs** | ⭐⭐⭐⭐⭐ Excellent | Perfect fit |
| **100-1000 VMs** | ⭐⭐⭐⭐ Very Good | DNS can handle it |
| **1000-10,000 VMs** | ⭐⭐⭐ Good | May need DNS optimization |
| **10,000+ VMs** | ⭐⭐ Fair | DNS load becomes concern |

#### Operational Complexity

- **Initial Setup**: ⭐⭐⭐ Medium (DNS server config, SRV records)
- **Day-2 Operations**: ⭐⭐⭐ Medium (SRV record automation)
- **Troubleshooting**: ⭐⭐⭐⭐ Easy (dig, nslookup)
- **Learning Curve**: ⭐⭐⭐⭐ Low (standard DNS)

#### Best Use Cases

✅ DNS-centric infrastructure
✅ When you want standardized discovery
✅ Stable environments with infrequent changes
✅ Integration with existing DNS automation
✅ Small to medium scale (< 500 VMs)
✅ **BEST UPGRADE PATH FROM CURRENT FQDN APPROACH**

#### Integration with Current Stack

**HIGHLY RECOMMENDED** as next evolution step:

```yaml
# ansible/roles/monitoring/defaults/main.yml
# Add DNS-SD configuration
prometheus_dns_sd_enabled: true
prometheus_dns_sd_configs:
  - name: '_jenkins._tcp.internal.local'
    type: 'SRV'
    refresh_interval: '30s'
  - name: '_node-exporter._tcp.internal.local'
    type: 'SRV'
    refresh_interval: '60s'

# ansible/roles/monitoring/templates/prometheus.yml.j2
{% if prometheus_dns_sd_enabled | default(false) %}
# DNS Service Discovery
{% for dns_config in prometheus_dns_sd_configs | default([]) %}
  - job_name: 'dns-sd-{{ dns_config.name | regex_replace("^_", "") | regex_replace("\\..*$", "") }}'
    dns_sd_configs:
      - names: ['{{ dns_config.name }}']
        type: '{{ dns_config.type | default("SRV") }}'
        refresh_interval: {{ dns_config.refresh_interval | default("30s") }}
{% endfor %}
{% endif %}
```

**Migration Path from Current FQDN**:
1. Phase 1: Add SRV records alongside existing A records
2. Phase 2: Enable dns_sd_configs in Prometheus (coexist with static)
3. Phase 3: Validate DNS-SD targets match static targets
4. Phase 4: Remove static configs, rely on DNS-SD
5. Phase 5: Automate SRV record creation via Ansible

---

## 3. Pull vs Push Models

### 3.1 Prometheus Pull Model (Current)

#### Architecture Overview

Prometheus actively scrapes metrics from targets at defined intervals.

```
┌────────────────────────────────────┐
│       Prometheus Server            │
│  - Scrape scheduler                │
│  - Target discovery                │
│  - TSDB storage                    │
└────────────────────────────────────┘
     │ Pull (HTTP GET /metrics)
     │ Every 30s
     ↓
┌────────────┐  ┌────────────┐  ┌────────────┐
│ Target 1   │  │ Target 2   │  │ Target N   │
│ :9100      │  │ :8080      │  │ :9200      │
│ (passive)  │  │ (passive)  │  │ (passive)  │
└────────────┘  └────────────┘  └────────────┘
```

#### Characteristics

**Pull Model Benefits**:
✅ **Centralized Control**: Prometheus controls what/when to scrape
✅ **Target Health**: Prometheus knows if target is down
✅ **No Authentication**: Targets don't need to auth to server
✅ **Firewall Friendly**: Only Prometheus needs outbound access
✅ **Consistent Timestamps**: Server-side timestamping
✅ **Easy Debugging**: Can manually curl target metrics

**Pull Model Limitations**:
❌ **Network Topology**: Prometheus must reach all targets
❌ **NAT/Firewall**: Targets behind NAT hard to scrape
❌ **Short-lived Jobs**: Batch jobs may finish before scrape
❌ **High Cardinality**: Pull interval limits short-lived metrics
❌ **Cross-Network**: VPN/firewall rules needed for multi-network

#### Scalability

| Aspect | Performance | Notes |
|--------|-------------|-------|
| **Targets per Prometheus** | 1000-5000 | Depends on scrape interval & cardinality |
| **Scrape Frequency** | 10-60s optimal | < 10s increases load significantly |
| **Network Bandwidth** | Low | Only scrape traffic (10-100KB/target) |
| **Scaling Method** | Horizontal | Federation or sharding required |

#### Best Use Cases

✅ **Current infrastructure** (already implemented)
✅ Long-lived services (always-on VMs/containers)
✅ Centralized monitoring within same network
✅ When you control network topology
✅ < 5000 targets per Prometheus instance

---

### 3.2 Push Gateway Pattern

#### Architecture Overview

Targets push metrics to Push Gateway, Prometheus pulls from gateway.

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ Batch Job 1 │  │ Batch Job 2 │  │ Short-lived │
│ (exits)     │  │ (exits)     │  │ Service     │
└─────────────┘  └─────────────┘  └─────────────┘
      │ Push              │ Push         │ Push
      │ HTTP POST         │ HTTP POST    │ HTTP POST
      ↓                   ↓              ↓
┌──────────────────────────────────────────────┐
│         Prometheus Push Gateway              │
│  - Accepts pushed metrics                    │
│  - Stores last push (ephemeral)              │
│  - Exposes /metrics endpoint                 │
└──────────────────────────────────────────────┘
                    ↑ Pull (every 15s)
                    │ HTTP GET /metrics
            ┌───────┴───────┐
            │  Prometheus   │
            │   Server      │
            └───────────────┘
```

#### Connection Mechanism

1. **Metric Push**: Jobs push metrics to Push Gateway via HTTP POST
2. **Gateway Storage**: Push Gateway stores last received metrics
3. **Prometheus Pull**: Prometheus pulls aggregated metrics from gateway
4. **Labeling**: Job name and instance labels identify metric source

**Push Metrics to Gateway**:
```bash
# Bash script pushing metrics
cat <<EOF | curl --data-binary @- http://pushgateway.internal.local:9091/metrics/job/backup-job/instance/vm1
# TYPE backup_duration_seconds gauge
backup_duration_seconds 123.45
# TYPE backup_size_bytes gauge
backup_size_bytes 1048576000
# TYPE backup_success gauge
backup_success 1
EOF
```

**Prometheus Configuration**:
```yaml
scrape_configs:
  - job_name: 'pushgateway'
    honor_labels: true  # Preserve pushed labels
    static_configs:
      - targets: ['pushgateway.internal.local:9091']
```

#### Pros and Cons

**Advantages**:
✅ **Short-Lived Jobs**: Capture metrics from batch jobs/cron
✅ **NAT/Firewall Friendly**: Jobs push out, no inbound required
✅ **Network Isolation**: Jobs behind NAT can push
✅ **Simple Integration**: Easy to push from scripts
✅ **Event-Driven**: Metrics pushed when event occurs

**Disadvantages**:
❌ **Anti-Pattern**: Prometheus documentation warns against overuse
❌ **Stale Metrics**: Gateway holds last push forever (until deleted)
❌ **No Health Check**: Can't tell if job is running
❌ **Single Point of Failure**: Gateway becomes critical
❌ **Timestamp Issues**: Push time != metric generation time
❌ **Label Conflicts**: Pushed labels can conflict

#### Scalability

| Aspect | Performance | Notes |
|--------|-------------|-------|
| **Push Rate** | Moderate | 100-1000 pushes/min per gateway |
| **Metric Retention** | In-memory only | Not for long-term storage |
| **Gateway HA** | Requires clustering | Not trivial to make HA |

#### Best Use Cases

✅ Batch jobs, cron jobs, one-off scripts
✅ Jobs behind NAT/firewall
✅ Network-isolated environments
✅ Event-driven metric collection
✅ **Supplement to pull model** (not replacement)

#### Integration with Current Stack

**Ansible Deployment**:
```yaml
# ansible/roles/monitoring/tasks/phase3-servers/pushgateway.yml
- name: Deploy Push Gateway
  community.docker.docker_container:
    name: pushgateway-{{ deployment_environment }}
    image: "prom/pushgateway:{{ pushgateway_version }}"
    ports:
      - "{{ pushgateway_port }}:9091"
    networks:
      - name: "{{ monitoring_docker_network }}"
    restart_policy: unless-stopped

# Add to Prometheus scrape config
- name: Add Push Gateway to Prometheus targets
  set_fact:
    prometheus_targets: "{{ prometheus_targets + [
      {
        'job': 'pushgateway',
        'targets': ['{{ monitoring_server_address }}:{{ pushgateway_port }}']
      }
    ] }}"
```

**Use Case in Jenkins HA**:
```groovy
// Jenkinsfile - Push build metrics
post {
  always {
    script {
      def duration = currentBuild.duration / 1000
      def success = currentBuild.result == 'SUCCESS' ? 1 : 0
      sh """
        cat <<EOF | curl --data-binary @- http://pushgateway:9091/metrics/job/jenkins-build/instance/${env.NODE_NAME}
# TYPE jenkins_build_duration_seconds gauge
jenkins_build_duration_seconds{job_name="${env.JOB_NAME}",build_number="${env.BUILD_NUMBER}"} ${duration}
# TYPE jenkins_build_success gauge
jenkins_build_success{job_name="${env.JOB_NAME}",build_number="${env.BUILD_NUMBER}"} ${success}
EOF
      """
    }
  }
}
```

---

### 3.3 Hybrid Approaches

#### Architecture Overview

Combine pull and push models based on workload type.

```
┌─────────────────────────────────────────────────┐
│              Prometheus Server                  │
│  - Pull from long-lived services                │
│  - Pull from Push Gateway                       │
│  - Remote_write from edge Prometheus            │
└─────────────────────────────────────────────────┘
    ↑ Pull         ↑ Pull           ↑ remote_write
    │              │                 │
┌───────┐    ┌─────────────┐   ┌──────────────┐
│Jenkins│    │PushGateway  │   │Edge Prometheus│
│VMs    │    │(batch jobs) │   │(remote site)  │
└───────┘    └─────────────┘   └──────────────┘
                  ↑ Push            ↑ Pull
                  │                 │
            ┌──────────┐      ┌──────────┐
            │Cron Jobs │      │Remote VMs│
            └──────────┘      └──────────┘
```

**Configuration Example**:
```yaml
scrape_configs:
  # Pull: Long-lived services (standard)
  - job_name: 'jenkins-masters'
    static_configs:
      - targets: ['vm1:8080', 'vm2:8080']

  # Pull: Node exporters (standard)
  - job_name: 'node-exporters'
    dns_sd_configs:
      - names: ['_node-exporter._tcp.internal.local']

  # Pull from Push Gateway: Batch jobs
  - job_name: 'pushgateway'
    honor_labels: true
    static_configs:
      - targets: ['pushgateway:9091']

# Remote write: Edge Prometheus instances
remote_write:
  - url: 'http://central-prometheus:9090/api/v1/write'
    remote_timeout: 30s
```

#### Benefits

✅ **Best of Both Worlds**: Pull for services, push for jobs
✅ **Network Flexibility**: Handle complex network topologies
✅ **Scalability**: Federation + sharding for large scale
✅ **Reliability**: Multiple collection methods

#### Best Use Cases

✅ **Mixed workload types** (services + batch jobs)
✅ Multi-site deployments
✅ Large-scale infrastructure (1000+ targets)
✅ Complex network topologies
✅ **RECOMMENDED for enterprise deployments**

---

## 4. Network Mesh/Relay Patterns

### 4.1 Prometheus Federation

#### Architecture Overview

Hierarchical Prometheus setup where central Prometheus pulls from edge Prometheus instances.

```
                  ┌────────────────────────┐
                  │  Global Prometheus     │
                  │  (aggregated metrics)  │
                  └────────────────────────┘
                     ↑ Federation          ↑ Federation
                     │ /federate            │ /federate
        ┌────────────┴──────────┐     ┌────┴──────────────┐
        │                       │     │                   │
   ┌────────────────┐      ┌────────────────┐      ┌─────────────┐
   │ DC1 Prometheus │      │ DC2 Prometheus │      │DC3 Prometheus│
   │ (regional)     │      │ (regional)     │      │ (regional)   │
   └────────────────┘      └────────────────┘      └─────────────┘
     ↑ Pull                  ↑ Pull                  ↑ Pull
     │                       │                       │
┌────┴────┐            ┌────┴────┐            ┌────┴────┐
│Jenkins  │            │Database │            │App      │
│Cluster  │            │Cluster  │            │Servers  │
└─────────┘            └─────────┘            └─────────┘
```

#### Connection Mechanism

1. **Edge Prometheus**: Scrapes local targets (pull model)
2. **Federation Endpoint**: Edge exposes `/federate` endpoint
3. **Global Prometheus**: Pulls aggregated metrics from edge instances
4. **Aggregation**: Global stores subset or full metric set

**Edge Prometheus Configuration** (no special config needed):
```yaml
# Standard scrape configs for local targets
scrape_configs:
  - job_name: 'jenkins-dc1'
    static_configs:
      - targets: ['jenkins1:8080', 'jenkins2:8080']
```

**Global Prometheus Federation Configuration**:
```yaml
scrape_configs:
  - job_name: 'federate-dc1'
    scrape_interval: 60s  # Longer interval for federation
    honor_labels: true    # Preserve original labels
    metrics_path: '/federate'
    params:
      'match[]':
        # Fetch all metrics (use selectively in production)
        - '{job=~".+"}'
        # OR: Only specific metrics
        - '{__name__=~"jenkins_.*"}'
        - '{__name__=~"up"}'
    static_configs:
      - targets:
        - 'dc1-prometheus.internal.local:9090'
        - 'dc2-prometheus.internal.local:9090'
        - 'dc3-prometheus.internal.local:9090'
```

**Selective Federation** (recommended):
```yaml
# Only federate aggregated metrics, not raw
params:
  'match[]':
    # High-level metrics only
    - '{__name__=~"jenkins_job_success_rate"}'
    - '{__name__=~"jenkins_executor_usage"}'
    - '{__name__="up"}'
    # Exclude high-cardinality metrics
    - '{__name__!~"jenkins_build_.*"}'
```

#### Pros and Cons

**Advantages**:
✅ **Hierarchical Scaling**: Scale across data centers
✅ **Network Isolation**: Edge instances isolated per region
✅ **Reduced Bandwidth**: Global only pulls aggregates
✅ **Regional Autonomy**: Each DC has local Prometheus
✅ **Simple Setup**: Built-in Prometheus feature
✅ **Multi-tenant**: Isolate teams/products per edge instance

**Disadvantages**:
❌ **Double Storage**: Metrics stored on edge + global
❌ **Query Complexity**: Must query correct instance
❌ **Cardinality Issues**: Federation can explode cardinality
❌ **Limited Aggregation**: Simple pull, no pre-aggregation
❌ **Management Overhead**: Multiple Prometheus instances

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **2-5 Edge Instances** | ⭐⭐⭐⭐⭐ Excellent | Perfect fit |
| **5-20 Edge Instances** | ⭐⭐⭐⭐ Very Good | Works well with selective federation |
| **20-100 Edge Instances** | ⭐⭐⭐ Good | Consider Thanos/Cortex instead |
| **100+ Edge Instances** | ⭐⭐ Fair | Not designed for this scale |

#### Operational Complexity

- **Initial Setup**: ⭐⭐⭐ Medium (multiple Prometheus instances)
- **Day-2 Operations**: ⭐⭐⭐ Medium (manage multiple instances)
- **Troubleshooting**: ⭐⭐⭐ Medium (identify correct instance)
- **Learning Curve**: ⭐⭐⭐⭐ Low (standard Prometheus)

#### Best Use Cases

✅ **Multi-datacenter deployments** (2-10 DCs)
✅ Team/product isolation (one Prometheus per team)
✅ Regional monitoring with global overview
✅ When you need local autonomy + central view
✅ Moderate scale (< 50,000 total targets)

#### Integration with Current Stack

**Ansible Deployment**:
```yaml
# Deploy edge Prometheus per team
- name: Deploy Team-Specific Prometheus
  community.docker.docker_container:
    name: "prometheus-{{ team_name }}"
    image: "prom/prometheus:{{ prometheus_version }}"
    ports:
      - "{{ prometheus_port + loop.index }}:9090"
    volumes:
      - "/etc/prometheus/{{ team_name }}:/etc/prometheus:ro"
      - "prometheus-{{ team_name }}-data:/prometheus"
  loop: "{{ jenkins_teams }}"
  loop_control:
    index_var: loop_index

# Deploy global Prometheus for federation
- name: Deploy Global Prometheus
  community.docker.docker_container:
    name: prometheus-global
    image: "prom/prometheus:{{ prometheus_version }}"
    ports:
      - "9090:9090"
    volumes:
      - "/etc/prometheus/global:/etc/prometheus:ro"
      - "prometheus-global-data:/prometheus"
```

**Use Case for Jenkins HA**:
- **Edge Prometheus per Team**: devops-prometheus, qa-prometheus, dev-prometheus
- **Global Prometheus**: Aggregates cross-team metrics
- **Benefits**: Team isolation, independent scaling, central overview

---

### 4.2 Grafana Agent (Prometheus remote_write)

#### Architecture Overview

Lightweight agent collects and forwards metrics to remote Prometheus/Cortex/Mimir.

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ VM1          │  │ VM2          │  │ VM N         │
│ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │
│ │ Grafana  │ │  │ │ Grafana  │ │  │ │ Grafana  │ │
│ │ Agent    │ │  │ │ Agent    │ │  │ │ Agent    │ │
│ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │
│  - Scrape    │  │  - Scrape    │  │  - Scrape    │
│  - Filter    │  │  - Filter    │  │  - Filter    │
│  - remote_   │  │  - remote_   │  │  - remote_   │
│    write     │  │    write     │  │    write     │
└──────────────┘  └──────────────┘  └──────────────┘
      │ Push             │ Push            │ Push
      │ remote_write     │ remote_write    │ remote_write
      ↓                  ↓                 ↓
┌───────────────────────────────────────────────────┐
│       Central Prometheus / Cortex / Mimir         │
│       - Receives remote_write                     │
│       - Long-term storage                         │
│       - Global queries                            │
└───────────────────────────────────────────────────┘
```

#### Connection Mechanism

1. **Agent Scrape**: Grafana Agent scrapes local targets (like Prometheus)
2. **Filtering**: Agent can filter/relabel metrics locally
3. **Remote Write**: Agent pushes metrics to remote endpoint
4. **Central Storage**: Central system stores all metrics

**Grafana Agent Configuration**:
```yaml
# /etc/grafana-agent/config.yaml
server:
  log_level: info

metrics:
  global:
    scrape_interval: 30s
    remote_write:
      - url: http://central-prometheus.internal.local:9090/api/v1/write
        queue_config:
          capacity: 10000
          max_shards: 10

  configs:
    - name: jenkins-devops
      scrape_configs:
        # Scrape local Jenkins
        - job_name: 'jenkins'
          static_configs:
            - targets: ['localhost:8080']
              labels:
                team: 'devops'
                site: 'dc1'

        # Scrape local node exporter
        - job_name: 'node'
          static_configs:
            - targets: ['localhost:9100']

      # Relabeling before remote_write
      remote_write:
        - url: http://central-prometheus.internal.local:9090/api/v1/write
          write_relabel_configs:
            # Drop high-cardinality metrics
            - source_labels: [__name__]
              regex: 'jenkins_build_.*'
              action: drop
            # Add site label
            - target_label: 'site'
              replacement: 'dc1'
```

**Central Prometheus Configuration**:
```yaml
# Enable remote_write receiver
# (No special config needed for Prometheus 2.x+)
# OR use Cortex/Mimir for scalable remote_write
```

#### Pros and Cons

**Advantages**:
✅ **Lightweight**: Agent uses 10x less resources than Prometheus
✅ **Push Model**: Agents push, no inbound firewall rules
✅ **Centralized Storage**: Single source of truth
✅ **Scalable**: Agents distribute scrape load
✅ **Filtering**: Reduce cardinality before sending
✅ **Multi-Backend**: Can write to Prometheus, Cortex, Mimir, Cloud

**Disadvantages**:
❌ **Network Overhead**: Constant remote_write traffic
❌ **No Local Query**: Must query central system
❌ **Backpressure**: Central system overload affects agents
❌ **Additional Component**: Agents to deploy and manage
❌ **Data Loss Risk**: If remote_write fails and buffer fills

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **10-100 Agents** | ⭐⭐⭐⭐⭐ Excellent | Agents scale linearly |
| **100-1000 Agents** | ⭐⭐⭐⭐⭐ Excellent | Perfect use case |
| **1000-10,000 Agents** | ⭐⭐⭐⭐ Very Good | Need Cortex/Mimir backend |
| **10,000+ Agents** | ⭐⭐⭐⭐ Very Good | Designed for this scale |

#### Operational Complexity

- **Initial Setup**: ⭐⭐⭐ Medium (agent deployment, central setup)
- **Day-2 Operations**: ⭐⭐⭐⭐ Easy (agents self-heal)
- **Troubleshooting**: ⭐⭐⭐ Medium (distributed debugging)
- **Learning Curve**: ⭐⭐⭐ Medium (similar to Prometheus)

#### Best Use Cases

✅ **Large-scale deployments** (100+ VMs)
✅ Cloud/multi-cloud environments
✅ Edge computing (agents on edge, storage in cloud)
✅ When agents behind NAT/firewall
✅ Centralized observability platform
✅ **EXCELLENT for scaling Jenkins HA monitoring**

#### Integration with Current Stack

**Ansible Deployment**:
```yaml
# ansible/roles/grafana-agent/tasks/main.yml
- name: Deploy Grafana Agent
  community.docker.docker_container:
    name: grafana-agent-{{ inventory_hostname }}
    image: "grafana/agent:{{ grafana_agent_version }}"
    network_mode: host
    volumes:
      - "/etc/grafana-agent:/etc/grafana-agent:ro"
      - "/var/lib/grafana-agent:/var/lib/grafana-agent"
    command: -config.file=/etc/grafana-agent/config.yaml
    restart_policy: unless-stopped

- name: Generate Grafana Agent configuration
  template:
    src: grafana-agent-config.yaml.j2
    dest: /etc/grafana-agent/config.yaml
  notify: restart grafana-agent
```

**Template**:
```yaml
# ansible/roles/grafana-agent/templates/grafana-agent-config.yaml.j2
metrics:
  global:
    scrape_interval: {{ scrape_interval | default('30s') }}
    remote_write:
      - url: {{ central_prometheus_url }}/api/v1/write
        queue_config:
          capacity: 10000

  configs:
    - name: {{ inventory_hostname }}
      scrape_configs:
{% for target in grafana_agent_scrape_targets %}
        - job_name: '{{ target.job }}'
          static_configs:
            - targets: {{ target.targets | to_json }}
              labels:
                site: '{{ site_name }}'
                host: '{{ inventory_hostname }}'
{% endfor %}
```

**Migration Strategy**:
1. Deploy Grafana Agent alongside current Node Exporter/Promtail
2. Configure agent to scrape local exporters
3. Enable remote_write to central Prometheus
4. Validate metrics in central Prometheus
5. Optionally remove direct Prometheus scraping
6. Benefits: Lower Prometheus load, better scaling

---

### 4.3 VictoriaMetrics Clustering

#### Architecture Overview

VictoriaMetrics is Prometheus-compatible TSDB with built-in clustering and remote_write.

```
┌──────────────────────────────────────────────────────┐
│          VictoriaMetrics Cluster                     │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐    │
│  │ vminsert   │  │ vminsert   │  │ vminsert   │    │
│  │ (ingestion)│  │ (ingestion)│  │ (ingestion)│    │
│  └────────────┘  └────────────┘  └────────────┘    │
│         │ Write       │ Write       │ Write         │
│         ↓             ↓             ↓               │
│  ┌────────────────────────────────────────────┐    │
│  │          vmstorage (sharded)               │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐│    │
│  │  │ Shard 1  │  │ Shard 2  │  │ Shard 3  ││    │
│  │  └──────────┘  └──────────┘  └──────────┘│    │
│  └────────────────────────────────────────────┘    │
│         ↑ Query       ↑ Query       ↑ Query        │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐   │
│  │ vmselect   │  │ vmselect   │  │ vmselect   │   │
│  │ (query)    │  │ (query)    │  │ (query)    │   │
│  └────────────┘  └────────────┘  └────────────┘   │
└──────────────────────────────────────────────────────┘
     ↑ remote_write        ↑ PromQL queries
     │                     │
┌────────────┐      ┌─────────────┐
│ Prometheus │      │  Grafana    │
│ (scrape)   │      │  (visualize)│
└────────────┘      └─────────────┘
```

#### Connection Mechanism

1. **Ingestion**: vminsert receives remote_write from Prometheus/agents
2. **Sharding**: Data distributed across vmstorage shards
3. **Querying**: vmselect queries all shards and aggregates
4. **Replication**: Optional data replication across shards

**Prometheus Configuration**:
```yaml
remote_write:
  - url: http://vminsert.internal.local:8480/insert/0/prometheus/
    queue_config:
      max_samples_per_send: 10000
      capacity: 500000
```

**VictoriaMetrics Cluster Deployment**:
```yaml
# vminsert (ingestion layer)
vminsert:
  - -storageNode=vmstorage-1:8400
  - -storageNode=vmstorage-2:8400
  - -storageNode=vmstorage-3:8400
  - -replicationFactor=2

# vmstorage (storage layer)
vmstorage:
  - -retentionPeriod=12  # months
  - -storageDataPath=/storage

# vmselect (query layer)
vmselect:
  - -storageNode=vmstorage-1:8401
  - -storageNode=vmstorage-2:8401
  - -storageNode=vmstorage-3:8401
```

#### Pros and Cons

**Advantages**:
✅ **High Performance**: 10x faster ingestion than Prometheus
✅ **Low Resource**: 7x less RAM than Prometheus
✅ **Long Retention**: Efficient compression (years of data)
✅ **Horizontal Scaling**: Add shards for capacity
✅ **PromQL Compatible**: Drop-in Grafana datasource
✅ **Multi-tenancy**: Built-in support
✅ **Deduplication**: Automatic duplicate removal

**Disadvantages**:
❌ **Operational Complexity**: Cluster management overhead
❌ **Not Prometheus**: Different codebase, potential issues
❌ **Migration Effort**: Move from Prometheus to VM cluster
❌ **HA Complexity**: Need load balancers for components
❌ **Documentation**: Less comprehensive than Prometheus

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **Single Node** | ⭐⭐⭐⭐⭐ Excellent | 1M samples/sec |
| **10-100k targets** | ⭐⭐⭐⭐⭐ Excellent | Perfect fit |
| **100k-1M targets** | ⭐⭐⭐⭐⭐ Excellent | Designed for this |
| **1M+ targets** | ⭐⭐⭐⭐ Very Good | Multi-cluster setup |

#### Operational Complexity

- **Initial Setup**: ⭐⭐ Medium-High (cluster deployment)
- **Day-2 Operations**: ⭐⭐⭐ Medium (cluster management)
- **Troubleshooting**: ⭐⭐⭐ Medium (good UI and metrics)
- **Learning Curve**: ⭐⭐⭐ Medium (similar to Prometheus)

#### Best Use Cases

✅ **Very large scale** (10,000+ targets)
✅ Long-term retention (months/years)
✅ Cost optimization (reduce infrastructure)
✅ Multi-tenant environments
✅ When Prometheus hits resource limits
✅ **FUTURE CONSIDERATION for massive scale**

#### Integration with Current Stack

**NOT IMMEDIATE PRIORITY** but excellent future path if:
- Scale exceeds 5,000 targets
- Need long-term retention (> 1 year)
- Prometheus resource usage becomes issue

---

### 4.4 Thanos / Cortex for Multi-Cluster

#### Architecture Overview (Thanos)

Thanos extends Prometheus with long-term storage and global query view.

```
┌────────────────────────────────────────────────────┐
│                 Thanos Architecture                │
│                                                    │
│  ┌──────────────┐         ┌──────────────┐       │
│  │   Grafana    │────────▶│Thanos Query  │       │
│  │  (visualize) │         │ (global view)│       │
│  └──────────────┘         └──────────────┘       │
│                                  ↓ Query          │
│         ┌────────────────────────┼────────────┐  │
│         │                        │            │  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  │Thanos Sidecar│  │Thanos Sidecar│  │Thanos Store  │
│  │(DC1)         │  │(DC2)         │  │(object store)│
│  └──────────────┘  └──────────────┘  └──────────────┘
│         ↑                  ↑                  ↑       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  │Prometheus DC1│  │Prometheus DC2│  │S3/GCS/Azure  │
│  │              │  │              │  │(long-term)   │
│  └──────────────┘  └──────────────┘  └──────────────┘
└────────────────────────────────────────────────────┘
```

**Thanos Components**:
- **Thanos Sidecar**: Runs alongside Prometheus, uploads blocks to object storage
- **Thanos Query**: Provides global query API across all Prometheus instances
- **Thanos Store**: Serves metrics from object storage (S3, GCS, Azure)
- **Thanos Compactor**: Compacts and downsamples historical data
- **Thanos Ruler**: Evaluates rules against historical data

#### Connection Mechanism

1. **Sidecar Upload**: Sidecars upload Prometheus blocks to object storage
2. **Global Query**: Thanos Query deduplicates and merges queries
3. **Long-term Storage**: Thanos Store serves historical data from S3/GCS
4. **Downsampling**: Compactor creates 5m and 1h resolution data

**Prometheus Configuration with Thanos**:
```yaml
# Prometheus with external labels for deduplication
global:
  external_labels:
    cluster: 'dc1'
    replica: 'prometheus-1'

# Enable Thanos sidecar
# (via command-line flags, not config file)
```

**Thanos Sidecar Deployment**:
```yaml
# Docker Compose / Kubernetes
thanos-sidecar:
  image: thanosio/thanos:latest
  command:
    - 'sidecar'
    - '--prometheus.url=http://localhost:9090'
    - '--objstore.config-file=/etc/thanos/bucket.yml'
    - '--tsdb.path=/prometheus/data'
  volumes:
    - prometheus-data:/prometheus
    - ./thanos-bucket.yml:/etc/thanos/bucket.yml
```

**Object Storage Configuration** (bucket.yml):
```yaml
type: S3
config:
  bucket: "thanos-metrics"
  endpoint: "s3.amazonaws.com"
  region: "us-east-1"
  access_key: "ACCESS_KEY"
  secret_key: "SECRET_KEY"
```

**Thanos Query Deployment**:
```yaml
thanos-query:
  image: thanosio/thanos:latest
  command:
    - 'query'
    - '--store=thanos-sidecar-dc1:10901'
    - '--store=thanos-sidecar-dc2:10901'
    - '--store=thanos-store:10901'
  ports:
    - '9090:10902'  # PromQL API
```

#### Pros and Cons

**Advantages**:
✅ **Global View**: Query across all Prometheus instances
✅ **Unlimited Retention**: Object storage (S3) is cheap
✅ **Deduplication**: Automatic dedup of HA Prometheus pairs
✅ **Downsampling**: Reduces storage for old data
✅ **Multi-Cluster**: Perfect for multi-DC deployments
✅ **PromQL Compatible**: Seamless Grafana integration

**Disadvantages**:
❌ **Complexity**: Many moving parts (sidecar, query, store, compactor)
❌ **Object Storage**: Requires S3/GCS/Azure Blob
❌ **Query Latency**: Object storage slower than local TSDB
❌ **Operational Overhead**: Multiple components to manage
❌ **Cost**: Object storage costs (though cheaper than disk)

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **Multi-DC (2-10)** | ⭐⭐⭐⭐⭐ Excellent | Designed for this |
| **10-100 Prometheus** | ⭐⭐⭐⭐⭐ Excellent | Perfect fit |
| **Long Retention** | ⭐⭐⭐⭐⭐ Excellent | Years of data |
| **Query Performance** | ⭐⭐⭐ Good | Slower than local Prometheus |

#### Operational Complexity

- **Initial Setup**: ⭐⭐ Medium-High (many components)
- **Day-2 Operations**: ⭐⭐⭐ Medium (self-healing, but complex)
- **Troubleshooting**: ⭐⭐ Medium-High (distributed debugging)
- **Learning Curve**: ⭐⭐ Medium-High (Thanos architecture)

#### Best Use Cases

✅ **Multi-datacenter monitoring** (5+ sites)
✅ Long-term retention (years)
✅ Global query across Prometheus instances
✅ HA Prometheus with deduplication
✅ Cloud-native deployments (Kubernetes)
✅ **ENTERPRISE-SCALE DEPLOYMENTS**

#### Integration with Current Stack

**FUTURE CONSIDERATION** when:
- Expand to 5+ data centers
- Need multi-year retention
- Prometheus retention becomes costly
- Want global query view across all sites

**Deployment Approach**:
1. Deploy Thanos Sidecar alongside existing Prometheus
2. Configure object storage (S3/GCS)
3. Deploy Thanos Query for global view
4. Gradually migrate queries to Thanos
5. Enable compaction and downsampling

---

## 5. Modern Observability Platforms

### 5.1 OpenTelemetry Collector Architecture

#### Architecture Overview

OpenTelemetry Collector is vendor-agnostic telemetry pipeline for metrics, logs, and traces.

```
┌──────────────────────────────────────────────────────┐
│         OpenTelemetry Collector (OTel Collector)     │
│                                                      │
│  ┌─────────────┐    ┌───────────────┐  ┌──────────┐│
│  │ Receivers   │───▶│  Processors   │─▶│Exporters ││
│  │ - OTLP      │    │  - Batch      │  │- Prom    ││
│  │ - Prometheus│    │  - Filter     │  │- Loki    ││
│  │ - Jaeger    │    │  - Transform  │  │- Jaeger  ││
│  │ - StatsD    │    │  - Attributes │  │- Cloud   ││
│  └─────────────┘    └───────────────┘  └──────────┘│
└──────────────────────���───────────────────────────────┘
     ↑ Receive               ↓ Export
     │ Multiple              │ Multiple
     │ Formats               │ Backends
┌────────────────┐    ┌──────────────────┐
│ Applications   │    │ Backends         │
│ - SDK metrics  │    │ - Prometheus     │
│ - Prometheus   │    │ - Loki           │
│ - Logs         │    │ - Jaeger/Tempo   │
│ - Traces       │    │ - Cloud vendors  │
└────────────────┘    └──────────────────┘
```

#### Connection Mechanism

1. **Receive**: OTel Collector receives telemetry via receivers (OTLP, Prometheus, logs)
2. **Process**: Processors filter, batch, enrich, transform telemetry
3. **Export**: Exporters send to backends (Prometheus, Loki, Tempo, Cloud)
4. **Service Discovery**: Uses Prometheus SD or custom discovery

**OTel Collector Configuration**:
```yaml
# /etc/otel-collector/config.yaml
receivers:
  # Prometheus receiver (scrapes like Prometheus)
  prometheus:
    config:
      scrape_configs:
        - job_name: 'jenkins'
          dns_sd_configs:
            - names: ['_jenkins._tcp.internal.local']
              type: 'SRV'

  # OTLP receiver (native OTel protocol)
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  # Batch telemetry for efficiency
  batch:
    timeout: 10s
    send_batch_size: 1024

  # Filter metrics
  filter/drop_high_cardinality:
    metrics:
      exclude:
        match_type: regexp
        metric_names:
          - 'jenkins_build_.*'

  # Add attributes
  attributes/add_cluster:
    actions:
      - key: cluster
        value: production
        action: insert

exporters:
  # Export to Prometheus via remote_write
  prometheusremotewrite:
    endpoint: http://prometheus.internal.local:9090/api/v1/write

  # Export logs to Loki
  loki:
    endpoint: http://loki.internal.local:9400/loki/api/v1/push

  # Export traces to Jaeger/Tempo
  otlp/jaeger:
    endpoint: jaeger.internal.local:4317

service:
  pipelines:
    # Metrics pipeline
    metrics:
      receivers: [prometheus, otlp]
      processors: [batch, filter/drop_high_cardinality, attributes/add_cluster]
      exporters: [prometheusremotewrite]

    # Logs pipeline
    logs:
      receivers: [otlp]
      processors: [batch, attributes/add_cluster]
      exporters: [loki]

    # Traces pipeline
    traces:
      receivers: [otlp]
      processors: [batch, attributes/add_cluster]
      exporters: [otlp/jaeger]
```

#### Pros and Cons

**Advantages**:
✅ **Vendor Neutral**: Works with any backend (Prometheus, Datadog, Splunk, etc.)
✅ **Unified Telemetry**: Metrics, logs, traces in one pipeline
✅ **Flexible Processing**: Rich processors for filtering, transformation
✅ **Service Discovery**: Supports all Prometheus SD mechanisms
✅ **Cloud Native**: CNCF graduated project
✅ **Future Proof**: Industry standard for observability

**Disadvantages**:
❌ **Complexity**: More moving parts than simple Prometheus
❌ **Resource Overhead**: Additional collector deployment
❌ **Learning Curve**: New concepts (receivers, processors, exporters)
❌ **YAML Hell**: Large configuration files
❌ **Debugging**: Pipeline debugging can be challenging

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **10-100 targets** | ⭐⭐⭐⭐ Very Good | Works but slight overkill |
| **100-1000 targets** | ⭐⭐⭐⭐⭐ Excellent | Sweet spot |
| **1000-10,000 targets** | ⭐⭐⭐⭐⭐ Excellent | Designed for this |
| **10,000+ targets** | ⭐⭐⭐⭐ Very Good | Horizontal scaling needed |

#### Operational Complexity

- **Initial Setup**: ⭐⭐ Medium-High (configuration complexity)
- **Day-2 Operations**: ⭐⭐⭐ Medium (stable but monitor pipelines)
- **Troubleshooting**: ⭐⭐ Medium-High (pipeline debugging)
- **Learning Curve**: ⭐⭐ Medium-High (OTel concepts)

#### Best Use Cases

✅ **Multi-backend environments** (Prometheus + Cloud + Splunk)
✅ Unified metrics, logs, traces pipeline
✅ Cloud migration (vendor flexibility)
✅ Large-scale deployments with complex processing
✅ When you want future-proof observability
✅ **RECOMMENDED for enterprise modernization**

#### Integration with Current Stack

**Ansible Deployment**:
```yaml
# ansible/roles/otel-collector/tasks/main.yml
- name: Deploy OpenTelemetry Collector
  community.docker.docker_container:
    name: otel-collector-{{ deployment_environment }}
    image: "otel/opentelemetry-collector-contrib:{{ otel_version }}"
    network_mode: host
    volumes:
      - "/etc/otel-collector:/etc/otelcol-contrib:ro"
    command: ["--config=/etc/otelcol-contrib/config.yaml"]
    restart_policy: unless-stopped
```

**Migration Strategy**:
1. **Phase 1**: Deploy OTel Collector alongside Prometheus (coexist)
2. **Phase 2**: Configure OTel to scrape targets and export to Prometheus
3. **Phase 3**: Add processing (filtering, enrichment)
4. **Phase 4**: Gradually move scrape configs from Prometheus to OTel
5. **Phase 5**: Enable logs and traces (unified observability)
6. **Benefits**: Vendor flexibility, unified pipeline, future-proof

---

### 5.2 Grafana Alloy Service Discovery

#### Architecture Overview

Grafana Alloy (formerly Grafana Agent v2) is next-generation telemetry collector with advanced service discovery.

```
┌──────────────────────────────────────────────────┐
│            Grafana Alloy                         │
│  ┌────────────────────────────────────────┐     │
│  │  Discovery                             │     │
│  │  - Kubernetes                          │     │
│  │  - Consul                              │     │
│  │  - Docker                              │     │
│  │  - File (custom JSON)                  │     │
│  │  - HTTP (API polling)                  │     │
│  └────────────────────────────────────────┘     │
│                    ↓                             │
│  ┌────────────────────────────────────────┐     │
│  │  Components (Pipelines)                │     │
│  │  - prometheus.scrape                   │     │
│  │  - prometheus.remote_write             │     │
│  │  - loki.source.file                    │     │
│  │  - loki.write                          │     │
│  └────────────────────────────────────────┘     │
└──────────────────────────────────────────────────┘
         ↓ Collect                  ↓ Forward
┌──────────────────┐        ┌──────────────────┐
│ Discovered       │        │ Backends         │
│ Targets          │        │ - Prometheus     │
│ - Auto Jenkins   │        │ - Loki           │
│ - Auto Databases │        │ - Tempo          │
│ - Auto Apps      │        │ - Grafana Cloud  │
└──────────────────┘        └──────────────────┘
```

#### Connection Mechanism

1. **Discovery Components**: Alloy discovers targets via SD mechanisms
2. **Pipeline Components**: Scrape, process, and forward telemetry
3. **Dynamic Config**: Configuration is a DAG of components
4. **Auto-wiring**: Components automatically connect based on exports/imports

**Grafana Alloy Configuration** (River language):
```river
// Discovery: Consul service discovery
discovery.consul "jenkins" {
  server = "consul.internal.local:8500"
  services = ["jenkins"]
  tags = ["production"]
}

// Discovery: Docker containers
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
  filter {
    name = "label"
    values = ["prometheus.scrape=true"]
  }
}

// Discovery: File-based (for custom sources)
discovery.file "custom" {
  files = ["/etc/alloy/targets/*.json"]
  refresh_interval = "30s"
}

// Scrape: Jenkins metrics
prometheus.scrape "jenkins" {
  targets = discovery.consul.jenkins.targets
  forward_to = [prometheus.remote_write.default.receiver]

  scrape_interval = "30s"
  metrics_path = "/prometheus"
}

// Scrape: Docker containers
prometheus.scrape "docker" {
  targets = discovery.docker.containers.targets
  forward_to = [prometheus.remote_write.default.receiver]
}

// Remote Write: Send to Prometheus
prometheus.remote_write "default" {
  endpoint {
    url = "http://prometheus.internal.local:9090/api/v1/write"
    queue_config {
      capacity = 10000
      max_shards = 10
    }
  }
}

// Loki: Scrape logs from files
loki.source.file "logs" {
  targets = discovery.file.custom.targets
  forward_to = [loki.write.default.receiver]
}

// Loki: Write to Loki
loki.write "default" {
  endpoint {
    url = "http://loki.internal.local:9400/loki/api/v1/push"
  }
}
```

**File-based Discovery JSON**:
```json
// /etc/alloy/targets/databases.json
[
  {
    "targets": ["mysql.internal.local:9104"],
    "labels": {
      "__meta_product": "mysql",
      "__meta_team": "platform",
      "job": "mysql-exporter"
    }
  },
  {
    "targets": ["postgres.internal.local:9187"],
    "labels": {
      "__meta_product": "postgres",
      "__meta_team": "platform",
      "job": "postgres-exporter"
    }
  }
]
```

#### Pros and Cons

**Advantages**:
✅ **Modern Architecture**: Component-based, declarative config
✅ **Rich Discovery**: Consul, K8s, Docker, file, HTTP, custom
✅ **Lightweight**: Efficient resource usage
✅ **Dynamic Pipelines**: Components auto-wire and adapt
✅ **Grafana Native**: Best integration with Grafana ecosystem
✅ **Future Forward**: Actively developed by Grafana Labs

**Disadvantages**:
❌ **New Tool**: River config language less familiar
❌ **Migration**: Different from Grafana Agent v1
❌ **Documentation**: Still maturing (v2 is newer)
❌ **Limited Adoption**: Fewer community examples than Prometheus
❌ **Vendor Specific**: Primarily Grafana ecosystem

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **10-100 targets** | ⭐⭐⭐⭐⭐ Excellent | Efficient at any scale |
| **100-1000 targets** | ⭐⭐⭐⭐⭐ Excellent | Designed for this |
| **1000-10,000 targets** | ⭐⭐⭐⭐⭐ Excellent | Scales horizontally |
| **10,000+ targets** | ⭐⭐⭐⭐ Very Good | Multi-instance deployment |

#### Operational Complexity

- **Initial Setup**: ⭐⭐⭐ Medium (new config language)
- **Day-2 Operations**: ⭐⭐⭐⭐ Easy (self-healing pipelines)
- **Troubleshooting**: ⭐⭐⭐ Medium (good UI and metrics)
- **Learning Curve**: ⭐⭐⭐ Medium (River language)

#### Best Use Cases

✅ **Grafana Cloud users** (seamless integration)
✅ Dynamic environments (auto-scaling, containers)
✅ Multi-backend telemetry (metrics + logs + traces)
✅ When you want modern, component-based architecture
✅ Organizations betting on Grafana ecosystem
✅ **EXCELLENT for cloud-native deployments**

#### Integration with Current Stack

**Ansible Deployment**:
```yaml
# ansible/roles/grafana-alloy/tasks/main.yml
- name: Deploy Grafana Alloy
  community.docker.docker_container:
    name: grafana-alloy-{{ inventory_hostname }}
    image: "grafana/alloy:{{ alloy_version }}"
    network_mode: host
    volumes:
      - "/etc/alloy:/etc/alloy:ro"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"  # For Docker discovery
    command: ["run", "/etc/alloy/config.alloy"]
    restart_policy: unless-stopped
```

**Migration Strategy**:
1. Deploy Grafana Alloy alongside existing Prometheus
2. Configure discovery (start with file-based for easy migration)
3. Enable remote_write to existing Prometheus
4. Validate metrics collection
5. Gradually add advanced discovery (Consul, Docker)
6. Optionally migrate from Grafana Agent v1 to Alloy

---

### 5.3 Telegraf with Discovery Plugins

#### Architecture Overview

Telegraf is InfluxDB's metric collector with extensive input plugins and service discovery.

```
┌──────────────────────────────────────────────────┐
│              Telegraf Agent                      │
│  ┌────────────────────────────────────────┐     │
│  │  Input Plugins (200+)                  │     │
│  │  - prometheus (scrape)                 │     │
│  │  - docker                              │     │
│  │  - mysql, postgres, mongodb            │     │
│  │  - systemd, nginx, apache              │     │
│  │  - consul (SD)                         │     │
│  └────────────────────────────────────────┘     │
│                    ↓                             │
│  ┌────────────────────────────────────────┐     │
│  │  Processors                            │     │
│  │  - filter, aggregate, rename           │     │
│  └────────────────────────────────────────┘     │
│                    ↓                             │
│  ┌────────────────────────────────────────┐     │
│  │  Output Plugins                        │     │
│  │  - prometheus_client (expose /metrics) │     │
│  │  - prometheus_remote_write             │     │
│  │  - influxdb, elasticsearch             │     │
│  └────────────────────────────────────────┘     │
└──────────────────────────────────────────────────┘
         ↑ Collect                  ↓ Export
┌──────────────────┐        ┌──────────────────┐
│ Data Sources     │        │ Backends         │
│ - Prometheus     │        │ - Prometheus     │
│ - Databases      │        │ - InfluxDB       │
│ - Applications   │        │ - Elasticsearch  │
│ - System metrics │        │ - Cloud          │
└──────────────────┘        └──────────────────┘
```

#### Connection Mechanism

1. **Input Plugins**: Collect metrics from diverse sources
2. **Service Discovery**: Consul input plugin discovers services
3. **Processing**: Transform and filter metrics
4. **Output**: Export to Prometheus (via remote_write or /metrics endpoint)

**Telegraf Configuration**:
```toml
# /etc/telegraf/telegraf.conf

# Global agent config
[agent]
  interval = "30s"
  flush_interval = "30s"
  hostname = "centos9-vm"

# Input: Prometheus scraping (like Prometheus)
[[inputs.prometheus]]
  urls = ["http://localhost:8080/prometheus"]
  metric_version = 2
  [inputs.prometheus.tags]
    product = "jenkins"
    team = "devops"

# Input: Docker container metrics
[[inputs.docker]]
  endpoint = "unix:///var/run/docker.sock"
  container_name_include = ["jenkins-*"]
  [inputs.docker.tags]
    product = "jenkins"

# Input: Consul service discovery
[[inputs.consul]]
  address = "consul.internal.local:8500"
  scheme = "http"
  services = ["jenkins", "database"]

  # Dynamically scrape discovered services
  [[inputs.consul.query]]
    service = "jenkins"
    tag = "production"

    # Execute prometheus input for each discovered service
    [[inputs.consul.query.prometheus]]
      urls = ["http://{{.Address}}:{{.ServicePort}}/prometheus"]

# Processor: Add tags
[[processors.enum]]
  [[processors.enum.mapping]]
    tag = "environment"
    dest = "env"
    [processors.enum.mapping.value_mappings]
      production = 1
      staging = 2
      development = 3

# Output: Prometheus remote_write
[[outputs.prometheus_remote_write]]
  url = "http://prometheus.internal.local:9090/api/v1/write"

  [outputs.prometheus_remote_write.headers]
    X-Scope-OrgID = "jenkins-ha"

# Output: Expose /metrics for Prometheus to scrape
[[outputs.prometheus_client]]
  listen = ":9273"
  metric_version = 2
```

#### Pros and Cons

**Advantages**:
✅ **200+ Input Plugins**: Extensive pre-built integrations
✅ **Multi-Backend**: Output to Prometheus, InfluxDB, Elasticsearch, Cloud
✅ **Service Discovery**: Consul integration for dynamic discovery
✅ **Easy Configuration**: Simple TOML format
✅ **Mature**: Battle-tested, large community
✅ **Lightweight**: Low resource usage

**Disadvantages**:
❌ **Not Prometheus Native**: Different data model (conversion needed)
❌ **Limited SD**: Not as rich as Prometheus native SD
❌ **InfluxDB Ecosystem**: Primarily designed for InfluxDB
❌ **Label Conversion**: Telegraf tags != Prometheus labels (can cause issues)
❌ **Less Common**: For Prometheus users, Grafana Agent/Alloy more common

#### Scalability

| Scale | Performance | Notes |
|-------|-------------|-------|
| **10-100 targets** | ⭐⭐⭐⭐⭐ Excellent | Works great |
| **100-1000 targets** | ⭐⭐⭐⭐ Very Good | Good performance |
| **1000-10,000 targets** | ⭐⭐⭐ Good | Horizontal scaling needed |
| **10,000+ targets** | ⭐⭐ Fair | Not designed for this scale |

#### Operational Complexity

- **Initial Setup**: ⭐⭐⭐⭐ Easy (simple TOML config)
- **Day-2 Operations**: ⭐⭐⭐⭐ Easy (stable, mature)
- **Troubleshooting**: ⭐⭐⭐⭐ Easy (good logging)
- **Learning Curve**: ⭐⭐⭐⭐ Low (simple concepts)

#### Best Use Cases

✅ **Multi-backend environments** (InfluxDB + Prometheus)
✅ When you need 200+ input plugins (databases, apps, systems)
✅ Simple TOML configuration preferred
✅ Organizations already using InfluxDB
✅ Small to medium scale (< 1000 targets)

#### Integration with Current Stack

**MODERATE FIT** for Jenkins HA monitoring:
- Good for multi-product monitoring (Jenkins + databases + apps)
- 200+ input plugins useful for diverse infrastructure
- BUT: Not as Prometheus-native as Grafana Agent/Alloy

**Use Case**: Consider if expanding beyond Jenkins to monitor:
- MySQL, PostgreSQL, MongoDB databases
- Nginx, Apache web servers
- Redis, Memcached caches
- Custom applications without Prometheus exporters

---

## Comparison Matrix

### Feature Comparison

| Approach | Auto-Discovery | Health Checks | Scalability (1-5) | Complexity (1-5) | Best For |
|----------|----------------|---------------|-------------------|------------------|----------|
| **FQDN/DNS Static** | ❌ Manual | ❌ No | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ Low | < 50 VMs, stable infra |
| **DNS-SD (SRV)** | ✅ Yes | ❌ No | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ Low | 50-500 VMs, DNS-centric |
| **Consul SD** | ✅✅ Excellent | ✅✅ Built-in | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ Medium | 100+ VMs, dynamic infra |
| **etcd SD** | ✅ Yes | ❌ External | ⭐⭐⭐⭐ | ⭐⭐⭐ Medium | K8s environments |
| **Kubernetes SD** | ✅✅ Native | ✅ K8s health | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ Medium | Containerized apps |
| **Push Gateway** | ❌ No | ❌ No | ⭐⭐⭐ | ⭐⭐⭐⭐ Low | Batch jobs only |
| **Prometheus Federation** | ❌ No | ✅ Yes | ⭐⭐⭐⭐ | ⭐⭐⭐ Medium | Multi-DC (2-20) |
| **Grafana Agent** | ✅ Various | ✅ Yes | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ Medium | 100+ VMs, centralized |
| **VictoriaMetrics** | ✅ Via Prom | ✅ Yes | ⭐⭐⭐⭐⭐ | ⭐⭐ Medium-High | 10k+ targets, low cost |
| **Thanos** | ✅ Via Prom | ✅ Yes | ⭐⭐⭐⭐⭐ | ⭐⭐ Medium-High | Multi-DC, long retention |
| **OpenTelemetry** | ✅ Various | ✅ Yes | ⭐⭐⭐⭐⭐ | ⭐⭐ Medium-High | Vendor-agnostic, unified |
| **Grafana Alloy** | ✅✅ Excellent | ✅ Yes | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ Medium | Cloud-native, Grafana |
| **Telegraf** | ✅ Limited | ❌ No | ⭐⭐⭐ | ⭐⭐⭐⭐ Low | Multi-backend, plugins |

### Cost Comparison (Relative)

| Approach | Infrastructure Cost | Operational Cost | Total Cost |
|----------|---------------------|------------------|------------|
| FQDN/DNS Static | 💰 Very Low | 💰💰💰 High (manual) | 💰💰 |
| DNS-SD | 💰 Very Low | 💰💰 Medium | 💰💰 |
| Consul SD | 💰💰💰 Medium (cluster) | 💰 Low (auto) | 💰💰💰 |
| etcd SD | 💰💰 Medium | 💰💰 Medium | 💰💰💰 |
| Kubernetes SD | 💰💰💰💰 High (K8s) | 💰 Low (auto) | 💰💰💰💰 |
| Grafana Agent | 💰 Very Low | 💰 Low | 💰💰 |
| VictoriaMetrics | 💰💰 Medium | 💰 Low | 💰💰 |
| Thanos | 💰💰💰 Medium (storage) | 💰💰 Medium | 💰💰💰 |
| OpenTelemetry | 💰 Very Low | 💰💰 Medium | 💰💰 |
| Grafana Alloy | 💰 Very Low | 💰 Low | 💰 |

---

## Recommendations by Scale

### Small Scale (2-50 VMs, 1-5 Products)

**RECOMMENDED**: **DNS-SD (SRV Records)**

**Rationale**:
- Natural evolution from current FQDN approach
- Minimal infrastructure overhead (just DNS)
- Automatic target discovery within DNS TTL
- Simple troubleshooting (standard DNS tools)
- Low operational complexity

**Architecture**:
```
┌─────────────────────────────────────────┐
│         DNS Server (BIND9/dnsmasq)      │
│  - SRV records for services             │
│  - Automated record updates (Ansible)   │
└─────────────────────────────────────────┘
                  ↑ SRV query
                  │
          ┌───────┴───────┐
          │  Prometheus   │
          │  dns_sd_config│
          └───────────────┘
```

**Implementation Path**:
1. Add SRV record automation to Ansible roles
2. Enable `dns_sd_configs` in Prometheus
3. Coexist with static FQDN configs during migration
4. Validate discovery matches static targets
5. Remove static configs

**Alternative**: **Current FQDN + File SD**
- If DNS changes are complex, use file-based SD with Ansible-generated JSON files
- Similar simplicity, no DNS dependency

---

### Medium Scale (50-500 VMs, 5-20 Products)

**RECOMMENDED**: **Grafana Agent + DNS-SD or Consul SD**

**Rationale**:
- Grafana Agent distributes scrape load across VMs
- Central Prometheus for storage and queries
- Choose DNS-SD if DNS-centric, Consul if need health checks
- Lightweight, scalable, Prometheus-compatible
- Good operational trade-off

**Architecture**:
```
┌────────┐  ┌────────┐  ┌────────┐
│ VM1    │  │ VM2    │  │ VM N   │
│ Agent  │  │ Agent  │  │ Agent  │
└────┬───┘  └────┬───┘  └────┬───┘
     │ remote_write │         │
     ↓              ↓         ↓
┌──────────────────────────────────┐
│  Central Prometheus / Cortex     │
│  - Receives remote_write         │
│  - Centralized storage/queries   │
└──────────────────────────────────┘
            ↑ Query
     ┌──────┴──────┐
     │   Grafana   │
     └─────────────┘
```

**Service Discovery Options**:
- **DNS-SD**: If existing DNS infrastructure strong
- **Consul SD**: If need health checks and dynamic infrastructure

**Implementation Path**:
1. Deploy Grafana Agent on all VMs (alongside exporters)
2. Configure agents to scrape local exporters
3. Enable remote_write to central Prometheus
4. Add Consul or DNS-SD for target discovery
5. Validate metrics in central Prometheus
6. Optionally remove direct Prometheus scraping

**Alternative**: **Consul SD + Prometheus Pull**
- If centralized Prometheus can reach all VMs
- Consul for service registration and health checks
- Direct Prometheus pull (no agents)

---

### Large Scale (500-5,000 VMs, 20-100 Products)

**RECOMMENDED**: **Grafana Agent + Consul SD + Prometheus Federation**

**Rationale**:
- Grafana Agent distributes load and handles push model
- Consul provides robust service discovery and health checks
- Federation for regional/product-based aggregation
- Scalable to thousands of VMs
- Good balance of complexity and capability

**Architecture**:
```
┌─────────────────────────────────────────────┐
│         Consul Cluster (Service Registry)   │
│         - Health checks                     │
│         - Service discovery                 │
└─────────────────────────────────────────────┘
     ↑ Register                ↓ Discover
     │                         │
┌────────────┐         ┌──────────────┐
│ VMs        │         │ Grafana      │
│ - Consul   │         │ Agents       │
│   Agent    │         │ - Consul SD  │
│ - Services │         │ - remote_    │
│ - Exporters│         │   write      │
└────────────┘         └──────────────┘
                              │ remote_write
       ┌──────────────────────┼─────────────────────┐
       ↓                      ↓                     ↓
┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│ Regional    │       │ Regional    │       │ Regional    │
│ Prometheus  │       │ Prometheus  │       │ Prometheus  │
│ (DC1)       │       │ (DC2)       │       │ (DC3)       │
└─────────────┘       └─────────────┘       └─────────────┘
       │ Federation         │                     │
       └────────────────────┼─────────────────────┘
                            ↓
                  ┌──────────────────┐
                  │ Global Prometheus│
                  │ (aggregated)     │
                  └──────────────────┘
```

**Implementation Path**:
1. Deploy Consul cluster (3-5 servers)
2. Deploy Consul agents on all VMs
3. Configure service registration (Jenkins, databases, etc.)
4. Deploy Grafana Agents with Consul SD
5. Setup regional Prometheus instances (per DC or product)
6. Configure federation to global Prometheus
7. Point Grafana to global Prometheus

**Alternative**: **VictoriaMetrics Cluster**
- If single global storage preferred over federation
- Lower resource usage and cost
- Better long-term retention
- Trade-off: operational complexity of VM cluster

---

### Very Large Scale (5,000-50,000+ VMs, 100+ Products)

**RECOMMENDED**: **OpenTelemetry Collector + Thanos or Cortex**

**Rationale**:
- OpenTelemetry for vendor-agnostic, unified telemetry pipeline
- Thanos for global view with object storage (cheap, unlimited retention)
- Cortex for multi-tenant, horizontally scalable TSDB
- Enterprise-grade observability platform
- Future-proof architecture

**Architecture** (Thanos variant):
```
┌─────────────────────────────────────────────────┐
│         OpenTelemetry Collectors (per VM)       │
│         - Service discovery (Consul/K8s/etc)    │
│         - Scrape exporters                      │
│         - Filter & process                      │
│         - remote_write to edge Prometheus       │
└─────────────────────────────────────────────────┘
                    ↓ remote_write
┌─────────────────────────────────────────────────┐
│         Edge Prometheus Instances               │
│         - Regional/Product-based                │
│         - Thanos Sidecar attached               │
│         - Upload blocks to S3/GCS               │
└─────────────────────────────────────────────────┘
                    ↓ Upload to object storage
┌─────────────────────────────────────────────────┐
│         Thanos Architecture                     │
│  ┌──────────────────────────────────────────┐  │
│  │ Thanos Query (Global View)               │  │
│  └──────────────────────────────────────────┘  │
│     ↑ Query all sidecars + stores              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │ Sidecar  │  │ Sidecar  │  │  Store   │     │
│  │ (DC1)    │  │ (DC2)    │  │ (S3/GCS) │     │
│  └──────────┘  └──────────┘  └──────────┘     │
└─────────────────────────────────────────────────┘
                    ↑ Global queries
              ┌─────┴─────┐
              │  Grafana  │
              └───────────┘
```

**Implementation Path**:
1. Deploy OpenTelemetry Collectors on all VMs
2. Configure multi-backend service discovery (Consul + K8s + etc.)
3. Setup edge Prometheus instances (per region/product)
4. Deploy Thanos components:
   - Sidecar on each Prometheus
   - Thanos Query for global view
   - Thanos Store for object storage
   - Thanos Compactor for downsampling
5. Configure object storage (S3/GCS)
6. Point Grafana to Thanos Query
7. Enable long-term retention (years)

**Alternative**: **Cortex for Multi-Tenancy**
- If strong multi-tenant isolation required
- Horizontal scaling of write and query paths
- Cloud-native (Kubernetes-based)
- Trade-off: operational complexity

---

## Migration Path

### Phase 1: Foundation (Current → DNS-SD)

**Timeline**: 1-2 weeks
**Risk**: Low
**Effort**: Low

**Steps**:
1. Implement DNS-SD automation in Ansible
2. Add SRV record creation for Jenkins teams
3. Enable `dns_sd_configs` in Prometheus (coexist with static)
4. Validate discovery matches static targets
5. Remove static FQDN configs

**Benefits**:
- Low risk (backward compatible)
- Foundation for future service discovery
- Minimal infrastructure changes

---

### Phase 2: Scale (DNS-SD → Grafana Agent + Consul SD)

**Timeline**: 4-6 weeks
**Risk**: Medium
**Effort**: Medium

**Steps**:
1. Deploy Consul cluster (3 servers, HA)
2. Deploy Consul agents on all VMs
3. Implement service registration automation
4. Deploy Grafana Agents with Consul SD
5. Configure remote_write to central Prometheus
6. Migrate from DNS-SD to Consul SD incrementally
7. Validate metrics consistency

**Benefits**:
- True dynamic discovery
- Health-aware monitoring
- Scales to hundreds of VMs
- Foundation for larger scale

---

### Phase 3: Enterprise (Agent + Consul → OTel + Thanos)

**Timeline**: 8-12 weeks
**Risk**: Medium-High
**Effort**: High

**Steps**:
1. Plan Thanos architecture (sidecar vs receiver mode)
2. Setup object storage (S3/GCS)
3. Deploy OpenTelemetry Collectors (replace Grafana Agents)
4. Deploy Thanos components:
   - Sidecar on edge Prometheus
   - Thanos Query for global view
   - Thanos Store for object storage
   - Compactor for downsampling
5. Migrate queries from Prometheus to Thanos Query
6. Enable long-term retention
7. Decommission old Prometheus instances

**Benefits**:
- Unlimited scalability (1000s of VMs)
- Multi-year retention
- Global query view
- Vendor-agnostic (OTel)
- Enterprise-grade observability

---

## Summary and Final Recommendations

### Current State (Jenkins HA)
Your **FQDN-based monitoring** is excellent for current scale (2-10 VMs). Well-architected, production-ready, and maintainable.

### Immediate Next Step (< 50 VMs)
**Implement DNS-SD (SRV Records)**:
- Natural evolution from FQDN approach
- Minimal complexity increase
- Automatic target discovery
- Foundation for future scaling

### Medium-Term (50-500 VMs)
**Add Grafana Agent + Consul SD**:
- Distributes scrape load
- Robust service discovery
- Health-aware monitoring
- Scales to hundreds of VMs

### Long-Term (500+ VMs, Enterprise)
**Migrate to OpenTelemetry + Thanos**:
- Vendor-agnostic observability
- Unlimited scalability
- Multi-year retention
- Global query view
- Future-proof architecture

### Key Decision Factors

| Factor | Small (<50) | Medium (50-500) | Large (500+) |
|--------|-------------|-----------------|--------------|
| **Auto-Discovery** | DNS-SD | Consul SD | Consul/K8s/OTel |
| **Collection** | Prometheus Pull | Grafana Agent | OTel Collector |
| **Storage** | Single Prometheus | Federation | Thanos/Cortex |
| **Retention** | 1-3 months | 3-6 months | Years |
| **Complexity** | Low | Medium | High |
| **Cost** | Low | Medium | High |

---

**Document Version**: 1.0
**Last Updated**: 2025-10-21
**Author**: AI Systems Engineer
**Status**: Research Complete - Ready for Implementation Planning
