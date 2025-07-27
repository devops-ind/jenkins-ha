#!/bin/bash
set -e

# Jenkins Docker Entrypoint Script
# Handles initialization and startup of Jenkins containers

# Set default values
JENKINS_HOME="${JENKINS_HOME:-/var/jenkins_home}"
JENKINS_WAR="${JENKINS_WAR:-/usr/share/jenkins/jenkins.war}"
JENKINS_UC="${JENKINS_UC:-https://updates.jenkins.io}"

# Create jenkins user if it doesn't exist
if ! id "jenkins" &>/dev/null; then
    echo "Creating jenkins user..."
    groupadd -g ${JENKINS_GID:-1000} jenkins
    useradd -u ${JENKINS_UID:-1000} -g jenkins -m -s /bin/bash jenkins
fi

# Create jenkins home directory
if [ ! -d "$JENKINS_HOME" ]; then
    mkdir -p "$JENKINS_HOME"
    chown jenkins:jenkins "$JENKINS_HOME"
fi

# Set permissions
chown -R jenkins:jenkins "$JENKINS_HOME"

# Initialize Jenkins if needed
if [ ! -f "$JENKINS_HOME/config.xml" ]; then
    echo "Initializing Jenkins home directory..."
    
    # Copy reference configurations
    if [ -d "/usr/share/jenkins/ref" ]; then
        cp -r /usr/share/jenkins/ref/* "$JENKINS_HOME/" 2>/dev/null || true
    fi
    
    # Set initial admin password if provided
    if [ -n "$JENKINS_ADMIN_PASSWORD" ]; then
        echo "$JENKINS_ADMIN_PASSWORD" > "$JENKINS_HOME/secrets/initialAdminPassword"
        chmod 600 "$JENKINS_HOME/secrets/initialAdminPassword"
    fi
    
    chown -R jenkins:jenkins "$JENKINS_HOME"
fi

# Handle plugin installation
if [ -f "$JENKINS_HOME/plugins.txt" ]; then
    echo "Installing plugins from plugins.txt..."
    jenkins-plugin-cli --plugin-file "$JENKINS_HOME/plugins.txt" --latest
fi

# Run any pre-start scripts
if [ -d "$JENKINS_HOME/init.groovy.d" ]; then
    echo "Found init scripts in $JENKINS_HOME/init.groovy.d"
fi

# Handle JCasC configuration
if [ -d "$JENKINS_HOME/casc_configs" ]; then
    export CASC_JENKINS_CONFIG="$JENKINS_HOME/casc_configs"
    echo "Configuration as Code enabled: $CASC_JENKINS_CONFIG"
fi

# Set default Java options if not provided
if [ -z "$JAVA_OPTS" ]; then
    export JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.DNSMultiCast.disabled=true"
fi

# Set default Jenkins options if not provided
if [ -z "$JENKINS_OPTS" ]; then
    export JENKINS_OPTS="--httpPort=8080"
fi

echo "Starting Jenkins with:"
echo "  JENKINS_HOME: $JENKINS_HOME"
echo "  JAVA_OPTS: $JAVA_OPTS"
echo "  JENKINS_OPTS: $JENKINS_OPTS"
echo "  USER: $(whoami)"

# Start Jenkins
exec "$@"