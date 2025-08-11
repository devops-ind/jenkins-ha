# Ansible Playbook Quick Reference

## 🎯 Main Deployments

### Full Infrastructure
```bash
# Production deployment
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

# Staging deployment  
ansible-playbook -i ansible/inventories/staging/hosts.yml ansible/site.yml

# Local development
ansible-playbook ansible/deploy-local.yml
```

### Component Deployments
```bash
# Backup system only
ansible-playbook -i inventory/production/hosts.yml ansible/deploy-backup.yml

# Monitoring stack only
ansible-playbook -i inventory/production/hosts.yml ansible/deploy-monitoring.yml

# Image building only
ansible-playbook -i inventory/production/hosts.yml ansible/deploy-images.yml
```

## 🔄 Blue-Green Operations

### Environment Status
```bash
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=status
```

### Environment Switching
```bash
# Switch single team to green
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=switch -e environment=green -e team_filter=devops

# Switch all teams to green
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e batch_blue_green_operation=switch-all -e batch_target_environment=green

# Rollback team to previous environment
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=rollback -e team_filter=devops
```

### Health Checks
```bash
# Health check single team
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e blue_green_operation=health-check -e team_filter=qa

# Health check all teams  
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/blue-green-operations.yml \
  -e batch_blue_green_operation=health-check-all
```

## 🚨 Disaster Recovery

### Infrastructure Assessment
```bash
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=assess
```

### Backup Restoration
```bash
# Dry run restore (preview)
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=restore -e backup_timestamp=latest -e dr_dry_run=true

# Actual restore (DESTRUCTIVE)
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=restore -e backup_timestamp=2024-01-15-14-30 -e dr_dry_run=false
```

### Emergency Failover
```bash
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=failover -e failover_environment=green
```

### Recovery Testing
```bash
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/disaster-recovery.yml \
  -e dr_operation=test-recovery
```

## 🔧 Server Management

### Bootstrap New Servers
```bash
ansible-playbook -i inventory/production/hosts.yml ansible/playbooks/bootstrap.yml
```

## 🛡️ Common Safety Options

### Pre-flight Checks
```bash
# Syntax check
ansible-playbook --syntax-check playbook.yml

# Dry run
ansible-playbook playbook.yml --check

# Test connectivity
ansible all -i inventory/hosts.yml -m ping
```

### Execution Options
```bash
# Verbose output
ansible-playbook playbook.yml -vvv

# Stop on first error
ansible-playbook playbook.yml --abort-on-error

# Skip health checks (emergency)
ansible-playbook playbook.yml -e skip_health_checks=true

# Force rebuild
ansible-playbook playbook.yml -e force_rebuild=true
```

## 📋 Common Variable Patterns

```bash
# Team filtering
-e team_filter=devops          # Single team
-e team_filter=all             # All teams

# Environment targeting
-e environment=blue            # Blue environment
-e environment=green           # Green environment

# Operation modes
-e blue_green_operation=switch # Switch environments
-e dr_operation=restore        # Disaster recovery restore
-e batch_blue_green_operation=switch-all # Batch switch all teams

# Safety controls
-e dr_dry_run=true            # Disaster recovery dry run
-e skip_health_checks=false   # Health check control
-e validate_recovery=true     # Recovery validation
```