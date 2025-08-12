#!/usr/bin/env python3
"""Test inventory configuration"""

import sys
import yaml

def test_inventory(inventory_path):
    """Test inventory file structure"""
    try:
        with open(inventory_path, 'r', encoding='utf-8') as stream:
            inventory = yaml.safe_load(stream)

        # Check required groups
        required_groups = ['jenkins_masters', 'jenkins_agents', 'monitoring']
        for group in required_groups:
            if group not in inventory:
                print(f"ERROR: Missing group {group}")
                return False

        print("Inventory validation passed")
        return True

    except (IOError, yaml.YAMLError) as err:
        print(f"ERROR: {err}")
        return False

if __name__ == "__main__":
    INVENTORY_FILE = sys.argv[1] if len(sys.argv) > 1 else "ansible/inventories/production/hosts.yml"
    if not test_inventory(INVENTORY_FILE):
        sys.exit(1)
