#!/bin/bash

# Jenkins Health Check Script
# Used by Docker health checks

set -e

# Configuration
JENKINS_PORT="${JENKINS_PORT:-8080}"
JENKINS_HOST="${JENKINS_HOST:-localhost}"
JENKINS_CONTEXT="${JENKINS_CONTEXT:-}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"

# Build the health check URL
HEALTH_URL="http://${JENKINS_HOST}:${JENKINS_PORT}${JENKINS_CONTEXT}/login"

echo "Checking Jenkins health at: $HEALTH_URL"

# Perform health check
if command -v curl >/dev/null 2>&1; then
    # Use curl if available
    if curl -f -s --max-time "$HEALTH_CHECK_TIMEOUT" "$HEALTH_URL" >/dev/null; then
        echo "Jenkins is healthy"
        exit 0
    else
        echo "Jenkins health check failed (curl)"
        exit 1
    fi
elif command -v wget >/dev/null 2>&1; then
    # Fallback to wget
    if wget -q --timeout="$HEALTH_CHECK_TIMEOUT" --tries=1 -O /dev/null "$HEALTH_URL"; then
        echo "Jenkins is healthy"
        exit 0
    else
        echo "Jenkins health check failed (wget)"
        exit 1
    fi
else
    # Fallback to checking if the process is running
    if pgrep -f jenkins.war >/dev/null; then
        echo "Jenkins process is running"
        exit 0
    else
        echo "Jenkins process not found"
        exit 1
    fi
fi