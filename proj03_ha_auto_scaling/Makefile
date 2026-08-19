SHELL := /bin/bash

SCRIPTS_DIR := scripts

.PHONY: all deploy enable stress update simulate clean help

all: deploy

deploy:
	chmod +x $(SCRIPTS_DIR)/deploy_ha_stack.sh
	$(SCRIPTS_DIR)/deploy_ha_stack.sh

enable:
	chmod +x $(SCRIPTS_DIR)/enable_autoscaling_policy.sh
	$(SCRIPTS_DIR)/enable_autoscaling_policy.sh

stress:
	chmod +x $(SCRIPTS_DIR)/stress_test.sh
	$(SCRIPTS_DIR)/stress_test.sh

update:
	chmod +x $(SCRIPTS_DIR)/update_fleet.sh
	$(SCRIPTS_DIR)/update_fleet.sh

simulate:
	chmod +x $(SCRIPTS_DIR)/simulate_failure.sh
	$(SCRIPTS_DIR)/simulate_failure.sh

clean:
	chmod +x $(SCRIPTS_DIR)/cleanup_ha_stack.sh
	$(SCRIPTS_DIR)/cleanup_ha_stack.sh

help:
	@echo "Available commands:"
	@echo "  make / make all -- deploys the full HA stack (deploy_ha_stack.sh)"
	@echo "  make deploy     -- same as above"
	@echo "  make enable     -- attaches the CPU 50% target tracking scaling policy"
	@echo "  make stress     -- sends a CPU stress test via SSM and watches the ASG scale out"
	@echo "  make update     -- rolling zero-downtime update via Instance Refresh"
	@echo "  make simulate   -- terminates an instance to test ASG self-healing"
	@echo "  make clean      -- destroys all proj03 resources (ASG, LB, TG, launch template, security groups)"
