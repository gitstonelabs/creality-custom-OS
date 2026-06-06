#!/bin/bash
# br_make.sh — Buildroot make wrapper that sanitizes PATH first.
#
# Buildroot's dependencies.sh refuses to run if PATH contains spaces, tabs,
# or newlines. WSL inherits Windows' contaminated PATH ("C:\Program Files\..."),
# so we always need to reset PATH before invoking make.
#
# Usage:
#   ./scripts/br_make.sh defconfig                     # load creality_hi_defconfig
#   ./scripts/br_make.sh -n | head                     # dry-run preview
#   ./scripts/br_make.sh menuconfig                    # tweak via UI
#   ./scripts/br_make.sh                               # full build
#   ./scripts/br_make.sh linux-rebuild                 # just the kernel
#   ./scripts/br_make.sh BR2_FOO=1 some-target         # arbitrary forward
set -e

# Force-strip every /mnt/c/... entry out of PATH. The export alone is not
# enough — Buildroot recipes run sub-shells with `env -i PATH=$PATH`, and if
# any /mnt/c/ entry leaks through, dependency check + bash recipes blow up
# with "C:/Program: not found". So we do BOTH: export here, AND pass PATH=...
# explicitly to make so it overrides the sub-make environment too.
CLEAN_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH="$CLEAN_PATH"
# Unset MAKEFLAGS too — PowerShell can inject WSL_INTEROP env that confuses make
unset MAKEFLAGS MAKELEVEL MFLAGS

BR_SRC="${BR_SRC:-$HOME/buildroot-yuzuki/buildroot}"
EXT_TREE="${EXT_TREE:-$(cd "$(dirname "$0")/.." && pwd)}"
OUT_DIR="${OUT_DIR:-$HOME/buildroot-creality-hi-out}"

cd "$BR_SRC"

# Forward any *_OVERRIDE_SRCDIR variables (Buildroot's mechanism for rsyncing
# a local source tree instead of downloading) through the env -i barrier.
FORWARD=()
for v in LINUX_OVERRIDE_SRCDIR BUSYBOX_OVERRIDE_SRCDIR \
         KLIPPER_OVERRIDE_SRCDIR MOONRAKER_OVERRIDE_SRCDIR \
         CREALITY_CFS_KLIPPER_OVERRIDE_SRCDIR \
         AIC8800_DRIVER_OVERRIDE_SRCDIR AIC8800_FIRMWARE_OVERRIDE_SRCDIR \
         BR2_DL_DIR BR2_CCACHE_DIR; do
    if [ -n "${!v:-}" ]; then
        FORWARD+=( "$v=${!v}" )
    fi
done

CMD="$1"
shift || true

# Note: `-rR` (disable built-in rules) is NOT applied at the top level —
# that would break packages like lz4 that rely on built-in `%.o: %.c`.
# Instead, the kernel-specific `-rR` is injected via a one-line patch to
# ~/buildroot-yuzuki/buildroot/linux/linux.mk that adds MAKEFLAGS=-rR to
# LINUX_MAKE_ENV. See scripts/patch-buildroot-linux-mk.sh.

# Explicit PATH= on the make line forces the value into the recipe environment
case "$CMD" in
    defconfig)
        rm -f "$OUT_DIR/.config"
        exec env -i PATH="$CLEAN_PATH" HOME="$HOME" USER="$USER" SHELL=/bin/bash \
            TERM="${TERM:-xterm}" LANG="${LANG:-C.UTF-8}" "${FORWARD[@]}" \
            make BR2_EXTERNAL="$EXT_TREE" O="$OUT_DIR" creality_hi_defconfig "$@"
        ;;
    "")
        exec env -i PATH="$CLEAN_PATH" HOME="$HOME" USER="$USER" SHELL=/bin/bash \
            TERM="${TERM:-xterm}" LANG="${LANG:-C.UTF-8}" "${FORWARD[@]}" \
            make BR2_EXTERNAL="$EXT_TREE" O="$OUT_DIR"
        ;;
    *)
        exec env -i PATH="$CLEAN_PATH" HOME="$HOME" USER="$USER" SHELL=/bin/bash \
            TERM="${TERM:-xterm}" LANG="${LANG:-C.UTF-8}" "${FORWARD[@]}" \
            make BR2_EXTERNAL="$EXT_TREE" O="$OUT_DIR" "$CMD" "$@"
        ;;
esac
