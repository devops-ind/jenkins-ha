# Jenkins HA Team Filtering - Usage Guide

## Quick Start

The Jenkins HA infrastructure now supports robust team filtering for selective deployments.

### Deploy Specific Teams
```bash
# Deploy only devops team
ansible-playbook ansible/site.yml -i ansible/inventories/production/hosts.yml -e deploy_teams=devops

# Deploy multiple teams
ansible-playbook ansible/site.yml -i ansible/inventories/production/hosts.yml -e deploy_teams="devops,dev-qa"

# Deploy with make
make deploy-production -e deploy_teams=devops
```

### Exclude Specific Teams
```bash
# Deploy all teams except frontend
ansible-playbook ansible/site.yml -i ansible/inventories/production/hosts.yml -e exclude_teams=frontend

# Exclude multiple teams
ansible-playbook ansible/site.yml -i ansible/inventories/production/hosts.yml -e exclude_teams="frontend,test"
```

### Deploy All Teams (Default)
```bash
# Deploy everything - no filtering
ansible-playbook ansible/site.yml -i ansible/inventories/production/hosts.yml

# Explicit all teams
make deploy-production
```

## Component-Specific Filtering

### HAProxy Load Balancer Only
```bash
# Update HAProxy for specific teams
ansible-playbook ansible/site.yml --tags ha -e deploy_teams=devops
```

### Monitoring Stack Only  
```bash
# Update monitoring for specific teams
ansible-playbook ansible/site.yml --tags monitoring -e deploy_teams=devops
```

### SSL Certificates Only
```bash
# Generate SSL certificates for specific teams
ansible-playbook ansible/site.yml --tags ssl -e deploy_teams=devops
```

## Testing and Validation

### Dry Run (Check Mode)
```bash
# Test team filtering without making changes
ansible-playbook ansible/site.yml --check -e deploy_teams=devops
```

### Validate Team Configuration
```bash
# Run our comprehensive test suite
ansible-playbook test-team-filtering.yml
```

## Team Configuration

Teams are defined in `ansible/group_vars/all/jenkins_teams.yml`:

```yaml
jenkins_teams:
  - team_name: devops          # ← This is what you filter on
    active_environment: green
    ports:
      web: 8080
    # ... other configuration

  - team_name: dev-qa          # ← This is what you filter on
    active_environment: blue  
    ports:
      web: 8089
    # ... other configuration
```

## Access URLs After Filtering

### With `deploy_teams=devops`:
- HAProxy: `http://your-server:8000`
- Devops Team: `http://devopsjenkins.your-domain.com`
- Monitoring: `http://your-server:9090` (Prometheus)

### With `deploy_teams=devops,dev-qa`:
- HAProxy: `http://your-server:8000` 
- Devops Team: `http://devopsjenkins.your-domain.com`
- Dev-QA Team: `http://dev-qajenkins.your-domain.com`
- Monitoring: `http://your-server:9090` (Prometheus)

## Troubleshooting

### Check Team Filtering Results
```bash
# See which teams were selected
ansible-playbook ansible/site.yml --tags verify -e deploy_teams=devops -v
```

### Validate Team Objects
```bash
# Run the validation test
ansible-playbook test-team-filtering.yml -e deploy_teams=your-teams
```

### Common Issues

#### "No teams to deploy" 
- Check team names in `jenkins_teams.yml`
- Ensure exact name matching (case-sensitive)
- Verify syntax: `deploy_teams="team1,team2"` (no spaces around commas)

#### HAProxy backend errors
- All team objects are now validated before template processing
- Check the defensive programming logs for specific issues

#### SSL certificate issues
- SSL generation now includes only filtered teams
- Certificates are automatically updated when teams change

## Best Practices

1. **Test First**: Always use `--check` for dry runs
2. **Team Names**: Use consistent, simple team names (alphanumeric, hyphens)
3. **Incremental Deployment**: Deploy one team at a time for validation
4. **Monitor Results**: Check HAProxy stats and team accessibility after deployment
5. **Use Variables**: Define team lists in inventory files for repeatability

```yaml
# In your inventory
jenkins_deploy_teams: "devops,dev-qa"
```

```bash
# Use in deployment
ansible-playbook ansible/site.yml -e deploy_teams="{{ jenkins_deploy_teams }}"
```

## Production Deployment Examples

### Rolling Team Deployment
```bash
# Phase 1: Deploy core infrastructure team
ansible-playbook ansible/site.yml -e deploy_teams=devops

# Phase 2: Add development teams
ansible-playbook ansible/site.yml -e deploy_teams="devops,dev-qa"

# Phase 3: Add all production teams
ansible-playbook ansible/site.yml -e deploy_teams="devops,dev-qa,frontend,backend"
```

### Maintenance Mode
```bash
# Remove specific team for maintenance
ansible-playbook ansible/site.yml -e exclude_teams=frontend

# Restore after maintenance
ansible-playbook ansible/site.yml  # All teams active
```

The robust team filtering architecture ensures reliable, predictable deployments across all Jenkins HA infrastructure components.