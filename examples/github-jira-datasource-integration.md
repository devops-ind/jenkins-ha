# GitHub Enterprise & Jira Cloud Datasource Integration

**Date**: October 24, 2025
**Status**: ✅ Production Ready
**Version**: 1.0
**Deployment Mode**: Docker-based Grafana with provisioned datasources

---

## Overview

This guide explains how to integrate GitHub Enterprise and Jira Cloud datasources into your Grafana monitoring stack. These plugins enable you to:

- **GitHub Metrics**: Monitor repository activity, pull requests, code reviews, and GitHub Actions workflows
- **Jira Metrics**: Track sprint progress, issue status, team velocity, and bug metrics
- **Correlation**: Link code changes to project management issues for end-to-end visibility

### Key Features

✅ Automated datasource provisioning via Ansible
✅ Secure credential management with Vault
✅ Pre-built dashboard with 10 panels
✅ Team-agnostic repository monitoring
✅ Sprint progress tracking and burndown
✅ Workflow status visualization

---

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│ Grafana Container (Port 9300)                              │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Installed Plugins:                                    │  │
│  │  • grafana-github-datasource (GitHub Enterprise)     │  │
│  │  • grafana-jira-datasource (Jira Cloud)              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Provisioned Datasources:                             │  │
│  │  • GitHub Enterprise (github-enterprise)             │  │
│  │  • Jira Cloud (jira-cloud)                           │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Dashboard: GitHub & Jira Metrics                     │  │
│  │  • Repository commit activity (timeseries)           │  │
│  │  • PR status by repository (table)                   │  │
│  │  • GitHub Actions success rate (pie chart)           │  │
│  │  • Open PRs count (stat)                             │  │
│  │  • Code review comments (stat)                       │  │
│  │  • Sprint progress trend (timeseries)                │  │
│  │  • Issue status distribution (pie chart)             │  │
│  │  • Active sprint issues (table)                      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
       ↑                                    ↑
       │                                    │
       │                                    │
  GitHub Enterprise                     Jira Cloud
  (github.yourcompany.com)              (atlassian.net)
  Token: ghp_xxxxx                      Email + Token
```

### Data Flow

```
┌──────────────────┐
│ GitHub Enterprise│
│  Repositories    │
│  PRs             │
│  Workflows       │
│  Issues          │
└────────┬─────────┘
         │
         │ GitHub API v3/GraphQL
         │
         ↓
┌──────────────────────────────────────┐
│   Grafana GitHub Datasource Plugin   │
│   (grafana-github-datasource)        │
│   UID: github-enterprise             │
│   Auth: Personal Access Token        │
└────────┬─────────────────────────────┘
         │
         │ Query Results
         │
         ↓
┌──────────────────────────────────────┐
│   GitHub & Jira Metrics Dashboard    │
│   • 10 visualization panels          │
│   • Real-time metrics                │
│   • 5-minute refresh interval        │
└──────────────────────────────────────┘
```

---

## Prerequisites

### Required

1. **Grafana Running**: Container deployed at `http://localhost:9300` or accessible hostname
2. **GitHub Enterprise Account**: Access to GitHub Enterprise instance
3. **GitHub Personal Access Token**: With scopes: `repo`, `read:org`, `workflow`
4. **Jira Cloud Account**: Access to atlassian.net instance
5. **Jira API Token**: Generated at https://id.atlassian.com/manage-profile/security/api-tokens
6. **Ansible Vault**: Credentials stored in `ansible/inventories/production/group_vars/all/vault.yml`

### Knowledge Required

- Jira JQL (Jira Query Language) - for writing custom issue queries
- GitHub repository names and organization structure
- Jira project keys (e.g., DEVOPS, INFRA, etc.)

---

## Installation & Deployment

### Step 1: Store Credentials in Vault

The credentials should be stored in your Ansible Vault file at:
`ansible/inventories/production/group_vars/all/vault.yml`

**Required variables**:

