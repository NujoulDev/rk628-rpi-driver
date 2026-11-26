#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail

output=${1:?Usage: prepare-pikvm.sh <kernel-env-file>}
: "${PIKVM_REPOSITORY:?Set PIKVM_REPOSITORY to the target package repository}"

configure_repository() {
  mkdir -p /etc/pacman.d/hooks
  ln -sf /dev/null /etc/pacman.d/hooks/30-systemd-tmpfiles.hook
  sed -i 's/^#DisableSandbox/DisableSandbox/' /etc/pacman.conf
  echo "Server = https://de3.mirror.archlinuxarm.org/\$arch/\$repo" > /etc/pacman.d/mirrorlist
  pacman-key --init
  pacman-key --populate archlinuxarm
  pacman-key --keyserver hkps://keyserver.ubuntu.com:443 --recv-keys 912C773ABBD1B584 \
    || pacman-key --keyserver hkps://keys.gnupg.net:443 --recv-keys 912C773ABBD1B584
  pacman-key --lsign-key 912C773ABBD1B584
  {
    echo '[pikvm]'
    echo "Server = $PIKVM_REPOSITORY"
    echo 'SigLevel = Required DatabaseOptional'
  } >> /etc/pacman.conf
}

install_headers() {
  pacman --noconfirm --ask=4 -Syu --needed \
    base-devel bc libelf openssl kmod python pahole linux-rpi-headers-pikvm
  headers_version=$(pacman -Q linux-rpi-headers-pikvm | awk '{print $2}')
  kernel_version=$(pacman -Si linux-rpi-pikvm | awk '$1 == "Version" {print $3}')
  test "$headers_version" = "$kernel_version"
  mapfile -t directories < <(pacman -Qlq linux-rpi-headers-pikvm | sed -n 's#/build/Makefile$#/build#p')
  test "${#directories[@]}" -eq 1
  kdir=${directories[0]}
  release=$(cat "$kdir/include/config/kernel.release")
  pacman -Q gcc linux-rpi-headers-pikvm
}

configure_repository
install_headers
printf 'KDIR=%q\nKERNEL_RELEASE=%q\n' "$kdir" "$release" > "$output"
{
  echo "### PiKVM OS / $PIKVM_REPOSITORY"
  echo "- Package version: $headers_version"
  echo "- Kernel: $release"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
