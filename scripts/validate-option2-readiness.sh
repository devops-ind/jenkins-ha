#!/bin/bash
# Option 2 Multi-VM Architecture Deployment Readiness Validation
# Validates all prerequisites before running the migration playbook

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Option 2 Multi-VM Deployment Readiness${NC}"
echo -e "${BLUE}========================================${NC}\n"

check_pass() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    echo -e "${RED}✗${NC} $1"
    echo -e "  ${RED}Error: $2${NC}"
}

check_warn() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
    echo -e "${YELLOW}⚠${NC} $1"
    echo -e "  ${YELLOW}Warning: $2${NC}"
}

# Check 1: Inventory file exists and is valid YAML
echo -e "\n${BLUE}[1/10] Checking inventory configuration...${NC}"
INVENTORY_FILE="ansible/inventories/production/hosts.yml"
if [ -f "$INVENTORY_FILE" ]; then
    if python3 -c "import yaml; yaml.safe_load(open('$INVENTORY_FILE'))" 2>/dev/null; then
        check_pass "Inventory file exists and is valid YAML"
    else
        check_fail "Inventory file YAML validation" "Invalid YAML syntax in $INVENTORY_FILE"
    fi
else
    check_fail "Inventory file" "$INVENTORY_FILE not found"
fi

# Check 2: Multi-VM configuration enabled
echo -e "\n${BLUE}[2/10] Checking multi-VM configuration...${NC}"
if grep -q "multi_vm_enabled: true" "$INVENTORY_FILE" 2>/dev/null; then
    check_pass "Multi-VM mode enabled"
else
    check_fail "Multi-VM configuration" "multi_vm_enabled not set to true in inventory"
fi

if grep -q "multi_vm_architecture: \"option2-hybrid\"" "$INVENTORY_FILE" 2>/dev/null; then
    check_pass "Option 2 architecture configured"
else
    check_warn "Architecture type" "multi_vm_architecture not set to 'option2-hybrid'"
fi

# Check 3: VM connectivity
echo -e "\n${BLUE}[3/10] Checking VM connectivity...${NC}"
VM1_IP="192.168.188.142"
VM2_IP="192.168.188.143"
VM3_IP="192.168.188.144"

for VM_IP in $VM1_IP $VM2_IP $VM3_IP; do
    if ping -c 1 -W 2 $VM_IP >/dev/null 2>&1; then
        check_pass "VM $VM_IP is reachable"
    else
        check_warn "VM connectivity" "Cannot ping $VM_IP (may require VPN or network access)"
    fi
done

# Check 4: Jenkins teams configuration
echo -e "\n${BLUE}[4/10] Checking jenkins_teams configuration...${NC}"
TEAMS_FILE="ansible/group_vars/all/jenkins_teams.yml"
if [ -f "$TEAMS_FILE" ]; then
    if python3 -c "import yaml; yaml.safe_load(open('$TEAMS_FILE'))" 2>/dev/null; then
        check_pass "jenkins_teams.yml exists and is valid YAML"

        # Check for required teams
        for TEAM in devops ma ba tw; do
            if grep -q "team_name: $TEAM" "$TEAMS_FILE"; then
                check_pass "Team '$TEAM' configured"
            else
                check_fail "Team configuration" "Team '$TEAM' not found in $TEAMS_FILE"
            fi
        done
    else
        check_fail "jenkins_teams.yml validation" "Invalid YAML syntax"
    fi
else
    check_fail "jenkins_teams.yml" "File not found at $TEAMS_FILE"
fi

# Check 5: Team distribution in inventory
echo -e "\n${BLUE}[5/10] Checking team distribution...${NC}"
if grep -q "jenkins_teams_on_vm:" "$INVENTORY_FILE" 2>/dev/null; then
    # Extract jenkins-blue teams
    BLUE_TEAMS=$(awk '/jenkins-blue:/,/jenkins-green:/ {if (/^        - /) print $2}' "$INVENTORY_FILE" | tr '\n' ',' | sed 's/,$//')
    if [ -n "$BLUE_TEAMS" ]; then
        check_pass "jenkins-blue teams: $BLUE_TEAMS"
    else
        check_fail "jenkins-blue team distribution" "No teams assigned to jenkins-blue"
    fi

    # Extract jenkins-green teams
    GREEN_TEAMS=$(awk '/jenkins-green:/,/^[^ ]/ {if (/^        - / && !/jenkins-green:/) print $2}' "$INVENTORY_FILE" | head -10 | tr '\n' ',' | sed 's/,$//')
    if [ -n "$GREEN_TEAMS" ]; then
        check_pass "jenkins-green teams: $GREEN_TEAMS"
    else
        check_fail "jenkins-green team distribution" "No teams assigned to jenkins-green"
    fi
else
    check_fail "Team distribution" "jenkins_teams_on_vm not found in inventory"
fi

# Check 6: HAProxy colocated configuration
echo -e "\n${BLUE}[6/10] Checking HAProxy configuration...${NC}"
if grep -A 15 "^load_balancers:" "$INVENTORY_FILE" | grep -q "jenkins-blue:" 2>/dev/null; then
    check_pass "HAProxy configured on jenkins-blue VM"
else
    check_fail "HAProxy configuration" "jenkins-blue not in load_balancers group"
fi

if grep -A 15 "^load_balancers:" "$INVENTORY_FILE" | grep -q "jenkins-green:" 2>/dev/null; then
    check_pass "HAProxy configured on jenkins-green VM"
else
    check_fail "HAProxy configuration" "jenkins-green not in load_balancers group"
fi

if grep -q "haproxy_backend_mode: \"local\"" "$INVENTORY_FILE" 2>/dev/null; then
    check_pass "HAProxy backend mode set to 'local'"
else
    check_warn "HAProxy backend mode" "Should be set to 'local' for colocated deployment"
fi

# Check 7: Monitoring VM configuration
echo -e "\n${BLUE}[7/10] Checking monitoring VM configuration...${NC}"
if grep -A 3 "monitoring:" "$INVENTORY_FILE" | grep -q "monitoring-vm:" 2>/dev/null; then
    check_pass "Dedicated monitoring VM configured"
else
    check_fail "Monitoring VM" "monitoring-vm not configured in monitoring group"
fi

if grep -q "192.168.188.144" "$INVENTORY_FILE" | grep -q "monitoring" 2>/dev/null; then
    check_pass "Monitoring VM IP correctly set (192.168.188.144)"
else
    check_warn "Monitoring VM IP" "Verify 192.168.188.144 is correct for monitoring VM"
fi

# Check 8: GlusterFS configuration
echo -e "\n${BLUE}[8/10] Checking GlusterFS configuration...${NC}"
if grep -q "shared_storage_type: \"glusterfs\"" "$INVENTORY_FILE" 2>/dev/null; then
    check_pass "GlusterFS storage type configured"
else
    check_fail "Storage configuration" "shared_storage_type should be 'glusterfs' for multi-VM"
fi

if grep -q "glusterfs_replicas: 2" "$INVENTORY_FILE" 2>/dev/null; then
    check_pass "GlusterFS replica count set to 2"
else
    check_warn "GlusterFS replicas" "Should be set to 2 for 2-VM replication"
fi

if grep -A 20 "^glusterfs_servers:" "$INVENTORY_FILE" | grep -q "jenkins-blue:" 2>/dev/null; then
    check_pass "jenkins-blue in glusterfs_servers group"
else
    check_fail "GlusterFS configuration" "jenkins-blue not in glusterfs_servers group"
fi

if grep -A 20 "^glusterfs_servers:" "$INVENTORY_FILE" | grep -q "jenkins-green:" 2>/dev/null; then
    check_pass "jenkins-green in glusterfs_servers group"
else
    check_fail "GlusterFS configuration" "jenkins-green not in glusterfs_servers group"