```yaml
# GitHub Enterprise
vault_github_enterprise_url: "https://github.yourcompany.com"
vault_github_enterprise_org: "your-organization"
vault_github_enterprise_repos:
  - "org/repo1"
  - "org/repo2"
  - "org/platform-*"  # Supports wildcards
vault_github_enterprise_token: "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # 40+ char token

# Jira Cloud
vault_jira_cloud_url: "https://yourcompany.atlassian.net"
vault_jira_cloud_email: "your-email@company.com"
vault_jira_cloud_projects:
  - "DEVOPS"
  - "INFRA"
  - "PLATFORM"
vault_jira_cloud_token: "xxxxxxxxxxxxxxxxxxxxx"  # Jira API token (32+ chars)
```

**To Encrypt Credentials**:

```bash
# Edit vault file (will prompt for password)
ansible-vault edit ansible/inventories/production/group_vars/all/vault.yml

# View encrypted content
ansible-vault view ansible/inventories/production/group_vars/all/vault.yml

# Re-encrypt if password changes
ansible-vault rekey ansible/inventories/production/group_vars/all/vault.yml
```

### Step 2: Deploy Grafana with Plugins

The plugins are automatically installed via the `GF_INSTALL_PLUGINS` environment variable.

**Deploy monitoring stack**:

```bash
# Full deployment with plugins
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring

# Or target just Grafana if already deployed
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring --limit monitoring_servers

# With vault password prompt
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags monitoring --ask-vault-pass
```

### Step 3: Verify Plugin Installation

```bash
# List installed plugins in Grafana container
docker exec grafana-production grafana-cli plugin ls

# Expected output:
# grafana-github-datasource @ 1.3.9 (grafana-plugin)
# grafana-jira-datasource @ 1.x.x (grafana-plugin)

# Check Grafana logs for plugin loading
docker logs grafana-production | grep -i plugin

# Verify datasources are provisioned
curl -u admin:password http://localhost:9300/api/datasources | jq '.'

# Expected datasources in response:
# {
#   "id": 3,
#   "uid": "github-enterprise",
#   "name": "GitHub Enterprise",
#   "type": "grafana-github-datasource",
#   "access": "proxy",
#   "basicAuth": false,
#   "isDefault": false
# }
# {
#   "id": 4,
#   "uid": "jira-cloud",
#   "name": "Jira Cloud",
#   "type": "grafana-jira-datasource",
#   "access": "proxy",
#   "basicAuth": false,
#   "isDefault": false
# }
```

### Step 4: Access Datasources in Grafana

1. Open Grafana: http://localhost:9300
2. Login with admin credentials
3. Go to **Connections → Datasources**
4. Verify **GitHub Enterprise** and **Jira Cloud** are listed and connected
5. Click each to verify authentication succeeded

---

## Dashboard: GitHub & Jira Metrics

### Location

- **Dashboard Name**: `GitHub & Jira Metrics`
- **UID**: `github-jira-metrics`
- **URL**: `http://localhost:9300/d/github-jira-metrics`
- **Category**: Enhanced
- **Template File**: `dashboards/github-jira-metrics.json.j2`

### Panel Descriptions

#### GitHub Metrics Row

**1. Repository Commit Activity** (Timeseries)
- **Purpose**: Track commit frequency across repositories
- **Datasource**: GitHub Enterprise
- **Time Range**: 30 days (customizable)
- **Refresh**: 5 minutes
- **Metrics Shown**:
  - Commits per repository
  - Trends over time
  - Peak activity identification

**2. Pull Request Status by Repository** (Table)
- **Purpose**: Show current PR health across repos
- **Columns**:
  - Repository name
  - Open PRs count (color-coded by threshold)
  - Merged PRs (30-day count)
  - Avg review time
  - Avg time to merge

**3. GitHub Actions Workflow Success Rate** (Pie Chart)
- **Purpose**: Visualize CI/CD pipeline health
- **Breakdown**:
  - Successful runs (green)
  - Failed runs (red)
  - Cancelled runs (gray)
