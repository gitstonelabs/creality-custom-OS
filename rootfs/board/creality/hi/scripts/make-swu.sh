#!/bin/sh
# make-swu.sh — Buildroot post-image hook (v2)
#
# Wraps the built rootfs.squashfs + zImage + dtb into an Android bootimg
# (via tools/mkbootimg_creality.py) and then into a swupdate .swu package
# (via tools/mkswu.sh) so the result drops directly onto the printer's
# A/B partitions through the stock /usr/bin/swupdate.
#
# v2 changes:
#   - Multi-UART kernel console (console=ttyS3,115200 console=ttyS4,115200
#     console=ttyS5,115200 console=ttyS0,115200) so boot output goes to ALL
#     candidate UARTs simultaneously, and ttyS0 ends up as the active console
#     (last-one-wins for getty).
#   - Output filename versioned: creality-hi-v2.swu
#   - SWU_VERSION bumped to 0.2-* to reflect the safety-feature line.
#   - Uses the kernel-and-rootfs-watchdog mode of mkswu.sh which injects
#     bootcount/bootlimit/altbootcmd env vars for U-Boot auto-rollback.
#
# Buildroot exports:
#   $BINARIES_DIR    — output/images/  (where rootfs.squashfs lives)
#   $TARGET_DIR
#   $HOST_DIR
#   $BR2_EXTERNAL_GITSTONELABS_PATH
#
# Output:
#   $BINARIES_DIR/creality-hi-v2.swu  — the final swupdate package

set -eu

EXT="$BR2_EXTERNAL_GITSTONELABS_PATH"
WORKSPACE="$(cd "$EXT/.." && pwd)"
MKBOOTIMG="$WORKSPACE/tools/mkbootimg_creality.py"
MKSWU="$WORKSPACE/tools/mkswu.sh"

# Kernel cmdline: replicate printk to all 4 candidate UARTs.
# Order matters — kernel uses the LAST console= as the primary tty (the one
# init/systemd attaches its stdio to). We want ttyS0 (J65 debug header) to be
# primary, so it goes last. The other three are echo-only and harmless even
# if nothing is wired to them.
KERNEL_CMDLINE="console=ttyS3,115200 console=ttyS4,115200 console=ttyS5,115200 console=ttyS0,115200 loglevel=7 earlyprintk"

# Version string for the .swu — exported so mkswu picks it up via its
# SWU_VERSION env var. Major.minor + UTC timestamp.
export SWU_VERSION="${SWU_VERSION:-0.2-gitstonelabs-$(date -u +%Y%m%d-%H%M%S)}"

echo "[gitstonelabs] post-image: binaries=$BINARIES_DIR"
echo "[gitstonelabs] SWU_VERSION=$SWU_VERSION"

if [ ! -f "$BINARIES_DIR/rootfs.squashfs" ]; then
    echo "[gitstonelabs] WARNING: rootfs.squashfs not found, skipping .swu build"
    exit 0
fi

if [ ! -f "$BINARIES_DIR/zImage" ] || [ ! -f "$BINARIES_DIR/sun8i-t113s-creality-hi.dtb" ]; then
    echo "[gitstonelabs] WARNING: kernel zImage or DTB missing, skipping bootimg pack"
    exit 0
fi

if [ ! -x "$MKBOOTIMG" ] || [ ! -x "$MKSWU" ]; then
    echo "[gitstonelabs] WARNING: $MKBOOTIMG / $MKSWU missing or not executable, skipping"
    exit 0
fi

# Pack the bootimg (zImage + appended DTB → Android bootimg v2) with
# multi-UART console in the cmdline. The cmdline gets merged with U-Boot's
# own bootargs (which holds root=/dev/${root_partition} etc) — our cmdline
# is appended, so root= still wins from U-Boot, but the console= overrides
# stock single-UART config.
echo "[gitstonelabs] packing bootimg with cmdline: $KERNEL_CMDLINE"
"$MKBOOTIMG" \
    --kernel "$BINARIES_DIR/zImage" \
    --dtb "$BINARIES_DIR/sun8i-t113s-creality-hi.dtb" \
    --cmdline "$KERNEL_CMDLINE" \
    --output "$BINARIES_DIR/boot.img"

# Wrap bootimg + rootfs into a .swu using the watchdog-enabled mode so the
# install sets bootcount/bootlimit/altbootcmd env vars at the same time. The
# rootfs's gitstonelabs-bootcount-reset.service then resets bootcount=0 on
# every healthy boot, completing the auto-rollback loop.
echo "[gitstonelabs] building swupdate package (kernel-and-rootfs-watchdog)..."
"$MKSWU" kernel-and-rootfs-watchdog \
    "$BINARIES_DIR/boot.img" \
    "$BINARIES_DIR/rootfs.squashfs" \
    "$BINARIES_DIR/creality-hi-v2.swu"

# Also build a no-env-flip variant for kernel-only smoke-test installs (writes
# bootB only, does NOT flip boot_partition). Useful when the user wants to
# probe the new kernel via U-Boot console "sunxi_flash read … bootm …" without
# committing to a reboot path change.
echo "[gitstonelabs] building kernel-only smoke-test .swu..."
"$MKSWU" kernel-only-B \
    "$BINARIES_DIR/boot.img" \
    "$BINARIES_DIR/creality-hi-v2-kernel-only.swu"

echo "[gitstonelabs] post-image done:"
echo "    full:        $BINARIES_DIR/creality-hi-v2.swu"
echo "    kernel-only: $BINARIES_DIR/creality-hi-v2-kernel-only.swu"