fi

# Check 9: Migration playbook exists
echo -e "\n${BLUE}[9/10] Checking migration playbook...${NC}"
MIGRATION_PLAYBOOK="ansible/playbooks/migrate-to-option2-multi-vm.yml"
if [ -f "$MIGRATION_PLAYBOOK" ]; then
    if python3 -c "import yaml; yaml.safe_load(open('$MIGRATION_PLAYBOOK'))" 2>/dev/null; then
        check_pass "Migration playbook exists and is valid YAML"
    else
        check_fail "Migration playbook validation" "Invalid YAML syntax in $MIGRATION_PLAYBOOK"
    fi
else
    check_fail "Migration playbook" "$MIGRATION_PLAYBOOK not found"
fi

# Check 10: Required Ansible roles
echo -e "\n${BLUE}[10/10] Checking required Ansible roles...${NC}"
for ROLE in jenkins-master-v2 high-availability-v2 monitoring shared-storage; do
    ROLE_PATH="ansible/roles/$ROLE"
    if [ -d "$ROLE_PATH" ]; then
        check_pass "Role '$ROLE' exists"
    else
        check_fail "Ansible role" "Role '$ROLE' not found at $ROLE_PATH"
    fi
done

# Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total checks: $TOTAL_CHECKS"
echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
echo -e "${YELLOW}Warnings: $WARNING_CHECKS${NC}\n"

# Architecture diagram
echo -e "${BLUE}Deployment Architecture:${NC}"
echo "┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐"
echo "│  jenkins-blue      │  │  jenkins-green     │  │  monitoring-vm     │"
echo "│  192.168.188.142   │  │  192.168.188.143   │  │  192.168.188.144   │"
echo "├────────────────────┤  ├────────────────────┤  ├────────────────────┤"
echo "│ Jenkins (devops)   │  │ Jenkins (ba)       │  │ Prometheus         │"
echo "│ Jenkins (ma)       │  │ Jenkins (tw)       │  │ Grafana            │"
echo "│ HAProxy            │  │ HAProxy            │  │ Loki               │"
echo "│ GlusterFS Server   │  │ GlusterFS Server   │  │ Alertmanager       │"
echo "└────────────────────┘  └────────────────────┘  └────────────────────┘"
echo ""

# Exit status and recommendations
if [ $FAILED_CHECKS -gt 0 ]; then
    echo -e "${RED}✗ Deployment readiness: FAILED${NC}"
    echo -e "${RED}Please fix the failed checks before proceeding with migration.${NC}\n"
    exit 1
elif [ $WARNING_CHECKS -gt 0 ]; then
    echo -e "${YELLOW}⚠ Deployment readiness: WARNING${NC}"
    echo -e "${YELLOW}Review warnings before proceeding. Migration can continue but may require attention.${NC}\n"
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Review warnings above"
    echo "2. Run migration: ansible-playbook -i $INVENTORY_FILE $MIGRATION_PLAYBOOK"
    echo "3. Monitor deployment progress\n"
    exit 0
else
    echo -e "${GREEN}✓ Deployment readiness: PASSED${NC}"
    echo -e "${GREEN}All checks passed! Ready to proceed with Option 2 migration.${NC}\n"
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Run migration: ansible-playbook -i $INVENTORY_FILE $MIGRATION_PLAYBOOK"
    echo "2. Or run phase-by-phase:"
    echo "   - Phase 1: ansible-playbook -i $INVENTORY_FILE $MIGRATION_PLAYBOOK --tags phase1"
    echo "   - Phase 2: ansible-playbook -i $INVENTORY_FILE $MIGRATION_PLAYBOOK --tags phase2"
    echo "   - Phase 3: ansible-playbook -i $INVENTORY_FILE $MIGRATION_PLAYBOOK --tags phase3"
    echo "   - Phase 4: ansible-playbook -i $INVENTORY_FILE $MIGRATION_PLAYBOOK --tags phase4\n"
    exit 0
fi
