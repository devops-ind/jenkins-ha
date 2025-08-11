#!/bin/bash
# Generate secure credentials for Jenkins HA deployment
# Usage: ./generate-secure-credentials.sh [environment]

set -euo pipefail

ENVIRONMENT=${1:-production}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VAULT_FILE="$PROJECT_DIR/ansible/inventories/$ENVIRONMENT/group_vars/all/vault.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to generate secure password
generate_password() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# Function to generate API token
generate_api_token() {
    openssl rand -hex 32
}

# Function to generate secret key
generate_secret_key() {
    openssl rand -hex 64
}

echo -e "${BLUE}🔐 Jenkins HA Secure Credential Generator${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

if [[ -f "$VAULT_FILE" && ! "$VAULT_FILE" == *.template ]]; then
    echo -e "${RED}❌ Error: Vault file already exists at $VAULT_FILE${NC}"
    echo -e "${RED}This script is for initial credential generation only.${NC}"
    echo -e "${YELLOW}Use 'ansible-vault edit $VAULT_FILE' to modify existing credentials.${NC}"
    exit 1
fi

echo -e "${YELLOW}⚠️  SECURITY WARNING:${NC}"
echo -e "${YELLOW}This script will generate a vault file with secure credentials.${NC}"
echo -e "${YELLOW}The vault file MUST be encrypted immediately after generation.${NC}"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo ""
echo -e "${BLUE}📧 Please provide your organization details:${NC}"
read -p "Company domain (e.g., company.com): " COMPANY_DOMAIN
read -p "DevOps email (e.g., devops@$COMPANY_DOMAIN): " DEVOPS_EMAIL
read -p "Organization name: " ORG_NAME

echo ""
echo -e "${BLUE}🔑 Generating secure credentials...${NC}"

# Generate all passwords and tokens
JENKINS_ADMIN_PASSWORD=$(generate_password 24)
JENKINS_API_TOKEN=$(generate_api_token)
JENKINS_SECRET_KEY=$(generate_secret_key)
JENKINS_AGENT_SECRET=$(generate_password 32)

LDAP_BIND_PASSWORD=$(generate_password 24)
JENKINS_DB_PASSWORD=$(generate_password 24)

HARBOR_ADMIN_PASSWORD=$(generate_password 24)
HARBOR_DB_PASSWORD=$(generate_password 24)
HARBOR_REGISTRY_PASSWORD=$(generate_password 24)
HARBOR_ROBOT_TOKEN=$(generate_api_token)

GRAFANA_ADMIN_PASSWORD=$(generate_password 24)
GRAFANA_SECRET_KEY=$(generate_password 32)
GRAFANA_DB_PASSWORD=$(generate_password 24)

PROMETHEUS_BASIC_AUTH_PASSWORD=$(generate_password 24)
PROMETHEUS_WEB_CONFIG_PASSWORD=$(generate_password 24)

ALERTMANAGER_AUTH_PASSWORD=$(generate_password 24)

VIP_AUTH_PASS=$(generate_password 24)
HAPROXY_STATS_PASSWORD=$(generate_password 24)
CLUSTER_AUTH_TOKEN=$(generate_api_token)

CA_KEY_PASSWORD=$(generate_password 24)
CA_CERT_PASSWORD=$(generate_password 24)
JENKINS_SSL_KEY_PASSWORD=$(generate_password 24)
HARBOR_SSL_KEY_PASSWORD=$(generate_password 24)
GRAFANA_SSL_KEY_PASSWORD=$(generate_password 24)
PROMETHEUS_SSL_KEY_PASSWORD=$(generate_password 24)

BACKUP_ENCRYPTION_KEY=$(generate_password 32)
BACKUP_PASSPHRASE=$(generate_password 24)
NFS_AUTH_PASSWORD=$(generate_password 24)

SMTP_PASSWORD=$(generate_password 24)
ARTIFACTORY_PASSWORD=$(generate_password 24)
ARTIFACTORY_API_KEY=$(generate_api_token)

SECURITY_SCANNER_API_KEY=$(generate_api_token)
VULNERABILITY_DB_TOKEN=$(generate_api_token)

EMERGENCY_SSH_KEY=$(generate_password 32)
BREAK_GLASS_PASSWORD=$(generate_password 24)

# Create the vault file
cat > "$VAULT_FILE" << EOF
---
# Production Vault Variables - ENCRYPTED with ansible-vault
# Generated on: $(date)
# Use: ansible-vault edit vault.yml to modify these values
# Vault password should be stored securely (not in repo)

# Infrastructure Access Credentials
vault_ansible_user: "jenkins-admin"
vault_ssh_private_key_file: "/etc/ansible/keys/jenkins-prod-key"

