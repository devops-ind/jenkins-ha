.PHONY: help deploy-production deploy-staging build-images backup monitor

help:
	@echo "Available targets:"
	@echo "  deploy-production  - Deploy to production environment"
	@echo "  deploy-staging     - Deploy to staging environment"
	@echo "  build-images      - Build and push Docker images"
	@echo "  backup            - Run backup procedures"
	@echo "  monitor           - Setup monitoring stack"

deploy-production:
	ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml

deploy-staging:
	ansible-playbook -i ansible/inventories/staging/hosts.yml ansible/site.yml

build-images:
	ansible-playbook -i ansible/inventories/production/hosts.yml ansible/deploy-images.yml

backup:
	ansible-playbook -i ansible/inventories/production/hosts.yml ansible/deploy-backup.yml

monitor:
	ansible-playbook -i ansible/inventories/production/hosts.yml ansible/deploy-monitoring.yml
