# Makefile for Spark DGX AI Stack
# Usage: make <target>

.PHONY: help lint syntax-check test deploy verify cleanup vault-encrypt vault-decrypt vault-view

# Default target
help:
	@echo "Spark DGX AI Stack - Make Targets"
	@echo ""
	@echo "Validation:"
	@echo "  make lint           Run ansible-lint and yamllint"
	@echo "  make syntax-check   Check playbook syntax"
	@echo "  make test           Run Molecule tests (requires Docker)"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy         Full deployment (ansible-playbook site.yml)"
	@echo "  make deploy-base    Deploy only base system"
	@echo "  make deploy-ai      Deploy only AI stack (vLLM + Router)"
	@echo "  make verify         Run post-deployment verification"
	@echo "  make benchmark      Run benchmark only"
	@echo ""
	@echo "Maintenance:"
	@echo "  make update         Pull latest images and restart"
	@echo "  make logs           Follow Docker logs"
	@echo "  make status         Show container status"
	@echo "  make cleanup        Remove stack (preserves data)"
	@echo ""
	@echo "Secrets:"
	@echo "  make vault-encrypt  Encrypt vault file"
	@echo "  make vault-decrypt  Decrypt vault file for editing"
	@echo "  make vault-view     View encrypted vault file"

# Validation
lint:
	cd ansible && ansible-lint . && yamllint .

syntax-check:
	cd ansible && ansible-playbook --syntax-check site.yml

test:
	cd ansible/roles/spark-base && molecule test

# Deployment
deploy:
	cd ansible && ansible-playbook -i inventory.yml site.yml

deploy-base:
	cd ansible && ansible-playbook -i inventory.yml site.yml --tags spark-base

deploy-ai:
	cd ansible && ansible-playbook -i inventory.yml site.yml --tags spark-ai,llm-router

verify:
	cd ansible && ansible-playbook -i inventory.yml site.yml --tags verify

benchmark:
	cd ansible && ansible-playbook -i inventory.yml site.yml --tags benchmark

# Maintenance
update:
	cd ansible && ansible-playbook -i inventory.yml site.yml --tags spark-ai,llm-router -e "force_pull=true"

logs:
	ssh ubuntu@$(shell grep ansible_host ansible/inventory.yml | awk '{print $$2}') "docker logs -f vllm-qwen-spark"

status:
	ssh ubuntu@$(shell grep ansible_host ansible/inventory.yml | awk '{print $$2}') "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

cleanup:
	cd ansible && ansible-playbook -i inventory.yml site.yml --tags cleanup

# Secrets
vault-encrypt:
	cd ansible && ansible-vault encrypt group_vars/vault.yml

vault-decrypt:
	cd ansible && ansible-vault decrypt group_vars/vault.yml

vault-view:
	cd ansible && ansible-vault view group_vars/vault.yml

# Development
install-deps:
	cd ansible && ansible-galaxy collection install -r requirements.yml

format:
	cd ansible && ansible-lint --fix . && yamllint --fix .