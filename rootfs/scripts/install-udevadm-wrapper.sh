#!/bin/bash
# install-udevadm-wrapper.sh — wraps Buildroot's host-udevadm to skip the
# hwdb --update step that crashes on Buildroot 2022.02 systemd 250.4 +
# glibc 2.39 host (WSL Ubuntu 24.04).
#
# Run once after `make host-systemd` completes, BEFORE the target-finalize
# step that calls udevadm hwdb --update.

set -e

HOSTBIN="${HOSTBIN:-$HOME/buildroot-creality-hi-out/host/bin}"
REAL="$HOSTBIN/udevadm.real"
WRAP="$HOSTBIN/udevadm"

if [ -L "$WRAP" ] && [ "$(readlink -f "$WRAP")" = "$REAL" ]; then
    echo "wrapper already installed"
    exit 0
fi

# Only move the real binary aside on first run
if [ ! -e "$REAL" ]; then
    mv "$WRAP" "$REAL"
fi

# Write a clean wrapper using a quoted heredoc so $1 is preserved literally
cat > "$WRAP" <<'SHIM'
#!/bin/bash
# Auto-installed by gitStoneLabs: skip the udevadm hwdb step that crashes
# on Buildroot 2022.02 systemd 250.4 + glibc 2.39 host. The hwdb is rebuilt
# by systemd-udevd at first boot on the target — losing it at build time
# is harmless.
case "$1" in
    hwdb)
        echo "[gitstonelabs] udevadm hwdb skipped (systemd 250.4 + glibc 2.39 buffer overflow workaround)" >&2
        exit 0
        ;;
    *)
        exec "$(dirname "$0")/udevadm.real" "$@"
        ;;
esac
SHIM
chmod +x "$WRAP"

echo "wrapper installed at $WRAP"
echo "real binary at $REAL"
