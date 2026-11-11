#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Uninstall RK628 modules, the overlay or the media service
set -eu

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
. "$PROJECT_DIR/scripts/common.sh"

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  echo "Usage: sudo sh scripts/uninstall.sh [media-service|all]"
  echo "No argument: remove DKMS modules and DTBO only; leave the service unchanged"
  echo "media-service: stop, disable and remove the service and media.sh only"
  echo "all: remove the service first, then DKMS modules and DTBO"
  echo "Boot configuration must be removed manually"
  exit 0
fi
[ "$#" -le 1 ] || die "Unexpected arguments; use --help"
case "${1:-}" in
  ''|media-service|all) ;;
  *) die "Unknown argument: $1; use --help" ;;
esac
[ "$(id -u)" -eq 0 ] || die "Run with sudo: sudo sh scripts/uninstall.sh"

if [ "${1:-}" = media-service ] || [ "${1:-}" = all ]; then
  command -v systemctl >/dev/null 2>&1 || die "Missing command: systemctl"
  SERVICE_FILE=/etc/systemd/system/rk628-media-init.service
  if [ -e "$SERVICE_FILE" ] || [ -L "$SERVICE_FILE" ]; then
    print REMOVE rk628-media-init.service
    systemctl disable --now rk628-media-init.service
  fi
  rm -f "$SERVICE_FILE" /usr/local/libexec/rk628/media.sh
  systemctl daemon-reload
  if [ "${1:-}" = media-service ]; then
    printf '\nDone. Media service and script removed.\n'
    exit 0
  fi
fi

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
