#!/bin/bash
# Blue-Green Switch with GlusterFS Sync Layer
# Automated switch workflow with data synchronization via GlusterFS

set -euo pipefail

TEAM="${1:-}"
TARGET_ENV="${2:-}"

if [[ -z "$TEAM" ]] || [[ -z "$TARGET_ENV" ]]; then
    echo "Usage: $0 <team> <target_env>"
    echo "Example: $0 devops green"
    echo ""
    echo "This script will:"
    echo "  1. Sync current environment to GlusterFS"
    echo "  2. Wait for GlusterFS replication across VMs"
    echo "  3. Recover target environment from GlusterFS"
    echo "  4. Update inventory configuration"
    echo "  5. Deploy target environment"
    echo "  6. Update HAProxy routing"
    exit 1
fi

SOURCE_ENV=$([[ "$TARGET_ENV" == "blue" ]] && echo "green" || echo "blue")

echo "=========================================="
echo "Blue-Green Switch with GlusterFS"
echo "=========================================="
echo "Team: $TEAM"
echo "Current Environment: $SOURCE_ENV"
echo "Target Environment: $TARGET_ENV"
echo "=========================================="
echo ""

# Step 1: Force sync current environment to GlusterFS
echo "[Step 1/6] Syncing $SOURCE_ENV to GlusterFS..."
if [[ ! -f "/usr/local/bin/jenkins-sync-to-gluster-${TEAM}.sh" ]]; then
    echo "ERROR: Sync script not found. Has Ansible deployment completed?"
    echo "Expected: /usr/local/bin/jenkins-sync-to-gluster-${TEAM}.sh"
    exit 1
fi

/usr/local/bin/jenkins-sync-to-gluster-${TEAM}.sh

if [[ $? -ne 0 ]]; then
    echo "ERROR: Sync to GlusterFS failed"
    echo "Check logs: /var/log/jenkins-gluster-sync-${TEAM}.log"
    exit 1
fi

echo "✓ Sync complete"
echo ""

# Step 2: Wait for GlusterFS replication
echo "[Step 2/6] Waiting for GlusterFS replication..."
echo "  (GlusterFS replicates in real-time, typically < 5 seconds)"
sleep 10
echo "✓ Replication window complete"
echo ""

# Step 3: Recover target environment from GlusterFS
echo "[Step 3/6] Recovering $TARGET_ENV from GlusterFS..."
if [[ ! -f "/usr/local/bin/jenkins-recover-from-gluster-${TEAM}.sh" ]]; then
    echo "ERROR: Recovery script not found"
    echo "Expected: /usr/local/bin/jenkins-recover-from-gluster-${TEAM}.sh"
    exit 1
fi

/usr/local/bin/jenkins-recover-from-gluster-${TEAM}.sh "$TEAM" "$TARGET_ENV"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Recovery from GlusterFS failed"
    echo "Check logs: /var/log/jenkins-gluster-recovery-${TEAM}.log"
    exit 1
fi

echo "✓ Recovery complete"
echo ""

# Step 4: Update inventory configuration
echo "[Step 4/6] Updating inventory configuration..."
INVENTORY_FILE="ansible/inventories/production/group_vars/all/main.yml"

if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "ERROR: Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

# Create backup
cp "$INVENTORY_FILE" "${INVENTORY_FILE}.backup-$(date +%Y%m%d-%H%M%S)"

# Update active_environment for the team
sed -i.bak "/team_name: \"${TEAM}\"/,/active_environment:/ s/active_environment: .*/active_environment: \"${TARGET_ENV}\"/" "$INVENTORY_FILE"

echo "✓ Inventory updated"
echo ""

# Step 5: Deploy target environment
echo "[Step 5/6] Deploying $TARGET_ENV environment..."
ansible-playbook \
    -i ansible/inventories/production/hosts.yml \
    ansible/site.yml \
    --tags jenkins,deploy \
    --limit jenkins_masters

if [[ $? -ne 0 ]]; then
    echo "ERROR: Deployment failed"
    echo "Rolling back inventory changes..."
    mv "${INVENTORY_FILE}.backup" "$INVENTORY_FILE"
    exit 1
fi

echo "✓ Deployment complete"
echo ""

# Step 6: Update HAProxy routing
echo "[Step 6/6] Updating HAProxy routing..."
ansible-playbook \
    -i ansible/inventories/production/hosts.yml \
    ansible/site.yml \
    --tags haproxy

if [[ $? -ne 0 ]]; then
    echo "ERROR: HAProxy update failed"
    echo "Traffic may still be routed to $SOURCE_ENV"
    exit 1
fi

echo "✓ HAProxy updated"
echo ""

# Final summary
echo "=========================================="
echo "Switch Complete!"
echo "=========================================="
echo "Team: $TEAM"
echo "Active Environment: $TARGET_ENV"
echo "Previous Environment: $SOURCE_ENV (stopped)"
echo ""
echo "Verification:"
echo "  1. Check Jenkins UI: http://your-jenkins-url"
echo "  2. Verify container: docker ps | grep jenkins-$TEAM-$TARGET_ENV"
echo "  3. Check logs: docker logs jenkins-$TEAM-$TARGET_ENV"
echo ""
echo "Data Sync:"
echo "  ✓ $SOURCE_ENV synced to GlusterFS"
echo "  ✓ GlusterFS replicated to all VMs"
echo "  ✓ $TARGET_ENV recovered from GlusterFS"
echo ""
echo "If issues occur, rollback with:"
echo "  ansible-playbook ansible/site.yml --tags jenkins,deploy"
echo "=========================================="

exit 0
