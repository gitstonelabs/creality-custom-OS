# creality-custom-OS

![status](https://img.shields.io/badge/status-WIP%3A%20builds%20clean%2C%20boot%20UNVERIFIED-red)

A custom mainline-Linux-6.6 operating system for the Creality Hi 3D printer (Allwinner T113-S3, sun8iw20p1). It pairs a ported Linux 6.6 kernel with a Buildroot rootfs that ships Klipper, Moonraker, and Fluidd, then packages the result as an Android bootimg v2 inside a swupdate `.swu` for installation onto the printer's A/B partitions. The intent is to replace Creality's stripped OpenWrt 21.02 fork and its proprietary Klipper `.so` modules with GPL sources. This is a gitStoneLabs GPL-3.0 effort and a work in progress.

## STATUS: builds clean, boot UNVERIFIED

This repo builds end-to-end and the build is reproducible on the maintainer's machines, but the resulting OS has never been confirmed to boot on hardware. Boot proof-of-life is NONE.

The only live flash, on 2026-05-26, reported swupdate success and flipped the env to `bootB`/`rootfsB`, then the board lost all communication with zero captured console output. The board was recovered to stock via FEL on 2026-05-31. There is no working debug console, so the failure mode is unknown: the custom kernel may have panicked, may have booted with no reachable network, or may never have started.

Do not flash this expecting a working printer. Treat every artifact as untested. Read [KNOWN-GAPS.md](KNOWN-GAPS.md) before doing anything with this code.

## Build pipeline

Three stages produce the `.swu`. Full source trees (linux-6.6, the T113 vendor BSP, and the Yuzuki Buildroot checkout) are per-machine and not stored in this repo, so the build is not yet reproducible from this repo alone. See [KNOWN-GAPS.md](KNOWN-GAPS.md).

### Stage 1: kernel

Linux 6.6 with the Hi device tree (`kernel/dts/sun8i-t113s-creality-hi.dts`) and a Buildroot-side defconfig (`kernel/defconfigs/creality_sunxi_defconfig`). The pinctrl driver and three CCUs are ported from the sun8iw20p1 vendor BSP into the 6.6 tree. Output: `zImage` plus the compiled `.dtb`. See [kernel/README.md](kernel/README.md).

### Stage 2: Android bootimg v2

`tools/mkbootimg_creality.py` wraps the `zImage` with the DTB appended (Creality-style, not in the v2 dtb-section field) into an Android bootimg v2 with a `page_size` of 2048. The kernel command line is injected here, including the multi-UART `console=` list. Output: `boot.img`, written to the `bootB` partition.

### Stage 3: Buildroot rootfs + swupdate .swu

The `rootfs/` directory is a `BR2_EXTERNAL` tree layered on the Yuzuki Buildroot 2022.02.2 checkout. It builds a squashfs rootfs with systemd, dropbear, nginx, Klipper, Moonraker, Fluidd, and the gitStoneLabs CFS Klipper module. The post-image hook `rootfs/board/creality/hi/scripts/make-swu.sh` calls `tools/mkbootimg_creality.py`, then `tools/mkswu.sh` to emit `creality-hi-v2.swu` (kernel + rootfs + watchdog env) and `creality-hi-v2-kernel-only.swu` (kernel only, no env change). See [rootfs/README.md](rootfs/README.md).

## Recovery backstop: MANDATORY before any flash

Stock U-Boot on the Hi has NO automatic A/B rollback. This was verified on a fresh board: `fw_printenv` shows no `bootcount`, no `bootlimit`, and no `altbootcmd`. The v2 `.swu` writes those env vars, but if vendor U-Boot does not honor `CONFIG_BOOTCOUNT_LIMIT`, they are inert and no rollback happens. The v2 watchdog has never been hardware-tested.

Consequences:

- Committing `boot_partition=bootB` is a one-way trip. If the custom kernel does not reach a state where you can run `fw_setenv boot_partition bootA`, there is no software path back.
- FEL (the BootROM USB recovery mode) is the only safety net. Trigger it by holding the LOAD button at power-on. The full recovery procedure (RTC boot-mode flag, vendor fastboot, env flash) is in the companion recovery repo.
- Companion repo: [creality-hi-recovery](https://github.com/gitstonelabs/creality-hi-recovery). Have it set up and tested on your unit BEFORE you flash anything from here.

Prefer the kernel-only-B flash mode. It writes the inactive `bootB` partition and does not change the boot env, so a power-cycle returns to stock. Use it to probe the custom kernel before you ever flip `boot_partition`.

## Security

The Buildroot config ships a weak default root password: `rootfs/configs/creality_hi_defconfig` sets `BR2_TARGET_GENERIC_ROOT_PASSWD="root"`. Nothing is forced on first boot, so change it yourself. Log in with `ssh root@<printer-ip>` (password `root`) or on the serial console, then:

```sh
passwd                 # change the root password
adduser myname         # create your own login (prompts for its password)
passwd myname          # change a password later
su -                   # become root from your account (this image has no sudo)
```

This image uses BusyBox, so user management is `adduser`/`deluser`/`passwd`, not `useradd`/`usermod`, and there is no `sudo`. Full setup, including SSH key login, renaming a user, and disabling remote root login over SSH, is in [SECURITY.md](SECURITY.md).

The bundled `printer.cfg` is a placeholder with `kinematics: none` and the `[mcu]` section commented out, so it drives no hardware.

## License

gitStoneLabs original work is GPL-3.0-or-later. The kernel defconfig, device tree, and driver ports are GPL-2.0 derivatives of the Linux kernel. The bundled `creality-cfs-klipper` and the proprietary `.so` replacements are clean-room GPL-3.0. The AIC8800 driver under `rootfs/package/aic8800-driver` is GPL vendor source kept as-is. Full attribution and per-component licensing is in [NOTICES.md](NOTICES.md). Known limitations are in [KNOWN-GAPS.md](KNOWN-GAPS.md).
