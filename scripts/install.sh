#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Install RK628
set -eu

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
. "$PROJECT_DIR/scripts/common.sh"

[ "$#" -eq 0 ] || die "Usage: sudo ./scripts/install.sh"
[ "$(id -u)" -eq 0 ] || die "Run with sudo"

command -v udevadm >/dev/null 2>&1 || die "Missing command: udevadm"
[ -f "$PROJECT_DIR/udev/99-rk628.rules" ] || die "Missing udev/99-rk628.rules"

install_udev() {
  print INSTALL "/etc/udev/rules.d/99-rk628.rules"
  install -D -m 644 "$PROJECT_DIR/udev/99-rk628.rules" "/etc/udev/rules.d/99-rk628.rules"
  reload_udev
}

KERNEL_RELEASE=$(uname -r)
command -v dkms >/dev/null 2>&1 || die "Missing command: dkms"
[ -f "/lib/modules/$KERNEL_RELEASE/build/Makefile" ] ||
  die "Missing matching kernel headers for $KERNEL_RELEASE"

read_package_name
PACKAGE_VERSION=$(grep '^PACKAGE_VERSION=' "$PROJECT_DIR/dkms.conf" | cut -d'"' -f2)
: "${PACKAGE_NAME:?Missing PACKAGE_NAME}" "${PACKAGE_VERSION:?Missing PACKAGE_VERSION}"
DKMS_SRC=/usr/src/$PACKAGE_NAME-$PACKAGE_VERSION
case "$PROJECT_DIR" in
  /usr/src/"$PACKAGE_NAME"-*) die "Run from your checkout, not /usr/src" ;;
esac

find_versions
for version in $VERSIONS; do
  print DKMS "remove $PACKAGE_NAME/$version --all"
  dkms remove -m "$PACKAGE_NAME" -v "$version" --all
  print CLEAN "/usr/src/$PACKAGE_NAME-$version"
  rm -rf -- "/usr/src/$PACKAGE_NAME-$version"
done

print COPY "$DKMS_SRC"
rm -rf -- "$DKMS_SRC"
mkdir -p "$DKMS_SRC"
cp "$PROJECT_DIR"/*.c "$PROJECT_DIR"/*.h "$DKMS_SRC/"
for file in Makefile Kbuild dkms.conf dkms.postinst \
            rk628-common.dtsi rk628-pi4-overlay.dts rk628-pi5-overlay.dts COPYING; do
  cp "$PROJECT_DIR/$file" "$DKMS_SRC/"
done
cp -a "$PROJECT_DIR/include" "$PROJECT_DIR/LICENSES" "$DKMS_SRC/"
chmod 755 "$DKMS_SRC/dkms.postinst"

print DKMS "add $PACKAGE_NAME/$PACKAGE_VERSION"
dkms add -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION"
print DKMS "build for $KERNEL_RELEASE"
dkms build -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION" -k "$KERNEL_RELEASE"
print DKMS "install for $KERNEL_RELEASE"
dkms install -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION" -k "$KERNEL_RELEASE" --force

install_udev

printf '\nDone.\n'
