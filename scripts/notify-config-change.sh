#!/bin/bash
# Configuration Change Notification Script
# Sends notifications about Jenkins configuration changes

set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 --team TEAM --message MESSAGE [OPTIONS]

Sends notifications about Jenkins configuration changes.

Required Arguments:
  --team TEAM           Team name
  --message MESSAGE     Notification message

Options:
  --title TITLE         Notification title (default: "Jenkins Config Update")
  --severity LEVEL      Severity level: info|warning|critical (default: info)
  --channel CHANNEL     Notification channel: email|slack|teams|grafana|all (default: all)
  --environment ENV     Environment (blue|green)
  --help                Show this help message

Environment Variables:
  SLACK_WEBHOOK_URL     Slack webhook URL
  TEAMS_WEBHOOK_URL     Microsoft Teams webhook URL
  NOTIFICATION_EMAIL    Email address for notifications
  GRAFANA_URL           Grafana URL for annotations
  GRAFANA_API_KEY       Grafana API key

Examples:
  $0 --team devops --message "Config deployed to standby"
  $0 --team devops --message "Traffic switched" --severity warning
  $0 --team devops --message "Deployment failed" --severity critical --channel slack

Exit codes:
  0 - Notification sent successfully
  1 - Notification failed
  2 - Usage error
EOF
    exit 2
}

send_slack_notification() {
    local title=$1
    local message=$2
    local severity=$3
    local team=$4

    if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
        echo "SLACK_WEBHOOK_URL not set, skipping Slack notification"
        return 0
    fi

    # Color based on severity
    local color="#36a64f"  # green
    case $severity in
        warning) color="#ff9900" ;;  # orange
        critical) color="#ff0000" ;;  # red
    esac

    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "${color}",
            "title": "${title}",
            "text": "${message}",
            "fields": [
                {
                    "title": "Team",
                    "value": "${team}",
                    "short": true
                },
                {
                    "title": "Severity",
                    "value": "${severity}",
                    "short": true
                },
                {
                    "title": "Timestamp",
                    "value": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
                    "short": true
                }
            ]
        }
    ]
}
EOF
)

    if curl -s -X POST -H 'Content-Type: application/json' \
        -d "$payload" "$SLACK_WEBHOOK_URL" >/dev/null; then
        echo "✅ Slack notification sent"
        return 0
    else
        echo "❌ Failed to send Slack notification"
        return 1
    fi
}

send_teams_notification() {
    local title=$1
    local message=$2
    local severity=$3
    local team=$4

    if [[ -z "${TEAMS_WEBHOOK_URL:-}" ]]; then
        echo "TEAMS_WEBHOOK_URL not set, skipping Teams notification"
        return 0
    fi

    # Theme color based on severity
    local theme_color="00FF00"  # green
    case $severity in
        warning) theme_color="FFA500" ;;  # orange
        critical) theme_color="FF0000" ;;  # red
    esac

    local payload=$(cat <<EOF
{
    "@type": "MessageCard",
    "@context": "https://schema.org/extensions",
    "summary": "${title}",
    "themeColor": "${theme_color}",
    "title": "${title}",
    "sections": [
        {
            "activityTitle": "${message}",
            "facts": [
                {
                    "name": "Team:",
                    "value": "${team}"
                },
                {
                    "name": "Severity:",
                    "value": "${severity}"
                },
                {
                    "name": "Timestamp:",
                    "value": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
                }
            ]
        }
    ]
}
EOF
)

    if curl -s -X POST -H 'Content-Type: application/json' \
        -d "$payload" "$TEAMS_WEBHOOK_URL" >/dev/null; then
        echo "✅ Teams notification sent"
        return 0
    else
        echo "❌ Failed to send Teams notification"
        return 1
    fi
}

