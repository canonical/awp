# auto-wp — test targets (see spec/tests.md).
#
# Levels 1 and 2 are run by `make test` and `make test-l2`. Levels 3 and 4
# (provision, smoke, workspace, acceptance) take hours and need a Claude
# token; they have targets but are never run by `test` or `test-l2`.

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
.DEFAULT_GOAL := help

PYTHON ?= python3
OUT    := tests/out
STAMP   = $(shell date -u +%Y%m%d-%H%M%S)

SCRIPTS := $(wildcard tests/lib/*.sh tests/c/*.sh tests/rust/*.sh sdks/*.sh sdks/*/prepare.sh)

.PHONY: help test test-l2 test-c-l2 test-rust-l2 check-scripts \
        provision-c provision-rust smoke-c smoke-c-gzip smoke-c-gzip-ws smoke-c-mbedtls smoke-c-mbedtls-ws \
        smoke-rust sudo-rs-rust sudo-rs-rust-ws workspace-rust \
        sdk-lean sdk-rocq sdk-framac sdk-creusot test-sdks clean clean-lxc

help: ## Show this help
	@echo "auto-wp test targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
	    | awk -F':.*## ' '{ printf "  %-16s %s\n", $$1, $$2 }'
	@echo "Logs go to $(OUT)/. KEEP=1 keeps level-2+ containers."

$(OUT):
	@mkdir -p $(OUT)

test: | $(OUT) ## Level 1: program and template tests on the host (seconds)
	$(PYTHON) -m unittest discover -s tests -v 2>&1 | tee $(OUT)/level1-$(STAMP).log

test-l2: ## Level 2: C and Rust install tests in fresh LXD containers (minutes)
	@rc=0; \
	$(MAKE) --no-print-directory test-c-l2 || rc=1; \
	$(MAKE) --no-print-directory test-rust-l2 || rc=1; \
	exit $$rc

test-c-l2: | $(OUT) ## Level 2, C: tests/c/install-test.sh
	tests/c/install-test.sh 2>&1 | tee $(OUT)/c-install-$(STAMP).log

test-rust-l2: | $(OUT) ## Level 2, Rust: tests/rust/install-test.sh
	tests/rust/install-test.sh 2>&1 | tee $(OUT)/rust-install-$(STAMP).log

check-scripts: ## bash -n on every script (+ shellcheck if installed), modes
	@rc=0; \
	for f in $(SCRIPTS); do \
	    if bash -n "$$f"; then echo "ok    bash -n $$f"; else echo "FAIL  bash -n $$f"; rc=1; fi; \
	    if [ ! -x "$$f" ]; then echo "FAIL  not executable: $$f"; rc=1; fi; \
	done; \
	if command -v shellcheck >/dev/null; then \
	    shellcheck -x -S warning $(SCRIPTS) && echo "ok    shellcheck" || rc=1; \
	else echo "skip  shellcheck (not installed)"; fi; \
	$(PYTHON) -m py_compile tests/test_auto_wp.py tests/test_templates.py \
	    && echo "ok    py_compile tests/*.py" || rc=1; \
	exit $$rc

# --- levels 3 and 4: by hand only (hours; need a Claude token) -------------

provision-c: | $(OUT) ## Build autowp-c-base (hours)
	tests/c/provision.sh 2>&1 | tee $(OUT)/c-provision-$(STAMP).log

provision-rust: | $(OUT) ## Build autowp-rust-base (hours)
	tests/rust/provision.sh 2>&1 | tee $(OUT)/rust-provision-$(STAMP).log

smoke-c: | $(OUT) ## Level 3, C: 3-hour /time-loop run (token)
	tests/c/smoke-test.sh 2>&1 | tee $(OUT)/c-smoke-$(STAMP).log

smoke-c-gzip: | $(OUT) ## Level 3, C: /time-loop run on gzip 1.9, 96 h by default (GZIP_HOURS) (token)
	tests/c/gzip-test.sh 2>&1 | tee $(OUT)/c-gzip-$(STAMP).log

smoke-c-gzip-ws: | $(OUT) ## Level 3, C: the gzip run in a generated project's workshop (token)
	WORKSHOP=1 tests/c/gzip-test.sh 2>&1 | tee $(OUT)/c-gzip-ws-$(STAMP).log

