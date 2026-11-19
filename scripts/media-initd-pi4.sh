#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Initialize Pi 4 Unicam legacy capture
set -eu

export LC_ALL=C

MEDIA=/dev/rk628-media
VIDEO=/dev/rk628-video

die() { echo "Error: $*" >&2; exit 1; }

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  echo "Usage: sudo sh media-initd-pi4.sh"
  echo "Wait for HDMI and configure Pi 4 capture"
  echo "Stop capture applications first"
  exit 0
fi
[ "$#" -eq 0 ] || die "Unexpected argument: $1"
[ "$(id -u)" -eq 0 ] || die "Run as root"

for command in media-ctl v4l2-ctl awk grep flock timeout mountpoint; do
  command -v "$command" >/dev/null 2>&1 || die "Missing command: $command"
done
mountpoint -q /sys/kernel/debug || die "debugfs not mounted at /sys/kernel/debug"

exec 9>/run/lock/rk628-media-pi4.lock
flock -n 9 || die "media-initd-pi4.sh is already running"

find_entity() {
  printf '%s\n' "$TOPOLOGY" | awk -v kind="$1" '
    /^- entity [0-9]+:/ {
      name = $0
      sub(/^- entity [0-9]+: /, "", name)
      sub(/ \([0-9]+ pads?,.*/, "", name)
      if ((kind == "rk628" && index(name, "rk628-csi")))
        print name
    }'
}

discover_devices() {
  [ -c "$MEDIA" ] && [ -c "$VIDEO" ] || return 1
  TOPOLOGY=$(media-ctl -d "$MEDIA" -p 2>/dev/null) || return 1

  RK_ENTITY=$(find_entity rk628)
  [ -n "$RK_ENTITY" ] || return 1
  STATUS_FILE=/sys/kernel/debug/rk628/${RK_ENTITY##* }/hdmirx/status
}

read_v4l2() {
  timeout --signal=TERM --kill-after=2s 5s v4l2-ctl "$@"
}

read_signal() {
  power=$(read_v4l2 -d "$VIDEO" --get-ctrl=power_present 2>/dev/null) || return 1
  printf '%s\n' "$power" | grep -Eq 'power_present:[[:space:]]*1[[:space:]]*$' || return 1
  [ -r "$STATUS_FILE" ] || return 1
  status=$(cat "$STATUS_FILE") || return 1
  printf '%s\n' "$status" | grep -q '^status: plugin$' || return 1
  printf '%s\n' "$status" | grep -Eq 'Clk-Ch:Lock[[:space:]]+Ch0:Lock[[:space:]]+Ch1:Lock[[:space:]]+Ch2:Lock' || return 1

  timings=$(read_v4l2 -d "$VIDEO" --query-dv-timings) || return 1
  detected=$(printf '%s\n' "$timings" | awk '
    /Active width:/ {w = $3}
    /Active height:/ {h = $3}
    /Frame format:/ {field = $3}
    END {
      if (w !~ /^[0-9]+$/ || h !~ /^[0-9]+$/ || w == 0 || h == 0 ||
          (field != "progressive" && field != "interlaced"))
        exit 1
      print w, h, field
    }') || return 1
  debug_size=$(printf '%s\n' "$status" | awk '
    /^Timing:/ {size = $2; sub(/[pi].*/, "", size); split(size, dimensions, "x")
      print dimensions[1], dimensions[2]}')
  [ "${detected% *}" = "$debug_size" ] || return 1

  video_format=$(read_v4l2 -d "$VIDEO" --get-fmt-video) || return 1
  pixel_format=$(printf '%s\n' "$video_format" | awk '
    /Pixel Format[[:space:]]*:/ {format = $4; gsub(/\047/, "", format); print format}')
  [ -n "$pixel_format" ] || return 1
  printf '%s %s\n' "$detected" "$pixel_format"
}

echo "Waiting for RK628 and a stable HDMI signal"
previous=
while :; do
  if discover_devices && current=$(read_signal); then
    identity="$MEDIA $VIDEO $STATUS_FILE $current"
    [ "$identity" != "$previous" ] || break
    previous=$identity
  else
    previous=
  fi
  sleep 1
done

read -r WIDTH HEIGHT FIELD PIXEL_FORMAT <<EOF
$current
EOF
[ "$FIELD" = progressive ] || die "Unsupported field: $FIELD (expected progressive)"
[ "$PIXEL_FORMAT" = UYVY ] || die "Unsupported capture format: $PIXEL_FORMAT"

v4l2-ctl -d "$VIDEO" \
  --set-fmt-video="width=$WIDTH,height=$HEIGHT,pixelformat=$PIXEL_FORMAT,field=none"

video_format=$(read_v4l2 -d "$VIDEO" --get-fmt-video) || die "Cannot read back video format"
printf '%s\n' "$video_format" | awk -v w="$WIDTH" -v h="$HEIGHT" -v pix="$PIXEL_FORMAT" '
  /Width\/Height[[:space:]]*:/ {split($3, size, "/"); width = size[1]; height = size[2]}
  /Pixel Format[[:space:]]*:/ {format = $4; gsub(/\047/, "", format)}
  /^[[:space:]]*Field[[:space:]]*:/ {field = $3}
  END {exit !(width == w && height == h && format == pix && field == "None")}
' || die "Video format mismatch"
final=$(read_signal) || die "HDMI signal lost; retry when stable"
[ "$final" = "$current" ] || die "HDMI input changed; retry"

echo "Ready: $VIDEO ${WIDTH}x${HEIGHT} $PIXEL_FORMAT"
