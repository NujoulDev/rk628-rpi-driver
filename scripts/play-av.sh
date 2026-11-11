#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Preview RK628 1080p60 video through KMS and audio through a USB sound card.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./play-av.sh

Run locally on the Raspberry Pi or over SSH. The source must output 1920x1080p60 video and 48 kHz stereo audio.
The script configures CSI capture, temporarily stops the desktop, and plays video on an HDMI display and audio through USB speakers.
Press Ctrl+C to stop. If the desktop was running, it is restored on exit.

Optional environment variables:
  VIDEO_DEVICE    Capture device; default: /dev/video0
  SUBDEV_DEVICE   RK628 subdevice; detected through sysfs by default
  AUDIO_CAPTURE  Default: hw:CARD=RK628HDMI,DEV=0
  AUDIO_PLAYBACK Default: hw:CARD=Device,DEV=0
  CONNECTOR_ID   HDMI connector ID; defaults to the first connected HDMI port
  LOG_FILE       Default: $HOME/rk628-kms-av.log; overwritten on each run
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

as_root() {
  if [ "$EUID" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

restore_desktop=0
cleanup() {
  local status=$?
  trap - EXIT
  if [ "$restore_desktop" -eq 1 ]; then
    echo 'Restoring desktop...'
    if ! as_root systemctl start display-manager; then
      echo 'Failed to restore desktop; run sudo systemctl start display-manager manually' >&2
      if [ "$status" -eq 0 ]; then
        status=1
      fi
    fi
  fi
  exit "$status"
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
fi

for command in gst-launch-1.0 gst-inspect-1.0 media-ctl v4l2-ctl \
               systemctl timeout awk grep tee; do
  command -v "$command" >/dev/null || die "Missing command: $command"
done
if [ "$EUID" -ne 0 ]; then
  command -v sudo >/dev/null || die 'Missing sudo'
fi

for element in v4l2src queue videoconvert kmssink alsasrc audioconvert alsasink; do
  gst-inspect-1.0 "$element" >/dev/null 2>&1 ||
    die "Missing GStreamer plugin: $element; see the README for dependencies"
done

VIDEO_DEVICE=${VIDEO_DEVICE:-/dev/video0}
SUBDEV_DEVICE=${SUBDEV_DEVICE:-}
AUDIO_CAPTURE=${AUDIO_CAPTURE:-hw:CARD=RK628HDMI,DEV=0}
AUDIO_PLAYBACK=${AUDIO_PLAYBACK:-hw:CARD=Device,DEV=0}
CONNECTOR_ID=${CONNECTOR_ID:-}
LOG_FILE=${LOG_FILE:-$HOME/rk628-kms-av.log}

if [ -z "$SUBDEV_DEVICE" ]; then
  for name in /sys/class/video4linux/v4l-subdev*/name; do
    [ -r "$name" ] || continue
    if grep -qi rk628 "$name"; then
      node=${name%/name}
      SUBDEV_DEVICE="/dev/${node##*/}"
      break
    fi
  done
fi
[ -n "$SUBDEV_DEVICE" ] || die 'RK628 subdevice not found'
[ -c "$SUBDEV_DEVICE" ] || die "Subdevice does not exist: $SUBDEV_DEVICE"
[ -c "$VIDEO_DEVICE" ] || die "Capture device does not exist: $VIDEO_DEVICE"

timings=$(timeout --signal=INT --kill-after=3s 5s \
  v4l2-ctl -d "$SUBDEV_DEVICE" --query-dv-timings) ||
  die 'Failed to query HDMI timings; check that the source is connected and sending video'
printf '%s\n' "$timings"
width=$(printf '%s\n' "$timings" | awk '/Active width:/ {print $3}')
height=$(printf '%s\n' "$timings" | awk '/Active height:/ {print $3}')
fps=$(printf '%s\n' "$timings" | awk '
  /frames per second/ {
    for (i = 1; i <= NF; i++)
      if ($i == "frames") {value = $(i - 1); sub(/^\(/, "", value); print value}
  }')
[ "$width" = 1920 ] && [ "$height" = 1080 ] ||
  die 'This script requires 1920x1080p60; adjust the source output first'
awk -v fps="$fps" 'BEGIN {exit !(fps >= 59 && fps <= 61)}' ||
  die "Input is not approximately 60 fps (detected: ${fps:-unknown}); adjust the source output first"

media_device=
for node in /dev/media*; do
  [ -e "$node" ] || continue
  topology=$(media-ctl -d "$node" -p 2>/dev/null) || continue
  if printf '%s\n' "$topology" |
     grep -Eq '^model[[:space:]]+rp1-cfe[[:space:]]*$' &&
     printf '%s\n' "$topology" | grep -qi rk628; then
    media_device=$node
    break
  fi
done
[ -n "$media_device" ] || die 'No rp1-cfe media device connected to RK628 was found'

if [ -z "$CONNECTOR_ID" ]; then
  for port in /sys/class/drm/card*-HDMI-A-*; do
    [ -r "$port/status" ] || continue
    if [ "$(< "$port/status")" = connected ]; then
      CONNECTOR_ID=$(< "$port/connector_id")
      break
    fi
  done
fi
[[ "$CONNECTOR_ID" =~ ^[0-9]+$ ]] || die 'No HDMI display found or invalid connector ID'

media-ctl -d "$media_device" \
  -l '"csi2":4 -> "rp1-cfe-csi2_ch0":0 [1]'
media-ctl -d "$media_device" \
  -V '"csi2":0 [fmt:UYVY8_1X16/1920x1080 field:none]'
v4l2-ctl -d "$VIDEO_DEVICE" \
  --set-fmt-video=width=1920,height=1080,pixelformat=UYVY

# Open the log before stopping the desktop, so path errors leave it running.
: > "$LOG_FILE"
if [ "$EUID" -ne 0 ]; then
  sudo -v
fi
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
if systemctl is-active --quiet display-manager; then
  restore_desktop=1
  as_root systemctl stop display-manager
fi

printf 'Starting playback: 1080p60, HDMI connector %s, speakers %s\n' \
  "$CONNECTOR_ID" "$AUDIO_PLAYBACK"
printf 'Press Ctrl+C to stop. Log: %s\n' "$LOG_FILE"

as_root gst-launch-1.0 -e -v \
  v4l2src device="$VIDEO_DEVICE" io-mode=mmap \
    ! 'video/x-raw,format=UYVY,width=1920,height=1080,framerate=60/1,colorimetry=1:3:5:1' \
    ! queue max-size-buffers=4 max-size-bytes=0 max-size-time=0 \
    ! videoconvert n-threads=4 \
    ! 'video/x-raw,format=NV16,width=1920,height=1080,framerate=60/1,colorimetry=1:3:5:1' \
    ! kmssink driver-name=vc4 connector-id="$CONNECTOR_ID" \
        force-modesetting=false can-scale=false sync=true \
        plane-properties='s,COLOR_ENCODING=(uint)1,COLOR_RANGE=(uint)1' \
  alsasrc device="$AUDIO_CAPTURE" \
    ! 'audio/x-raw,format=S32LE,rate=48000,channels=2,layout=interleaved' \
    ! queue max-size-buffers=0 max-size-bytes=0 max-size-time=200000000 \
    ! audioconvert \
    ! 'audio/x-raw,format=S16LE,rate=48000,channels=2,layout=interleaved' \
    ! alsasink device="$AUDIO_PLAYBACK" sync=true \
  2>&1 | tee "$LOG_FILE"
