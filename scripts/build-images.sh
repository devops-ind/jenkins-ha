#!/bin/bash
# build-images automation script

set -e

ENVIRONMENT=${1:-production}
INVENTORY="ansible/inventories/$ENVIRONMENT/hosts.yml"

echo "Running build-images for $ENVIRONMENT environment"

# Add your script logic here
case "$ENVIRONMENT" in
    production)
        echo "Executing build-images for production"
        ;;
    staging)
        echo "Executing build-images for staging"
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT"
        exit 1
        ;;
esac
