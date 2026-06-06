#!/bin/sh
# gitstonelabs-heartbeat.sh
#
# Emit a periodic heartbeat byte to /dev/ttyS3 (the bed-MCU RS232 link).
# This is a debug side-channel: even without UART, WiFi, or USB Ethernet
# access, an ST-Link operator can read the GD32F303 bed-MCU's UART RX
# register and see the heartbeat byte arrive — confirming our kernel is
# alive and running userspace.
#
# Stops itself as soon as Klipper takes over /dev/ttyS3 (then the bed-MCU
# is in active comm with the real driver). Until then, this is the only
# traffic on the bus.
#
# Protocol: every 2 seconds, send a 3-byte frame:
#   0x55 0xAA <wallclock_seconds & 0xFF>
#
# Stop conditions:
#   - /dev/ttyS3 fails to open / disappears
#   - klippy process detected as running
#   - SIGTERM (systemd shutting us down)

PORT=/dev/ttyS3
BAUD=230400
INTERVAL=2

# Catch SIGTERM so systemd can stop us cleanly
trap 'echo "gitstonelabs-heartbeat: terminated"; exit 0' TERM INT

if [ ! -e "$PORT" ]; then
    echo "gitstonelabs-heartbeat: $PORT does not exist; nothing to do"
    exit 0
fi

# Configure the port
stty -F "$PORT" "$BAUD" cs8 -cstopb -parenb -ixon -ixoff raw 2>/dev/null || {
    echo "gitstonelabs-heartbeat: failed to configure $PORT, exiting"
    exit 0
}

echo "gitstonelabs-heartbeat: starting heartbeat on $PORT @ $BAUD baud"

while true; do
    # If Klipper has taken over ttyS3, stop sending so we don't confuse it
    if pgrep -f "klippy.py" >/dev/null 2>&1; then
        # Quick check: is klippy actually using this port? If so, exit.
        if lsof "$PORT" 2>/dev/null | grep -q klippy; then
            echo "gitstonelabs-heartbeat: Klipper has $PORT — yielding"
            exit 0
        fi
    fi

    # Emit the heartbeat: 0x55 0xAA <wallclock_byte>
    SEC=$(($(date +%s) & 0xFF))
    printf '\x55\xAA' > "$PORT"
    printf '%b' "$(printf '\\x%02X' "$SEC")" > "$PORT"

    sleep $INTERVAL
done
