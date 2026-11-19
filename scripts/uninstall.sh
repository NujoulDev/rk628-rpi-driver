#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Uninstall RK628
set -eu

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
. "$PROJECT_DIR/scripts/common.sh"

usage() {
  echo "Usage: sudo sh scripts/uninstall.sh -p pi4|pi5 [-c all|service]"
  echo "Default: driver, DTBO and udev rules"
  echo "  -c service  Media service"
  echo "  -c all      All"
}

parse_options "$@"
[ "$(id -u)" -eq 0 ] || die "Run with sudo"

if [ "$COMPONENT" = service ] || [ "$COMPONENT" = all ]; then
  select_media_service
  command -v systemctl >/dev/null 2>&1 || die "Missing command: systemctl"
  SERVICE_FILE=/etc/systemd/system/$SERVICE_NAME
  if [ -e "$SERVICE_FILE" ] || [ -L "$SERVICE_FILE" ]; then
    print REMOVE "$SERVICE_NAME"
    systemctl disable --now "$SERVICE_NAME"
  fi
  rm -f "$SERVICE_FILE" "/usr/local/libexec/rk628/$MEDIA_SCRIPT"
  systemctl daemon-reload
  if [ "$COMPONENT" = service ]; then
    printf '\nService removed\n'
    exit 0
  fi
fi

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

print REMOVE "$OVERLAY_DIR/rk628-$PLATFORM.dtbo"
rm -f "$OVERLAY_DIR/rk628-$PLATFORM.dtbo"

print REMOVE "/etc/udev/rules.d/99-rk628.rules"
rm -f /etc/udev/rules.d/99-rk628.rules
reload_udev
