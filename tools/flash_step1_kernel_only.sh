#!/bin/sh
# Step 1 of two-step flash: install kernel_only_B (safe, bootA stays active)

set -e

echo "=== BEFORE: env state ==="
fw_printenv boot_partition root_partition 2>/dev/null

echo
echo "=== INSTALLING kernel_only_B ==="
swupdate -i /mnt/UDISK/creality-hi-kernel-only.swu -e stable,kernel_only_B -l 4 2>&1 | tail -30

echo
echo "=== AFTER: env state (should be unchanged) ==="
fw_printenv boot_partition root_partition 2>/dev/null

echo
echo "=== bootB first 32 bytes ==="
dd if=/dev/by-name/bootB bs=1 count=32 2>/dev/null | od -c | head -2

echo
echo "=== bootA first 32 bytes (compare) ==="
dd if=/dev/by-name/bootA bs=1 count=32 2>/dev/null | od -c | head -2

echo
echo "=== bootB size ==="
dd if=/dev/by-name/bootB of=/dev/null bs=1M 2>&1 | grep records
