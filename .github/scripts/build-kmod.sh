#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail

# shellcheck source=/dev/null
source "${1:?Usage: build-kmod.sh <kernel-env-file>}"
: "${KDIR:?Missing KDIR}" "${KERNEL_RELEASE:?Missing KERNEL_RELEASE}"
export ARCH=arm64
cd "$(dirname "$0")/../.."

test "$(cat "$KDIR/include/config/kernel.release")" = "$KERNEL_RELEASE"
grep -qx 'CONFIG_ARM64=y' "$KDIR/.config"
test -s "$KDIR/Module.symvers"

make -j"$(nproc)" module KDIR="$KDIR"
for module in video-rk628 rk628-csi rk628-hdmirx-class; do
  test -s "build/$module.ko"
  actual=$(modinfo -F vermagic "build/$module.ko")
  test "${actual%% *}" = "$KERNEL_RELEASE"
done
