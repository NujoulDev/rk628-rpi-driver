# SPDX-License-Identifier: GPL-2.0
# Standalone module build against prepared Raspberry Pi kernel headers.
KDIR ?= /lib/modules/$(shell uname -r)/build
DTC ?= dtc
# DTC does not recognize Raspberry Pi __dormant__ fragment unit addresses.
DTC_FLAGS := -@ -Wno-unit_address_vs_reg -I dts -O dtb
BUILD_DIR := $(CURDIR)/build
SOURCES := $(wildcard *.c *.h)

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

dtbo: $(BUILD_DIR)/rk628-pi5.dtbo

$(BUILD_DIR)/rk628-pi5.dtbo: rk628-pi5-overlay.dts
	@mkdir -p "$(BUILD_DIR)"
	$(DTC) $(DTC_FLAGS) -o "$@" "$<"

clean:
	$(RM) -r "$(BUILD_DIR)"
