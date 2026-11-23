#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Uninstall RK628
set -eu

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
. "$PROJECT_DIR/scripts/common.sh"

[ "$#" -eq 0 ] || die "Usage: sudo ./scripts/uninstall.sh"
[ "$(id -u)" -eq 0 ] || die "Run with sudo"

if [ -d /boot/firmware/overlays ]; then
  OVERLAY_DIR=/boot/firmware/overlays
elif [ -d /boot/overlays ]; then
  OVERLAY_DIR=/boot/overlays
else
  echo "Error: overlays directory not found" >&2
  exit 1
fi

command -v dkms >/dev/null 2>&1 || die "Missing command: dkms"
command -v udevadm >/dev/null 2>&1 || die "Missing command: udevadm"

read_package_name

find_versions
for version in $VERSIONS; do
  print DKMS "remove $PACKAGE_NAME/$version --all"
  dkms remove -m "$PACKAGE_NAME" -v "$version" --all
done

for directory in /usr/src/"$PACKAGE_NAME"-*; do
  [ -d "$directory" ] || continue
  print CLEAN "$directory"
  rm -rf -- "$directory"
done

for platform in pi4 pi5; do
  print REMOVE "$OVERLAY_DIR/rk628-$platform.dtbo"
  rm -f "$OVERLAY_DIR/rk628-$platform.dtbo"
done

print REMOVE "/etc/udev/rules.d/99-rk628.rules"
rm -f /etc/udev/rules.d/99-rk628.rules
reload_udev
