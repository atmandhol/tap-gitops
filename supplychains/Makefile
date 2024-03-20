GO ?= $(shell which go)
ARCH := $(shell $(GO) env GOARCH)
OS := $(shell $(GO) env GOOS)

SHELL := /usr/bin/env bash

NAMESPACE_FLAG=
ifdef NAMESPACE
NAMESPACE_FLAG=-n $(NAMESPACE)
endif

.DEFAULT_GOAL := install

## kapp deploy app names are templated by tanzu supplychain init command.
.PHONY: install
install: require-kapp ## Installs the supply chains in the group to your active context.
	kapp deploy $(NAMESPACE_FLAG) -a components.supplychains.tanzu.vmware.com -f components -f pipelines -f tasks -y --dangerous-allow-empty-list-of-resources
	kapp deploy $(NAMESPACE_FLAG) -a supplychain.supplychains.tanzu.vmware.com -f supplychains -y --dangerous-allow-empty-list-of-resources

## kapp delete app names are templated by tanzu supplychain init command.
.PHONY: uninstall
uninstall: require-kapp ## Uninstalls the supply chains in this group from your active context.
	kapp delete $(NAMESPACE_FLAG) -a components.supplychains.tanzu.vmware.com -y
	kapp delete $(NAMESPACE_FLAG) -a supplychain.supplychains.tanzu.vmware.com -y

# =====================================================================================
# Helpers
# =====================================================================================

.PHONY: require-kapp
require-kapp: ## Checks if the required command exists on the command line
	@if ! command -v kapp 1> /dev/null 2>&1; then echo "kapp CLI not installed or found in PATH"; exit 1; fi

help: ## Print help for each make target.
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%!s(MISSING)\033[0m %!s(MISSING)\n", $$1, $$2}'
