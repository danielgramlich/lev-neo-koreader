# ELAN touchscreen driver for the Lev Neo (Allwinner A13, Linux 3.0.8)

The Lev Neo's touch controller is an **ELAN eKTF2xxx on I2C bus 2, address 0x15**
(not the Cypress cyttsp4 the reinstalled rootfs expected). The rootfs had no
`elan_touch.ko`, so this driver was written from scratch.

- Reports multitouch protocol "A" events (`ABS_MT_POSITION_X/Y`, `ABS_MT_TRACKING_ID`,
  `ABS_MT_TOUCH_MAJOR`, `SYN_MT_REPORT`), input device name `elan_ts_d`.
- Orientation follows `ctp_exchange_x_y_flag` / `ctp_revert_x_flag` / `ctp_revert_y_flag`
  and `ctp_screen_max_x/y` from the board's `script.bin` (`[ctp_para]`).
- Runtime parameters in `/sys/module/elan_touch/parameters/`: `debug`, `swap`,
  `invx`, `invy`, `xmax`, `ymax`, `rawx`, `rawy`, `rxmin`, `rymin`, `pkt`, `poll`.

## Build

The module must match the device kernel exactly (vermagic and symbol CRCs):

1. Kernel source: the GPL release `github.com/BOOKEEN/kernel-linux-3.0`, configured
   with `a13_defconfig` (that config reproduces the CRCs of the stock kernel,
   e.g. `module_layout`).
2. Toolchain: an old GCC is required. A Docker image based on Ubuntu 14.04 (amd64)
   with `gcc-4.7-arm-linux-gnueabi` works:

```sh
# inside the container, with the kernel tree in /w/linux and an out-of-tree build dir /w/o
make -C /w/linux O=/w/o ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- a13_defconfig
make -C /w/linux O=/w/o ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- modules_prepare
make -C /w/linux O=/w/o ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- M=$PWD modules
```

## Install

Copy `elan_touch.ko` to `/lib/modules/3.0.8+/` on the device's root filesystem and load
it at boot (for example from the init script that loads the other modules):

```sh
insmod /lib/modules/3.0.8+/elan_touch.ko
```

If the touchscreen ever stops responding, reloading the module and restarting
KOReader brings it back:

```sh
rmmod elan_touch && insmod /lib/modules/3.0.8+/elan_touch.ko
```
