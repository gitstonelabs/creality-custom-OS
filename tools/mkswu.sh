#!/usr/bin/env bash
# mkswu.sh — build a Creality-compatible .swu package for the Creality Hi
#
# Generates a cpio (SVR4 with CRC) archive containing:
#   sw-description    libconfig describing what to install where
#   kernel            an Android bootimg v2 (written to bootB partition)
#   (optionally) rootfs    a squashfs image (written to rootfsB)
#
# The resulting .swu is consumed by the printer's stock swupdate v2019.11.0
# via:    swupdate -i pkg.swu -e stable,now_A_next_B
#
# Modes (called "stable.<mode>" in the sw-description):
#   now_A_next_B    — currently running on slot A, write to slot B
#   now_B_next_A    — currently running on slot B, write to slot A
#   kernel_only_B   — just write a new kernel to bootB without changing boot_partition env
#                     (RECOMMENDED for first-test of a new kernel — no commitment)
#
# Usage:
#   ./mkswu.sh kernel /path/to/bootimg.img out/custom.swu
#   ./mkswu.sh kernel-and-rootfs bootimg.img rootfs.squashfs out/full.swu
#   ./mkswu.sh kernel-only-B bootimg.img out/test.swu       # NO boot env change
#
# Safety:
#   - "kernel-only-B" mode writes to inactive partition AND does NOT change
#     boot_partition env. The printer continues booting stock on next reboot
#     until you manually `fw_setenv boot_partition bootB` to commit.
#   - The "now_A_next_B" / "now_B_next_A" modes DO change boot_partition.
#     Use only when confident the new bootimg works.
#
# License: GPL-3.0
# Author: gitstonelabs

set -euo pipefail

MODE="${1:-}"
VERSION="${SWU_VERSION:-0.1-gitstonelabs-$(date +%Y%m%d-%H%M%S)}"

usage() {
    cat <<USAGE
Usage:
    $0 kernel-only-B  <bootimg.img>   <output.swu>      # write bootB only, no env change (SAFEST)
    $0 kernel         <bootimg.img>   <output.swu>      # write bootB + set boot_partition=bootB
    $0 kernel-and-rootfs <bootimg.img> <rootfs.squashfs> <output.swu>  # write both + flip env
    $0 kernel-and-rootfs-watchdog <bootimg.img> <rootfs.squashfs> <output.swu>
                                                        # write both + flip env + set up auto-rollback
                                                        # (v2 default, see notes below)

Watchdog mode (v2):
    Sets these U-Boot env vars at install time so a failed boot rolls back
    automatically:
        bootcount   = 0           # incremented every boot, reset by userspace on success
        bootlimit   = 3           # max consecutive failures before flipping
        altbootcmd  = swap A/B    # what U-Boot runs when bootcount > bootlimit
    The rootfs ships gitstonelabs-bootcount-reset.service which writes
    bootcount=0 via fw_setenv after multi-user.target is reached.

    Risk: if Creality's vendor U-Boot 2018.07 has stripped CONFIG_BOOTCOUNT_LIMIT,
    the env vars are inert (no rollback). The .swu still installs cleanly and
    behaves identically to kernel-and-rootfs; the watchdog is best-effort.

Environment:
    SWU_VERSION       version string to embed (default: timestamp-based)

After building, deploy to the printer:
    scp output.swu hi:/mnt/UDISK/
    ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/output.swu -e stable,<mode> -l 4'
        (where <mode> is one of: kernel_only_B, now_A_next_B, now_B_next_A)

To inspect a .swu without installing:
    cpio -t < output.swu
    cpio -i sw-description < output.swu && cat sw-description
USAGE
    exit 1
}

[ "$MODE" = "" ] && usage

# Make a temp workdir
WORK="$(mktemp -d)"
trap "rm -rf $WORK" EXIT

