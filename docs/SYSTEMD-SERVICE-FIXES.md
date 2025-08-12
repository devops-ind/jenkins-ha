# Jenkins HA Systemd Service Fixes

## Issue Summary

**Error**: `Could not find the requested service jenkins-master: host`

**Root Cause**: Systemd service dependencies (scripts, directories, permissions) were not created before attempting to enable/start the service.

## Fixed Components

### 1. Task Execution Order (`ansible/roles/jenkins-master/tasks/systemd-services.yml`)

**Changes Made:**
- ✅ Create required directories first (`{{ jenkins_home_dir }}/bin`, `{{ jenkins_home_dir }}/logs`)
- ✅ Generate all required scripts before systemd service template
- ✅ Force systemd daemon reload immediately after service file creation
- ✅ Add pause and verification steps before service activation
- ✅ Verify service file exists before attempting to enable/start
- ✅ Add container verification step before systemd service startup

### 2. Systemd Service Template (`ansible/roles/jenkins-master/templates/jenkins-master.service.j2`)

**Improvements:**
- ✅ Increased timeout values (600s start, 60s stop)
- ✅ Added proper network dependencies (`network-online.target`)
- ✅ Enhanced pre-start checks with directory creation and ownership
- ✅ Added retry logic in health check scripts
- ✅ Improved error handling and logging

### 3. Main Task Order (`ansible/roles/jenkins-master/tasks/main.yml`)

**Changes:**
- ✅ Ensured containers are deployed before systemd services
- ✅ Added wait time for containers to become operational
- ✅ Added conditional execution for systemd tasks

### 4. Handler Configuration (`ansible/roles/jenkins-master/handlers/main.yml`)

**Updates:**
- ✅ Added `daemon_reload: yes` to jenkins-master restart handler
- ✅ Added proper privilege escalation (`become: yes`)

## New Scripts Created

### Container Verification Script
**File**: `ansible/roles/jenkins-master/templates/jenkins-container-verify.sh.j2`
- Verifies all team containers are running before systemd service activation
- Provides detailed logging and retry logic
- Prevents systemd service from starting with non-functional containers

### Debug Script  
**File**: `scripts/debug-jenkins-systemd.sh`
- Comprehensive debugging tool for systemd service issues
- Checks service files, permissions, containers, logs, and system resources
- Executable: `chmod +x scripts/debug-jenkins-systemd.sh`

## Deployment Sequence (Fixed)

1. **Infrastructure Setup**
   - Create Jenkins user/group
   - Configure networks and volumes

2. **Container Deployment**
   - Deploy blue-green containers for each team
   - Wait for containers to become operational

3. **Systemd Service Configuration**
   - Create required directories
   - Generate all script dependencies
   - Create systemd service template
   - Force daemon reload
   - Verify container readiness
   - Enable and start systemd service

4. **Verification**
   - Wait for service to become active
   - Validate all team environments

## Usage

### Deploy with Fixed Configuration
```bash
# Full deployment
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags jenkins,systemd

# Systemd services only
ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml --tags systemd

# Debug systemd issues
./scripts/debug-jenkins-systemd.sh
```

### Manual Service Operations
```bash
# Check service status
sudo systemctl status jenkins-master

# View service logs
sudo journalctl -u jenkins-master -f

# Restart service
sudo systemctl restart jenkins-master

# Reload systemd and restart
sudo systemctl daemon-reload && sudo systemctl restart jenkins-master
```

## Key Architecture Points

### Coordination Model
- **Systemd Service**: Acts as coordinator/monitor, not container manager
- **Container Management**: Handled by Ansible tasks (docker/podman modules)
- **Health Monitoring**: Systemd service verifies container health, doesn't manage lifecycle
- **Blue-Green Switching**: Independent of systemd, managed by Ansible playbooks

### Service Dependencies
- Requires container runtime (docker/podman) service
- Depends on network connectivity
- Validates container readiness before declaring success
- Monitors but doesn't directly control containers

## Troubleshooting

### If Service Still Fails
1. Run debug script: `./scripts/debug-jenkins-systemd.sh`
2. Check container status: `podman ps` or `docker ps`
3. Verify script permissions: `ls -la /var/jenkins/bin/`
4. Check systemd logs: `journalctl -u jenkins-master`
5. Validate service file: `systemctl cat jenkins-master`

### Common Issues
- **Scripts not executable**: Fixed with proper mode setting in tasks
- **Directory permissions**: Fixed with proper ownership in systemd service
- **Container not ready**: Fixed with verification steps before service start
- **Service file missing**: Fixed with stat verification before enable/start