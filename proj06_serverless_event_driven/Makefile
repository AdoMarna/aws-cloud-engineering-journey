SHELL := /bin/bash

ENV ?= dev
VAR_FILE := environments/$(ENV).tfvars
SCRIPTS_DIR := scripts
BOOTSTRAP_SCRIPT := ../bootstrap/bootstrap.sh

.PHONY: all bootstrap init validate plan apply test destroy fmt clean help

all: apply

bootstrap:
	chmod +x $(BOOTSTRAP_SCRIPT)
	$(BOOTSTRAP_SCRIPT)

init:
	mkdir -p build
	terraform init

validate:
	terraform fmt -check
	terraform validate

plan:
	mkdir -p build
	terraform plan -var-file=$(VAR_FILE)

apply:
	mkdir -p build
	terraform apply -var-file=$(VAR_FILE)

test:
	chmod +x $(SCRIPTS_DIR)/test_pipeline.sh
	$(SCRIPTS_DIR)/test_pipeline.sh

destroy:
	terraform destroy -auto-approve -var-file=$(VAR_FILE)

fmt:
	terraform fmt -recursive

clean: destroy
	chmod +x $(SCRIPTS_DIR)/cleanup_serverless.sh
	$(SCRIPTS_DIR)/cleanup_serverless.sh
	rm -rf build

help:
	@echo "Available commands:"
	@echo "  make / make all -- deploys the complete Terraform infrastructure"
	@echo "  make bootstrap  -- provisions the S3 state bucket (and lock table) via ../bootstrap/bootstrap.sh"
	@echo "  make init       -- initializes Terraform providers, modules and backend"
	@echo "  make validate   -- validates the Terraform configuration"
	@echo "  make plan       -- displays the Terraform execution plan (ENV=dev by default)"
	@echo "  make apply      -- creates/updates the serverless pipeline"
	@echo "  make test       -- runs scripts/test_pipeline.sh against the deployed stack"
	@echo "  make destroy    -- destroys all Terraform-managed resources"
	@echo "  make clean      -- destroy + scripts/cleanup_serverless.sh + local build/"
	@echo "  make fmt        -- formats all Terraform files"
	@echo "  make help       -- displays this help"
	@echo ""
	@echo "Examples:"
	@echo "  make plan ENV=prod"
	@echo "  make apply ENV=dev"
