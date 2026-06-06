#!/bin/sh
# gitstonelabs-bootcount-reset.sh
#
# Reset the U-Boot `bootcount` env var so the next boot starts fresh.
#
# Triggered by gitstonelabs-bootcount-reset.service AFTER all other
# multi-user.target.wants services are up, including WiFi/network/SSH.
# Logic: if we reach this point, the system has booted far enough to
# be considered "healthy" — clear the failure counter.
#
# If we DON'T reach this point (kernel panic, systemd init failure,
# Klipper hang at boot, etc.), `bootcount` will NOT be reset. After
# `bootlimit` (default 3) consecutive failed boots, U-Boot runs
# `altbootcmd` which flips back to the stock bootA / rootfsA. This is
# our auto-rollback safety net.

set -e

# Check that fw_setenv is available — needed to write to the U-Boot env partition
if ! command -v fw_setenv >/dev/null 2>&1; then
    echo "gitstonelabs-bootcount-reset: fw_setenv not installed — cannot reset bootcount" >&2
    exit 1
fi

# Reset bootcount to 0. Don't change other env vars.
fw_setenv bootcount 0 || {
    echo "gitstonelabs-bootcount-reset: failed to write env" >&2
    exit 1
}

echo "gitstonelabs-bootcount-reset: bootcount cleared (boot considered healthy)"
exit 0
