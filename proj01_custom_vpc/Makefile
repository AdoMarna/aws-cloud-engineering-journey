SHELL := /bin/bash

SCRIPTS_DIR := scripts

.PHONY: all deploy network-security clean help

all: deploy

deploy:
	chmod +x $(SCRIPTS_DIR)/deploy_vpc.sh $(SCRIPTS_DIR)/apply_network_security.sh
	$(SCRIPTS_DIR)/deploy_vpc.sh

network-security:
	chmod +x $(SCRIPTS_DIR)/apply_network_security.sh
	$(SCRIPTS_DIR)/apply_network_security.sh

clean:
	chmod +x $(SCRIPTS_DIR)/cleanup_vpc.sh
	$(SCRIPTS_DIR)/cleanup_vpc.sh

help:
	@echo "Available commands:"
	@echo "  make / make all       -- provisions the full VPC (deploy_vpc.sh, includes network security)"
	@echo "  make deploy           -- same as above, provisions the full VPC"
	@echo "  make network-security -- re-runs only apply_network_security.sh (SG + NACL)"
	@echo "  make clean            -- runs scripts/cleanup_vpc.sh (destroys all created VPC resources)"
