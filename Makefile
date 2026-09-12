# =============================================================================
# Makefile — single entry point for all lab operations
# =============================================================================
# Principle: every target that changes the cluster depends on "verify".
# Nothing gets deployed without a passing air-gap proof.
# (Targets planned for M4/M5, such as "infra" and "cluster", follow the same
# pattern.)
# =============================================================================

SHELL := /bin/bash

# Every Ansible SSH connection goes through the generated .ssh-config
export ANSIBLE_SSH_ARGS := -F $(CURDIR)/.ssh-config -o ControlMaster=auto -o ControlPersist=60s
export ANSIBLE_CONFIG   := $(CURDIR)/ansible/ansible.cfg

ANSIBLE_PLAYBOOK := cd ansible && ansible-playbook

.DEFAULT_GOAL := help
.PHONY: help up down destroy seal unseal status ssh-config verify

help: ## Show this overview
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: ## Create/start the VMs (each one is sealed automatically afterwards)
	vagrant up

down: ## Shut the VMs down
	vagrant halt

destroy: ## Delete the VMs completely
	vagrant destroy -f

seal: ## Disconnect the NAT link of all VMs
	scripts/airgap.sh seal

unseal: ## BREAK GLASS: reconnect the NAT link (logged)
	scripts/airgap.sh unseal

status: ## Host-side air-gap check
	scripts/airgap.sh status

ssh-config: ## Generate .ssh-config from the inventory
	$(ANSIBLE_PLAYBOOK) playbooks/ssh-config.yml

verify: status ssh-config ## Full air-gap proof (host + guests)
	$(ANSIBLE_PLAYBOOK) playbooks/verify-airgap.yml
