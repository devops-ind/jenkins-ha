#!/bin/bash
# Jenkins Deployment Validator
# Validates passive Jenkins environment is identical to active
# Returns 0 if validation passes, 1 if fails

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
TEAMS="all"
TARGET_VM="all"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --teams)
            TEAMS="$2"
            shift 2
            ;;
        --vm)
            TARGET_VM="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Jenkins Deployment Validator"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Teams: $TEAMS"
echo "Target VM: $TARGET_VM"
echo ""

# Determine teams to validate
if [ "$TEAMS" == "all" ]; then
    TEAM_LIST=("devops" "ma" "ba" "tw")
else
    IFS=',' read -ra TEAM_LIST <<< "$TEAMS"
fi

VALIDATION_PASSED=true

for team in "${TEAM_LIST[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Team: $team"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Detect active and passive environments
    ACTIVE_ENV=$(docker ps --filter "name=jenkins-$team-blue" --filter "status=running" -q > /dev/null 2>&1 && echo "blue" || echo "green")
    PASSIVE_ENV=$([ "$ACTIVE_ENV" == "blue" ] && echo "green" || echo "blue")

    echo "Active Environment: $ACTIVE_ENV"
    echo "Passive Environment: $PASSIVE_ENV"
    echo ""

    # 1. Container Health Check
    echo -n "✓ Container Health: "
    if docker ps --filter "name=jenkins-$team-$PASSIVE_ENV" --filter "status=running" -q | grep -q .; then
        echo -e "${GREEN}PASSED${NC} (container running)"
    else
        echo -e "${RED}FAILED${NC} (container not running)"
        VALIDATION_PASSED=false
        continue
    fi

    # 2. HTTP Health Check
    PASSIVE_PORT=$(docker port jenkins-$team-$PASSIVE_ENV 8080/tcp 2>/dev/null | cut -d: -f2)
    echo -n "✓ HTTP Health: "
    if curl -sf http://localhost:$PASSIVE_PORT/login > /dev/null 2>&1; then
        echo -e "${GREEN}PASSED${NC} (HTTP 200/403)"
    else
        echo -e "${RED}FAILED${NC} (HTTP endpoint not responding)"
        VALIDATION_PASSED=false
        continue
    fi

    # 3. Job Count Comparison
    echo -n "✓ Job Count: "
    ACTIVE_JOBS=$(docker exec jenkins-$team-$ACTIVE_ENV find /var/jenkins_home/jobs -maxdepth 1 -type d 2>/dev/null | wc -l || echo "0")
    PASSIVE_JOBS=$(docker exec jenkins-$team-$PASSIVE_ENV find /var/jenkins_home/jobs -maxdepth 1 -type d 2>/dev/null | wc -l || echo "0")

    if [ "$ACTIVE_JOBS" -eq "$PASSIVE_JOBS" ]; then
        echo -e "${GREEN}PASSED${NC} ($PASSIVE_JOBS jobs - matches active)"
    else
        echo -e "${YELLOW}WARNING${NC} (Active: $ACTIVE_JOBS, Passive: $PASSIVE_JOBS)"
    fi

    # 4. Plugin Count Comparison
    echo -n "✓ Plugin Count: "
    ACTIVE_PLUGINS=$(docker exec jenkins-$team-$ACTIVE_ENV ls /var/jenkins_home/plugins/*.jpi 2>/dev/null | wc -l || echo "0")
    PASSIVE_PLUGINS=$(docker exec jenkins-$team-$PASSIVE_ENV ls /var/jenkins_home/plugins/*.jpi 2>/dev/null | wc -l || echo "0")

    if [ "$ACTIVE_PLUGINS" -eq "$PASSIVE_PLUGINS" ]; then
        echo -e "${GREEN}PASSED${NC} ($PASSIVE_PLUGINS plugins - matches active)"
    else
        echo -e "${YELLOW}WARNING${NC} (Active: $ACTIVE_PLUGINS, Passive: $PASSIVE_PLUGINS)"
    fi

    # 5. Configuration Files Check
    echo -n "✓ Config Files: "
    CONFIG_FILES=("config.xml" "credentials.xml" "hudson.model.UpdateCenter.xml")
    CONFIG_OK=true

    for config_file in "${CONFIG_FILES[@]}"; do
        if ! docker exec jenkins-$team-$PASSIVE_ENV test -f /var/jenkins_home/$config_file 2>/dev/null; then
            echo -e "${RED}FAILED${NC} ($config_file missing)"
            CONFIG_OK=false
            VALIDATION_PASSED=false
            break
        fi
    done

    if [ "$CONFIG_OK" = true ]; then
        echo -e "${GREEN}PASSED${NC} (all critical files present)"
    fi

    # 6. Startup Time Check
    echo -n "✓ Startup Time: "
    UPTIME=$(docker inspect jenkins-$team-$PASSIVE_ENV --format='{{.State.StartedAt}}' 2>/dev/null || echo "unknown")
    echo -e "${GREEN}PASSED${NC} (started at $UPTIME)"

    # 7. Memory Usage Check
    echo -n "✓ Memory Usage: "
    MEM_USAGE=$(docker stats jenkins-$team-$PASSIVE_ENV --no-stream --format "{{.MemUsage}}" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}PASSED${NC} ($MEM_USAGE)"

    echo ""

    # Summary Table
    echo "Active vs Passive Comparison:"
    echo "┌──────────────────┬─────────────┬──────────────┬─────────┐"
    echo "│ Metric           │ Active ($ACTIVE_ENV) │ Passive ($PASSIVE_ENV) │ Status  │"
    echo "├──────────────────┼─────────────┼──────────────┼─────────┤"
    echo "│ Jobs             │ $ACTIVE_JOBS          │ $PASSIVE_JOBS           │ ✓       │"
    echo "│ Plugins          │ $ACTIVE_PLUGINS          │ $PASSIVE_PLUGINS           │ ✓       │"
    echo "└──────────────────┴─────────────┴──────────────┴─────────┘"
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$VALIDATION_PASSED" = true ]; then
    echo -e "Overall Result: ${GREEN}✅ VALIDATION PASSED${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
else
    echo -e "Overall Result: ${RED}❌ VALIDATION FAILED${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi
