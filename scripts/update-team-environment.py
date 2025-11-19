#!/usr/bin/env python3

"""
update-team-environment.py - Update Jenkins team active environment configuration
Safely updates the ansible configuration for blue-green environment switching
Version: 1.0.0
"""

import sys
import os
import yaml
import json
import shutil
from datetime import datetime
from pathlib import Path

def log_info(message):
    """Log info message with timestamp"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[INFO] {timestamp} {message}")

def log_error(message):
    """Log error message with timestamp"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[ERROR] {timestamp} {message}")

def log_success(message):
    """Log success message with timestamp"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[SUCCESS] {timestamp} {message}")

def backup_config_file(config_path):
    """Create backup of configuration file"""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_path = f"{config_path}.backup_{timestamp}"
    
    try:
        shutil.copy2(config_path, backup_path)
        log_info(f"Created backup: {backup_path}")
        return backup_path
    except Exception as e:
        log_error(f"Failed to create backup: {e}")
        return None

def load_yaml_config(config_path):
    """Load YAML configuration file"""
    try:
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
    except Exception as e:
        log_error(f"Failed to load config {config_path}: {e}")
        return None

def save_yaml_config(config, config_path):
    """Save YAML configuration file"""
    try:
        with open(config_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, indent=2, sort_keys=False)
        return True
    except Exception as e:
        log_error(f"Failed to save config {config_path}: {e}")
        return False

def find_team_in_config(config, team_name):
    """Find team configuration in jenkins_teams_config"""
    if 'jenkins_teams_config' not in config:
        log_error("jenkins_teams_config not found in configuration")
        return None, -1
    
    teams = config['jenkins_teams_config']
    
    for i, team_config in enumerate(teams):
        if team_config.get('team_name') == team_name:
            return team_config, i
    
    return None, -1

def validate_environment(environment):
    """Validate environment name"""
    if environment not in ['blue', 'green']:
        log_error(f"Invalid environment: {environment}. Must be 'blue' or 'green'")
        return False
    return True

def update_team_environment(team_name, new_environment, config_path):
    """Update team's active environment in configuration"""
    
    # Validate inputs
    if not validate_environment(new_environment):
        return False
    
    # Check if config file exists
    if not os.path.exists(config_path):
        log_error(f"Configuration file not found: {config_path}")
        return False
    
    # Create backup
    backup_path = backup_config_file(config_path)
    if not backup_path:
        return False
    
    # Load configuration
    config = load_yaml_config(config_path)
    if config is None:
        return False
    
    # Find team configuration
    team_config, team_index = find_team_in_config(config, team_name)
    if team_config is None:
        log_error(f"Team '{team_name}' not found in configuration")
        return False
    
    # Get current environment
    current_environment = team_config.get('active_environment', 'blue')
    
    # Check if change is needed
    if current_environment == new_environment:
        log_info(f"Team '{team_name}' is already on environment '{new_environment}'")
        return True
    
    log_info(f"Updating team '{team_name}' from '{current_environment}' to '{new_environment}'")
    
    # Update the environment
    config['jenkins_teams_config'][team_index]['active_environment'] = new_environment
    
    # Save updated configuration
    if not save_yaml_config(config, config_path):
        log_error("Failed to save updated configuration")
        # Attempt to restore backup
        try:
            shutil.copy2(backup_path, config_path)
            log_info("Restored configuration from backup")
        except Exception as e:
            log_error(f"Failed to restore backup: {e}")
        return False
    
    log_success(f"Successfully updated team '{team_name}' to environment '{new_environment}'")
    
    # Verify the change
    verify_config = load_yaml_config(config_path)
    if verify_config:
        verify_team_config, _ = find_team_in_config(verify_config, team_name)
        if verify_team_config and verify_team_config.get('active_environment') == new_environment:
            log_success("Configuration change verified")
            return True
        else:
            log_error("Configuration verification failed")
            return False
    
    return True

def show_team_environments(config_path):
    """Show current environments for all teams"""
    if not os.path.exists(config_path):
        log_error(f"Configuration file not found: {config_path}")
        return False
    
    config = load_yaml_config(config_path)
    if config is None:
        return False
    
    if 'jenkins_teams_config' not in config:
        log_error("jenkins_teams_config not found in configuration")
        return False
    
    print("\n=== Current Team Environments ===")
    for team_config in config['jenkins_teams_config']:
        team_name = team_config.get('team_name', 'unknown')
        environment = team_config.get('active_environment', 'unknown')
        blue_green_enabled = team_config.get('blue_green_enabled', False)
        
        status = "✅ Enabled" if blue_green_enabled else "❌ Disabled"
        print(f"Team: {team_name:8} | Environment: {environment:5} | Blue-Green: {status}")
    
    print("")
    return True

def validate_team_configuration(config_path, team_name):
    """Validate team configuration completeness"""
    config = load_yaml_config(config_path)
    if config is None:
        return False
    
    team_config, _ = find_team_in_config(config, team_name)
    if team_config is None:
        log_error(f"Team '{team_name}' not found")
        return False
    
    required_fields = ['team_name', 'blue_green_enabled', 'active_environment', 'ports']
    missing_fields = []
    
    for field in required_fields:
        if field not in team_config:
            missing_fields.append(field)
    
    if missing_fields:
        log_error(f"Team '{team_name}' missing required fields: {missing_fields}")
        return False
    
    if not team_config.get('blue_green_enabled', False):
        log_error(f"Team '{team_name}' does not have blue-green deployment enabled")
        return False
    
    log_success(f"Team '{team_name}' configuration is valid")
    return True

def main():
    """Main function"""
    if len(sys.argv) < 2:
        print("""
Usage: update-team-environment.py <command> [options]

COMMANDS:
    update <team> <environment>     - Update team's active environment
    show                           - Show current environments for all teams  
    validate <team>                - Validate team configuration
    
EXAMPLES:
    python3 update-team-environment.py update devops green
    python3 update-team-environment.py show
    python3 update-team-environment.py validate ma

ENVIRONMENTS:
    blue    - Blue environment
    green   - Green environment
        """)
        sys.exit(1)
    
    command = sys.argv[1]
    
    # Default configuration path
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    config_path = project_root / "ansible" / "inventories" / "production" / "group_vars" / "all" / "main.yml"
    
    # Handle different commands
    if command == "update":
        if len(sys.argv) != 4:
            log_error("Usage: update-team-environment.py update <team> <environment>")
            sys.exit(1)
        
        team_name = sys.argv[2]
        new_environment = sys.argv[3]
        
        if update_team_environment(team_name, new_environment, str(config_path)):
            sys.exit(0)
        else:
            sys.exit(1)
    
    elif command == "show":
        if show_team_environments(str(config_path)):
            sys.exit(0)
        else:
            sys.exit(1)
    
    elif command == "validate":
        if len(sys.argv) != 3:
            log_error("Usage: update-team-environment.py validate <team>")
            sys.exit(1)
        
        team_name = sys.argv[2]
        
        if validate_team_configuration(str(config_path), team_name):
            sys.exit(0)
        else:
            sys.exit(1)
    
    else:
        log_error(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()