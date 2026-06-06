# Notices and attribution

This repo mixes original work, kernel derivatives, and vendor source under different licenses. Per-component terms are below.

## gitStoneLabs original work: GPL-3.0-or-later

The build scripts, packaging tools, Buildroot external tree, board overlays, and documentation authored by gitStoneLabs are licensed GPL-3.0-or-later. This covers `tools/`, `rootfs/scripts/`, `rootfs/board/`, the Buildroot `.mk` recipes and `Config.in` files, and the docs.

## Kernel defconfig, device tree, and driver ports: GPL-2.0

`kernel/defconfigs/creality_sunxi_defconfig`, `kernel/dts/sun8i-t113s-creality-hi.dts`, and the pinctrl and CCU driver ports are derivative works of the Linux kernel and inherit its GPL-2.0 license. They derive from the sun8iw20p1 vendor BSP and mainline Linux 6.6.

## creality-cfs-klipper and the .so replacements: clean-room GPL-3.0

The bundled `creality-cfs-klipper` module and the gitStoneLabs replacements for Creality's proprietary `.so` files are clean-room implementations licensed GPL-3.0. They were written from observed behavior and the device's own Python sources, not by decompiling the proprietary binaries.

## AIC8800 driver: GPL vendor source, kept as-is

`rootfs/package/aic8800-driver/` is GPL vendor source from the Yuzuki BSP collection, kept unmodified. It is declared `GPL-2.0` in its `.mk`. It does not build against kernel 6.6 (see [KNOWN-GAPS.md](KNOWN-GAPS.md)). It is retained for a future port, not because it works today.

## AIC8800 firmware blobs: intentionally excluded

The AIC8800 firmware blobs are not included in this repo. Their redistribution terms are murky, and they are non-functional on 6.6 anyway because the driver does not build. They were excluded on purpose, not omitted by accident.