smoke-c-mbedtls: | $(OUT) ## Level 3, C: a fips `/time-loop mbedtls` campaign on Mbed TLS (level 4, 96 h, token)
	tests/c/mbed-tls-test.sh 2>&1 | tee $(OUT)/c-mbedtls-$(STAMP).log

smoke-c-mbedtls-ws: | $(OUT) ## Level 3, C: the mbedtls fips campaign in a generated project's workshop (token)
	WORKSHOP=1 tests/c/mbed-tls-test.sh 2>&1 | tee $(OUT)/c-mbedtls-ws-$(STAMP).log

sudo-rs-rust: | $(OUT) ## Level 3, Rust: a Creusot campaign on sudo-rs (token)
	tests/rust/sudo-rs-test.sh 2>&1 | tee $(OUT)/rust-sudo-rs-$(STAMP).log

sudo-rs-rust-ws: | $(OUT) ## Level 3, Rust: the sudo-rs campaign in a generated project's workshop (token)
	WORKSHOP=1 tests/rust/sudo-rs-test.sh 2>&1 | tee $(OUT)/rust-sudo-rs-ws-$(STAMP).log

workspace-rust: | $(OUT) ## Level 3, Rust: why3find.json workspace cases A-H
	tests/rust/workspace-test.sh 2>&1 | tee $(OUT)/rust-workspace-$(STAMP).log

smoke-rust: | $(OUT) ## Level 3, Rust: creusot-launch smoke test (token)
	tests/rust/smoke-test.sh 2>&1 | tee $(OUT)/rust-smoke-$(STAMP).log

# --- Workshop SDKs (spec/workshop-autowp-c-base-spec.md) ------------------------
# Each target packs the SDK with `sdkcraft try` and runs sdks/test-sdk.sh on a
# throwaway workshop. Needs sdkcraft, workshop and LXD 6.8+. Not run by `test`.

sdk-lean: | $(OUT) ## Pack and test the lean SDK
	cd sdks/lean && sdkcraft try
	sdks/test-sdk.sh lean 2>&1 | tee $(OUT)/sdk-lean-$(STAMP).log

sdk-rocq: | $(OUT) ## Pack and test the rocq SDK (about an hour)
	cd sdks/rocq && sdkcraft try
	sdks/test-sdk.sh rocq 2>&1 | tee $(OUT)/sdk-rocq-$(STAMP).log

sdk-framac: | $(OUT) ## Pack and test the frama-c-sdk SDK (hours)
	sdks/frama-c-sdk/prepare.sh
	cd sdks/frama-c-sdk && sdkcraft try
	sdks/test-sdk.sh frama-c-sdk 2>&1 | tee $(OUT)/sdk-framac-$(STAMP).log

sdk-creusot: | $(OUT) ## Pack and test the creusot SDK (hours)
	cd sdks/creusot && sdkcraft try
	sdks/test-sdk.sh creusot 2>&1 | tee $(OUT)/sdk-creusot-$(STAMP).log

test-sdks: | $(OUT) ## Test the four tried SDKs together in one workshop
	sdks/test-sdk.sh frama-c-sdk rocq lean creusot 2>&1 | tee $(OUT)/sdks-$(STAMP).log

# --- cleanup ---------------------------------------------------------------

clean: ## Remove temporary files (never sources, test.txt or LXD objects)
	@removed=$$( { \
	    find . -path ./.git -prune -o -type d -name __pycache__ -print; \
	    find . -path ./.git -prune -o -type f \( -name '*.pyc' -o -name '*.pyo' -o -name '*~' \) -print; \
	    [ -e $(OUT) ] && echo ./$(OUT); \
	} | sort -u ); \
	if [ -n "$$removed" ]; then \
	    echo "$$removed" | sed 's/^/removing /'; \
	    echo "$$removed" | xargs -d '\n' rm -rf --; \
	else echo "nothing to clean"; fi

clean-lxc: ## Delete leftover test containers autowp-* (not the base containers)
	@for c in $$(lxc list --format csv -c n); do \
	    case "$$c" in \
	        autowp-c-base|autowp-rust-base) echo "keeping $$c" ;; \
	        autowp-*) echo "deleting $$c"; lxc delete --force "$$c" ;; \
	    esac; \
	done
