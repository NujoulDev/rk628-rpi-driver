#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Shared installer functions

print() { printf '  %-7s %s\n' "$1" "$2"; }
die() { echo "Error: $*" >&2; exit 1; }

read_package_name() {
  PACKAGE_NAME=$(grep '^PACKAGE_NAME=' "$PROJECT_DIR/dkms.conf" | cut -d'"' -f2)
  : "${PACKAGE_NAME:?Missing PACKAGE_NAME}"
}

find_versions() {
  STATUS=$(dkms status -m "$PACKAGE_NAME")
  VERSIONS=$(printf '%s\n' "$STATUS" |
    awk -F '[/,:]' -v package="$PACKAGE_NAME" '$1 == package {print $2}' | sort -u)
}

reload_udev() {
  udevadm control --reload-rules
  udevadm trigger --action=add --subsystem-match=video4linux --subsystem-match=media
  udevadm settle
}
