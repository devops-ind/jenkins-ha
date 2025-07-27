# Jenkins Infrastructure Production

This repository contains Ansible playbooks and configurations for managing Jenkins infrastructure in production.

## Quick Start

1. Install dependencies: `pip install -r requirements.txt`
2. Configure inventory: Edit `ansible/inventories/production/hosts.yml`
3. Set up vault passwords: `ansible-vault create ansible/inventories/production/group_vars/all/vault.yml`
4. Deploy: `make deploy-production`

## Documentation

See the `docs/` directory for detailed documentation.
