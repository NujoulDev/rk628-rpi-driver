# RK628 kernel driver for Raspberry Pi4/5

[![Debian 13 (trixie)](https://img.shields.io/badge/Debian-13_%28trixie%29-blue?logo=debian)](https://www.debian.org/)
[![Tested kernel 6.18](https://img.shields.io/badge/tested_kernel-6.18-blue?logo=raspberrypi)](https://github.com/raspberrypi/linux/tree/rpi-6.18.y)

该项目为 `瑞莎 4K HDMI IN 转 MIPI CSI-2 转接板` 在 Raspberry Pi4/5 上的驱动程序，支持音频、视频采集。

## 已测试环境

| 平台 | 系统 | 架构 | 内核 |
| --- | --- | --- | --- |
| Raspberry Pi 4 | Debian GNU/Linux 13.7 (trixie) | `aarch64` | `6.18.60+rpt-rpi-v8` |
| Raspberry Pi 5 | Debian GNU/Linux 13.7 (trixie) | `aarch64` | `6.18.50+rpt-rpi-2712` |

驱动需使用与当前运行内核匹配的头文件构建。其他系统及内核版本尚未验证。

## 关键参数
- 转接板提供 2-lane 和 4-lane 两种 MIPI CSI-2 接口，目前在 Pi5上仅支持 4-lane 接口，Pi4 上仅支持 2-lane 接口。

- 视频输入：HDMI输入最高支持 4K（3840×2160）30fps。

- 视频输出：4-lane 接口在 Pi5 上的最大分辨率为 4K（3840×2160）30fps，2-lane 接口在 Pi4 上的最大分辨率为 2K（2560×1440）30fps。

## Systemd service 介绍
- 树莓派官方支持的摄像头通过 `libcamera` 和 `rpicam-apps` 进行 pipeline 的自动配置，本项目使用自己的 Systemd 服务来实现类似的功能，避免每次开机后都需要手动配置。
- 服务启动后等待第一个稳定的 HDMI 信号，配置成功后退出。
- 后续如果 HDMI 输入时序发生变化需要手动执行 `v4l2-ctl` 和 `media-ctl` 命令或者由用户自己的应用程序调用 `v4l2` 接口才能采集视频，参考指令如下：

Pi4 上的参考命令：

```bash
# 查询 HDMI 输入时序
v4l2-ctl -d /dev/video0 --query-dv-timings
# 根据 HDMI 输入时序设置视频分辨率
v4l2-ctl -d /dev/video0 \
  --set-fmt-video=width=1920,height=1080,pixelformat=UYVY,field=none
```

Pi5 上的参考命令：

```bash
MEDIA=
for dev in /dev/media*; do
  if media-ctl -d "$dev" -p 2>/dev/null | grep -q rk628-csi; then
    MEDIA="$dev"
    break
  fi
done
# m00_b_rk628-csi 后的为 rk628 视频输出节点
media-ctl -d "$MEDIA" -p
# 查询 HDMI 输入时序，/dev/v4l-subdev2使用前面查询到的 rk628 视频输出节点
v4l2-ctl -d /dev/v4l-subdev2 --query-dv-timings
# 根据 HDMI 输入时序设置视频分辨率


media-ctl -d "$MEDIA" \
  -l '"csi2":4 -> "rp1-cfe-csi2_ch0":0 [1]'

media-ctl -d "$MEDIA" \
  -V '"csi2":0 [fmt:UYVY8_1X16/3840x2160 field:none]'

media-ctl -d "$MEDIA" \
  -V '"csi2":4 [fmt:UYVY8_1X16/3840x2160 field:none]'

v4l2-ctl -d /dev/video0 \
  --set-fmt-video=width=3840,height=2160,pixelformat=UYVY
```

## 硬件连接

### 所需配件

- 瑞莎 4K HDMI IN 转 MIPI CSI-2 转接板
- Pi4 或 Pi5
- 6根母对母杜邦线
- Pi4 需要 `15P-to-15P 排线` 
- Pi5 需要 `31P-to-31P 排线` 和 `22P-to-22P 排线`，以及 `22P-to-31P 转接板`

### HDMI

接入 HDMI 信号源，支持 4K（3840×2160）30fps。

### MIPI CSI

使用 Pi4 时，使用 `15pin to 15pin` 排线将转接板的 MIPI CSI 2lane 接口连接到 Pi4 的 `CAMERA` 接口上。

使用 Pi5 时，使用 `31pin to 31pin` 排线将转接板的 MIPI CSI 4lane 接口连接 `22P-to-31P 转接板` 的31Pin接口 ，再使用 `22P-to-22P` 将 `22P-to-31P 转接板` 的22Pin接口连接到 Pi5 的 `CAM/DISP0` 或 `CAM/DISP1` 接口上。 

### I2S

| 转接板7pin排针 | Pi 4/5 接点 |
| :---: | :---: |
| I2S D0 | GPIO20，物理脚 **38** |
| I2S LRCK | GPIO19，物理脚 **35** |
| I2S SCLK | GPIO18，物理脚 **12** |
| GND | 树莓派上任意GND引脚 |

### DET、INT

|  转接板7pin排针 | Pi 4/5 接点 |
| :---: | :---: |
| DET | GPIO24，物理脚 **18** |
| INT | GPIO23，物理脚 **16** |

## 安装

本项目可通过源码内置的安装脚本一键安装所有产物，其中包括编译后的驱动模块、设备树覆盖文件、dkms配置和 Systemd service 配置。其中 System service 可选。

安装必要依赖

```bash
sudo apt update
sudo apt install -y \
  build-essential dkms device-tree-compiler \
  "linux-headers-$(uname -r)" \
  v4l-utils alsa-utils
```

检查当前内核版本，以及匹配的头文件构建目录是否存在

```bash
uname -r
ls "/lib/modules/$(uname -r)/build/Makefile"
```

下拉源码

```bash
git clone 
cd rk628-rpi-driver
```

脚本参数表：

以下参数适用于 `scripts/install.sh` 和 `scripts/uninstall.sh`。

| 参数 | 可选值 | 说明 |
| --- | --- | --- |
| `-p` | `pi4`、`pi5` | 必填，选择平台 |
| `-c` | `service`、`all` | 可选，`service` 仅处理 Systemd service；`all` 处理全部；省略时仅处理驱动 |
| `-h`、`--help` | 无 | 显示帮助 |

运行驱动安装脚本

```bash
sudo ./scripts/install.sh -p pi5 -c all
```

看到 “Done” 后，启用 Systemd service，没有安装 Systemd service 的用户可以跳过此步骤。

```bash
# 根据平台选择 “pi4” 或 “pi5”
sudo systemctl enable --now rk628-media-init-pi5.service
```

## dtoverlay options

打开 `/boot/firmware/config.txt` 文件
将默认的 `camera_auto_detect=1` 改为：
```txt
camera_auto_detect=0
```

修改文件末尾的 `[all]` 节点：

Pi 4 使用 `rk628-pi4`，固定 2-lane：

| 可选参数 | 默认状态 | 说明 |
| --- | --- | --- |
| `audio` | 关闭 | 启用 HDMI 音频的 I2S 输出和 ALSA 采集声卡 `RK628HDMI`，需连接 I2S 信号线。 |


Pi 5 使用 `rk628-pi5`，固定 4-lane：

| 可选参数 | 默认状态 | 说明 |
| --- | --- | --- |
| `audio` | 关闭 | 启用 HDMI 音频的 I2S 输出和 ALSA 采集声卡 `RK628HDMI`，需连接 I2S 信号线。 |
| `cam0` | 默认选择 | 使用 CAM/DISP0，同时选择对应的 I2C、CSI 和供电控制。 |
| `cam1` | 未选择 | 使用 CAM/DISP1，同时选择对应的 I2C、CSI 和供电控制。 |

`cam0`、`cam1` 二选一，省略时使用 CAM/DISP0。Pi 5 不提供 lane 数选择参数。

配置示例（只保留与平台和接线对应的一行）：

```txt
# Pi 4：视频和音频
dtoverlay=rk628-pi4,audio

# Pi 5 CAM/DISP0：视频和音频
dtoverlay=rk628-pi5,audio

# Pi 5 CAM/DISP1：视频和音频
dtoverlay=rk628-pi5,cam1,audio
```

仅采集视频时去掉 `,audio`。

重启

```bash
sudo reboot
```

手动配置视频分辨率和格式：

配置好 Systemd service 的用户可以跳过该步骤
但是后续 HDMI 输入时序发生变化时仍然需要手动或者自己的程序进行配置，一定要根据 `--query-dv-timings` 的结果来设置视频分辨率，否则可能无法采集到视频，具体参考上文的 `v4l2-ctl` 和 `media-ctl` 命令。

## 验证

验证服务是否正常运行，未部署服务的用户可以跳过此步骤。

```bash
# 根据平台选择 “pi4” 或 “pi5”
systemctl status rk628-media-init-pi5.service
```
正确启用会有以下类似输出：

```bash
● rk628-media-init-pi4.service - RK628 Pi 4 media initialization
     Loaded: loaded (/etc/systemd/system/rk628-media-init-pi4.service; enabled; preset: enabled)
     Active: active (exited) since Thu 2026-11-12 17:34:49 CST; 22s ago
 Invocation: de04fe43c43f4113901ac69046fee0ab
    Process: 1987 ExecStart=/bin/sh /usr/local/libexec/rk628/media-pi4.sh (code=exited, status=0/SUCCESS)
   Main PID: 1987 (code=exited, status=0/SUCCESS)
        CPU: 272ms

Nov 12 17:34:49 pi4 systemd[1]: Started rk628-media-init-pi4.service - RK628 Pi 4 media initialization.
Nov 12 17:34:49 pi4 sh[1987]: Waiting for RK628 and a stable HDMI signal
Nov 12 17:34:52 pi4 sh[1987]: Ready: /dev/video0 1920x1080 UYVY  
```

验证视频采集驱动

```bash
sudo dmesg | grep -i rk628
```

正确加载驱动会有以下类似输出：

```bash
RK628 I2C driver version: 00.01.00
rk628 version is: RK628F/H (20230321)
rk628-csi-v4l2 found @ 0xa0 (rk3x-i2c)
rk628_csi_format_change: New format: 1920x1080p60.00 (2200x1125)
```

实际采集 300 帧到 `/dev/null`，查看帧率和丢帧提示，设备节点按实际情况替换。

```bash
v4l2-ctl -d /dev/video0 --get-fmt-video
v4l2-ctl -d /dev/video0 \
  --stream-mmap=4 --stream-count=300 --stream-to=/dev/null
echo $?
```

正常完成时退出码为 `0`，打印的帧率应接近 HDMI 输入帧率，且没有持续的 `dropped buffers` 提示。需要提前停止时按 `Ctrl+C`。

验证音频采集驱动

```bash
arecord -l
```

正确加载驱动会有以下类似输出：

```bash
**** List of CAPTURE Hardware Devices ****
card 3: RK628HDMI [RK628HDMI], device 0: bcm2835-i2s-dir-hifi dir-hifi-0 [bcm2835-i2s-dir-hifi dir-hifi-0]
  Subdevices: 1/1
  Subdevice #0: subdevice #0
```

测试音频采集

```bash
arecord -D hw:CARD=RK628HDMI,DEV=0 \
  -t raw -f S32_LE -r 48000 -c 2 -d 10 /dev/null

echo $?
```

正常完成时退出码为 0

## 升级

使用最新的代码，然后运行安装脚本并且重启即可。

```bash
# 根据平台选择 “pi4” 或 “pi5”
sudo ./scripts/install.sh -p pi5 -c all
sudo systemctl enable --now rk628-media-init-pi5.service
sudo reboot
```

## 卸载

运行卸载脚本

```bash
# 根据平台选择 “pi4” 或 “pi5”
sudo ./scripts/uninstall.sh -p pi5 -c all
```

删除对 `/boot/firmware/config.txt` 的修改

```txt
sudo vi /boot/firmware/config.txt
```

把 `dtoverlay=rk628-pi5,audio` 删除掉，恢复 `camera_auto_detect=1`

重启

```bash
sudo reboot
```
