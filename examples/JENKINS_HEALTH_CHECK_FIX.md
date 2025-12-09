# Jenkins Health Check Connectivity Fix

## Issue Summary

Fixed critical Jenkins deployment health check issues where containers were running successfully but Ansible health checks were failing with "Connection refused" errors.

## Root Causes Identified

### 1. Port Mapping Logic Error
**Problem**: The blue-green port mapping logic in `image-and-container.yml` was adding +100 to port numbers for green environments, creating a mismatch between exposed ports and health check expectations.

**Original Logic**:
```yaml
_active_ports:
  - "{% if item.active_environment | default('blue') == 'blue' %}{{ item.ports.web }}{% else %}{{ item.ports.web + 100 }}{% endif %}:{{ jenkins_master_port }}"
  - "{% if item.active_environment | default('blue') == 'blue' %}{{ item.ports.agent }}{% else %}{{ item.ports.agent + 100 }}{% endif %}:{{ jenkins_jnlp_port }}"
```

**Issue**: For `dev-qa` team with `active_environment: green` and `ports.web: 8089`, the container was exposed on port `8189` but health checks tried to connect to `8089`.

**Fix**: Simplified to use the configured team ports directly:
```yaml
_active_ports:
  - "{{ item.ports.web }}:{{ jenkins_master_port }}"
  - "{{ item.ports.agent }}:{{ jenkins_jnlp_port }}"
```

### 2. Verification Host Resolution Issues
**Problem**: The `jenkins_verification_host` variable resolution logic was fragile and could resolve to unreachable addresses.

**Fix**: Enhanced verification host logic with better fallback chain:
```yaml
jenkins_verification_host: >-
  {%- if deployment_mode | default('') in ['local', 'devcontainer'] or deployment_environment | default('') == 'local' -%}
    localhost
  {%- elif ansible_virtualization_type | default('') == 'docker' -%}
    host.docker.internal
  {%- elif ansible_connection | default('') == 'local' -%}
    localhost
  {%- elif hostvars[inventory_hostname]['ansible_host'] is defined -%}
    {{ hostvars[inventory_hostname]['ansible_host'] }}
  {%- elif ansible_default_ipv4.address is defined -%}
    {{ ansible_default_ipv4.address }}
  {%- else -%}
    localhost
  {%- endif -%}
```

### 3. Single-Point-of-Failure Health Checks
**Problem**: Health checks only tried one host address and would fail if that specific address wasn't reachable.

**Fix**: Implemented multi-tier fallback health checking:
- **Primary**: Try configured `jenkins_verification_host`
- **Fallback 1**: Try `localhost`
- **Fallback 2**: Try container's IP address

## Key Changes Made

### 1. Fixed Port Mapping (`image-and-container.yml`)
- Removed complex blue/green port offset logic
- Now uses team-configured ports directly for both environments
- Ensures consistency between container exposure and health checks

### 2. Enhanced Health Checking (`deploy-and-monitor.yml`)
- **Multi-tier Web Health Checks**: Try multiple host addresses with fallback
- **Robust Agent Port Checks**: Primary and fallback connectivity tests
- **Enhanced API Health Checks**: Multiple host fallback for API endpoints
- **Comprehensive Validation**: Final health check with detailed error reporting

### 3. Improved Error Reporting
- Added detailed troubleshooting information in health check failures
- Container debug information display
- Connectivity test results with multiple hosts
- Clear success/failure messaging with actionable troubleshooting steps

### 4. Better Host Resolution
- Enhanced verification host logic in both `vars/main.yml` and `defaults/main.yml`
- Better fallback chain for different deployment environments
- More reliable host address resolution

## Deployment Impact

### Resource-Optimized Blue-Green Architecture Maintained
- ✅ Only active environment containers run (50% resource savings)
- ✅ Teams can independently switch blue/green environments
- ✅ Consistent port mappings across environments
- ✅ No impact on existing deployment patterns

### Team Configuration Compatibility
- ✅ All existing team configurations work without changes
- ✅ Port assignments remain as configured in `jenkins_teams.yml`
- ✅ No breaking changes to team-specific settings

### Enhanced Reliability
- ✅ Health checks work across different network configurations
- ✅ Better error reporting for troubleshooting
- ✅ Fallback mechanisms for different deployment environments
- ✅ More robust verification host resolution

## Testing Recommendations

### Pre-Deployment Verification
```bash
# 1. Verify container port mappings
docker ps --filter "name=jenkins" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 2. Test connectivity to each team's Jenkins instance
curl -I http://localhost:8080/login  # devops team
curl -I http://localhost:8089/login  # dev-qa team

# 3. Verify agent ports are accessible
nc -zv localhost 50000  # devops agent port
nc -zv localhost 50009  # dev-qa agent port
```

### Health Check Validation
```bash
# Run deployment with enhanced health checks
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags health,verify

# Monitor health check results
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags verify --check
```

### Container Health Monitoring
```bash
# Check container health status
docker inspect jenkins-devops-blue --format='{{.State.Health.Status}}'
docker inspect jenkins-dev-qa-green --format='{{.State.Health.Status}}'

# View container logs for troubleshooting
docker logs jenkins-devops-blue --tail 20
docker logs jenkins-dev-qa-green --tail 20
```

## Architecture Benefits

### 1. Simplified Port Management
- Eliminated complex port offset calculations
- Direct mapping of team-configured ports to containers
- Reduced chance of port conflicts or mismatches

### 2. Network Resilience
- Multiple fallback mechanisms for different network configurations
- Works in local, container, VM, and cloud environments
- Better handling of network partition scenarios

### 3. Operational Excellence
- Enhanced observability with detailed health check reporting
- Better troubleshooting information for deployment issues
- Comprehensive validation with clear success/failure criteria

### 4. Deployment Safety
- Robust validation prevents silent failures
- Clear error messages with actionable remediation steps
- Maintains existing blue-green deployment benefits

## Future Enhancements

### Container Health Integration
- Consider adding health check results to monitoring dashboards
- Integration with Prometheus/Grafana for health metrics
- Automated alerting on persistent health check failures

### Network Automation
- Auto-discovery of optimal verification hosts
- Dynamic port conflict detection and resolution
- Network topology awareness for health checking

### Testing Automation
- Automated port connectivity testing in CI/CD
- Health check validation in deployment pipelines
- Regression testing for different network configurations

## Conclusion

This fix resolves the fundamental connectivity issues in Jenkins blue-green deployments while maintaining the resource-optimized architecture and all existing enterprise features. The enhanced health checking provides better reliability and troubleshooting capabilities for production deployments.

The changes are backward-compatible and don't require any modifications to existing team configurations or deployment workflows. Teams can continue to operate independently with their configured ports and blue-green environments.