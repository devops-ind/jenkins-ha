# Team Filtering Fix for jenkins-master-v2 Role

## Issue Description

The Ansible tasks for filtering teams based on `deploy_teams` and `exclude_teams` parameters were not working correctly due to how Jinja2's `selectattr` filter was evaluating complex expressions.

## Root Cause

The original code attempted to parse the comma-separated team list inline within the `selectattr` filter:

```yaml
# BEFORE (BROKEN)
- name: Filter teams for deployment - Deploy specific teams
  set_fact:
    jenkins_teams_filtered: "{{ jenkins_teams_config | selectattr('team_name', 'in', deploy_teams.split(',') | map('trim') | list) | list }}"
  when: deploy_teams is defined and deploy_teams != ""
```

**Problem**: The Jinja2 parser was not correctly evaluating `deploy_teams.split(',') | map('trim') | list` before passing it to the `'in'` test within `selectattr`, causing the filter to fail silently and return all teams instead of the filtered subset.

## Solution

The fix separates the parsing of the team list from the filtering operation:

```yaml
# AFTER (FIXED)
- name: Parse deploy_teams parameter into list
  set_fact:
    deploy_teams_list: "{{ deploy_teams.split(',') | map('trim') | reject('equalto', '') | list }}"
  when: deploy_teams is defined and deploy_teams != ""

- name: Filter teams for deployment - Deploy specific teams
  set_fact:
    jenkins_teams_filtered: "{{ jenkins_teams_config | selectattr('team_name', 'in', deploy_teams_list) | list }}"
  when:
    - deploy_teams is defined and deploy_teams != ""
    - deploy_teams_list is defined
    - deploy_teams_list | length > 0
```

### Key Improvements

1. **Two-step parsing**: Parse the comma-separated string into a list first, then use it for filtering
2. **Empty string rejection**: Added `reject('equalto', '')` to handle extra commas or spaces
3. **Safety checks**: Added validation that the parsed list exists and is not empty
4. **Better debugging**: New debug output shows both raw and parsed team lists
5. **Safety fallback**: Ensures `jenkins_teams_filtered` is always defined with a fallback to all teams

## Usage Examples

### Deploy Specific Teams

```bash
# Deploy only devops and ma teams
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "deploy_teams=devops,ma"

# Deploy only one team
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "deploy_teams=devops"

# Deploy teams with extra spaces (now handled correctly)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "deploy_teams=devops, ma, ba"
```

### Exclude Specific Teams

```bash
# Deploy all teams except ba and tw
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "exclude_teams=ba,tw"

# Exclude one team
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "exclude_teams=tw"
```

### Deploy All Teams (Default)

```bash
# No parameters = deploy all teams
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins
```

### Multi-VM Architecture

When using multi-VM deployment (Option 2 architecture), the filtering works in combination:

```bash
# Deploy only devops team on jenkins-blue VM
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  --limit jenkins-blue \
  -e "deploy_teams=devops"

# On jenkins-blue with jenkins_teams_on_vm=['devops', 'ma']:
# - First filter: deploy_teams=devops → ['devops']
# - Second filter: jenkins_teams_on_vm=['devops', 'ma'] → ['devops']
# Result: Only devops team deployed
```

## Debugging

Enable verbose output to see the parsed team lists:

```bash
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "deploy_teams=devops,ma" \
  -v
```

Expected output:

```
====================================================
Team Filtering Debug Information
====================================================
Original teams count: 4
Original teams: devops, ma, ba, tw
deploy_teams parameter: devops,ma
deploy_teams_list (parsed): devops, ma
Filtered teams count: 2
Filtered teams: devops, ma
====================================================
```

## Validation

The fix includes comprehensive validation:

1. **Team name validation**: Checks that requested teams exist in the configuration
2. **Empty filter detection**: Ensures at least one team is selected after filtering
3. **Case-sensitive matching**: Team names must match exactly (case-sensitive)
4. **Helpful error messages**: Provides detailed error messages with suggestions

### Example Validation Errors

```bash
# Non-existent team
ansible-playbook ... -e "deploy_teams=invalid"
# ERROR: Team 'invalid' not found in configuration.
# Available teams: devops, ma, ba, tw

# Empty result
ansible-playbook ... -e "exclude_teams=devops,ma,ba,tw"
# ERROR: No teams selected for deployment!
# WARNING: All teams have been excluded from deployment!
```

## Testing

```bash
# Test 1: Deploy specific teams
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "deploy_teams=devops" \
  --check -vv

# Test 2: Exclude teams
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "exclude_teams=ba,tw" \
  --check -vv

# Test 3: Invalid team name (should fail)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "deploy_teams=invalid" \
  --check -vv

# Test 4: Extra spaces (should work)
ansible-playbook -i ansible/inventories/production/hosts.yml \
  ansible/site.yml --tags jenkins \
  -e "deploy_teams=devops , ma , ba" \
  --check -vv
```

## Files Modified

- `ansible/roles/jenkins-master-v2/tasks/main.yml`: Updated team filtering logic with two-step parsing

## Backward Compatibility

This fix is fully backward compatible:

- **No parameter changes**: Same `deploy_teams` and `exclude_teams` parameters
- **Same behavior**: Just fixes the broken filtering logic
- **Default behavior unchanged**: No parameters still deploys all teams
- **Multi-VM compatible**: Works with Option 2 multi-VM architecture

## Related Documentation

- [CLAUDE.md](../CLAUDE.md) - Main project documentation
- [Multi-VM Architecture Guide](../examples/option2-multi-vm-architecture-guide.md)
- [Infrastructure Deployment Plan](infrastructure-deployment-plan.md)

## Date

2025-12-12
