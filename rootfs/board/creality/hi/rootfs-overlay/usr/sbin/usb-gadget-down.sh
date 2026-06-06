#!/bin/sh
# usb-gadget-down.sh — teardown counterpart for usb-gadget-up.sh
set -eu
GADGET=/sys/kernel/config/usb_gadget/g1
[ -d "$GADGET" ] || exit 0
echo "" > "$GADGET/UDC" 2>/dev/null || true
rm -f "$GADGET"/configs/c.1/rndis.usb0
rm -f "$GADGET"/configs/c.1/ecm.usb1
rmdir "$GADGET"/configs/c.1/strings/0x409 2>/dev/null || true
rmdir "$GADGET"/configs/c.1 2>/dev/null || true
rmdir "$GADGET"/functions/rndis.usb0 2>/dev/null || true
rmdir "$GADGET"/functions/ecm.usb1 2>/dev/null || true
rmdir "$GADGET"/strings/0x409 2>/dev/null || true
rmdir "$GADGET" 2>/dev/null || true
echo "[usb-gadget] teardown done"