send_email_notification() {
    local title=$1
    local message=$2
    local severity=$3
    local team=$4

    if [[ -z "${NOTIFICATION_EMAIL:-}" ]]; then
        echo "NOTIFICATION_EMAIL not set, skipping email notification"
        return 0
    fi

    # Check if mail command is available
    if ! command -v mail &>/dev/null; then
        echo "mail command not found, skipping email notification"
        return 0
    fi

    local subject="[${severity^^}] ${title} - ${team}"

    local body=$(cat <<EOF
Jenkins Configuration Update Notification

Team: ${team}
Severity: ${severity}
Timestamp: $(date)

Message:
${message}

---
This is an automated notification from Jenkins HA infrastructure.
EOF
)

    if echo "$body" | mail -s "$subject" "$NOTIFICATION_EMAIL"; then
        echo "✅ Email notification sent to $NOTIFICATION_EMAIL"
        return 0
    else
        echo "❌ Failed to send email notification"
        return 1
    fi
}

send_grafana_annotation() {
    local title=$1
    local message=$2
    local severity=$3
    local team=$4

    if [[ -z "${GRAFANA_URL:-}" ]] || [[ -z "${GRAFANA_API_KEY:-}" ]]; then
        echo "GRAFANA_URL or GRAFANA_API_KEY not set, skipping Grafana annotation"
        return 0
    fi

    # Tags based on severity
    local tags="config-update,${team},${severity}"

    local payload=$(cat <<EOF
{
    "tags": ["${tags}"],
    "text": "${title}: ${message}",
    "time": $(date +%s)000
}
EOF
)

    if curl -s -X POST \
        -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${GRAFANA_URL}/api/annotations" >/dev/null; then
        echo "✅ Grafana annotation created"
        return 0
    else
        echo "❌ Failed to create Grafana annotation"
        return 1
    fi
}

main() {
    local team=""
    local message=""
    local title="Jenkins Config Update"
    local severity="info"
    local channel="all"
    local environment=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --team)
                team="$2"
                shift 2
                ;;
            --message)
                message="$2"
                shift 2
                ;;
            --title)
                title="$2"
                shift 2
                ;;
            --severity)
                severity="$2"
                shift 2
                ;;
            --channel)
                channel="$2"
                shift 2
                ;;
            --environment)
                environment="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                echo "Unknown argument: $1"
                usage
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$team" ]] || [[ -z "$message" ]]; then
        echo "Team and message are required"
        usage
    fi

    # Validate severity
    if [[ "$severity" != "info" ]] && [[ "$severity" != "warning" ]] && [[ "$severity" != "critical" ]]; then
        echo "Invalid severity: $severity (must be info, warning, or critical)"
        exit 2
    fi

    # Add environment to message if provided
    if [[ -n "$environment" ]]; then
        message="${message} (environment: ${environment})"
    fi

    echo "Sending notifications..."
    echo "Team: $team"
    echo "Title: $title"
    echo "Message: $message"
    echo "Severity: $severity"
    echo "Channel: $channel"
    echo ""

    local failed=0

    # Send to requested channels
    case $channel in
        slack)
            send_slack_notification "$title" "$message" "$severity" "$team" || ((failed++))
            ;;
        teams)
            send_teams_notification "$title" "$message" "$severity" "$team" || ((failed++))
            ;;
        email)
            send_email_notification "$title" "$message" "$severity" "$team" || ((failed++))
            ;;
        grafana)
            send_grafana_annotation "$title" "$message" "$severity" "$team" || ((failed++))
            ;;
        all)
            send_slack_notification "$title" "$message" "$severity" "$team" || true
            send_teams_notification "$title" "$message" "$severity" "$team" || true
            send_email_notification "$title" "$message" "$severity" "$team" || true
            send_grafana_annotation "$title" "$message" "$severity" "$team" || true
            ;;
        *)
            echo "Invalid channel: $channel"
            exit 2
            ;;
    esac

    if [[ $failed -gt 0 ]]; then
        echo "⚠️  Some notifications failed"
        exit 1
    else
        echo "✅ Notifications sent successfully"
        exit 0
    fi
}

main "$@"
