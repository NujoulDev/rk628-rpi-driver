#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Install RK628 modules, the overlay or the media service
set -eu

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
. "$PROJECT_DIR/scripts/common.sh"

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  echo "Usage: sudo sh scripts/install.sh [media-service]"
  echo "No argument: install DKMS modules and DTBO only"
  echo "media-service: install media.sh and the service only; do not enable or start"
  exit 0
fi
[ "$#" -le 1 ] || die "Unexpected arguments; use --help"
case "${1:-}" in
  ''|media-service) ;;
  *) die "Unknown argument: $1; use --help" ;;
esac
[ "$(id -u)" -eq 0 ] || die "Run with sudo: sudo sh scripts/install.sh"

if [ "${1:-}" = media-service ]; then
  command -v systemctl >/dev/null 2>&1 || die "Missing command: systemctl"
  [ -f "$PROJECT_DIR/scripts/media.sh" ] || die "Missing scripts/media.sh"
  [ -f "$PROJECT_DIR/scripts/rk628-media-init.service" ] || die "Missing service file"
  print INSTALL /usr/local/libexec/rk628/media.sh
  install -D -m 755 "$PROJECT_DIR/scripts/media.sh" /usr/local/libexec/rk628/media.sh
  print INSTALL /etc/systemd/system/rk628-media-init.service
  install -D -m 644 "$PROJECT_DIR/scripts/rk628-media-init.service" \
    /etc/systemd/system/rk628-media-init.service
  systemctl daemon-reload
  printf '\nDone. Service installed\n'
  exit 0
fi

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
