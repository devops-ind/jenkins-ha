# Jenkins Master Role Migration Guide

## Overview

**Migration Complete:** The `jenkins-infrastructure` role has been removed and replaced with the unified `jenkins-master` role. This document serves as historical reference for understanding the migration process.

## Benefits of the New Role

### Before (jenkins-infrastructure - REMOVED)
- **Code Duplication**: 60% overlap between Docker/Podman implementations
- **Monolithic Design**: Single 322-line main.yml file
- **Team-Specific Configuration**: Hard-coded team settings in role logic
- **Limited Reusability**: Adding teams requires role modification

### After (jenkins-master)
- **Universal Container Support**: Single deployment logic for Docker/Podman
- **Modular Architecture**: 8 focused task files instead of 1 monolithic file
- **Team-Agnostic**: Add teams through inventory variables only
- **Standardized Configuration**: Consistent variable patterns across teams

## Migration Strategy

### Phase 1: Parallel Deployment (Recommended)

1. **Keep Existing Role**: Maintain `jenkins-master` role during transition
2. **Deploy New Role**: Test `jenkins-master` role with one team in staging
3. **Validate Functionality**: Ensure blue-green deployment works correctly
4. **Gradual Migration**: Move teams one by one to new role
5. **Archive Old Role**: Remove `jenkins-master` after successful migration

### Phase 2: Direct Migration (Advanced)

1. **Backup Current Setup**: Export team configurations and data
2. **Replace Role**: Switch from `jenkins-master` to `jenkins-master`
3. **Update Inventory**: Convert team configurations to new variable structure
4. **Deploy and Test**: Validate all teams function correctly

## Variable Structure Changes

### Old Configuration (jenkins-master)
```yaml
# ansible/roles/jenkins-master/defaults/main.yml
jenkins_teams:
  - name: "devops"
    port: 8080
    agent_port: 50000
    memory: "3g"
    cpu_limit: "2.0"
    active_environment: "blue"
  - name: "developer"
    port: 8081
    agent_port: 50001
    memory: "2g"
    cpu_limit: "1.5"
    active_environment: "blue"
```

### New Configuration (jenkins-master)
```yaml
# Per-team deployment in playbook
- name: Deploy DevOps Team Jenkins Master
  hosts: jenkins_masters
  vars:
    jenkins_master_config:
      team_name: "devops"
      active_environment: "blue"
      ports:
        web: 8080
        agent: 50000
      resources:
        memory: "3g"
        cpu: "2.0"
      env_vars:
        JENKINS_TEAM: "devops"
      labels:
        team: "devops"
        tier: "production"
  roles:
    - jenkins-master

- name: Deploy Developer Team Jenkins Master  
  hosts: jenkins_masters
  vars:
    jenkins_master_config:
      team_name: "developer"
      active_environment: "blue"
      ports:
        web: 8081
        agent: 50001
      resources:
        memory: "2g"
        cpu: "1.5"
      env_vars:
        JENKINS_TEAM: "developer"
      labels:
        team: "developer"
        tier: "production"
  roles:
    - jenkins-master
```

## Step-by-Step Migration

### Step 1: Backup Current Configuration

```bash
# Create backup directory
mkdir -p migration-backup/$(date +%Y%m%d)

# Backup current role
cp -r ansible/roles/jenkins-master migration-backup/$(date +%Y%m%d)/

# Backup current site.yml
cp ansible/site.yml migration-backup/$(date +%Y%m%d)/site.yml.backup

# Export current Jenkins data (if needed)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/playbooks/backup.yml --tags jenkins
```

### Step 2: Create New Role Structure

The new `jenkins-master` role is already created with the following structure:
```
ansible/roles/jenkins-master/
├── tasks/
│   ├── main.yml              # Entry point
│   ├── validate.yml          # Input validation
│   ├── configuration.yml     # System setup
│   ├── networking.yml        # Network configuration
│   ├── container.yml         # Container management
│   ├── blue-green.yml        # Blue-green deployment
│   ├── health-check.yml      # Health validation
│   ├── cleanup.yml           # Maintenance
│   ├── volumes/
│   │   ├── docker.yml        # Docker volume management
│   │   └── podman.yml        # Podman volume management
│   └── containers/
│       ├── docker.yml        # Docker container deployment
│       └── podman.yml        # Podman container deployment
├── defaults/main.yml         # Default variables
├── vars/main.yml            # Internal variables
├── handlers/main.yml        # Event handlers
└── templates/               # Configuration templates
```

### Step 3: Update Inventory Variables

Convert your existing team configurations to the new structure:

#### Before
```yaml
# group_vars/all/jenkins.yml
jenkins_teams:
  - name: "devops"
    port: 8080
    agent_port: 50000
    memory: "3g"
    cpu_limit: "2.0"
    active_environment: "blue"
```

