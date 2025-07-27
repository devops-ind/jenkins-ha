#!/usr/bin/env python3
"""Test inventory configuration"""

import yaml
import sys

def test_inventory(inventory_file):
    """Test inventory file structure"""
    try:
        with open(inventory_file, 'r') as f:
            inventory = yaml.safe_load(f)
        
        # Check required groups
        required_groups = ['jenkins_masters', 'jenkins_agents', 'monitoring', 'harbor']
        for group in required_groups:
            if group not in inventory:
                print(f"ERROR: Missing group {group}")
                return False
        
        print("Inventory validation passed")
        return True
        
    except Exception as e:
        print(f"ERROR: {e}")
        return False

if __name__ == "__main__":
    inventory_file = sys.argv[1] if len(sys.argv) > 1 else "ansible/inventories/production/hosts.yml"
    if not test_inventory(inventory_file):
        sys.exit(1)
