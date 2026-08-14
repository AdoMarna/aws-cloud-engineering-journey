SHELL := /bin/bash

SCRIPTS_DIR := scripts

.PHONY: all deploy connect check clean help

all: deploy

deploy:
	chmod +x $(SCRIPTS_DIR)/deploy_compute.sh $(SCRIPTS_DIR)/connect_instance.sh
	$(SCRIPTS_DIR)/deploy_compute.sh

connect:
	chmod +x $(SCRIPTS_DIR)/connect_instance.sh
	$(SCRIPTS_DIR)/connect_instance.sh

check:
	chmod +x $(SCRIPTS_DIR)/check_nodes_health.sh
	$(SCRIPTS_DIR)/check_nodes_health.sh

clean:
	chmod +x $(SCRIPTS_DIR)/cleanup_compute.sh
	$(SCRIPTS_DIR)/cleanup_compute.sh

help:
	@echo "Available commands:"
	@echo "  make / make all       -- provisions the full project (deploy_compute.sh)"
	@echo "  make deploy           -- same as above, provisions the full project"
	@echo "  make connect          -- opens an SSM session on my_instance_one (connect_instance.sh)"
	@echo "  make check            -- runs a health check on both nodes (check_nodes_health.sh)"
	@echo "  make clean            -- runs scripts/cleanup_compute.sh (destroys the created resources)"
