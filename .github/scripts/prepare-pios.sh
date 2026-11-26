#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail

output=${1:?Usage: prepare-pios.sh <kernel-env-file>}
: "${FLAVOUR:?Set FLAVOUR to rpi-v8 or rpi-2712}"

configure_repository() {
  apt-get install -y --no-install-recommends \
    build-essential curl gnupg kmod \
    bc bison flex libssl-dev libelf-dev pahole
  mkdir -p /etc/apt/keyrings
  curl --fail --silent --show-error --location --retry 3 \
    https://raw.githubusercontent.com/raspberrypi/rpi-image-gen/1f5851b24a6ac25b91edfaed5f2b59e770d0ac9e/keydir/raspberrypi-archive-keyring.gpg \
    -o /etc/apt/keyrings/raspberrypi.gpg
  fingerprint=$(gpg --batch --show-keys --with-colons /etc/apt/keyrings/raspberrypi.gpg \
    | awk -F: '$1 == "fpr" {print $10; exit}')
  test "$fingerprint" = CF8A1AF502A2AA2D763BAE7E82B129927FA3303E
  echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/raspberrypi.gpg] https://archive.raspberrypi.com/debian/ trixie main" \
    > /etc/apt/sources.list.d/raspberrypi.list
  apt-get update
}

install_headers() {
  apt-get install -y --no-install-recommends "linux-headers-$FLAVOUR"
  headers_version=$(dpkg-query -W -f='${Version}' "linux-headers-$FLAVOUR")
  kernel_version=$(apt-cache policy "linux-image-$FLAVOUR" | awk '$1 == "Candidate:" {print $2}')
  test "$headers_version" = "$kernel_version"
  mapfile -t directories < <(find /usr/src -maxdepth 1 -type d -name "linux-headers-*-$FLAVOUR")
  test "${#directories[@]}" -eq 1
  kdir=${directories[0]}
  release=$(cat "$kdir/include/config/kernel.release")
  dpkg-query -W 'linux-headers-*' 'linux-kbuild-*'
}

configure_repository
install_headers
printf 'KDIR=%q\nKERNEL_RELEASE=%q\n' "$kdir" "$release" > "$output"
{
  echo "### Raspberry Pi OS / $FLAVOUR"
  echo "- Source: Raspberry Pi trixie/main, arm64"
  echo "- Kernel: $release"
  echo "- Package version: $headers_version"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
