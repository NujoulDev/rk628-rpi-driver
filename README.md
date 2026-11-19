# RK628 kernel driver for Raspberry Pi4/5

**English** | [简体中文](README.zh-CN.md)

[![Debian 13 (trixie)](https://img.shields.io/badge/Debian-13_%28trixie%29-blue?logo=debian)](https://www.debian.org/)
[![Tested kernel 6.18](https://img.shields.io/badge/tested_kernel-6.18-blue?logo=raspberrypi)](#tested-environments)

This project provides a Raspberry Pi 4/5 driver for the `Radxa 4K HDMI IN to MIPI CSI-2 Adapter`, with support for audio and video capture.


## Tested environments

| Platform | OS | Architecture | Kernel |
| --- | --- | --- | --- |
| Raspberry Pi 4 | Debian GNU/Linux 13.7 (trixie) | `aarch64` | `6.18.60+rpt-rpi-v8` |
| Raspberry Pi 5 | Debian GNU/Linux 13.7 (trixie) | `aarch64` | `6.18.50+rpt-rpi-2712` |

The driver must be built against headers matching the running kernel. Other operating systems and kernel versions have not been tested.

## Specifications

- The adapter provides both 2-lane and 4-lane MIPI CSI-2 interfaces. Currently, only the 4-lane interface is supported on Pi 5, and only the 2-lane interface is supported on Pi 4.

- Video input: HDMI input supports up to 4K (3840×2160) at 30 fps.

- Video output: the 4-lane interface supports up to 4K (3840×2160) at 30 fps on Pi 5; the 2-lane interface supports up to 2K (2560×1440) at 30 fps on Pi 4.

## Hardware connections

### Required parts

- Radxa 4K HDMI IN to MIPI CSI-2 Adapter
- Pi 4 or Pi 5
- Six female-to-female jumper wires
- Pi 4: a `15P-to-15P ribbon cable`
- Pi 5: a `31P-to-31P ribbon cable`, a `22P-to-22P ribbon cable`, and a `22P-to-31P adapter`

### HDMI

Connect an HDMI source. Input up to 4K (3840×2160) at 30 fps is supported.

### MIPI CSI

For Pi 4, use a `15pin to 15pin` ribbon cable to connect the adapter's 2-lane MIPI CSI interface to the Pi 4's `CAMERA` connector.

For Pi 5, use a `31pin to 31pin` ribbon cable to connect the adapter's 4-lane MIPI CSI interface to the 31-pin connector on the `22P-to-31P adapter`. Then use a `22P-to-22P` ribbon cable to connect the adapter's 22-pin connector to the Pi 5's `CAM/DISP0` or `CAM/DISP1` connector.

### I2S

| Adapter 7-pin header | Pi 4/5 connection |
| :---: | :---: |
| I2S D0 | GPIO20, physical pin **38** |
| I2S LRCK | GPIO19, physical pin **35** |
| I2S SCLK | GPIO18, physical pin **12** |
| GND | Any GND pin on the Raspberry Pi |

### DET, INT

| Adapter 7-pin header | Pi 4/5 connection |
| :---: | :---: |
| DET | GPIO25, physical pin **22** |
| INT | GPIO17, physical pin **11** |

## About media-initd

media-initd is an optional service for configuring video capture. It waits for the first stable HDMI signal, sets the resolution and format, configures the capture pipeline on Pi 5, and exits once configuration is complete.

For officially supported Raspberry Pi cameras, this configuration is handled by `libcamera` in userspace.

After changing the HDMI source or resolution, or reconnecting HDMI, restart media-initd or configure capture manually; see [Video capture configuration](#video-capture-configuration). Applications that configure the capture pipeline themselves do not need media-initd.

## Installation and configuration

The following steps apply to standard Raspberry Pi OS. By default, the installation script installs the driver modules, device tree overlays, DKMS configuration, and udev rules. Install media-initd if needed.

### Install dependencies

```bash
sudo apt update
sudo apt install -y \
  git ca-certificates \
  build-essential dkms device-tree-compiler \
  "linux-headers-$(uname -r)" \
  v4l-utils alsa-utils
```

Check the running kernel version and confirm that the build directory for the matching headers exists:

```bash
uname -r
ls "/lib/modules/$(uname -r)/build/Makefile"
```

### Install the driver

Clone the source:

```bash
git clone https://github.com/Nujoul1/rk628-rpi-driver.git
cd rk628-rpi-driver
```

Script options:

The following options apply to both `scripts/install.sh` and `scripts/uninstall.sh`.

| Option | Values | Description |
| --- | --- | --- |
| `-p` | `pi4`, `pi5` | Required; selects the platform |
| `-c` | `service`, `all` | Optional. When omitted, handles the driver, DTBO, and udev rules. `all` also handles media-initd. `service` handles only media-initd; installation also installs its required udev rules, while uninstallation leaves the rules in place |
| `-h`, `--help` | None | Show help |

Install the driver and media-initd. Replace `pi5` with `pi4` for Pi 4:

```bash
sudo ./scripts/install.sh -p pi5 -c all
```

Omit `-c all` if you do not need media-initd:

```bash
sudo ./scripts/install.sh -p pi5
```

Once `Done` appears, enable media-initd. Skip this step if you did not install media-initd.

```bash
# Choose "pi4" or "pi5" for your platform
sudo systemctl enable rk628-media-initd-pi5.service
```

### Overlay configuration

Open `/boot/firmware/config.txt`.
Change the default `camera_auto_detect=1` to:
```txt
camera_auto_detect=0
```

Edit the `[all]` section at the end of the file:

Pi 4 uses `rk628-pi4`, with a fixed 2-lane configuration:

| Optional parameter | Default | Description |
| --- | --- | --- |
| `audio` | Disabled | Enable HDMI audio output over I2S and the `RK628HDMI` ALSA capture device. I2S wiring is required. |


Pi 5 uses `rk628-pi5`, with a fixed 4-lane configuration:

| Optional parameter | Default | Description |
| --- | --- | --- |
| `audio` | Disabled | Enable HDMI audio output over I2S and the `RK628HDMI` ALSA capture device. I2S wiring is required. |
| `cam0` | Selected | Use CAM/DISP0 and select its corresponding I2C, CSI, and power controls. |
| `cam1` | Not selected | Use CAM/DISP1 and select its corresponding I2C, CSI, and power controls. |

Choose either `cam0` or `cam1`. If neither is specified, CAM/DISP0 is used.

Configuration examples (keep only the line matching your platform and wiring):

```txt
# Pi 4: video and audio
dtoverlay=rk628-pi4,audio

# Pi 5 CAM/DISP0: video and audio
dtoverlay=rk628-pi5,audio

# Pi 5 CAM/DISP1: video and audio
dtoverlay=rk628-pi5,cam1,audio
```

For video capture only, remove `,audio`.

Reboot:

```bash
sudo reboot
```

### Video capture configuration

After rebooting, udev creates device aliases for RK628, so the following commands do not need to be changed when device numbers change:

| Device path | Purpose |
| --- | --- |
| `/dev/rk628-video` | Video capture node |
| `/dev/rk628-media` | Media device for viewing and configuring the capture pipeline |
| `/dev/rk628-subdev` | RK628 subdevice, used to query HDMI input timings on Pi 5 |

View the corresponding symbolic links:

```bash
ls -l /dev/rk628-*
```

If you have configured [media-initd](#about-media-initd), you can skip manual configuration after the first boot. After changing the HDMI source or input resolution, or reconnecting HDMI, stop any running capture applications and restart media-initd to automatically configure capture for the current HDMI signal:

```bash
# Choose "pi4" or "pi5" for your platform
sudo systemctl restart rk628-media-initd-pi5.service
```

You can also configure capture manually using the commands below. The video resolution must match the result of `--query-dv-timings`.

Manually configure the video resolution and format:

Example commands for Pi 4:

```bash
# Query HDMI input timings
v4l2-ctl -d /dev/rk628-video --query-dv-timings
# Set the video resolution to match the HDMI input timings
v4l2-ctl -d /dev/rk628-video \
  --set-fmt-video=width=1920,height=1080,pixelformat=UYVY,field=none
```

Example commands for Pi 5 (the example uses `csi2` input pad `0` and output pad `4`, which connects to `rp1-cfe-csi2_ch0`; use the actual pad numbers if your topology differs):

```bash
# View the capture pipeline
media-ctl -d /dev/rk628-media -p
# Query HDMI input timings
v4l2-ctl -d /dev/rk628-subdev --query-dv-timings
# Set the video resolution to match the HDMI input timings
media-ctl -d /dev/rk628-media \
  -l '"csi2":4 -> "rp1-cfe-csi2_ch0":0 [1]'

media-ctl -d /dev/rk628-media \
  -V '"csi2":0 [fmt:UYVY8_1X16/3840x2160 field:none]'

media-ctl -d /dev/rk628-media \
  -V '"csi2":4 [fmt:UYVY8_1X16/3840x2160 field:none]'

v4l2-ctl -d /dev/rk628-video \
  --set-fmt-video=width=3840,height=2160,pixelformat=UYVY
```

## Verification

Check that media-initd is working. Skip this step if you have not installed media-initd.

```bash
# Choose "pi4" or "pi5" for your platform
systemctl status rk628-media-initd-pi5.service
```
When enabled and configured successfully, the output should look similar to this:

```bash
● rk628-media-initd-pi5.service - RK628 Pi 5 media initialization
     Loaded: loaded (/etc/systemd/system/rk628-media-initd-pi5.service; enabled; preset: enabled)
     Active: active (exited) since Wed 2026-11-18 20:17:05 CST; 1min 15s ago
 Invocation: 2c4a2f35c78644aaaa6a16d38b3e20eb
    Process: 768 ExecStart=/bin/sh /usr/local/libexec/rk628/media-initd-pi5.sh (code=exited, status=0/SUCCESS)
   Main PID: 768 (code=exited, status=0/SUCCESS)
        CPU: 358ms

Nov 18 20:17:05 pi5 systemd[1]: Started rk628-media-initd-pi5.service - RK628 Pi 5 media initialization.
Nov 18 20:17:05 pi5 sh[768]: Waiting for RK628 and a stable HDMI signal
Nov 18 20:17:14 pi5 sh[768]: Ready: /dev/rk628-video 1920x1080 UYVY
```

Check the video capture driver:

```bash
sudo dmesg | grep -i rk628
```

When the driver is loaded correctly, the output should look similar to this:

```bash
RK628 I2C driver version: 00.01.00
rk628 version is: RK628F/H (20230321)
rk628-csi-v4l2 found @ 0xa0 (rk3x-i2c)
rk628_csi_format_change: New format: 1920x1080p60.00 (2200x1125)
```

Capture 300 frames to `/dev/null` and check the frame rate and dropped-buffer messages.

```bash
v4l2-ctl -d /dev/rk628-video --get-fmt-video
v4l2-ctl -d /dev/rk628-video \
  --stream-mmap=4 --stream-count=300 --stream-to=/dev/null
echo $?
```

On successful completion, the exit code is 0 and 300 frames have been captured. The reported frame rate should be close to the HDMI input frame rate, with no `VIDIOC_STREAMON` errors or persistent `dropped buffers` messages. Press `Ctrl+C` to stop early.

Check the audio capture driver:

```bash
arecord -l
```

When the driver is loaded correctly, the output should look similar to this:

```bash
**** List of CAPTURE Hardware Devices ****
card 3: RK628HDMI [RK628HDMI], device 0: bcm2835-i2s-dir-hifi dir-hifi-0 [bcm2835-i2s-dir-hifi dir-hifi-0]
  Subdevices: 1/1
  Subdevice #0: subdevice #0
```

Test audio capture:

```bash
arecord -D hw:CARD=RK628HDMI,DEV=0 \
  -t raw -f S32_LE -r 48000 -c 2 -d 10 /dev/null

echo $?
```

The exit code is 0 on successful completion.

## Upgrade

Use the latest source, reinstall the same components you selected during the initial installation, and reboot. The example below installs media-initd on Pi 5 as well. If you do not use media-initd, omit `-c all` and the `systemctl enable` command. The updated DTBO takes effect after rebooting.

```bash
# Choose "pi4" or "pi5" for your platform
sudo ./scripts/install.sh -p pi5 -c all
sudo systemctl enable rk628-media-initd-pi5.service
sudo reboot
```

## Uninstall

Run the uninstall script:

```bash
# Choose "pi4" or "pi5" for your platform
sudo ./scripts/uninstall.sh -p pi5 -c all
```

Undo the changes to `/boot/firmware/config.txt`:

```txt
sudo vi /boot/firmware/config.txt
```

Remove the `dtoverlay=rk628-pi4` or `dtoverlay=rk628-pi5` line added during installation, including any parameters, and restore `camera_auto_detect` to its previous setting.

Reboot:

```bash
sudo reboot
```
