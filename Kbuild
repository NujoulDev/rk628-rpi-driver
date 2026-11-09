# SPDX-License-Identifier: GPL-2.0
# Module composition for the out-of-tree RK628 driver.

ccflags-y += -I$(src)/include
obj-m += video-rk628.o rk628-csi.o rk628-hdmirx-class.o
video-rk628-objs := rk628.o rk628_cru.o rk628_hdmirx.o rk628_dsi.o \
		rk628_combrxphy.o rk628_combtxphy.o rk628_mipi_dphy.o \
		rk628_post_process.o
rk628-csi-objs := rk628_csi_v4l2.o
rk628-hdmirx-class-objs := rk628_hdmirx_class.o
