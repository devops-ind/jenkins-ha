#!/bin/bash

# Jenkins Systemd Debug Script
# Diagnoses systemd service issues with Jenkins blue-green infrastructure

set -e

echo "🔍 Jenkins Systemd Service Debug Tool"
echo "======================================"

# Check systemd service file
echo "1. Systemd Service File Check:"
SERVICE_FILE="/etc/systemd/system/jenkins-master.service"
if [ -f "$SERVICE_FILE" ]; then
    echo "✅ Service file exists: $SERVICE_FILE"
    echo "   Permissions: $(ls -la $SERVICE_FILE)"
    echo "   Size: $(stat -c%s $SERVICE_FILE 2>/dev/null || stat -f%z $SERVICE_FILE 2>/dev/null) bytes"
else
    echo "❌ Service file missing: $SERVICE_FILE"
fi

# Check systemd daemon status
echo ""
echo "2. Systemd Daemon Status:"
systemctl daemon-reload
echo "✅ Daemon reloaded"

# List all services matching jenkins
echo ""
echo "3. Jenkins Services:"
systemctl list-units --all | grep jenkins || echo "No Jenkins services found"

# Check service status
echo ""
echo "4. Service Status:"
if systemctl list-units --all | grep -q jenkins-master; then
    echo "Service found in systemd"
    systemctl status jenkins-master --no-pager || true
else
    echo "❌ jenkins-master service not found in systemd"
fi

# Check logs
echo ""
echo "5. Service Logs:"
journalctl -u jenkins-master --no-pager -n 20 || echo "No logs found"

# Check file syntax
echo ""
echo "6. Service File Syntax:"
if [ -f "$SERVICE_FILE" ]; then
    echo "Service file content:"
    cat "$SERVICE_FILE"
    
    # Basic syntax check
    if grep -q "^\[Unit\]" "$SERVICE_FILE" && grep -q "^\[Service\]" "$SERVICE_FILE" && grep -q "^\[Install\]" "$SERVICE_FILE"; then
        echo "✅ Basic service file structure looks correct"
    else
        echo "❌ Service file structure may be invalid"
    fi
fi

echo ""
echo "🔍 Debug complete. If service still fails, check the service file syntax and permissions."