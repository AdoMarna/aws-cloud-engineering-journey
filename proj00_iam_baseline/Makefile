SHELL := /bin/bash

PREFIX ?= /usr/local

BIN_DIR := $(PREFIX)/bin

SCRIPTS_DIR := scripts

SCRIPTS := $(notdir $(wildcard $(SCRIPTS_DIR)/*))

PROGRAMS := $(addprefix $(BIN_DIR)/, $(SCRIPTS))

.PHONY: all install setup clean uninstall help

all: install setup

install: $(PROGRAMS)

$(BIN_DIR)/%: $(SCRIPTS_DIR)/%
	install -Dm755 $< $@

setup: install
	chmod +x $(SCRIPTS_DIR)/setup_iam.sh
	$(SCRIPTS_DIR)/setup_iam.sh

clean:
	chmod +x $(SCRIPTS_DIR)/cleanup_iam.sh
	$(SCRIPTS_DIR)/cleanup_iam.sh

uninstall:
	rm -f $(PROGRAMS)

help:
	@echo "Available commands:"
	@echo "  make / make all -- installs the scripts then runs the full IAM setup"
	@echo "  make install    -- installs/makes the scripts executable (no provisioning)"
	@echo "  make setup      -- runs scripts/setup_iam.sh (group, policies, user, password policy)"
	@echo "  make clean      -- runs scripts/cleanup_iam.sh (destroys the created IAM resources)"
	@echo "  make uninstall  -- removes the scripts installed in $(BIN_DIR)"
	@echo ""
	@echo "To assume the admin role in YOUR shell session (credentials"
	@echo "valid for 1h), source it directly, don't go through make:"
	@echo "  source scripts/assume_admin_role.sh"
