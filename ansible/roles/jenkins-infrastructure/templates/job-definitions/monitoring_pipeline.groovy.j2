<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.47">
  <actions/>
  <description>Infrastructure Pipeline: Monitoring Stack Management

This pipeline manages the monitoring infrastructure including:
- Prometheus configuration updates
- Grafana dashboard deployment
- Alertmanager rule management
- Monitoring stack health verification
- Performance metrics collection
- Custom dashboard creation and updates

Used for maintaining and updating the monitoring infrastructure.
</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <jenkins.model.BuildDiscarderProperty>
      <strategy class="hudson.tasks.LogRotator">
        <daysToKeep>30</daysToKeep>
        <numToKeep>20</numToKeep>
        <artifactDaysToKeep>-1</artifactDaysToKeep>
        <artifactNumToKeep>-1</artifactNumToKeep>
      </strategy>
    </jenkins.model.BuildDiscarderProperty>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <n>ACTION</n>
          <description>Monitoring action to perform</description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>deploy</string>
              <string>update-config</string>
              <string>update-dashboards</string>
              <string>update-alerts</string>
              <string>health-check</string>
              <string>restart-services</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <n>UPDATE_PROMETHEUS</n>
          <description>Update Prometheus configuration</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <n>UPDATE_GRAFANA</n>
          <description>Update Grafana dashboards and datasources</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <n>UPDATE_ALERTMANAGER</n>
          <description>Update Alertmanager configuration</description>
          <defaultValue>false</defaultValue>
        </hudson.model.BooleanParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <n>RESTART_SERVICES</n>
          <description>Restart monitoring services after updates</description>
          <defaultValue>false</defaultValue>
        </hudson.model.BooleanParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <n>CUSTOM_DASHBOARD</n>
          <description>Deploy specific dashboard (JSON file name)</description>
          <defaultValue></defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.94">
    <script>#!/usr/bin/env groovy