- **Use Case**: Quick health check of automated pipelines

**4. Open Pull Requests** (Stat)
- **Purpose**: Real-time count of pending reviews
- **Color Coding**:
  - Green: < 5 open PRs (healthy)
  - Yellow: 5-10 PRs (review backlog)
  - Red: > 10 PRs (action needed)

**5. Code Review Comments** (Stat)
- **Purpose**: Track code review activity
- **Indicates**: Team engagement in reviews
- **Use Case**: Monitor review velocity

#### Jira Metrics Row

**6. Sprint Progress Over Time** (Timeseries)
- **Purpose**: Burndown trend across active sprints
- **Metrics**:
  - To Do items
  - In Progress items
  - Completed items
- **Use Case**: Identify sprint velocity and trends
- **Color Coding**:
  - Orange: To Do
  - Blue: In Progress
  - Green: Done

**7. Issue Status Distribution** (Pie Chart)
- **Purpose**: Breakdown of all open issues by status
- **Shows**: Blocker, Critical, High, Medium, Low issues
- **Use Case**: Understand issue backlog composition
- **Filter**: Current sprint view

**8. Active Sprint Issues** (Table)
- **Purpose**: List all issues in current active sprint
- **Columns**:
  - Issue Key (DEVOPS-123)
  - Issue Title
  - Issue Type (Bug, Task, Story)
  - Status (To Do, In Progress, Done)
  - Assignee
  - Priority (color-coded)
  - Story Points
- **Sorting**: By priority (descending)
- **Use Case**: Sprint execution tracking

### Dashboard Variables

The dashboard includes two datasource variables for flexibility:

```json
{
  "name": "github_ds",
  "label": "GitHub Datasource",
  "type": "datasource",
  "query": "grafana-github-datasource",
  "current": "github-enterprise"
}

{
  "name": "jira_ds",
  "label": "Jira Datasource",
  "type": "datasource",
  "query": "grafana-jira-datasource",
  "current": "jira-cloud"
}
```

These allow switching between multiple GitHub or Jira instances if configured.

---

## Configuration Files

### 1. Plugin Installation

**File**: `ansible/roles/monitoring/tasks/phase3-servers/grafana.yml`

The `GF_INSTALL_PLUGINS` environment variable triggers automatic installation:

```yaml
env:
  GF_INSTALL_PLUGINS: "grafana-github-datasource,grafana-jira-datasource"
```

### 2. Plugin Provisioning

**File**: `ansible/roles/monitoring/templates/plugins/plugins.yml.j2`

Enables plugins and sets plugin-level configurations:

```yaml
apps:
  - type: grafana-github-datasource
    org_id: 1
    disabled: false
    settings:
      githubUrl: "{{ github_enterprise_url }}"
      tokenConfigured: "true"

  - type: grafana-jira-datasource
    org_id: 1
    disabled: false
    settings:
      jiraUrl: "{{ jira_cloud_url }}"
      tokenConfigured: "true"
```

### 3. GitHub Datasource Configuration

**File**: `ansible/roles/monitoring/templates/datasources/github-datasource.yml.j2`

Provisions the GitHub Enterprise datasource:

```yaml
datasources:
  - name: GitHub Enterprise
    type: grafana-github-datasource
    uid: github-enterprise
    jsonData:
      githubUrl: "{{ github_enterprise_url }}"
      organization: "{{ github_enterprise_org }}"
      repositories: {{ github_enterprise_repos | to_json }}
      cacheTimeInSeconds: 300
    secureJsonData:
      accessToken: "{{ github_enterprise_token }}"
```

### 4. Jira Datasource Configuration

**File**: `ansible/roles/monitoring/templates/datasources/jira-datasource.yml.j2`

Provisions the Jira Cloud datasource:

```yaml
datasources:
  - name: Jira Cloud
    type: grafana-jira-datasource
    uid: jira-cloud
    jsonData:
      url: "{{ jira_cloud_url }}"
      username: "{{ jira_cloud_email }}"
      projects: {{ jira_cloud_projects | to_json }}
    secureJsonData:
      apiToken: "{{ jira_cloud_token }}"
```

