#!/bin/bash
# ha-setup automation script

set -e

ENVIRONMENT=${1:-production}
INVENTORY="ansible/inventories/$ENVIRONMENT/hosts.yml"

echo "Running ha-setup for $ENVIRONMENT environment"

# Add your script logic here
case "$ENVIRONMENT" in
    production)
        echo "Executing ha-setup for production"
        ;;
    staging)
        echo "Executing ha-setup for staging"
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT"
        exit 1
        ;;
esac
