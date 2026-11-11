#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Uninstall RK628 modules and the overlay installed through DKMS.
set -eu

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
. "$PROJECT_DIR/scripts/common.sh"

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  echo "Usage: sudo sh scripts/uninstall.sh"
  echo "Remove all DKMS versions and the overlay"
  exit 0
fi
[ "$#" -eq 0 ] || die "Unexpected arguments; use --help"
[ "$(id -u)" -eq 0 ] || die "Run with sudo: sudo sh scripts/uninstall.sh"

command -v dkms >/dev/null 2>&1 || die "Missing command: dkms"

read_package_name

find_versions
for version in $VERSIONS; do
  print DKMS "remove $PACKAGE_NAME/$version (all kernels)"
  dkms remove -m "$PACKAGE_NAME" -v "$version" --all
done

for directory in /usr/src/"$PACKAGE_NAME"-*; do
  [ -d "$directory" ] || continue
  print CLEAN "$directory"
  rm -rf -- "$directory"
done

print REMOVE /boot/firmware/overlays/rk628-pi5.dtbo
rm -f /boot/firmware/overlays/rk628-pi5.dtbo

printf '\nDone. Remove the dtoverlay=rk628-pi5 line (including any parameters) from /boot/firmware/config.txt and reboot manually.\n'
