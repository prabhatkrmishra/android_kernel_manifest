# msm-4.19 kernel build wrappers. Same targets as build-kernel.sh in this
# directory; every recipe forwards to it. Works through the root `Makefile`
# symlink too: plain `make kernel` from the tree root does the same thing.
# The synced tree is only read from, never written.
# Pass fragments to any target:  make kernel FRAGMENTS="@X00TD/FRAGMENTS"
# Or use a full config file:     make kernel --config path/to/.config
KB := $(shell dirname $$(readlink -f $(lastword $(MAKEFILE_LIST))))
.PHONY: kernel bacon config menuconfig clean mrproper help

kernel:
	$(KB)/build-kernel.sh kernel $(FRAGMENTS)

# `bacon` builds the kernel and stages a flashable dir (out/build/).
# It does not produce a signed package.
bacon:
	$(KB)/build-kernel.sh kernel $(FRAGMENTS)
	FRAGMENTS="$(FRAGMENTS)" $(KB)/scripts/stage-anykernel.sh

config:
	$(KB)/build-kernel.sh config $(FRAGMENTS)

menuconfig:
	$(KB)/build-kernel.sh menuconfig

clean:
	$(KB)/build-kernel.sh clean

mrproper:
	$(KB)/build-kernel.sh mrproper

help:
	@echo "targets: config | kernel | bacon | menuconfig | clean | mrproper"
	@echo "TREE_TOP is auto-detected; override with TREE_TOP=<tree-root>"
	@echo "env overrides: TREE_TOP= KERNEL_SRC= KERNEL_OUT= JOBS= FRAGMENTS="
	@echo "examples:"
	@echo "  make kernel FRAGMENTS=\"vendor/base_defconfig vendor/extra.config\""
	@echo "  make kernel FRAGMENTS=\"@X00TD/FRAGMENTS\""
	@echo "  ./build kernel --config path/to/.config"
