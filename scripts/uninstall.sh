#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Uninstall RK628
set -eu

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
. "$PROJECT_DIR/scripts/common.sh"

usage() {
  echo "Usage: sudo sh scripts/uninstall.sh -p pi4|pi5 [-c all|service]"
  echo "Default: driver and DTBO"
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

command -v dkms >/dev/null 2>&1 || die "Missing command: dkms"

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

print REMOVE "/boot/firmware/overlays/rk628-$PLATFORM.dtbo"
rm -f "/boot/firmware/overlays/rk628-$PLATFORM.dtbo"

printf '\nRemove dtoverlay=rk628-%s from /boot/firmware/config.txt, then reboot.\n' "$PLATFORM"