case "$MODE" in
    kernel-only-B)
        [ $# -ne 3 ] && usage
        BOOTIMG="$2"
        OUT="$3"
        [ ! -f "$BOOTIMG" ] && { echo "missing bootimg: $BOOTIMG" >&2; exit 1; }
        cp "$BOOTIMG" "$WORK/kernel"
        cat > "$WORK/sw-description" <<EOF
software = {
    version = "$VERSION";
    description = "gitStoneLabs custom kernel — write to bootB ONLY (no boot env change)";
    stable = {
        kernel_only_B = {
            images: (
                {
                    filename = "kernel";
                    device = "/dev/by-name/bootB";
                    installed-directly = true;
                },
            );
        };
    };
}
EOF
        ;;

    kernel)
        [ $# -ne 3 ] && usage
        BOOTIMG="$2"
        OUT="$3"
        [ ! -f "$BOOTIMG" ] && { echo "missing bootimg: $BOOTIMG" >&2; exit 1; }
        cp "$BOOTIMG" "$WORK/kernel"
        cat > "$WORK/sw-description" <<EOF
software = {
    version = "$VERSION";
    description = "gitStoneLabs custom kernel — write bootB + activate";
    stable = {
        now_A_next_B = {
            images: (
                {
                    filename = "kernel";
                    device = "/dev/by-name/bootB";
                    installed-directly = true;
                },
            );
            bootenv: (
                { name = "boot_partition"; value = "bootB"; },
                { name = "swu_next";       value = "reboot"; },
                { name = "version";        value = "$VERSION"; }
            );
        };
        now_B_next_A = {
            images: (
                {
                    filename = "kernel";
                    device = "/dev/by-name/bootA";
                    installed-directly = true;
                },
            );
            bootenv: (
                { name = "boot_partition"; value = "bootA"; },
                { name = "swu_next";       value = "reboot"; },
                { name = "version";        value = "$VERSION"; }
            );
        };
    };
}
EOF
        ;;

    kernel-and-rootfs)
        [ $# -ne 4 ] && usage
        BOOTIMG="$2"
        ROOTFS="$3"
        OUT="$4"
        [ ! -f "$BOOTIMG" ] && { echo "missing bootimg: $BOOTIMG" >&2; exit 1; }
        [ ! -f "$ROOTFS" ]  && { echo "missing rootfs: $ROOTFS" >&2; exit 1; }
        cp "$BOOTIMG" "$WORK/kernel"
        cp "$ROOTFS" "$WORK/rootfs"
        cat > "$WORK/sw-description" <<EOF
software = {
    version = "$VERSION";
    description = "gitStoneLabs full A/B update — kernel + rootfs";
    stable = {
        now_A_next_B = {
            images: (
                {
                    filename = "kernel";
                    device = "/dev/by-name/bootB";
                    installed-directly = true;
                },
                {
                    filename = "rootfs";
                    device = "/dev/by-name/rootfsB";
                    installed-directly = true;
                },
            );
            bootenv: (
                { name = "boot_partition"; value = "bootB"; },
                { name = "root_partition"; value = "rootfsB"; },
                { name = "swu_next";       value = "reboot"; },
                { name = "version";        value = "$VERSION"; }
            );
        };
        now_B_next_A = {
            images: (
                {
                    filename = "kernel";
                    device = "/dev/by-name/bootA";
                    installed-directly = true;
                },
                {
                    filename = "rootfs";
                    device = "/dev/by-name/rootfsA";
                    installed-directly = true;
                },
            );
            bootenv: (
                { name = "boot_partition"; value = "bootA"; },
                { name = "root_partition"; value = "rootfsA"; },
                { name = "swu_next";       value = "reboot"; },
                { name = "version";        value = "$VERSION"; }
            );
        };
    };
}
EOF
        ;;

    kernel-and-rootfs-watchdog)
        # v2 mode: same as kernel-and-rootfs PLUS bootcount/bootlimit/altbootcmd
        # set up for U-Boot auto-rollback. The rootfs's
        # gitstonelabs-bootcount-reset.service zeroes bootcount once
        # multi-user.target is reached; if userspace never gets there N times
        # in a row (default N=3), U-Boot runs altbootcmd which flips back to
        # the previous slot's env and reboots into stock.
        #
        # If Creality's U-Boot doesn't honor bootcount, these env vars are
        # inert — the install still succeeds and behaves identically to the
        # non-watchdog mode, just without the safety net.
        [ $# -ne 4 ] && usage
        BOOTIMG="$2"
        ROOTFS="$3"
        OUT="$4"
        [ ! -f "$BOOTIMG" ] && { echo "missing bootimg: $BOOTIMG" >&2; exit 1; }
        [ ! -f "$ROOTFS" ]  && { echo "missing rootfs: $ROOTFS" >&2; exit 1; }
        cp "$BOOTIMG" "$WORK/kernel"
        cp "$ROOTFS" "$WORK/rootfs"
        # altbootcmd intentionally hard-coded to the symmetric flip: if we're
        # currently set to bootB/rootfsB and bootcount tripped, flip back to
        # bootA/rootfsA. We don't try to chain further fallbacks — stock is
        # the only known-good baseline.
        cat > "$WORK/sw-description" <<EOF
software = {
    version = "$VERSION";
    description = "gitStoneLabs v2 A/B update — kernel + rootfs + U-Boot watchdog rollback";
    stable = {
        now_A_next_B = {
            images: (
                {
                    filename = "kernel";
                    device = "/dev/by-name/bootB";
                    installed-directly = true;
                },
                {
                    filename = "rootfs";
                    device = "/dev/by-name/rootfsB";
                    installed-directly = true;
                },
            );
            bootenv: (
                { name = "boot_partition"; value = "bootB"; },
                { name = "root_partition"; value = "rootfsB"; },
                { name = "bootcount";      value = "0"; },
                { name = "bootlimit";      value = "3"; },
                { name = "altbootcmd";     value = "setenv boot_partition bootA; setenv root_partition rootfsA; setenv bootcount 0; saveenv; run setargs_nand boot_normal"; },
                { name = "upgrade_available"; value = "1"; },
                { name = "swu_next";       value = "reboot"; },
                { name = "version";        value = "$VERSION"; }
            );
        };
        now_B_next_A = {
            images: (
                {
                    filename = "kernel";
                    device = "/dev/by-name/bootA";
                    installed-directly = true;
                },
                {
                    filename = "rootfs";
                    device = "/dev/by-name/rootfsA";
                    installed-directly = true;
                },
            );
            bootenv: (
                { name = "boot_partition"; value = "bootA"; },
                { name = "root_partition"; value = "rootfsA"; },
                { name = "bootcount";      value = "0"; },
                { name = "bootlimit";      value = "3"; },
                { name = "altbootcmd";     value = "setenv boot_partition bootB; setenv root_partition rootfsB; setenv bootcount 0; saveenv; run setargs_nand boot_normal"; },
                { name = "upgrade_available"; value = "1"; },
                { name = "swu_next";       value = "reboot"; },
                { name = "version";        value = "$VERSION"; }
            );
        };
    };
}
EOF
        ;;

    *) usage ;;