#### After
```yaml
# group_vars/all/jenkins-teams.yml
jenkins_teams:
  devops:
    team_name: "devops"
    active_environment: "blue"
    ports:
      web: 8080
      agent: 50000
    resources:
      memory: "3g"
      cpu: "2.0"
    env_vars:
      JENKINS_TEAM: "devops"
    labels:
      team: "devops"
      tier: "production"
```

### Step 4: Update Site Playbook

Replace the jenkins-master deployment section with individual team deployments:

#### Before
```yaml
- name: Deploy Jenkins Infrastructure
  hosts: jenkins_masters
  roles:
    - role: jenkins-master
      tags: ['jenkins', 'deploy']
```

#### After
```yaml
- name: Deploy Jenkins Teams
  include: playbooks/deploy-jenkins-teams.yml
  tags: ['jenkins', 'deploy']
```

Create `playbooks/deploy-jenkins-teams.yml`:
```yaml
---
- name: Deploy DevOps Team Jenkins Master
  hosts: jenkins_masters
  vars:
    jenkins_master_config: "{{ jenkins_teams.devops }}"
  roles:
    - jenkins-master

- name: Deploy Developer Team Jenkins Master
  hosts: jenkins_masters
  vars:
    jenkins_master_config: "{{ jenkins_teams.developer }}"
  roles:
    - jenkins-master
```

### Step 5: Test in Staging

```bash
# Test new role in staging
ansible-playbook -i ansible/inventories/staging/hosts.yml \
  ansible/site-new.yml --limit jenkins_masters --tags jenkins,devops

# Validate deployment
ansible-playbook -i ansible/inventories/staging/hosts.yml \
  tests/jenkins-master-test.yml
```

### Step 6: Validate Functionality

```bash
# Check team health
/var/jenkins/scripts/blue-green-healthcheck-devops.sh health

# Test blue-green switch
/var/jenkins/scripts/blue-green-switch-devops.sh switch

# Verify HAProxy integration
curl -f http://jenkins-master:8080/login
```

### Step 7: Production Migration

```bash
# Deploy to production (one team at a time)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site-new.yml --limit jenkins_masters --tags jenkins,devops

# Verify before proceeding to next team
/var/jenkins/scripts/blue-green-healthcheck-devops.sh health

# Deploy next team
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site-new.yml --limit jenkins_masters --tags jenkins,developer
```

## Key Differences and Considerations

### Configuration Management
- **Old**: All teams configured in single role defaults
- **New**: Each team configured as separate play with individual variables

### Container Management
- **Old**: Separate tasks for Docker and Podman with duplication
- **New**: Universal container management with runtime-specific includes

### Blue-Green Deployment
- **Old**: Embedded in main container deployment logic
- **New**: Separate blue-green.yml with dedicated management scripts

### Health Monitoring
- **Old**: Basic health checks integrated with deployment
- **New**: Comprehensive health monitoring with detailed scripts and logging

### Script Management
- **Old**: Shared scripts for all teams
- **New**: Team-specific scripts with individual configuration

## Validation Checklist

After migration, verify:

- [ ] All teams accessible on correct ports
- [ ] Blue-green switching works for each team
- [ ] Health checks pass for all environments
- [ ] HAProxy routing functions correctly
- [ ] Dynamic agents provision successfully
- [ ] Monitoring integration works
- [ ] Backup procedures function
- [ ] Team-specific configurations applied
- [ ] Management scripts executable and functional

## Troubleshooting

### Common Issues

1. **Port Conflicts**
   - Ensure unique ports for each team
   - Check firewall rules allow new port ranges

2. **Container Runtime Issues**
   - Verify Docker/Podman service running
   - Check container runtime specified correctly in variables

3. **Volume Permissions**
   - Ensure jenkins user has correct ownership
   - Verify volume mount paths exist

4. **Network Configuration**
   - Check Jenkins network exists and accessible
   - Verify container-to-container communication

5. **Blue-Green State**
   - Validate blue-green-state.json files created
   - Check active environment matches expectations

### Rollback Procedure

If issues occur during migration:

```bash
# Stop new containers
for team in devops developer qa; do
  podman stop jenkins-${team}-blue jenkins-${team}-green 2>/dev/null || true
done

# Restore original site.yml
cp migration-backup/$(date +%Y%m%d)/site.yml.backup ansible/site.yml

# Redeploy with original role
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins
```

## Support and Resources

- **Role Documentation**: `ansible/roles/jenkins-master/README.md`
- **Example Playbooks**: `ansible/site-new.yml`
- **Team Scripts**: `/var/jenkins/scripts/`
- **Health Monitoring**: `/var/jenkins/logs/health-monitor-{team}.log`
- **Blue-Green State**: `/var/jenkins/{team}/blue-green-state.json`

## Next Steps

After successful migration:

1. **Archive Old Role**: Move `jenkins-master` to archive directory
2. **Update Documentation**: Update team onboarding procedures
3. **Train Teams**: Provide training on new management scripts
4. **Monitor Performance**: Track resource usage and performance improvements
5. **Continuous Improvement**: Gather feedback and enhance role functionality