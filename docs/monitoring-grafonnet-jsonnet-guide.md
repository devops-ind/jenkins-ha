# Grafonnet/Jsonnet Dashboard-as-Code Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [How Jsonnet Works](#how-jsonnet-works)
4. [Current Implementation](#current-implementation)
5. [Using External Repositories](#using-external-repositories)
6. [Dynamic Configuration](#dynamic-configuration)
7. [Advanced Usage](#advanced-usage)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### What is Jsonnet?

**Jsonnet** is a data templating language that extends JSON with:
- **Variables**: Define values once, use them everywhere
- **Functions**: Reusable logic for generating JSON
- **Conditionals**: Dynamic configuration based on conditions
- **Imports**: Modular code organization and reusability
- **Mixins**: Composition and extension of JSON objects

### What is Grafonnet?

**Grafonnet** is a Jsonnet library specifically designed for generating Grafana dashboards. It provides:
- Type-safe dashboard creation
- Reusable panel templates
- Consistent dashboard structure
- Version-controlled dashboards
- Code review workflows

### Why Dashboard-as-Code?

| Traditional (UI) | Dashboard-as-Code (Grafonnet) |
|------------------|-------------------------------|
| Manual clicking | Programmatic generation |
| Hard to version control | Git-friendly code |
| Inconsistent styling | Enforced standards |
| Difficult to replicate | Easy replication |
| No code review | Pull request workflows |
| Error-prone | Type-safe |

---

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Monitoring Stack                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────┐         ┌──────────────────┐          │
│  │  Jsonnet Files  │         │  jsonnetfile.json│          │
│  │  (.jsonnet)     │────────▶│  (dependencies)  │          │
│  └─────────────────┘         └──────────────────┘          │
│         │                              │                     │
│         │                              │                     │
│         ▼                              ▼                     │
│  ┌─────────────────┐         ┌──────────────────┐          │
│  │ Jsonnet Bundler │         │   Grafonnet Lib  │          │
│  │      (jb)       │────────▶│  (from GitHub)   │          │
│  └─────────────────┘         └──────────────────┘          │
│         │                              │                     │
│         │                              │                     │
│         ▼                              ▼                     │
│  ┌──────────────────────────────────────────────┐          │
│  │         Jsonnet Compiler                      │          │
│  │  (compiles .jsonnet → .json)                 │          │
│  └──────────────────────────────────────────────┘          │
│         │                                                    │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────────────────────────────────────┐          │
│  │      Generated JSON Dashboards                │          │
│  │  (/opt/monitoring/grafana/dashboards-generated)│         │
│  └──────────────────────────────────────────────┘          │
│         │                                                    │
│         │  (Docker volume mount)                            │
│         ▼                                                    │
│  ┌──────────────────────────────────────────────┐          │
│  │         Grafana Container                     │          │
│  │  /var/lib/grafana/dashboards-generated       │          │
│  └──────────────────────────────────────────────┘          │
│         │                                                    │
│         │  (Auto-provisioning)                              │
│         ▼                                                    │
│  ┌──────────────────────────────────────────────┐          │
│  │         Grafana UI                            │          │
│  │  Folder: "Generated"                          │          │
│  └──────────────────────────────────────────────┘          │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Directory Structure

```bash
/opt/grafonnet/                              # Jsonnet project directory
├── jsonnetfile.json                          # Dependency definition
├── jsonnetfile.lock.json                     # Locked dependencies
├── vendor/                                   # Downloaded dependencies
│   └── grafonnet/                            # Grafonnet library
│       └── gen/g.libsonnet                   # Main Grafonnet API
├── lib/                                      # Local libraries
│   └── common.libsonnet                      # Reusable components
├── infrastructure-health.jsonnet             # Dashboard source
└── jenkins-overview.jsonnet                  # Dashboard source

/opt/monitoring/grafana/dashboards-generated/ # Output directory
├── infrastructure-health.json                # Generated dashboard
├── jenkins-overview.json                     # Generated dashboard
└── .backups/                                 # Version backups
    ├── infrastructure-health.json-20251212_100530
    └── jenkins-overview.json-20251212_100530
```

---

## How Jsonnet Works

### 1. Dependency Management (jsonnetfile.json)

**Location**: `ansible/roles/monitoring/files/dashboards/jsonnet/jsonnetfile.json`

```json
{
  "version": 1,
  "dependencies": [
    {
      "source": {
        "git": {
          "remote": "https://github.com/grafana/grafonnet",
          "subdir": "grafonnet"
        }
      },
      "version": "main"
    }
  ]
}
```

**How it works:**
1. **Jsonnet Bundler (jb)** reads `jsonnetfile.json`
2. Downloads dependencies from specified Git repositories
3. Installs them in `vendor/` directory
4. Creates `jsonnetfile.lock.json` to lock versions

### 2. Reusable Component Library (lib/common.libsonnet)

**Location**: `ansible/roles/monitoring/files/dashboards/jsonnet/lib/common.libsonnet`

```jsonnet
local g = import 'grafonnet/gen/g.libsonnet';

{
  // Reusable panel templates
  statPanel(title, query, unit='short', decimals=0)::
    g.stat.new(
      title=title,
      targets=[
        g.target.prometheus.new(
          expr=query,
          refId='A',
        ),
      ],
      unit=unit,
      decimals=decimals,
    ),

  // Grid position helper
  gridPos(h, w, x, y):: {
    h: h,  // height
    w: w,  // width
    x: x,  // x position
    y: y,  // y position
  },
}
```

**How it works:**
- Defines reusable functions for creating panels
- Provides consistent styling and configuration
- Reduces code duplication across dashboards
- Can be imported by any dashboard: `local common = import './lib/common.libsonnet';`

### 3. Dashboard Source Files (.jsonnet)

**Location**: `ansible/roles/monitoring/files/dashboards/jsonnet/*.jsonnet`

**Example**: `infrastructure-health.jsonnet`

```jsonnet
// Import dependencies
local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';

// Dashboard metadata
local dashboardTitle = 'Infrastructure Health';
local dashboardUid = 'infrastructure-health-modern';

// Create dashboard
common.defaultDashboard(
  title=dashboardTitle,
  uid=dashboardUid,
  tags=['infrastructure', 'system']
)
.addPanels([
  // Add panels
  common.statPanel(
    title='Nodes Up',
    query='count(node_up)',
    unit='short',
    decimals=0,
  ),
  gridPos=common.gridPos(h=8, w=4, x=0, y=1)
])
```

**How it works:**
1. Imports Grafonnet library and local components
2. Defines dashboard configuration (title, UID, tags)
3. Creates dashboard using template functions
4. Adds panels with queries and positioning
5. Compiles to JSON when processed by jsonnet compiler

### 4. Compilation Process

**Command**: `jsonnet -J vendor infrastructure-health.jsonnet -o infrastructure-health.json`

**Flow:**
```
infrastructure-health.jsonnet
    │
    ├─▶ import 'grafonnet/gen/g.libsonnet'  (from vendor/)
    │       │
    │       └─▶ Grafonnet library code
    │
    ├─▶ import './lib/common.libsonnet'
    │       │
    │       └─▶ Local reusable components
    │
    └─▶ Dashboard definition
        │
        └─▶ Jsonnet Compiler
            │
            └─▶ infrastructure-health.json (Grafana-compatible JSON)
```

### 5. Provisioning to Grafana

**Configuration**: `ansible/roles/monitoring/templates/dashboards/dashboard.yml.j2`

```yaml
apiVersion: 1
providers:
  - name: 'Jenkins Infrastructure - Grafonnet'
    orgId: 1
    folder: 'Generated'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: false  # Code-managed, no UI edits
    options:
      path: /var/lib/grafana/dashboards-generated
```

**How it works:**
1. Grafana container mounts volume: `/opt/monitoring/grafana/dashboards-generated:/var/lib/grafana/dashboards-generated`
2. Provisioning configuration points to `/var/lib/grafana/dashboards-generated`
3. Grafana scans directory every 10 seconds
4. Auto-loads new/changed JSON dashboards
5. Displays in "Generated" folder in UI
6. UI edits disabled (dashboards managed via code)

---

## Current Implementation

### Ansible Role Integration

**Role**: `ansible/roles/monitoring`

**Key Variables** (`defaults/main.yml`):

```yaml
# Enable/disable Grafonnet
grafonnet_enabled: true

# Directories
grafonnet_project_dir: "/opt/grafonnet"              # Jsonnet source files
grafonnet_output_dir: "/opt/monitoring/grafana/dashboards-generated"  # Generated JSON

# Tools
jsonnet_compiler: "jsonnet"
jsonnet_bundler: "jb"

# Backup
grafonnet_backup_versions: 7  # Keep last 7 versions

# Dashboards to generate
grafonnet_dashboards:
  - name: "infrastructure-health"
    enabled: true
    description: "System health monitoring dashboard"
  - name: "jenkins-overview"
    enabled: true
    description: "Comprehensive Jenkins monitoring dashboard"
```

### Deployment Phases

**Phase 1: Setup** (`tasks/phase4-dashboards/setup-grafonnet.yml`)

```yaml
# 1. Create directories
- /opt/grafonnet/
- /opt/monitoring/grafana/dashboards-generated/

# 2. Install tools
- jsonnet compiler (via yum/apt)
- jsonnet-bundler (jb) - from GitHub releases

# 3. Copy source files
- jsonnetfile.json
- lib/common.libsonnet
- *.jsonnet dashboards

# 4. Install dependencies
- jb install (downloads grafonnet to vendor/)
```

**Phase 2: Generate** (`tasks/phase4-dashboards/generate-dashboards.yml`)

```yaml
# 1. Backup existing dashboards
- Copy current .json to .backups/
- Keep last 7 versions

# 2. Compile dashboards
- For each .jsonnet file:
  - jsonnet -J vendor <file>.jsonnet -o <output>.json

# 3. Validate JSON
- Check valid JSON syntax
- Verify file size

# 4. Set permissions
- owner: monitoring_user
- group: monitoring_group
- mode: 0644
```

**Phase 3: Test** (`tasks/phase4-dashboards/test-dashboards.yml`)

```yaml
# 1. Validate structure
- Check required fields: title, uid, panels, templating
- Validate panel types
- Check variable configuration

# 2. Generate statistics
- Count dashboards
- Count total panels
- Count total variables

# 3. Report results
- Display validation summary
- Show dashboard statistics
```

### Deployment Commands

```bash
# Full deployment (all phases)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Setup only
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,phase5.5,grafonnet,setup

# Generate dashboards only (after modifying .jsonnet files)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,phase5.5,grafonnet,generate

# Test/validate only
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,phase5.5,grafonnet,test
```

---

## Using External Repositories

### Method 1: Direct Git Repository Reference

**Use Case**: Load dashboard libraries from external Git repositories

**Update `jsonnetfile.json`**:

```json
{
  "version": 1,
  "dependencies": [
    {
      "source": {
        "git": {
          "remote": "https://github.com/grafana/grafonnet",
          "subdir": "grafonnet"
        }
      },
      "version": "main"
    },
    {
      "source": {
        "git": {
          "remote": "https://github.com/your-org/custom-dashboards",
          "subdir": "lib"
        }
      },
      "version": "v1.2.3"  // Specific tag/branch
    },
    {
      "source": {
        "git": {
          "remote": "https://github.com/your-company/monitoring-lib",
          "subdir": ""  // Root of repo
        }
      },
      "version": "main"
    }
  ]
}
```

**Deploy and use**:

```bash
# 1. Update jsonnetfile.json (as shown above)

# 2. Deploy updated dependencies
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring,grafonnet,setup

# 3. Use in dashboard
# your-dashboard.jsonnet
local customLib = import 'your-company-lib/panels.libsonnet';

customLib.specialPanel(
  title='Custom Metric',
  query='custom_metric_total'
)
```

### Method 2: Ansible Template Variables

**Use Case**: Dynamic configuration from inventory variables

**Update `ansible/roles/monitoring/defaults/main.yml`**:

```yaml
# External Grafonnet repositories
grafonnet_external_repos:
  - name: "company-dashboards"
    git_url: "https://github.com/your-org/grafana-dashboards"
    version: "main"
    subdir: "jsonnet"
  - name: "shared-panels"
    git_url: "https://github.com/your-team/shared-panels"
    version: "v2.0.0"
    subdir: "lib"

# Dynamic dashboard configuration
dashboard_config:
  prometheus_url: "{{ prometheus_url }}"
  loki_url: "{{ loki_url }}"
  teams: "{{ jenkins_teams_config | map(attribute='team_name') | list }}"
  environments: ["blue", "green"]
```

**Create template**: `ansible/roles/monitoring/templates/jsonnetfile.json.j2`

```jinja2
{
  "version": 1,
  "dependencies": [
    {
      "source": {
        "git": {
          "remote": "https://github.com/grafana/grafonnet",
          "subdir": "grafonnet"
        }
      },
      "version": "main"
    },
{% for repo in grafonnet_external_repos %}
    {
      "source": {
        "git": {
          "remote": "{{ repo.git_url }}",
          "subdir": "{{ repo.subdir }}"
        }
      },
      "version": "{{ repo.version }}"
    }{{ "," if not loop.last else "" }}
{% endfor %}
  ]
}
```

**Update task** (`tasks/phase4-dashboards/setup-grafonnet.yml`):

```yaml
- name: Generate jsonnetfile.json from template
  template:
    src: jsonnetfile.json.j2
    dest: "{{ grafonnet_project_dir }}/jsonnetfile.json"
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0644'
  tags: ['monitoring', 'grafonnet', 'setup']

- name: Install Grafonnet dependencies (including external repos)
  shell: |
    cd "{{ grafonnet_project_dir }}"
    /usr/local/bin/jb install
  tags: ['monitoring', 'grafonnet', 'setup']
```

### Method 3: Git Submodules

**Use Case**: Version-controlled external dependencies within your repository

**Setup**:

```bash
# 1. Add submodule
cd ansible/roles/monitoring/files/dashboards/jsonnet/
git submodule add https://github.com/your-org/dashboard-lib vendor/custom

# 2. Commit
git add .gitmodules vendor/custom
git commit -m "Add custom dashboard library as submodule"

# 3. Use in dashboards
# your-dashboard.jsonnet
local custom = import 'vendor/custom/panels.libsonnet';

custom.enterprisePanel(...)
```

**Update on deployment**:

```yaml
# ansible/roles/monitoring/tasks/phase4-dashboards/setup-grafonnet.yml

- name: Update git submodules for external libraries
  shell: |
    cd "{{ role_path }}/files/dashboards/jsonnet/"
    git submodule update --init --recursive
  tags: ['monitoring', 'grafonnet', 'setup']
```

### Method 4: Ansible Git Module (Dynamic Clone)

**Use Case**: Clone external repositories dynamically during deployment

**Task** (`tasks/phase4-dashboards/setup-external-libs.yml`):

```yaml
---
- name: Clone external Grafonnet libraries
  git:
    repo: "{{ item.git_url }}"
    dest: "{{ grafonnet_project_dir }}/vendor/{{ item.name }}"
    version: "{{ item.version }}"
    force: yes
  loop: "{{ grafonnet_external_repos }}"
  tags: ['monitoring', 'grafonnet', 'external-libs']

- name: Create vendor directory symlinks for imports
  file:
    src: "{{ grafonnet_project_dir }}/vendor/{{ item.name }}/{{ item.subdir }}"
    dest: "{{ grafonnet_project_dir }}/vendor/{{ item.name }}-lib"
    state: link
  loop: "{{ grafonnet_external_repos }}"
  when: item.subdir != ""
  tags: ['monitoring', 'grafonnet', 'external-libs']
```

**Inventory configuration** (`ansible/inventories/production/group_vars/all/monitoring.yml`):

```yaml
grafonnet_external_repos:
  - name: "corporate-standards"
    git_url: "git@github.com:company/grafana-standards.git"
    version: "v3.1.0"
    subdir: "jsonnet/lib"

  - name: "sre-dashboards"
    git_url: "https://github.com/sre-team/monitoring.git"
    version: "main"
    subdir: "grafonnet"

  - name: "security-panels"
    git_url: "https://gitlab.com/security/grafana-panels.git"
    version: "release/2.0"
    subdir: "lib"
```

**Use in dashboards**:

```jsonnet
// infrastructure-health.jsonnet
local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local corporate = import 'corporate-standards/panels.libsonnet';
local sre = import 'sre-dashboards/dashboards.libsonnet';

// Use corporate standards
corporate.defaultDashboard(
  title='Infrastructure Health',
  uid='infra-health'
)
.addPanels([
  // SRE team's standard panels
  sre.uptimePanel(),
  sre.latencyPanel(),

  // Custom panels
  common.statPanel(
    title='Nodes Up',
    query='count(node_up)'
  ),
])
```

---

## Dynamic Configuration

### Team-Based Dashboard Generation

**Goal**: Automatically generate dashboards for each Jenkins team

**Create template**: `ansible/roles/monitoring/files/dashboards/jsonnet/team-dashboard.jsonnet.j2`

```jinja2
// Auto-generated team dashboard for {{ team_name }}
local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';

local teamName = '{{ team_name }}';
local teamPort = {{ team_port }};
local environment = '{{ active_environment }}';

common.defaultDashboard(
  title='{{ team_name | title }} Team Dashboard',
  uid='team-{{ team_name }}-dashboard',
  team=teamName,
  environment=environment,
  tags=['jenkins', 'team', teamName]
)
.addPanels([
  common.statPanel(
    title='Jenkins Up',
    query='jenkins_up{jenkins_team="' + teamName + '"}',
  ),
  common.timeSeriesPanel(
    title='Build Success Rate',
    query='sum(increase(jenkins_builds_success_total{jenkins_team="' + teamName + '"}[5m])) / sum(increase(jenkins_builds_started_total{jenkins_team="' + teamName + '"}[5m])) * 100',
  ),
])
```

**Generate task**:

```yaml
# ansible/roles/monitoring/tasks/phase4-dashboards/generate-team-dashboards.yml

- name: Generate team-specific dashboard Jsonnet files
  template:
    src: "{{ role_path }}/files/dashboards/jsonnet/team-dashboard.jsonnet.j2"
    dest: "{{ grafonnet_project_dir }}/team-{{ item.team_name }}-dashboard.jsonnet"
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0644'
  loop: "{{ jenkins_teams_config }}"
  tags: ['monitoring', 'grafonnet', 'team-dashboards']

- name: Compile team dashboards
  shell: |
    cd "{{ grafonnet_project_dir }}"
    for team_file in team-*-dashboard.jsonnet; do
      dashboard_name=$(basename "${team_file}" .jsonnet)
      jsonnet -J vendor "${team_file}" -o "{{ grafonnet_output_dir }}/${dashboard_name}.json"
    done
  tags: ['monitoring', 'grafonnet', 'team-dashboards']
```

### Environment-Specific Configuration

**Create config file**: `ansible/roles/monitoring/files/dashboards/jsonnet/config.libsonnet.j2`

```jinja2
// Auto-generated configuration
{
  // Environment
  environment: '{{ deployment_environment }}',

  // Datasources
  prometheus: {
    uid: '${DS_PROMETHEUS}',
    url: '{{ prometheus_url }}',
  },
  loki: {
    uid: '${DS_LOKI}',
    url: '{{ loki_url }}',
  },

  // Teams
  teams: [
{% for team in jenkins_teams_config %}
    {
      name: '{{ team.team_name }}',
      port: {{ team.ports.web }},
      active_env: '{{ team.active_environment | default("blue") }}',
    },
{% endfor %}
  ],

  // Thresholds
  thresholds: {
    cpu_warning: {{ monitoring_thresholds.cpu_warning | default(70) }},
    cpu_critical: {{ monitoring_thresholds.cpu_critical | default(90) }},
    memory_warning: {{ monitoring_thresholds.memory_warning | default(80) }},
    memory_critical: {{ monitoring_thresholds.memory_critical | default(95) }},
  },
}
```

**Use in dashboards**:

```jsonnet
// infrastructure-health.jsonnet
local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local config = import './config.libsonnet';  // Import generated config

// Use config values
common.defaultDashboard(
  title='Infrastructure Health - ' + config.environment,
  uid='infra-health-' + config.environment
)
.addPanels([
  common.statPanel(
    title='CPU Warning Threshold',
    query='node_cpu_usage > ' + config.thresholds.cpu_warning,
  ),

  // Generate panel for each team
  std.map(
    function(team)
      common.statPanel(
        title=team.name + ' Jenkins',
        query='jenkins_up{jenkins_team="' + team.name + '"}',
      ),
    config.teams
  ),
])
```

---

## Advanced Usage

### Custom Panel Library

**Create**: `ansible/roles/monitoring/files/dashboards/jsonnet/lib/jenkins-panels.libsonnet`

```jsonnet
local g = import 'grafonnet/gen/g.libsonnet';

{
  // Jenkins-specific panel templates
  buildSuccessRatePanel(team)::
    g.stat.new(
      title=team + ' Build Success Rate',
      targets=[
        g.target.prometheus.new(
          expr='sum(increase(jenkins_builds_success_total{jenkins_team="' + team + '"}[5m])) / sum(increase(jenkins_builds_started_total{jenkins_team="' + team + '"}[5m])) * 100',
          refId='A',
        ),
      ],
      unit='percent',
      decimals=1,
    )
    .addThresholds([
      { value: 0, color: 'red' },
      { value: 80, color: 'yellow' },
      { value: 95, color: 'green' },
    ]),

  queueLengthPanel(team)::
    g.timeSeries.new(
      title=team + ' Queue Length',
      targets=[
        g.target.prometheus.new(
          expr='jenkins_queue_size{jenkins_team="' + team + '"}',
          legendFormat='Queue Size',
          refId='A',
        ),
      ],
      unit='short',
    ),

  buildDurationHistogram(team)::
    g.timeSeries.new(
      title=team + ' Build Duration (P50, P95, P99)',
      targets=[
        g.target.prometheus.new(
          expr='histogram_quantile(0.50, sum(rate(jenkins_builds_duration_seconds_bucket{jenkins_team="' + team + '"}[5m])) by (le))',
          legendFormat='P50',
          refId='A',
        ),
        g.target.prometheus.new(
          expr='histogram_quantile(0.95, sum(rate(jenkins_builds_duration_seconds_bucket{jenkins_team="' + team + '"}[5m])) by (le))',
          legendFormat='P95',
          refId='B',
        ),
        g.target.prometheus.new(
          expr='histogram_quantile(0.99, sum(rate(jenkins_builds_duration_seconds_bucket{jenkins_team="' + team + '"}[5m])) by (le))',
          legendFormat='P99',
          refId='C',
        ),
      ],
      unit='s',
    ),
}
```

**Use in dashboards**:

```jsonnet
local jenkinsLib = import './lib/jenkins-panels.libsonnet';

jenkinsLib.buildSuccessRatePanel('devops')
jenkinsLib.queueLengthPanel('devops')
jenkinsLib.buildDurationHistogram('devops')
```

### Conditional Dashboard Elements

```jsonnet
local g = import 'grafonnet/gen/g.libsonnet';
local config = import './config.libsonnet';

// Conditional panel based on environment
local panels = [
  common.statPanel('Base Metric', 'up'),
]

// Add production-only panels
+ if config.environment == 'production' then [
  common.statPanel('SLA Compliance', 'sla_metric'),
  common.alertPanel('Critical Alerts', 'ALERTS{severity="critical"}'),
] else []

// Add development-only panels
+ if config.environment == 'development' then [
  common.statPanel('Debug Metrics', 'debug_metric'),
] else [];
```

### Multi-Dashboard Generation from Single Source

**Template**: `ansible/roles/monitoring/files/dashboards/jsonnet/multi-team-generator.jsonnet`

```jsonnet
local g = import 'grafonnet/gen/g.libsonnet';
local common = import './lib/common.libsonnet';
local config = import './config.libsonnet';

// Generate dashboard for each team
std.manifestYamlStream([
  {
    'team-' + team.name + '-dashboard.json': common.defaultDashboard(
      title=team.name + ' Dashboard',
      uid='team-' + team.name,
      team=team.name
    )
    .addPanels([
      common.statPanel(
        'Jenkins Up',
        'jenkins_up{jenkins_team="' + team.name + '"}'
      ),
    ])
  }
  for team in config.teams
])
```

### Version Control Integration

**Pre-commit hook** (`.git/hooks/pre-commit`):

```bash
#!/bin/bash
# Validate Jsonnet files before commit

echo "Validating Jsonnet syntax..."
find ansible/roles/monitoring/files/dashboards/jsonnet -name "*.jsonnet" -exec jsonnet -J vendor {} \; > /dev/null

if [ $? -ne 0 ]; then
    echo "ERROR: Jsonnet validation failed"
    exit 1
fi

echo "✓ Jsonnet validation passed"
```

---

## Troubleshooting

### Common Issues

#### 1. Import Not Found

**Error**: `RUNTIME ERROR: couldn't open import "grafonnet/gen/g.libsonnet"`

**Solution**:
```bash
# Install dependencies
cd /opt/grafonnet
/usr/local/bin/jb install

# Verify vendor/ directory exists
ls -la vendor/grafonnet/
```

#### 2. JSON Compilation Error

**Error**: `STATIC ERROR: Expected , got: }`

**Solution**:
```bash
# Check syntax manually
jsonnet -J vendor /opt/grafonnet/infrastructure-health.jsonnet

# Common causes:
# - Missing comma in array/object
# - Unmatched brackets/braces
# - Incorrect function parameters
```

#### 3. Dashboard Not Appearing in Grafana

**Solution**:
```bash
# 1. Check file exists
ls -la /opt/monitoring/grafana/dashboards-generated/*.json

# 2. Check Grafana container mount
docker exec grafana-production ls -la /var/lib/grafana/dashboards-generated/

# 3. Check provisioning config
docker exec grafana-production cat /etc/grafana/provisioning/dashboards/dashboard.yml

# 4. Check Grafana logs
docker logs grafana-production | grep -i dashboard

# 5. Force reload (restart Grafana)
docker restart grafana-production
```

#### 4. Permission Denied

**Error**: `Permission denied: /opt/monitoring/grafana/dashboards-generated/dashboard.json`

**Solution**:
```bash
# Fix ownership
sudo chown -R monitoring:monitoring /opt/monitoring/grafana/dashboards-generated/

# Fix permissions
sudo chmod 0755 /opt/monitoring/grafana/dashboards-generated/
sudo chmod 0644 /opt/monitoring/grafana/dashboards-generated/*.json
```

#### 5. External Repo Not Loading

**Error**: `jb install failed: unable to access repository`

**Solution**:
```bash
# 1. Check network connectivity
ping github.com

# 2. Test git clone manually
git clone https://github.com/grafana/grafonnet /tmp/test

# 3. Check credentials (for private repos)
# Use SSH keys or Personal Access Tokens
git config --global credential.helper store

# 4. Use specific version/tag
# Edit jsonnetfile.json
{
  "version": "v0.4.0"  // Instead of "main"
}
```

### Debugging Commands

```bash
# Validate Jsonnet syntax
jsonnet -J /opt/grafonnet/vendor \
  /opt/grafonnet/infrastructure-health.jsonnet

# Pretty-print output
jsonnet -J /opt/grafonnet/vendor \
  /opt/grafonnet/infrastructure-health.jsonnet | jq .

# Check dependencies
cd /opt/grafonnet
/usr/local/bin/jb list

# Update dependencies
/usr/local/bin/jb update

# Check generated dashboard JSON
python3 -m json.tool /opt/monitoring/grafana/dashboards-generated/infrastructure-health.json

# Validate dashboard structure
cat > /tmp/validate.py <<'EOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
    print(f"Title: {d['title']}")
    print(f"UID: {d['uid']}")
    print(f"Panels: {len(d['panels'])}")
    print(f"Variables: {len(d.get('templating', {}).get('list', []))}")
EOF

python3 /tmp/validate.py /opt/monitoring/grafana/dashboards-generated/infrastructure-health.json
```

### Manual Regeneration

```bash
# Full regeneration workflow

# 1. Backup current dashboards
cp -r /opt/monitoring/grafana/dashboards-generated /tmp/dashboards-backup

# 2. Clean output directory
rm -f /opt/monitoring/grafana/dashboards-generated/*.json

# 3. Recompile all dashboards
cd /opt/grafonnet
for file in *.jsonnet; do
    echo "Compiling $file..."
    jsonnet -J vendor "$file" -o "/opt/monitoring/grafana/dashboards-generated/$(basename $file .jsonnet).json"
done

# 4. Validate
find /opt/monitoring/grafana/dashboards-generated -name "*.json" -exec python3 -m json.tool {} \; > /dev/null

# 5. Fix permissions
sudo chown -R monitoring:monitoring /opt/monitoring/grafana/dashboards-generated/

# 6. Restart Grafana
docker restart grafana-production
```

---

## Best Practices

### 1. Version Control Everything
- Commit all `.jsonnet` files to Git
- Use `jsonnetfile.lock.json` for reproducible builds
- Tag releases for dashboard versions

### 2. Use Reusable Libraries
- Create `lib/` directory for common components
- Avoid code duplication across dashboards
- Share libraries across teams via Git

### 3. Test Before Deploying
- Validate JSON syntax locally
- Use `--check` mode for Ansible deployments
- Review generated JSON before applying

### 4. Document Dashboards
- Add comments in `.jsonnet` files
- Include dashboard description in metadata
- Maintain README for custom libraries

### 5. Automate Updates
- Use CI/CD to regenerate dashboards
- Auto-test dashboard changes
- Deploy via GitOps workflows

---

## Quick Reference

### File Locations

| Purpose | Path |
|---------|------|
| Jsonnet source files | `/opt/grafonnet/*.jsonnet` |
| Dependencies definition | `/opt/grafonnet/jsonnetfile.json` |
| Downloaded libraries | `/opt/grafonnet/vendor/` |
| Local libraries | `/opt/grafonnet/lib/` |
| Generated dashboards | `/opt/monitoring/grafana/dashboards-generated/` |
| Dashboard backups | `/opt/monitoring/grafana/dashboards-generated/.backups/` |
| Grafana container mount | `/var/lib/grafana/dashboards-generated/` |

### Key Commands

```bash
# Install dependencies
cd /opt/grafonnet && jb install

# Compile single dashboard
jsonnet -J vendor dashboard.jsonnet -o output.json

# Compile all dashboards
ansible-playbook site.yml --tags monitoring,grafonnet,generate

# Validate JSON
python3 -m json.tool dashboard.json

# View in Grafana
# http://grafana-url:9300/dashboards → "Generated" folder
```

---

## See Also

- [Official Grafonnet Documentation](https://github.com/grafana/grafonnet)
- [Jsonnet Tutorial](https://jsonnet.org/learning/tutorial.html)
- [Jsonnet Bundler](https://github.com/jsonnet-bundler/jsonnet-bundler)
- [CLAUDE.md](../CLAUDE.md) - Project documentation
- [Monitoring Modernization Guide](monitoring-modernization-guide.md)
