#!/bin/bash
# Test script for team filtering fix in jenkins-master-v2 role
# This script validates that deploy_teams and exclude_teams parameters work correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY="${PROJECT_ROOT}/ansible/inventories/production/hosts.yml"
PLAYBOOK="${PROJECT_ROOT}/ansible/site.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_test() {
    echo -e "${YELLOW}Test $1:${NC} $2"
}

print_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
}

run_test() {
    local test_name="$1"
    local expected_teams="$2"
    local extra_args="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    print_test "${TESTS_RUN}" "${test_name}"

    # Run ansible-playbook in check mode with verbose output
    # Capture the team filtering debug information
    local output
    output=$(ansible-playbook -i "${INVENTORY}" "${PLAYBOOK}" \
        --tags jenkins \
        ${extra_args} \
        --check -v 2>&1 | grep -A 20 "Team Filtering Debug Information" || true)

    # Extract filtered teams from output
    local filtered_teams
    filtered_teams=$(echo "${output}" | grep "Filtered teams:" | sed 's/.*Filtered teams: //' || echo "")

    # Check if expected teams match
    if [[ "${filtered_teams}" == "${expected_teams}" ]]; then
        print_pass "Expected teams: ${expected_teams}, Got: ${filtered_teams}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_fail "Expected teams: ${expected_teams}, Got: ${filtered_teams}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    echo ""
}

# Main test suite
print_header "Team Filtering Test Suite"

echo "Testing jenkins-master-v2 role team filtering functionality"
echo "Project root: ${PROJECT_ROOT}"
echo "Inventory: ${INVENTORY}"
echo ""

# Test 1: Deploy all teams (default)
run_test \
    "Deploy all teams (default, no parameters)" \
    "devops, ma, ba, tw" \
    ""

# Test 2: Deploy specific single team
run_test \
    "Deploy specific single team (devops)" \
    "devops" \
    "-e deploy_teams=devops"

# Test 3: Deploy multiple teams
run_test \
    "Deploy multiple specific teams (devops, ma)" \
    "devops, ma" \
    "-e deploy_teams=devops,ma"

# Test 4: Deploy with extra spaces
run_test \
    "Deploy teams with extra spaces (devops , ma)" \
    "devops, ma" \
    "-e 'deploy_teams=devops , ma'"

# Test 5: Exclude single team
run_test \
    "Exclude single team (exclude tw)" \
    "devops, ma, ba" \
    "-e exclude_teams=tw"

# Test 6: Exclude multiple teams
run_test \
    "Exclude multiple teams (exclude ba, tw)" \
    "devops, ma" \
    "-e exclude_teams=ba,tw"

# Test 7: Deploy all teams on specific VM (multi-VM scenario)
# This test assumes jenkins-blue has teams: devops, ma
# We'll skip this if multi_vm_enabled is not set
echo -e "${YELLOW}Test $((TESTS_RUN + 1)):${NC} Multi-VM filtering (jenkins-blue VM with devops, ma assigned)"
if grep -q "multi_vm_enabled.*true" "${INVENTORY}" 2>/dev/null; then
    run_test \
        "Multi-VM filtering on jenkins-blue (should filter to devops, ma)" \
        "devops, ma" \
        "--limit jenkins-blue"
else
    echo -e "${YELLOW}⊘ SKIP:${NC} Multi-VM not enabled in inventory"
    echo ""
fi

# Test 8: Deploy specific team on specific VM (multi-VM scenario)
echo -e "${YELLOW}Test $((TESTS_RUN + 1)):${NC} Multi-VM with deploy_teams filter"
if grep -q "multi_vm_enabled.*true" "${INVENTORY}" 2>/dev/null; then
    run_test \
        "Multi-VM + deploy_teams (jenkins-blue + deploy_teams=devops)" \
        "devops" \
        "--limit jenkins-blue -e deploy_teams=devops"
else
    echo -e "${YELLOW}⊘ SKIP:${NC} Multi-VM not enabled in inventory"
    echo ""
fi

# Summary
print_header "Test Summary"
echo "Total tests run: ${TESTS_RUN}"
echo -e "${GREEN}Tests passed: ${TESTS_PASSED}${NC}"
if [ ${TESTS_FAILED} -gt 0 ]; then
    echo -e "${RED}Tests failed: ${TESTS_FAILED}${NC}"
else
    echo -e "${GREEN}Tests failed: ${TESTS_FAILED}${NC}"
fi

# Exit with failure if any tests failed
if [ ${TESTS_FAILED} -gt 0 ]; then
    echo ""
    echo -e "${RED}FAILURE: Some tests failed${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}SUCCESS: All tests passed!${NC}"
    exit 0
fi
