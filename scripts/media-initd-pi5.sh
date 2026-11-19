#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Initialize Pi 5 capture
set -eu

export LC_ALL=C

MEDIA=/dev/rk628-media
VIDEO=/dev/rk628-video
RK_SUBDEV=/dev/rk628-subdev

die() { echo "Error: $*" >&2; exit 1; }

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  echo "Usage: sudo sh media-initd-pi5.sh"
  echo "Wait for HDMI and configure Pi 5 capture"
  echo "Stop capture applications first"
  exit 0
fi
[ "$#" -eq 0 ] || die "Unexpected argument: $1"
[ "$(id -u)" -eq 0 ] || die "Run as root"

for command in media-ctl v4l2-ctl awk grep flock timeout mountpoint; do
  command -v "$command" >/dev/null 2>&1 || die "Missing command: $command"
done
mountpoint -q /sys/kernel/debug || die "debugfs not mounted at /sys/kernel/debug"

exec 9>/run/lock/rk628-media.lock
flock -n 9 || die "media-initd-pi5.sh is already running"

find_entity() {
  printf '%s\n' "$TOPOLOGY" | awk -v kind="$1" '
    /^- entity [0-9]+:/ {
      name = $0
      sub(/^- entity [0-9]+: /, "", name)
      sub(/ \([0-9]+ pads?,.*/, "", name)
      if ((kind == "rk628" && index(name, "rk628-csi")) ||
          (kind == "csi2" && name == "csi2") ||
          (kind == "video" && name == "rp1-cfe-csi2_ch0"))
        print name
    }'
}

find_link() {
  printf '%s\n' "$TOPOLOGY" | awk -v source="$1" -v sink="$2" '
    /^- entity [0-9]+:/ {
      entity = $0
      sub(/^- entity [0-9]+: /, "", entity)
      sub(/ \([0-9]+ pads?,.*/, "", entity)
      pad = ""
    }
    entity == source && /^[[:space:]]*pad[0-9]+:/ {
      pad = ""
      if ($0 ~ /:[[:space:]]*SOURCE/) {
        pad = $0
        sub(/^[[:space:]]*pad/, "", pad)
        sub(/:.*/, "", pad)
      }
    }
    entity == source && pad != "" {
      link = $0
      sub(/^[[:space:]]*/, "", link)
      prefix = "-> \"" sink "\":"
      if (index(link, prefix) == 1) {
        remote = substr(link, length(prefix) + 1)
        sub(/[^0-9].*/, "", remote)
        if (remote != "") {
          source_pad = pad
          sink_pad = remote
          count++
        }
      }
    }
    END {
      if (count != 1)
        exit 1
      print source_pad, sink_pad
    }'
}

discover_devices() {
  [ -c "$MEDIA" ] && [ -c "$VIDEO" ] || return 1
  [ -c "$RK_SUBDEV" ] || return 1
  TOPOLOGY=$(media-ctl -d "$MEDIA" -p 2>/dev/null) || return 1

  RK_ENTITY=$(find_entity rk628)
  CSI_ENTITY=$(find_entity csi2)
  VIDEO_ENTITY=$(find_entity video)
  [ -n "$RK_ENTITY" ] && [ -n "$CSI_ENTITY" ] &&
    [ -n "$VIDEO_ENTITY" ] || return 1
  CSI_SUBDEV=$(media-ctl -d "$MEDIA" -e "$CSI_ENTITY") || return 1
  [ -c "$CSI_SUBDEV" ] || return 1
  pads=$(find_link "$RK_ENTITY" "$CSI_ENTITY") ||
    die "Expected one direct link from $RK_ENTITY to $CSI_ENTITY"
  RK_PAD=${pads%% *}
  CSI_SINK_PAD=${pads#* }
  pads=$(find_link "$CSI_ENTITY" "$VIDEO_ENTITY") ||
    die "Expected one direct link from $CSI_ENTITY to $VIDEO_ENTITY"
  CSI_SOURCE_PAD=${pads%% *}
  VIDEO_PAD=${pads#* }
  STATUS_FILE=/sys/kernel/debug/rk628/${RK_ENTITY##* }/hdmirx/status
}

read_v4l2() {
  timeout --signal=TERM --kill-after=2s 5s v4l2-ctl "$@"
}

read_pad_format() {
  output=$(read_v4l2 -d "$1" --get-subdev-fmt="pad=$2,stream=0") || return 1
  printf '%s\n' "$output" | awk '
    /Width\/Height[[:space:]]*:/ {split($3, size, "/"); w = size[1]; h = size[2]}
    /Mediabus Code[[:space:]]*:/ {code = $4}
    /^[[:space:]]*Field[[:space:]]*:/ {field = $3}
    END {
      if (w !~ /^[0-9]+$/ || h !~ /^[0-9]+$/ || w == 0 || h == 0 ||
          code !~ /^0x[0-9a-fA-F]+$/ || field == "")
        exit 1
      print code, w, h, field
    }'
}

read_signal() {
  power=$(read_v4l2 -d "$RK_SUBDEV" --get-ctrl=power_present 2>/dev/null) || return 1
  printf '%s\n' "$power" | grep -Eq 'power_present:[[:space:]]*1[[:space:]]*$' || return 1
  [ -r "$STATUS_FILE" ] || return 1
  status=$(cat "$STATUS_FILE") || return 1
  printf '%s\n' "$status" | grep -q '^status: plugin$' || return 1
  printf '%s\n' "$status" | grep -Eq 'Clk-Ch:Lock[[:space:]]+Ch0:Lock[[:space:]]+Ch1:Lock[[:space:]]+Ch2:Lock' || return 1
  read_v4l2 -d "$RK_SUBDEV" --query-dv-timings >/dev/null 2>&1 || return 1
  read_pad_format "$RK_SUBDEV" "$RK_PAD"
}

echo "Waiting for RK628 and a stable HDMI signal"
previous=
while :; do
  if discover_devices && current=$(read_signal); then
    identity="$MEDIA $RK_SUBDEV $CSI_SUBDEV $VIDEO $RK_PAD $CSI_SINK_PAD $CSI_SOURCE_PAD $VIDEO_PAD $current"
    [ "$identity" != "$previous" ] || break
    previous=$identity
  else
    previous=
  fi
  sleep 1
done

read -r CODE WIDTH HEIGHT FIELD <<EOF
$current
EOF
case "$CODE" in
  0x200f) BUS_FORMAT=UYVY8_1X16; PIXEL_FORMAT=UYVY ;;
  *) die "Unsupported CSI format: $CODE" ;;
esac
[ "$FIELD" = None ] || die "Unsupported field: $FIELD (expected None)"

media-ctl -d "$MEDIA" -l "\"$CSI_ENTITY\":$CSI_SOURCE_PAD -> \"$VIDEO_ENTITY\":$VIDEO_PAD [1]"
for pad in "$CSI_SINK_PAD" "$CSI_SOURCE_PAD"; do
  media-ctl -d "$MEDIA" \
    -V "\"$CSI_ENTITY\":$pad [fmt:$BUS_FORMAT/${WIDTH}x${HEIGHT} field:none]"
done
v4l2-ctl -d "$VIDEO" \
  --set-fmt-video="width=$WIDTH,height=$HEIGHT,pixelformat=$PIXEL_FORMAT,field=none"

for pad in "$CSI_SINK_PAD" "$CSI_SOURCE_PAD"; do
  actual=$(read_pad_format "$CSI_SUBDEV" "$pad") || die "Cannot read back CSI pad $pad"
  [ "$actual" = "$current" ] || die "CSI pad $pad format mismatch: $actual"
done
video_format=$(read_v4l2 -d "$VIDEO" --get-fmt-video) || die "Cannot read back video format"
printf '%s\n' "$video_format" | awk -v w="$WIDTH" -v h="$HEIGHT" -v pix="$PIXEL_FORMAT" '
  /Width\/Height[[:space:]]*:/ {split($3, size, "/"); width = size[1]; height = size[2]}
  /Pixel Format[[:space:]]*:/ {format = $4; gsub(/\047/, "", format)}
  /^[[:space:]]*Field[[:space:]]*:/ {field = $3}
  END {exit !(width == w && height == h && format == pix && field == "None")}
' || die "Video format mismatch"
final=$(read_signal) || die "HDMI signal lost; retry when stable"
[ "$final" = "$current" ] || die "CSI output changed; retry"

echo "Ready: $VIDEO ${WIDTH}x${HEIGHT} $PIXEL_FORMAT"
