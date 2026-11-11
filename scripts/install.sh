#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Install RK628 modules and the overlay through DKMS.
set -eu

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
. "$PROJECT_DIR/scripts/common.sh"

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  echo "Usage: sudo sh scripts/install.sh"
  echo "Build and install for the running kernel"
  exit 0
fi
[ "$#" -eq 0 ] || die "Unexpected arguments; use --help"
[ "$(id -u)" -eq 0 ] || die "Run with sudo: sudo sh scripts/install.sh"

KERNEL_RELEASE=$(uname -r)
command -v dkms >/dev/null 2>&1 || die "Install DKMS first: sudo apt install dkms"
[ -f "/lib/modules/$KERNEL_RELEASE/build/Makefile" ] ||
  die "Missing matching kernel headers for $KERNEL_RELEASE"

read_package_name
PACKAGE_VERSION=$(grep '^PACKAGE_VERSION=' "$PROJECT_DIR/dkms.conf" | cut -d'"' -f2)
: "${PACKAGE_NAME:?Missing PACKAGE_NAME}" "${PACKAGE_VERSION:?Missing PACKAGE_VERSION}"
DKMS_SRC=/usr/src/$PACKAGE_NAME-$PACKAGE_VERSION
case "$PROJECT_DIR" in
  /usr/src/"$PACKAGE_NAME"-*) die "Run from your checkout, outside /usr/src/$PACKAGE_NAME-*" ;;
esac

find_versions
for version in $VERSIONS; do
  print DKMS "remove $PACKAGE_NAME/$version (all kernels)"
  dkms remove -m "$PACKAGE_NAME" -v "$version" --all
  print CLEAN "/usr/src/$PACKAGE_NAME-$version"
  rm -rf -- "/usr/src/$PACKAGE_NAME-$version"
done

print COPY "source -> $DKMS_SRC"
rm -rf -- "$DKMS_SRC"
mkdir -p "$DKMS_SRC"
cp "$PROJECT_DIR"/*.c "$PROJECT_DIR"/*.h "$DKMS_SRC/"
for file in Makefile Kbuild dkms.conf dkms.postinst rk628-pi5-overlay.dts COPYING; do
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

printf '\nDone. Review config.txt and reboot manually.\n'