esac

# Resolve OUT to an absolute path NOW, while we're still in the caller's CWD
OUT_ABS="$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)/$(basename "$OUT")" || OUT_ABS="$OUT"
[ -z "$OUT_ABS" ] && OUT_ABS="$OUT"

# Build the cpio archive (must be SVR4 with CRC, matches Creality template)
cd "$WORK"
LIST="sw-description"
[ -f kernel ] && LIST="$LIST kernel"
[ -f rootfs ] && LIST="$LIST rootfs"
echo "$LIST" | tr ' ' '\n' | cpio -ov -H crc -L > "$OUT_ABS" 2>/tmp/mkswu.log
cd - > /dev/null
OUT="$OUT_ABS"
tail -1 /tmp/mkswu.log

echo
echo "=== Built $OUT ==="
ls -la "$OUT"
echo
echo "=== Contents ==="
cpio -tv < "$OUT" 2>&1 | grep -v "blocks$"
echo
echo "=== sw-description ==="
cpio -i --to-stdout sw-description < "$OUT" 2>/dev/null
echo
echo "=== Deploy with ==="
case "$MODE" in
    kernel-only-B)
        echo "scp $OUT hi:/mnt/UDISK/"
        echo "ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/$(basename $OUT) -e stable,kernel_only_B'"
        echo "(printer continues booting stock — no env change)"
        ;;
    kernel)
        echo "scp $OUT hi:/mnt/UDISK/"
        echo "ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/$(basename $OUT) -e stable,now_A_next_B'"
        echo "(commits boot_partition=bootB and reboots into new kernel)"
        ;;
    kernel-and-rootfs)
        echo "scp $OUT hi:/mnt/UDISK/"
        echo "ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/$(basename $OUT) -e stable,now_A_next_B'"
        echo "(commits BOTH boot+root to slot B and reboots)"
        ;;
    kernel-and-rootfs-watchdog)
        echo "scp $OUT hi:/mnt/UDISK/"
        echo "ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/$(basename $OUT) -e stable,now_A_next_B'"
        echo "(commits boot+root to slot B AND arms U-Boot bootcount auto-rollback)"
        echo "Verify rollback armed after install:"
        echo "    ssh root@<printer-ip> 'fw_printenv bootcount bootlimit altbootcmd'"
        echo "Expect:"
        echo "    bootcount=0"
        echo "    bootlimit=3"
        echo "    altbootcmd=setenv boot_partition bootA; ... saveenv; run setargs_nand boot_normal"
        ;;
esac
