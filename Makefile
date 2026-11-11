# SPDX-License-Identifier: GPL-2.0
# RK628 modules and DTBO
KDIR ?= /lib/modules/$(shell uname -r)/build
DTC ?= dtc
DTS_CPP ?= cpp
# Raspberry Pi __dormant__ fragments trigger this warning
DTC_FLAGS := -@ -Wno-unit_address_vs_reg -I dts -O dtb
BUILD_DIR := $(CURDIR)/build
SOURCES := $(wildcard *.c *.h)
PLATFORM ?= $(shell grep '^RK628_PLATFORM=' dkms.conf | cut -d'"' -f2)
DTBO := $(BUILD_DIR)/rk628-$(PLATFORM).dtbo

ifneq ($(filter all dtbo,$(or $(MAKECMDGOALS),all)),)
ifneq ($(PLATFORM),pi4)
ifneq ($(PLATFORM),pi5)
$(error Specify PLATFORM=pi4 or PLATFORM=pi5)
endif
endif
endif

.PHONY: all modules module dtbo prepare clean
all: modules dtbo
module: modules

prepare:
	@mkdir -p "$(BUILD_DIR)"
	@for src in $(SOURCES) Kbuild include; do \
		ln -sfn "$(CURDIR)/$$src" "$(BUILD_DIR)/$$src"; \
	done

modules: prepare
	$(MAKE) -C "$(KDIR)" M="$(BUILD_DIR)" modules

dtbo: $(DTBO)

$(BUILD_DIR)/rk628-%.dtbo: rk628-%-overlay.dts rk628-common.dtsi
	@mkdir -p "$(BUILD_DIR)"
	$(DTS_CPP) -nostdinc -undef -D__DTS__ -x assembler-with-cpp -P \
		"$<" -o "$(@:.dtbo=.dts)"
	$(DTC) $(DTC_FLAGS) -o "$@" "$(@:.dtbo=.dts)"

clean:
	$(RM) -r "$(BUILD_DIR)"