# Network Configuration - Production IPs
vault_jenkins_master_01_ip: "10.0.1.10"
vault_jenkins_master_02_ip: "10.0.1.11"
vault_jenkins_agent_01_ip: "10.0.1.20"
vault_jenkins_agent_02_ip: "10.0.1.21"
vault_jenkins_agent_03_ip: "10.0.1.22"
vault_monitoring_01_ip: "10.0.1.30"
vault_harbor_01_ip: "10.0.1.40"
vault_lb_01_ip: "10.0.1.50"
vault_lb_02_ip: "10.0.1.51"
vault_storage_01_ip: "10.0.1.60"

# Virtual IPs for Load Balancer
vault_jenkins_vip: "10.0.1.100"
vault_monitoring_vip: "10.0.1.101"
vault_harbor_vip: "10.0.1.102"

# Jenkins Security Configuration
vault_jenkins_admin_username: "admin"
vault_jenkins_admin_password: "$JENKINS_ADMIN_PASSWORD"
vault_jenkins_admin_email: "jenkins-admin@$COMPANY_DOMAIN"
vault_jenkins_api_token: "$JENKINS_API_TOKEN"
vault_jenkins_secret_key: "$JENKINS_SECRET_KEY"
vault_jenkins_agent_secret: "$JENKINS_AGENT_SECRET"

# LDAP Integration (if enabled)
vault_ldap_server: "ldap://ldap.$COMPANY_DOMAIN:389"
vault_ldap_bind_dn: "cn=jenkins-service,ou=ServiceAccounts,dc=${COMPANY_DOMAIN//./ dc=}"
vault_ldap_bind_password: "$LDAP_BIND_PASSWORD"
vault_ldap_user_search_base: "ou=Users,dc=${COMPANY_DOMAIN//./ dc=}"
vault_ldap_group_search_base: "ou=Groups,dc=${COMPANY_DOMAIN//./ dc=}"

# Database Credentials
vault_jenkins_db_username: "jenkins_prod"
vault_jenkins_db_password: "$JENKINS_DB_PASSWORD"
vault_jenkins_db_name: "jenkins_production"
vault_jenkins_db_host: "db.$COMPANY_DOMAIN"

# Harbor Registry Credentials
vault_harbor_admin_username: "admin"
vault_harbor_admin_password: "$HARBOR_ADMIN_PASSWORD"
vault_harbor_database_password: "$HARBOR_DB_PASSWORD"
vault_harbor_registry_username: "jenkins-registry"
vault_harbor_registry_password: "$HARBOR_REGISTRY_PASSWORD"
vault_harbor_robot_token: "$HARBOR_ROBOT_TOKEN"

# Monitoring Stack Credentials
vault_grafana_admin_username: "admin"
vault_grafana_admin_password: "$GRAFANA_ADMIN_PASSWORD"
vault_grafana_secret_key: "$GRAFANA_SECRET_KEY"
vault_grafana_database_password: "$GRAFANA_DB_PASSWORD"

vault_prometheus_basic_auth_username: "prometheus"
vault_prometheus_basic_auth_password: "$PROMETHEUS_BASIC_AUTH_PASSWORD"
vault_prometheus_web_config_password: "$PROMETHEUS_WEB_CONFIG_PASSWORD"

vault_alertmanager_auth_username: "alertmanager"
vault_alertmanager_auth_password: "$ALERTMANAGER_AUTH_PASSWORD"
vault_alertmanager_webhook_url: "https://hooks.slack.com/services/CHANGE_TO_REAL_WEBHOOK"

# High Availability Configuration
vault_vip_auth_pass: "$VIP_AUTH_PASS"
vault_haproxy_stats_user: "haproxy-admin"
vault_haproxy_stats_password: "$HAPROXY_STATS_PASSWORD"
vault_cluster_auth_token: "$CLUSTER_AUTH_TOKEN"

# SSL Certificate Configuration
vault_ssl_country: "US"
vault_ssl_state: "California"
vault_ssl_city: "San Francisco"
vault_ssl_organization: "$ORG_NAME"
vault_ssl_organizational_unit: "DevOps"
vault_ssl_email: "$DEVOPS_EMAIL"

# Certificate Authority
vault_ca_key_password: "$CA_KEY_PASSWORD"
vault_ca_cert_password: "$CA_CERT_PASSWORD"

# SSL Certificate Passwords
vault_jenkins_ssl_key_password: "$JENKINS_SSL_KEY_PASSWORD"
vault_harbor_ssl_key_password: "$HARBOR_SSL_KEY_PASSWORD"
vault_grafana_ssl_key_password: "$GRAFANA_SSL_KEY_PASSWORD"
vault_prometheus_ssl_key_password: "$PROMETHEUS_SSL_KEY_PASSWORD"

