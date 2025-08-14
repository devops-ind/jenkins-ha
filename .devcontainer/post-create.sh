#!/bin/bash
set -e

echo "🚀 Setting up your Ansible + Jenkins development environment..."

cd /workspace

# Install Ansible collections
if [ -f "ansible/requirements.yml" ]; then
    echo "📦 Installing Ansible Galaxy requirements..."
    ansible-galaxy install -r ansible/requirements.yml --force
    ansible-galaxy collection install -r ansible/requirements.yml --force
    echo "✅ Ansible Galaxy requirements installed"
else
    echo "📦 Installing essential Ansible collections..."
    ansible-galaxy collection install community.docker community.general ansible.posix --force
    echo "✅ Essential collections installed"
fi

# Fix file permissions (excluding .git)
echo "🔧 Setting up file permissions..."
sudo find /workspace -maxdepth 1 -type d -not -name ".git" -exec chown -R ansible:ansible {} \; 2>/dev/null || true
sudo find /workspace -maxdepth 1 -type f -exec chown ansible:ansible {} \; 2>/dev/null || true
echo "✅ File permissions configured"

# Create directories
mkdir -p /workspace/ansible/logs
mkdir -p /workspace/jenkins-deploy
mkdir -p /home/ansible/.ansible/tmp

# Setup ansible user in sudoers for passwordless sudo
echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers

# Create jenkins user and directories
sudo useradd -m -s /bin/bash jenkins || true
sudo mkdir -p /var/jenkins
sudo chown jenkins:jenkins -R /var/jenkins

# Ansible configuration
if [ ! -f "/home/ansible/.ansible.cfg" ]; then
    echo "⚙️  Creating Ansible user configuration..."
    cat > /home/ansible/.ansible.cfg << EOF
[defaults]
inventory = /workspace/ansible/inventory
roles_path = /workspace/ansible/roles
host_key_checking = False
stdout_callback = default
callbacks_enabled = profile_tasks, timer
log_path = /workspace/ansible/logs/ansible.log
deprecation_warnings = False
become = False
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no
pipelining = True
EOF
    echo "✅ Ansible configuration created"
fi

# Test Docker connectivity
echo "🐳 Testing Docker connectivity..."
if ! docker --version; then
    echo "❌ Docker CLI not available"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "🔧 Starting Docker service..."
    sudo service docker start 2>/dev/null || true
    sleep 5
    
    if ! docker info >/dev/null 2>&1; then
        echo "⚠️  Docker daemon not accessible"
    fi
fi

docker --version
docker compose version

# Test Ansible
echo "🔍 Testing Ansible installation..."
ansible --version
ansible-galaxy --version

# Test inventory
if [ -f "/workspace/ansible/inventory/hosts.yml" ]; then
    echo "📋 Testing inventory configuration..."
    ansible-inventory --list > /dev/null && echo "✅ Inventory configuration is valid"
fi

# Git configuration
if [ ! -f "/home/ansible/.gitconfig" ]; then
    echo "📝 Setting up basic Git configuration..."
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    echo "ℹ️  You may want to set your Git user name and email:"
    echo "   git config --global user.name 'Your Name'"
    echo "   git config --global user.email 'your.email@example.com'"
fi

# Auto-deploy Jenkins
echo ""
echo "🚀 Auto-deploying Jenkins infrastructure in local mode..."
echo ""

export DEPLOYMENT_MODE=local
export JENKINS_ADMIN_USER=admin
export JENKINS_ADMIN_PASSWORD=admin123
export JENKINS_DOMAIN=jenkins.dev.local

cd /workspace/ansible
if ansible-playbook deploy-local.yml -e deployment_mode=devcontainer --skip-tags health,verify --become; then
    echo ""
    echo "🎉 Jenkins deployment completed successfully!"
    echo ""
    echo "🌐 Jenkins is available at: https://jenkins.dev.local"
    echo "👤 Username: admin"
    echo "🔐 Password: admin123"
    echo "📊 HAProxy Stats: https://jenkins.dev.local:8404/stats"
    echo ""
else
    echo ""
    echo "⚠️  Jenkins deployment encountered an issue, but dev environment is ready"
    echo "   You can manually deploy Jenkins with: ansible-playbook site.yml -e deployment_mode=local"
    echo ""
fi

echo "🎉 Development environment setup complete!"
echo ""
echo "💡 Quick start commands:"
echo "   • Deploy Jenkins locally:     ansible-playbook site.yml -e deployment_mode=local"
echo "   • Deploy to remote VM:        DEPLOYMENT_MODE=remote ansible-playbook site.yml"
echo "   • Check Jenkins status:       docker ps"
echo "   • Access Jenkins:             https://jenkins.dev.local"
echo ""
echo "📚 Your unified Ansible + Jenkins environment is ready!"

chmod +x /workspace/.devcontainer/post-create.sh