pipeline {
    agent {
        label 'dind docker-manager static privileged'
    }
    
    options {
        buildDiscarder(logRotator(daysToKeepStr: '30', numToKeepStr: '20'))
        timeout(time: 1, unit: 'HOURS')
        timestamps()
        ansiColor('xterm')
        skipDefaultCheckout()
    }
    
    environment {
        ANSIBLE_HOST_KEY_CHECKING = 'False'
        ANSIBLE_STDOUT_CALLBACK = 'yaml'
        MONITORING_HOST = '{{ hostvars[groups["monitoring"][0]]["ansible_default_ipv4"]["address"] | default("localhost") }}'
        PROMETHEUS_URL = "http://${MONITORING_HOST}:9090"
        GRAFANA_URL = "http://${MONITORING_HOST}:3000"
        GRAFANA_CREDENTIALS = credentials('grafana-admin')
        TIMESTAMP = sh(script: 'date +%Y%m%d_%H%M%S', returnStdout: true).trim()
        HOSTNAME = sh(script: 'hostname', returnStdout: true).trim()
    }
    
    stages {
        stage('Initialize Monitoring Pipeline') {
            steps {
                script {
                    echo "📊 Jenkins Monitoring Stack Management"
                    echo "🎯 Action: ${params.ACTION}"
                    echo "⏰ Timestamp: ${TIMESTAMP}"
                    echo "🖥️ Hostname: ${HOSTNAME}"
                    echo "📊 Monitoring Host: ${MONITORING_HOST}"
                    echo "📈 Prometheus: ${params.UPDATE_PROMETHEUS}"
                    echo "📊 Grafana: ${params.UPDATE_GRAFANA}"
                    echo "🚨 Alertmanager: ${params.UPDATE_ALERTMANAGER}"
                    
                    currentBuild.description = "Monitoring ${params.ACTION} - ${TIMESTAMP}"
                }
            }
        }
        
        stage('Checkout Infrastructure Repository') {
            steps {
                script {
                    echo "📥 Checking out infrastructure repository..."
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],
                        userRemoteConfigs: [[
                            url: '{{ jenkins_infrastructure_repo_url }}',
                            credentialsId: '{{ git_credentials_id }}'
                        ]]
                    ])
                }
            }
        }
        
        stage('Monitoring Stack Health Check') {
            when {
                anyOf {
                    equals expected: 'health-check', actual: params.ACTION
                    equals expected: 'deploy', actual: params.ACTION
                }
            }
            steps {
                script {
                    echo "🏥 Checking monitoring stack health..."
                    
                    sh """
                        echo "=== Monitoring Health Check ==="
                        
                        # Check Prometheus
                        echo "🔍 Checking Prometheus..."
                        if curl -f -s --connect-timeout 10 ${PROMETHEUS_URL}/api/v1/query?query=up > /dev/null; then
                            echo "✅ Prometheus: ACCESSIBLE"
                            
                            # Get Prometheus targets status
                            TARGETS_UP=\$(curl -s ${PROMETHEUS_URL}/api/v1/query?query=up | jq '.data.result | map(select(.value[1] == "1")) | length' 2>/dev/null || echo 0)
                            TARGETS_DOWN=\$(curl -s ${PROMETHEUS_URL}/api/v1/query?query=up | jq '.data.result | map(select(.value[1] == "0")) | length' 2>/dev/null || echo 0)
                            
                            echo "📈 Targets UP: \${TARGETS_UP}"
                            echo "📉 Targets DOWN: \${TARGETS_DOWN}"
                            
                            if [ "\${TARGETS_DOWN}" -gt "0" ]; then
                                echo "⚠️ Some monitoring targets are down"
                            fi
                        else
                            echo "❌ Prometheus: NOT ACCESSIBLE"
                            exit 1
                        fi
                        
                        # Check Grafana
                        echo "🔍 Checking Grafana..."
                        if curl -f -s --connect-timeout 10 ${GRAFANA_URL}/api/health > /dev/null; then
                            echo "✅ Grafana: ACCESSIBLE"
                            
                            # Get Grafana info
                            GRAFANA_VERSION=\$(curl -s ${GRAFANA_URL}/api/health | jq -r '.version' 2>/dev/null || echo "unknown")
                            echo "📊 Grafana version: \${GRAFANA_VERSION}"
                        else
                            echo "❌ Grafana: NOT ACCESSIBLE"
                            exit 1
                        fi
                        
                        # Check Alertmanager (if enabled)
                        if curl -f -s --connect-timeout 5 http://${MONITORING_HOST}:9093/api/v1/status > /dev/null; then
                            echo "✅ Alertmanager: ACCESSIBLE"
                        else
                            echo "ℹ️ Alertmanager: NOT ACCESSIBLE (may be disabled)"
                        fi
                        
                        echo "✅ Monitoring stack health check completed"
                    """
                }
            }
        }
        
        stage('Deploy Monitoring Stack') {
            when {
                equals expected: 'deploy', actual: params.ACTION
            }
            steps {
                script {
                    echo "🚀 Deploying monitoring stack..."
                    
                    sh """
                        cd ansible
                        
                        # Deploy monitoring stack
                        ANSIBLE_VAULT_PASSWORD_FILE=../environments/vault-passwords/production.txt \
                        ansible-playbook -i inventories/production deploy-monitoring.yml \
                            -e deployment_environment=production \
                            -e monitoring_enabled=true \
                            -e prometheus_update=${params.UPDATE_PROMETHEUS} \
                            -e grafana_update=${params.UPDATE_GRAFANA} \
                            -e alertmanager_update=${params.UPDATE_ALERTMANAGER}
                        
                        echo "✅ Monitoring stack deployment completed"
                    """
                }
            }
        }
        
        stage('Update Prometheus Configuration') {
            when {
                anyOf {
                    equals expected: 'update-config', actual: params.ACTION
                    allOf {
                        not { equals expected: 'health-check', actual: params.ACTION }
                        expression { params.UPDATE_PROMETHEUS }
                    }
                }
            }
            steps {
                script {
                    echo "📈 Updating Prometheus configuration..."
                    
                    sh """
                        cd ansible
                        
                        # Update Prometheus configuration
                        ANSIBLE_VAULT_PASSWORD_FILE=../environments/vault-passwords/production.txt \
                        ansible-playbook -i inventories/production deploy-monitoring.yml \
                            -e deployment_environment=production \
                            -e monitoring_enabled=true \
                            --tags prometheus,prometheus-config
                        
                        # Reload Prometheus configuration
                        if [ "${params.RESTART_SERVICES}" = "true" ]; then
                            echo "🔄 Reloading Prometheus configuration..."
                            curl -X POST ${PROMETHEUS_URL}/-/reload || echo "Reload failed, may need service restart"
                        fi
                        
                        echo "✅ Prometheus configuration updated"
                    """
                }
            }
        }
        
        stage('Update Grafana Dashboards') {
            when {
                anyOf {
                    equals expected: 'update-dashboards', actual: params.ACTION
                    allOf {
                        not { equals expected: 'health-check', actual: params.ACTION }
                        expression { params.UPDATE_GRAFANA }
                    }
                }
            }
            steps {
                script {
                    echo "📊 Updating Grafana dashboards..."
                    
                    sh """
                        cd ansible
                        
                        # Update Grafana dashboards
                        ANSIBLE_VAULT_PASSWORD_FILE=../environments/vault-passwords/production.txt \
                        ansible-playbook -i inventories/production deploy-monitoring.yml \
                            -e deployment_environment=production \
                            -e monitoring_enabled=true \
                            --tags grafana,grafana-dashboards
                        
                        echo "✅ Grafana dashboards updated"
                    """
                    
                    // Import dashboards via API
                    if (params.CUSTOM_DASHBOARD) {
                        echo "📋 Importing custom dashboard: ${params.CUSTOM_DASHBOARD}"
                        
                        sh """
                            # Import specific dashboard
                            if [ -f "monitoring/grafana/dashboards/${params.CUSTOM_DASHBOARD}" ]; then
                                echo "📤 Importing ${params.CUSTOM_DASHBOARD}..."
                                
                                curl -X POST \
                                     -H "Content-Type: application/json" \
                                     -u \${GRAFANA_CREDENTIALS_USR}:\${GRAFANA_CREDENTIALS_PSW} \
                                     -d @monitoring/grafana/dashboards/${params.CUSTOM_DASHBOARD} \
                                     ${GRAFANA_URL}/api/dashboards/db
                                
                                echo "✅ Custom dashboard imported"
                            else
                                echo "❌ Custom dashboard file not found: ${params.CUSTOM_DASHBOARD}"
                            fi
                        """
                    } else {
                        echo "📋 Importing all standard dashboards..."
                        
                        sh """
                            # Import all standard dashboards
                            for dashboard in monitoring/grafana/dashboards/*.json; do
                                if [ -f "\$dashboard" ]; then
                                    echo "📤 Importing \$(basename \$dashboard)..."
                                    
                                    curl -X POST \
                                         -H "Content-Type: application/json" \
                                         -u \${GRAFANA_CREDENTIALS_USR}:\${GRAFANA_CREDENTIALS_PSW} \
                                         -d @\$dashboard \
                                         ${GRAFANA_URL}/api/dashboards/db || echo "Import failed for \$dashboard"
                                fi
                            done
                            
                            echo "✅ All dashboards imported"
                        """
                    }
                }
            }
        }
        
        stage('Update Alert Rules') {
            when {
                anyOf {
                    equals expected: 'update-alerts', actual: params.ACTION
                    allOf {
                        not { equals expected: 'health-check', actual: params.ACTION }
                        expression { params.UPDATE_ALERTMANAGER }
                    }
                }
            }
            steps {
                script {
                    echo "🚨 Updating alert rules..."
                    
                    sh """
                        cd ansible
                        
                        # Update Alertmanager and alert rules
                        ANSIBLE_VAULT_PASSWORD_FILE=../environments/vault-passwords/production.txt \
                        ansible-playbook -i inventories/production deploy-monitoring.yml \
                            -e deployment_environment=production \
                            -e monitoring_enabled=true \
                            -e alertmanager_enabled=true \
                            --tags alertmanager,alert-rules
                        
                        # Reload Prometheus rules
                        if [ "${params.RESTART_SERVICES}" = "true" ]; then
                            echo "🔄 Reloading Prometheus rules..."
                            curl -X POST ${PROMETHEUS_URL}/-/reload || echo "Reload failed, may need service restart"
                        fi
                        
                        echo "✅ Alert rules updated"
                    """
                }
            }
        }
        
        stage('Restart Services') {
            when {
                anyOf {
                    equals expected: 'restart-services', actual: params.ACTION
                    expression { params.RESTART_SERVICES }
                }
            }
            steps {
                script {
                    echo "🔄 Restarting monitoring services..."
                    
                    sh """
                        cd ansible
                        
                        # Restart monitoring services
                        ANSIBLE_VAULT_PASSWORD_FILE=../environments/vault-passwords/production.txt \
                        ansible monitoring -i inventories/production -m systemd \
                            -a "name={{ item }} state=restarted" -b \
                            --extra-vars "item=prometheus" || true
                        
                        ANSIBLE_VAULT_PASSWORD_FILE=../environments/vault-passwords/production.txt \
                        ansible monitoring -i inventories/production -m systemd \
                            -a "name={{ item }} state=restarted" -b \
                            --extra-vars "item=grafana" || true
                        
                        if [ "${params.UPDATE_ALERTMANAGER}" = "true" ]; then
                            ANSIBLE_VAULT_PASSWORD_FILE=../environments/vault-passwords/production.txt \
                            ansible monitoring -i inventories/production -m systemd \
                                -a "name={{ item }} state=restarted" -b \
                                --extra-vars "item=alertmanager" || true
                        fi
                        
                        echo "✅ Services restarted"
                    """
                }
            }
        }
        
        stage('Post-Update Verification') {
            steps {
                script {
                    echo "✅ Verifying monitoring stack after updates..."
                    
                    sh """
                        echo "=== Post-Update Verification ==="
                        
                        # Wait for services to be ready
                        echo "⏳ Waiting for services to be ready..."
                        sleep 30
                        
                        # Verify Prometheus
                        echo "🔍 Verifying Prometheus..."
                        for i in {1..12}; do
                            if curl -f -s --connect-timeout 5 ${PROMETHEUS_URL}/api/v1/query?query=up > /dev/null; then
                                echo "✅ Prometheus is responsive"
                                break
                            else
                                echo "⏳ Waiting for Prometheus... (\$i/12)"
                                sleep 10
                            fi
                        done
                        
                        # Check Prometheus targets
                        TARGETS_DATA=\$(curl -s ${PROMETHEUS_URL}/api/v1/targets 2>/dev/null || echo '{"data":{"activeTargets":[]}}')
                        ACTIVE_TARGETS=\$(echo "\$TARGETS_DATA" | jq '.data.activeTargets | length' 2>/dev/null || echo 0)
                        HEALTHY_TARGETS=\$(echo "\$TARGETS_DATA" | jq '.data.activeTargets | map(select(.health == "up")) | length' 2>/dev/null || echo 0)
                        
                        echo "📊 Active targets: \${ACTIVE_TARGETS}"
                        echo "✅ Healthy targets: \${HEALTHY_TARGETS}"
                        
                        # Verify Grafana
                        echo "🔍 Verifying Grafana..."
                        for i in {1..12}; do
                            if curl -f -s --connect-timeout 5 ${GRAFANA_URL}/api/health > /dev/null; then
                                echo "✅ Grafana is responsive"
                                break
                            else
                                echo "⏳ Waiting for Grafana... (\$i/12)"
                                sleep 10
                            fi
                        done
                        
                        # Check Grafana dashboards
                        DASHBOARDS=\$(curl -s -u \${GRAFANA_CREDENTIALS_USR}:\${GRAFANA_CREDENTIALS_PSW} \
                                     ${GRAFANA_URL}/api/search?type=dash-db 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
                        echo "📊 Grafana dashboards: \${DASHBOARDS}"
                        
                        # Check data sources
                        DATASOURCES=\$(curl -s -u \${GRAFANA_CREDENTIALS_USR}:\${GRAFANA_CREDENTIALS_PSW} \
                                      ${GRAFANA_URL}/api/datasources 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
                        echo "🔗 Grafana datasources: \${DATASOURCES}"
                        
                        # Test Prometheus datasource
                        echo "🔍 Testing Prometheus datasource..."
                        DATASOURCE_TEST=\$(curl -s -u \${GRAFANA_CREDENTIALS_USR}:\${GRAFANA_CREDENTIALS_PSW} \
                                          ${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query?query=up | \
                                          jq '.status' 2>/dev/null || echo '"error"')
                        
                        if [ "\$DATASOURCE_TEST" = '"success"' ]; then
                            echo "✅ Prometheus datasource is working"
                        else
                            echo "⚠️ Prometheus datasource test failed"
                        fi
                        
                        echo "✅ Post-update verification completed"
                    """
                }
            }
        }
        
        stage('Generate Monitoring Report') {
            steps {
                script {
                    echo "📋 Generating monitoring status report..."
                    
                    sh """
                        # Create monitoring report
                        cat > monitoring-report-${TIMESTAMP}.md << EOF
# Monitoring Stack Report

**Date**: \$(date)
**Action**: ${params.ACTION}
**Build**: ${env.BUILD_NUMBER}

## Configuration Updates
- Prometheus: ${params.UPDATE_PROMETHEUS}
- Grafana: ${params.UPDATE_GRAFANA}
- Alertmanager: ${params.UPDATE_ALERTMANAGER}
- Services Restarted: ${params.RESTART_SERVICES}

## Service Status
EOF
                        
                        # Add Prometheus status
                        if curl -f -s --connect-timeout 5 ${PROMETHEUS_URL}/api/v1/query?query=up > /dev/null; then
                            echo "- Prometheus: ✅ Running" >> monitoring-report-${TIMESTAMP}.md
                            
                            TARGETS_UP=\$(curl -s ${PROMETHEUS_URL}/api/v1/query?query=up | jq '.data.result | map(select(.value[1] == "1")) | length' 2>/dev/null || echo 0)
                            TARGETS_DOWN=\$(curl -s ${PROMETHEUS_URL}/api/v1/query?query=up | jq '.data.result | map(select(.value[1] == "0")) | length' 2>/dev/null || echo 0)
                            
                            echo "  - Targets UP: \${TARGETS_UP}" >> monitoring-report-${TIMESTAMP}.md
                            echo "  - Targets DOWN: \${TARGETS_DOWN}" >> monitoring-report-${TIMESTAMP}.md
                        else
                            echo "- Prometheus: ❌ Not accessible" >> monitoring-report-${TIMESTAMP}.md
                        fi
                        
                        # Add Grafana status
                        if curl -f -s --connect-timeout 5 ${GRAFANA_URL}/api/health > /dev/null; then
                            echo "- Grafana: ✅ Running" >> monitoring-report-${TIMESTAMP}.md
                            
                            DASHBOARDS=\$(curl -s -u \${GRAFANA_CREDENTIALS_USR}:\${GRAFANA_CREDENTIALS_PSW} \
                                         ${GRAFANA_URL}/api/search?type=dash-db 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
                            echo "  - Dashboards: \${DASHBOARDS}" >> monitoring-report-${TIMESTAMP}.md
                        else
                            echo "- Grafana: ❌ Not accessible" >> monitoring-report-${TIMESTAMP}.md
                        fi
                        
                        # Add access information
                        cat >> monitoring-report-${TIMESTAMP}.md << EOF

## Access Information
- Prometheus: ${PROMETHEUS_URL}
- Grafana: ${GRAFANA_URL}
- Monitoring Host: ${MONITORING_HOST}

## Next Actions
- Monitor system performance for 24 hours
- Verify alert notifications are working
- Review dashboard functionality
- Update documentation if needed

EOF
                        
                        echo "📋 Monitoring report generated"
                        cat monitoring-report-${TIMESTAMP}.md
                    """
                    
                    // Archive the report
                    archiveArtifacts artifacts: "monitoring-report-${TIMESTAMP}.md", fingerprint: true
                }
            }
        }
    }
    
    post {
        always {
            script {
                // Clean workspace
                cleanWs()
            }
        }
        
        success {
            script {
                echo "✅ Monitoring Pipeline Completed Successfully!"
                
                def monitoringStatus = """
                    ✅ Monitoring ${params.ACTION}: SUCCESS
                    
                    📊 Action: ${params.ACTION}
                    🖥️ Host: ${MONITORING_HOST}
                    ⏰ Time: ${TIMESTAMP}
                    ⏱️ Duration: ${currentBuild.durationString}
                    
                    📈 Prometheus: ${PROMETHEUS_URL}
                    📊 Grafana: ${GRAFANA_URL}
                    
                    🔗 Build: ${env.BUILD_URL}
                """.stripIndent()
                
                if (env.SLACK_WEBHOOK) {
                    slackSend(
                        channel: '#infrastructure',
                        color: 'good',
                        message: monitoringStatus
                    )
                }
                
                echo monitoringStatus
            }
        }
        
        failure {
            script {
                echo "❌ Monitoring Pipeline Failed!"
                
                def failureMessage = """
                    ❌ Monitoring ${params.ACTION}: FAILED
                    
                    📊 Action: ${params.ACTION}
                    🖥️ Host: ${MONITORING_HOST}
                    ⏰ Time: ${TIMESTAMP}
                    ⏱️ Duration: ${currentBuild.durationString}
                    
                    🔗 Build: ${env.BUILD_URL}
                    📋 Please check logs and verify services
                """.stripIndent()
                
                if (env.SLACK_WEBHOOK) {
                    slackSend(
                        channel: '#infrastructure',
                        color: 'danger',
                        message: failureMessage
                    )
                }
            }
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>