# Backup and Storage Credentials
vault_backup_encryption_key: "$BACKUP_ENCRYPTION_KEY"
vault_backup_s3_access_key: "CHANGE_TO_REAL_AWS_ACCESS_KEY"
vault_backup_s3_secret_key: "CHANGE_TO_REAL_AWS_SECRET_KEY"
vault_backup_s3_bucket: "jenkins-production-backups"
vault_backup_passphrase: "$BACKUP_PASSPHRASE"

vault_nfs_auth_user: "nfs-jenkins"
vault_nfs_auth_password: "$NFS_AUTH_PASSWORD"

# External Service Integrations
vault_slack_webhook_url: "https://hooks.slack.com/services/CHANGE_TO_REAL_WEBHOOK"
vault_slack_channel: "#jenkins-alerts"
vault_slack_username: "Jenkins Production"

vault_email_smtp_host: "smtp.$COMPANY_DOMAIN"
vault_email_smtp_port: "587"
vault_email_smtp_username: "jenkins-alerts@$COMPANY_DOMAIN"
vault_email_smtp_password: "$SMTP_PASSWORD"

vault_jira_url: "https://${ORG_NAME,,}.atlassian.net"
vault_jira_username: "jenkins-integration@$COMPANY_DOMAIN"
vault_jira_api_token: "CHANGE_TO_REAL_JIRA_API_TOKEN"

vault_sonarqube_url: "https://sonar.$COMPANY_DOMAIN"
vault_sonarqube_token: "CHANGE_TO_REAL_SONARQUBE_TOKEN"

vault_artifactory_url: "https://artifactory.$COMPANY_DOMAIN"
vault_artifactory_username: "jenkins-artifactory"
vault_artifactory_password: "$ARTIFACTORY_PASSWORD"
vault_artifactory_api_key: "$ARTIFACTORY_API_KEY"

# Security Scanning Tools
vault_security_scanner_api_key: "$SECURITY_SCANNER_API_KEY"
vault_vulnerability_db_token: "$VULNERABILITY_DB_TOKEN"

# License Keys
vault_jenkins_enterprise_license: "CHANGE_TO_REAL_LICENSE_KEY"
vault_harbor_enterprise_license: "CHANGE_TO_REAL_LICENSE_KEY"

# Emergency Access
vault_emergency_ssh_key: "$EMERGENCY_SSH_KEY"
vault_break_glass_password: "$BREAK_GLASS_PASSWORD"
EOF

echo ""
echo -e "${GREEN}✅ Secure credentials generated successfully!${NC}"
echo -e "${GREEN}Vault file created: $VAULT_FILE${NC}"
echo ""

# Create credentials summary for secure storage
CREDENTIALS_SUMMARY_FILE="$PROJECT_DIR/generated-credentials-$(date +%Y%m%d-%H%M%S).txt"
cat > "$CREDENTIALS_SUMMARY_FILE" << EOF
Jenkins HA Secure Credentials Summary
Generated: $(date)
Environment: $ENVIRONMENT

=== CRITICAL: Store these credentials securely ===

Jenkins Admin: admin / $JENKINS_ADMIN_PASSWORD
Grafana Admin: admin / $GRAFANA_ADMIN_PASSWORD  
Harbor Admin: admin / $HARBOR_ADMIN_PASSWORD
HAProxy Stats: haproxy-admin / $HAPROXY_STATS_PASSWORD

Emergency Access: $BREAK_GLASS_PASSWORD

=== Next Steps ===
1. IMMEDIATELY encrypt the vault file:
   ansible-vault encrypt $VAULT_FILE

2. Store the vault password securely (not in this repo)

3. Update external service tokens (marked as CHANGE_TO_REAL_*)

4. Delete this summary file after securely storing credentials:
   rm $CREDENTIALS_SUMMARY_FILE
EOF

echo -e "${RED}🚨 CRITICAL SECURITY STEPS:${NC}"
echo ""
echo -e "${YELLOW}1. IMMEDIATELY encrypt the vault file:${NC}"
echo -e "${BLUE}   ansible-vault encrypt $VAULT_FILE${NC}"
echo ""
echo -e "${YELLOW}2. Credentials summary created: $CREDENTIALS_SUMMARY_FILE${NC}"
echo -e "${RED}   Review and securely store these credentials, then DELETE this file!${NC}"
echo ""
echo -e "${YELLOW}3. Update external service tokens in the vault file (marked as CHANGE_TO_REAL_*)${NC}"
echo ""
echo -e "${YELLOW}4. Store the vault password securely (NOT in the repository)${NC}"
echo ""

chmod 600 "$CREDENTIALS_SUMMARY_FILE"
echo -e "${GREEN}✅ Credential generation complete. Follow security steps above!${NC}"