---

## Query Examples

### GitHub Queries

These examples show typical queries used in the dashboard:

```
# Repository commits (GitHub GraphQL)
Commit frequency for organization repositories

# Pull request metrics
Pull requests merged in last 30 days by repository

# Workflow status
GitHub Actions runs - success rate for all workflows

# Issue trending
Open security issues by repository
```

### Jira Queries

Jira uses JQL (Jira Query Language) for queries:

```jql
# Current sprint
project in (DEVOPS, INFRA, PLATFORM) AND sprint = activeSprints()

# Sprint burndown data
project in (DEVOPS) AND status in (Todo, "In Progress", Done)

# Velocity metric
project = DEVOPS AND sprint = (previous(3)) AND status = Done

# Bug tracking
project in (DEVOPS) AND issuetype = Bug AND status = Open

# Team capacity
project = DEVOPS AND assignee in (userMatching('team-devops'))

# Aging issues
project = DEVOPS AND created < -30d AND status != Done

# High priority backlog
project in (DEVOPS, INFRA) AND priority >= High AND status = Todo
ORDER BY priority DESC
```

---

## Troubleshooting

### Issue: Plugins Not Installing

**Symptom**: Plugins not listed after deployment

**Solution**:

1. Check Grafana logs:
   ```bash
   docker logs grafana-production | grep -i plugin
   ```

2. Verify environment variable is set:
   ```bash
   docker inspect grafana-production | grep GF_INSTALL_PLUGINS
   ```

3. Restart Grafana:
   ```bash
   docker restart grafana-production
   ```

4. Wait 30-60 seconds for plugins to download and install

### Issue: "Datasource not found" Error in Queries

**Symptom**: Dashboard panels fail with "datasource not found"

**Solution**:

1. Verify datasources are provisioned:
   ```bash
   curl -u admin:password http://localhost:9300/api/datasources | jq '.[] | {name, type, uid}'
   ```

2. Check if UIDs match in dashboard JSON and datasource config:
   - GitHub: Should be `github-enterprise`
   - Jira: Should be `jira-cloud`

3. Verify dashboard template uses correct UIDs:
   ```json
   "datasource": {
     "type": "grafana-github-datasource",
     "uid": "github-enterprise"
   }
   ```

### Issue: Authentication Failures

**Symptom**: Red "Authentication Failed" in datasource health check

**GitHub**:
- Verify token scope: `repo`, `read:org`, `workflow`
- Check token expiration at https://github.yourcompany.com/settings/tokens
- Regenerate if needed

**Jira**:
- Verify email matches Jira account email
- Regenerate API token at https://id.atlassian.com/manage-profile/security/api-tokens
- Ensure token has `read:jira-work` scope

### Issue: No Data Appearing in Panels

**Symptom**: Dashboard loads but panels show no data

**Solution**:

1. Verify datasources have test data:
   ```bash
   # GitHub test
   curl -H "Authorization: token {{ github_enterprise_token }}" \
     https://github.yourcompany.com/api/v3/user/repos | head -n 20

   # Jira test
   curl -u {{ jira_cloud_email }}:{{ jira_cloud_token }} \
     https://{{ jira_cloud_url }}/rest/api/3/myself | jq '.displayName'
   ```

2. Check query syntax:
   - GitHub: Ensure repositories are correctly formatted
   - Jira: Test JQL at https://yourcompany.atlassian.net/browse/

3. Verify data exists:
   - Do repositories have commits in last 30 days?
   - Are there active sprints in Jira?

### Issue: Rate Limiting

**Symptom**: "API rate limit exceeded" in logs

**Solution**:

- **GitHub**: Personal Access Token has higher rate limits
  - Unauthenticated: 60 requests/hour
  - Authenticated: 5,000 requests/hour

- **Jira**: Cloud API has rate limits
  - Free tier: 180 requests/minute
  - Upgrade plan if needed

