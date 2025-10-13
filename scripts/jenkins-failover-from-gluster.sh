#!/bin/bash
# Jenkins Automated Failover using GlusterFS Sync Layer
# Recovers Jenkins on target VM when source VM fails

set -euo pipefail

TEAM="${1:-}"
ENV="${2:-}"
FAILED_VM="${3:-}"
TARGET_VM="${4:-$(hostname)}"

if [[ -z "$TEAM" ]] || [[ -z "$ENV" ]] || [[ -z "$FAILED_VM" ]]; then
    echo "Usage: $0 <team> <env> <failed_vm> [target_vm]"
    echo "Example: $0 devops blue vm1 vm2"
    echo ""
    echo "This script will:"
    echo "  1. Recover Jenkins data from GlusterFS on target VM"
    echo "  2. Start Jenkins container on target VM"
    echo "  3. Update HAProxy to route traffic to target VM"
    echo "  4. Verify failover success"
    exit 1
fi

echo "=========================================="
echo "Jenkins Automated Failover"
echo "=========================================="
echo "Team: $TEAM"
echo "Environment: $ENV"
echo "Failed VM: $FAILED_VM"
echo "Target VM: $TARGET_VM"
echo "=========================================="
echo ""

START_TIME=$(date +%s)

# Step 1: Recover data from GlusterFS on target VM
echo "[Step 1/4] Recovering data from GlusterFS on $TARGET_VM..."
ssh "$TARGET_VM" "/usr/local/bin/jenkins-recover-from-gluster-${TEAM}.sh $TEAM $ENV"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Recovery from GlusterFS failed on $TARGET_VM"
    echo "Check logs on $TARGET_VM: /var/log/jenkins-gluster-recovery-${TEAM}.log"
    exit 1
fi

echo "✓ Data recovered"
echo ""

# Step 2: Start Jenkins container on target VM
echo "[Step 2/4] Starting Jenkins container on $TARGET_VM..."
CONTAINER_NAME="jenkins-${TEAM}-${ENV}"

ssh "$TARGET_VM" "docker start $CONTAINER_NAME"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to start container on $TARGET_VM"
    exit 1
fi

# Wait for container to be ready
echo "  Waiting for container to be ready..."
sleep 15

# Check container is running
CONTAINER_RUNNING=$(ssh "$TARGET_VM" "docker ps -q -f name=$CONTAINER_NAME" | wc -l)

if [[ $CONTAINER_RUNNING -eq 0 ]]; then
    echo "ERROR: Container not running on $TARGET_VM"
    echo "Check logs: ssh $TARGET_VM docker logs $CONTAINER_NAME"
    exit 1
fi

echo "✓ Container started"
echo ""

# Step 3: Update HAProxy routing
echo "[Step 3/4] Updating HAProxy routing..."
ansible-playbook \
    -i ansible/inventories/production/hosts.yml \
    ansible/site.yml \
    --tags haproxy \
    --limit load_balancers

if [[ $? -ne 0 ]]; then
    echo "ERROR: HAProxy update failed"
    echo "Manual intervention required"
    exit 1
fi

echo "✓ HAProxy updated"
echo ""

# Step 4: Verify failover
echo "[Step 4/4] Verifying failover..."

# Get Jenkins port (assuming standard ports)
JENKINS_PORT=$([[ "$ENV" == "blue" ]] && echo "8080" || echo "8180")

# Check Jenkins is accessible on target VM
HTTP_CODE=$(ssh "$TARGET_VM" "curl -s -o /dev/null -w '%{http_code}' http://localhost:$JENKINS_PORT/login" || echo "000")

if [[ "$HTTP_CODE" =~ ^(200|403)$ ]]; then
    echo "✓ Jenkins is accessible on $TARGET_VM (HTTP $HTTP_CODE)"
else
    echo "WARNING: Jenkins may not be fully ready (HTTP $HTTP_CODE)"
    echo "Check container logs: ssh $TARGET_VM docker logs $CONTAINER_NAME"
fi

# Calculate RTO
END_TIME=$(date +%s)
RTO=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Failover Complete!"
echo "=========================================="
echo "Team: $TEAM"
echo "Environment: $ENV"
echo "Active VM: $TARGET_VM"
echo "Failed VM: $FAILED_VM"
echo "RTO (Recovery Time): ${RTO} seconds"
echo ""
echo "Verification:"
echo "  1. Check Jenkins UI: http://your-jenkins-url"
echo "  2. Container status: ssh $TARGET_VM docker ps | grep $CONTAINER_NAME"
echo "  3. Container logs: ssh $TARGET_VM docker logs $CONTAINER_NAME"
echo "  4. HAProxy stats: http://haproxy-url:8404/stats"
echo ""
echo "Next steps:"
echo "  1. Investigate $FAILED_VM failure"
echo "  2. Fix issues on $FAILED_VM"
echo "  3. When $FAILED_VM recovers, sync will resume automatically"
echo "=========================================="

exit 0
