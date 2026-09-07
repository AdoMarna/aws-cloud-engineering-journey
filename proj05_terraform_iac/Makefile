SHELL := /bin/bash

SCRIPTS_DIR := scripts

.PHONY: all bootstrap init validate lint plan apply destroy drift fmt clean help

all: apply

bootstrap:
	chmod +x $(SCRIPTS_DIR)/bootstrap_backend.sh
	$(SCRIPTS_DIR)/bootstrap_backend.sh

init:
	terraform init

validate:
	terraform fmt -check
	terraform validate

lint: validate
	trivy config . || checkov -d .

plan:
	terraform plan -var-file=environments/dev.tfvars

apply:
	terraform apply -var-file=environments/dev.tfvars

destroy:
	terraform destroy -auto-approve -var-file=environments/dev.tfvars

drift:
	chmod +x $(SCRIPTS_DIR)/check_drift.sh
	$(SCRIPTS_DIR)/check_drift.sh

fmt:
	terraform fmt -recursive

clean:
	chmod +x $(SCRIPTS_DIR)/cleanup_terraform.sh
	$(SCRIPTS_DIR)/cleanup_terraform.sh

help:
	@echo "Available commands:"
	@echo "  make / make all -- initializes and deploys the complete Terraform infrastructure"
	@echo "  make bootstrap  -- provisions the S3 bucket + DynamoDB table for the remote backend (bootstrap_backend.sh)"
	@echo "  make init       -- initializes Terraform providers and modules"
	@echo "  make validate   -- checks formatting and validates the Terraform configuration"
	@echo "  make lint       -- runs validate, then a security scan (trivy or checkov) on the IaC code"
	@echo "  make plan       -- displays the Terraform execution plan"
	@echo "  make apply      -- creates/updates the complete infrastructure and Docker image"
	@echo "  make destroy    -- destroys all Terraform-managed resources"
	@echo "  make drift      -- checks for configuration drift against real infrastructure (check_drift.sh)"
	@echo "  make fmt        -- formats all Terraform files"
	@echo "  make clean      -- destroys the stack, purges the remote backend, and cleans local state (cleanup_terraform.sh)"
	@echo "  make help       -- displays this help"