### Issue: Cross-Origin (CORS) Errors

**Symptom**: Browser console shows CORS errors

**Solution**:

Grafana's proxy mode (`access: proxy`) handles CORS automatically. If you see errors:

1. Ensure datasource is set to `access: proxy` (not `direct`)
2. Verify Grafana container can reach GitHub/Jira URLs
3. Check firewall rules between Grafana and external services

---

## Security Considerations

### Credential Management

- **Vault Storage**: All tokens stored in encrypted Ansible Vault
- **Environment Variables**: Tokens passed to Grafana via secure Docker configuration
- **Grafana Security**: Datasource passwords stored in Grafana's encrypted database
- **Network**: Use HTTPS for all external communications

### Token Rotation

**GitHub Enterprise Token Rotation** (every 90 days recommended):

1. Generate new token at `https://github.yourcompany.com/settings/tokens`
2. Update `vault_github_enterprise_token` in Vault
3. Re-encrypt: `ansible-vault edit ansible/inventories/production/group_vars/all/vault.yml`
4. Redeploy: `ansible-playbook -i inventory site.yml --tags monitoring`
5. Delete old token from GitHub

**Jira API Token Rotation** (every 90 days recommended):

1. Generate new token at `https://id.atlassian.com/manage-profile/security/api-tokens`
2. Update `vault_jira_cloud_token` in Vault
3. Follow same process as GitHub

### Access Control

- **Grafana RBAC**: Configure user roles to restrict dashboard access
- **GitHub RBAC**: Token scopes limit what GitHub API calls can do
- **Jira RBAC**: Jira project permissions respected in datasource

---

## Maintenance

### Regular Tasks

- **Weekly**: Monitor dashboard for anomalies
- **Monthly**: Review GitHub workflow failures
- **Quarterly**: Rotate authentication tokens
- **Quarterly**: Update Grafana plugin versions
- **Quarterly**: Review and archive old sprint data in Jira

### Plugin Updates

To update plugins to latest versions:

```bash
# Update GF_INSTALL_PLUGINS to include version
# In grafana.yml, change:
GF_INSTALL_PLUGINS: "grafana-github-datasource@latest,grafana-jira-datasource@latest"

# Then redeploy
ansible-playbook -i inventory site.yml --tags monitoring

# Or manually update via CLI
docker exec grafana-production grafana-cli plugin update grafana-github-datasource
docker exec grafana-production grafana-cli plugin update grafana-jira-datasource
```

### Backup & Recovery

Datasource credentials are stored in Grafana's database:

```bash
# Backup Grafana database (included in monitoring backup)
docker exec grafana-production tar czf /var/lib/grafana/grafana-backup.tar.gz /var/lib/grafana/

# Restore from backup
docker cp grafana-production:/var/lib/grafana/grafana-backup.tar.gz ./
# Stop Grafana, restore, restart
```

---

## References

- **Grafana GitHub Datasource**: https://grafana.com/grafana/plugins/grafana-github-datasource/
- **Grafana Jira Datasource**: https://grafana.com/grafana/plugins/grafana-jira-datasource/
- **GitHub Enterprise API**: https://docs.github.com/en/enterprise-server@latest/rest
- **GitHub GraphQL API**: https://docs.github.com/en/graphql
- **Jira Cloud API**: https://developer.atlassian.com/cloud/jira/rest/
- **JQL Reference**: https://support.atlassian.com/jira-software-cloud/articles/advanced-searching-issues-in-jira/
- **Grafana Provisioning**: https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/provision-grafana/

---

## Support & Issues

For problems or questions:

1. **Check Logs**: `docker logs grafana-production`
2. **Test Connectivity**: Verify firewall/network access to GitHub/Jira
3. **Verify Credentials**: Test tokens manually with curl commands
4. **Check Dashboard Template**: Verify datasource UIDs in dashboard JSON
5. **Review Configuration**: Ensure provisioning YAML files are correctly rendered

See troubleshooting section above for detailed solutions.
