SHELL := /bin/bash

SCRIPTS_DIR := scripts

.PHONY: all deploy enable update clean help

all: deploy

deploy:
	chmod +x $(SCRIPTS_DIR)/deploy_containers.sh
	$(SCRIPTS_DIR)/deploy_containers.sh

enable:
	chmod +x $(SCRIPTS_DIR)/enable_ecs_autoscaling.sh
	$(SCRIPTS_DIR)/enable_ecs_autoscaling.sh

update:
	chmod +x $(SCRIPTS_DIR)/deploy_new_version.sh
	$(SCRIPTS_DIR)/deploy_new_version.sh

clean:
	chmod +x $(SCRIPTS_DIR)/cleanup_containers.sh
	$(SCRIPTS_DIR)/cleanup_containers.sh

help:
	@echo "Available commands:"
	@echo "  make / make all -- builds, pushes and deploys the full ECS Fargate stack (deploy_containers.sh)"
	@echo "  make deploy     -- same as above"
	@echo "  make enable     -- attaches the CPU 60% target tracking scaling policy (enable_ecs_autoscaling.sh)"
	@echo "  make update     -- builds a new image version and rolls it out to the ECS service (deploy_new_version.sh)"
	@echo "  make clean      -- destroys all proj04 resources (ECS services/cluster, ALB, target groups, ECR, IAM role, log groups, security groups)"
