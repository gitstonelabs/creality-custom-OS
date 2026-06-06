#!/bin/sh
# usb-gadget-up.sh — bring up a USB Ethernet gadget on the printer's OTG port.
#
# Creates a single composite USB device exposing TWO Ethernet personalities:
#   - RNDIS (Microsoft/Linux-friendly — Windows hosts pick this)
#   - ECM   (Linux/macOS-friendly)
# Both are bound to the SAME usb0 netif on the printer side. The host PC
# enumerates whichever one its OS prefers; the other is ignored at the
# host's discretion.
#
# Static printer-side IP: 10.55.0.1/24
# PC side: set static 10.55.0.2/24 OR plug printer into a network with a
# DHCP server (printer doesn't run one here for simplicity).
#
# Run by /usr/lib/systemd/system/usb-gadget.service at boot.

set -eu

GADGET=/sys/kernel/config/usb_gadget/g1

# Bail early if OTG controller isn't ready
if [ ! -d /sys/class/udc ] || [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; then
    echo "[usb-gadget] no UDC available; skipping (the OTG port may not be wired)"
    exit 0
fi

UDC="$(ls /sys/class/udc | head -1)"
echo "[usb-gadget] UDC=$UDC"

# Idempotent: if a previous instance is around, tear it down
if [ -d "$GADGET" ]; then
    echo "[usb-gadget] gadget already exists, tearing down first"
    /usr/sbin/usb-gadget-down.sh || true
fi

mkdir -p /sys/kernel/config 2>/dev/null || true
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

mkdir -p "$GADGET"
cd "$GADGET"

# USB device identity (using Linux Foundation's "Multifunction Composite Gadget" VID/PID)
echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB
# Composite device class so the host enumerates each interface independently
echo 0xEF > bDeviceClass
echo 0x02 > bDeviceSubClass
echo 0x01 > bDeviceProtocol

mkdir -p strings/0x409
echo "gitStoneLabs"             > strings/0x409/manufacturer
echo "Creality Hi USB Ethernet" > strings/0x409/product
SERIAL="$(cat /etc/machine-id 2>/dev/null | head -c 8 || echo 00000000)"
echo "$SERIAL"                  > strings/0x409/serialnumber

# Configuration 1: RNDIS + ECM
mkdir -p configs/c.1
echo 250 > configs/c.1/MaxPower
mkdir -p configs/c.1/strings/0x409
echo "RNDIS + ECM" > configs/c.1/strings/0x409/configuration

# Derive four locally-administered MACs (02:.. prefix) from this unit's
# machine-id, so every printer is unique and no real hardware MAC is baked
# into the image. The last byte distinguishes the four endpoints.
MID="$(cat /etc/machine-id 2>/dev/null | tr -dc 0-9a-f)"
[ "${#MID}" -ge 8 ] || MID="0123456789abcdef"
MACBASE="02:${MID:0:2}:${MID:2:2}:${MID:4:2}:${MID:6:2}"

# Function: RNDIS
mkdir -p functions/rndis.usb0
echo "${MACBASE}:02" > functions/rndis.usb0/host_addr
echo "${MACBASE}:01" > functions/rndis.usb0/dev_addr
ln -s functions/rndis.usb0 configs/c.1/ 2>/dev/null || true

# Function: ECM (sub-set works on Mac/Linux when host doesn't honor RNDIS)
mkdir -p functions/ecm.usb1
echo "${MACBASE}:04" > functions/ecm.usb1/host_addr
echo "${MACBASE}:03" > functions/ecm.usb1/dev_addr
ln -s functions/ecm.usb1 configs/c.1/ 2>/dev/null || true

# Bind to the controller
echo "$UDC" > UDC

# Bring up the printer-side interface with static IP
# (usb0 is created by the rndis function; usb1 by ecm — bring both up)
sleep 1
for iface in usb0 usb1; do
    if [ -d "/sys/class/net/$iface" ]; then
        ip link set "$iface" up
        # 10.55.0.1 for RNDIS path, 10.55.1.1 for ECM (different subnets so
        # host's routing table never gets confused if both enumerate)
        case "$iface" in
            usb0) ip addr add 10.55.0.1/24 dev "$iface" 2>/dev/null || true ;;
            usb1) ip addr add 10.55.1.1/24 dev "$iface" 2>/dev/null || true ;;
        esac
        echo "[usb-gadget] $iface up"
    fi
done

echo "[usb-gadget] gadget bound to $UDC"
