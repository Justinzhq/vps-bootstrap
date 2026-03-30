SHELL := /usr/bin/env bash

.PHONY: help chmod check init harden-ssh xray-install xray-secrets xray-config

help:
	@echo "Available targets:"
	@echo "  make chmod"
	@echo "  make check"
	@echo "  make init USER=user PUBKEY='ssh-ed25519 AAAA...'"
	@echo "  make harden-ssh SSH_PORT=2222 DISABLE_ROOT_LOGIN=true DISABLE_PASSWORD_AUTH=true"
	@echo "  make xray-install"
	@echo "  make xray-secrets"
	@echo "  make xray-config XRAY_UUID=... REALITY_PRIVATE_KEY=... REALITY_SHORT_ID=..."

chmod:
	chmod +x scripts/*.sh

check:
	bash -n scripts/initial.sh
	bash -n scripts/harden-ssh.sh
	bash -n scripts/install-xray.sh
	bash -n scripts/gen-reality-secrets.sh
	bash -n scripts/generate-xray-config.sh

init:
	bash scripts/initial.sh "$(or $(USER),user)" "$(PUBKEY)"

harden-ssh:
	bash scripts/harden-ssh.sh

xray-install:
	bash scripts/install-xray.sh

xray-secrets:
	bash scripts/gen-reality-secrets.sh

xray-config:
	bash scripts/generate-xray-config.sh
