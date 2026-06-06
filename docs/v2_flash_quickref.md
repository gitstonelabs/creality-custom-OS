# creality-hi-v2.swu — flash quick-reference

**Version:** 1.0 — 2026-05-28
**Status:** Built and inspected. Untested on hardware (gated on RMA replacement board, expected Friday).

This is the one-screen reference for installing `creality-hi-v2.swu` once you have a working printer to test on. For the design rationale, see `swu_v2_design.md`. For first-time install background (USB-Eth gadget, OTG path, etc.), see `two_step_flash_plan.md`.

---

## What v2 does that v1 didn't

| | v1 (`creality-hi.swu`) | v2 (`creality-hi-v2.swu`) |
|---|---|---|
| Kernel console | `ttyS0` only | `ttyS3 + ttyS4 + ttyS5 + ttyS0` (last wins for getty) |
| U-Boot watchdog | None | `bootcount`/`bootlimit=3`/`altbootcmd` set up at install time |
| Userspace bootcount reset | N/A | `gitstonelabs-bootcount-reset.service` after multi-user.target |
| Bed-MCU side channel | None | `gitstonelabs-heartbeat.service` writes `0x55 0xAA <wallclock>` to ttyS3 @ 230400 every 2 s |
| `fw_setenv` in rootfs | No | Yes (`/usr/sbin/fw_setenv`, `/etc/fw_env.config`) |
| Recovery initramfs | No | Still No (deferred to v2.1) |
| WiFi (AIC8800) | No | Still No (deferred to Phase 2.6) |

---

## Two artifacts produced by the build

```
~/buildroot-creality-hi-out/images/creality-hi-v2.swu              # 39.5 MB — kernel + rootfs + watchdog bootenv
~/buildroot-creality-hi-out/images/creality-hi-v2-kernel-only.swu  # 7.3 MB — kernel only, no env change, SAFEST
```

Use `kernel-only` first whenever possible — it doesn't change `boot_partition`, so a power-cycle reliably returns to stock.

---

## Pre-flight on the replacement board (stock firmware)

```bash
# 1. Snapshot stock partitions (full backup, irreplaceable)
ssh root@<printer-ip> 'dd if=/dev/by-name/bootA   bs=1M | gzip > /mnt/UDISK/factory_bootA.img.gz'
ssh root@<printer-ip> 'dd if=/dev/by-name/rootfsA bs=1M | gzip > /mnt/UDISK/factory_rootfsA.img.gz'
scp hi:/mnt/UDISK/factory_*.gz ~/printer-backups/

# 2. Capture stock fw_env.config + env partitions
ssh root@<printer-ip> 'cat /etc/fw_env.config 2>/dev/null; ls -la /dev/by-name/env*'
ssh root@<printer-ip> 'fw_printenv 2>&1 | head -40 > /tmp/stock-uboot-env.txt'
scp hi:/tmp/stock-uboot-env.txt ~/printer-backups/

# 3. Confirm vendor U-Boot supports CONFIG_BOOTCOUNT_LIMIT
ssh root@<printer-ip> 'fw_printenv altbootcmd bootcount bootlimit 2>&1'
#   If the vars exist (even empty), U-Boot probably honors them.
#   If `fw_printenv` returns "## Error: ... not defined", check during the
#   U-Boot console interactive prompt: `printenv | grep -E "bootcount|altboot"`
#   Final answer requires U-Boot console + strings on the U-Boot binary:
#     dd if=/dev/by-name/bootloader bs=1 count=512K | strings | grep -i bootcount
```

If our `/etc/fw_env.config` (`env0`/`env1`, 0x20000 each) doesn't match stock's actual layout, the bootcount-reset service will silently fail. Fix-forward: copy stock's fw_env.config verbatim into the rootfs-overlay and rebuild v2.

---

## Smoke test 1 — kernel-only (writes bootB without flipping boot_partition)

Goal: prove our kernel boots without any commitment.

```bash
# Deploy the kernel-only smoke-test .swu
scp ~/buildroot-creality-hi-out/images/creality-hi-v2-kernel-only.swu hi:/mnt/UDISK/
ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/creality-hi-v2-kernel-only.swu -e stable,kernel_only_B'

# Verify the kernel landed in bootB without env changes
ssh root@<printer-ip> 'fw_printenv boot_partition'         # MUST still be bootA
ssh root@<printer-ip> 'dd if=/dev/by-name/bootB bs=1 count=8 2>/dev/null | xxd | head -1'
# Expected: 41 4e 44 52 4f 49 44 21  ('ANDROID!') — our v2 bootimg header
```

### Boot the new kernel ONCE via U-Boot console (no env commit)

1. Connect UART to **any** of: ttyS0 (J65), ttyS3 (3PEAK RS232 to bed-MCU), ttyS4, ttyS5
   - v2's multi-UART cmdline means at least one of them sees output if the kernel boots
2. Power-cycle the printer; interrupt U-Boot autoboot (any key during the 1-3 sec countdown)
3. At the `=>` prompt:
   ```
   sunxi_flash read 43000000 bootB
   bootm 43000000
   ```
4. Watch UART for boot messages.
5. If hung/panic: power-cycle. Stock comes up next (boot_partition was never changed).

### Indirect signs the kernel is running (when UART is silent)

- **Bed-MCU heartbeat**: with ST-Link on J2, halt the GD32F303 and read its UART RX register; bytes `0x55 0xAA <varying>` arriving every ~2s mean userspace reached `gitstonelabs-heartbeat.service`.
- **USB Eth gadget**: if the kernel's USB OTG controller comes up, plug USB-C from printer to your PC; new network interface should appear within ~30s.
- **MAC table on your router**: if the printer's WiFi were on, the AIC8800 MAC pin would show; but WiFi is deferred, so ignore.

---

## Smoke test 2 — full v2 .swu (kernel + rootfs + watchdog)

Run this ONLY after smoke test 1 boots successfully.

```bash
# Deploy the full v2 .swu
scp ~/buildroot-creality-hi-out/images/creality-hi-v2.swu hi:/mnt/UDISK/
ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/creality-hi-v2.swu -e stable,now_A_next_B -l 4'
# swupdate -l 4 = verbose; watch for any failed images: or bootenv: lines

# Verify env vars were set
ssh root@<printer-ip> 'fw_printenv boot_partition root_partition bootcount bootlimit altbootcmd'
# Expected:
#   boot_partition=bootB
#   root_partition=rootfsB
#   bootcount=0
#   bootlimit=3
#   altbootcmd=setenv boot_partition bootA; ...; saveenv; run setargs_nand boot_normal

# Reboot into v2
ssh root@<printer-ip> 'sync; reboot'
```

### After reboot — connect via USB-C OTG

`ssh root@10.55.0.1` (USB Ethernet gadget). The printer's USB-C OTG comes up early in boot and stays up until something fails. Once you have a shell:

```bash
# Confirm boot is "healthy" from our service's perspective
systemctl status gitstonelabs-bootcount-reset.service
#   Expected: Active: active (exited) since ...
#   Logs: "bootcount cleared (boot considered healthy)"

# Confirm bootcount actually was reset
fw_printenv bootcount
#   Expected: bootcount=0

# Confirm we're on our build
cat /etc/gitstonelabs-release
#   NAME="gitStoneLabs Linux", BOARD="creality-hi", BUILD_DATE=..., REVISION=...

# Confirm Klipper started
systemctl status klipper.service moonraker.service
# Bonus — see boot log on all UARTs to verify multi-UART worked:
journalctl -b | grep -i 'console\|uart' | head -20
```

---

## If something goes wrong

### Symptom: After reboot, printer comes up on stock (bootA) anyway

Cause #1: our kernel panic'd, bootcount tripped, U-Boot ran altbootcmd. Confirm by checking from stock:
```bash
ssh root@<printer-ip> 'fw_printenv boot_partition bootcount'
# If boot_partition=bootA AND bootcount=0, altbootcmd fired. Check journal once
# we get back into v2 (or read u-boot console captures).
```
This is **the watchdog working as designed** — the system rolled back to stock automatically. Investigate dmesg from a UART capture during the failed boot attempts, fix, rebuild.

Cause #2: swupdate didn't actually write the new env. Confirm via `fw_printenv | head`. If everything is stock values, swupdate likely errored — re-run with `-l 5` and read the log.

### Symptom: ssh root@10.55.0.1 doesn't respond, no UART output anywhere

Likely: kernel failed before getty. Power-cycle 3 times. On the 4th boot, altbootcmd should have fired and put us back to stock. If still dead → UART recovery only path.

### Symptom: bootcount climbs even on healthy boots

The bootcount-reset service isn't running successfully. Possible reasons:
1. `fw_env.config` partition/offset is wrong → `fw_setenv` silently fails
2. `/dev/by-name/env0` doesn't exist → udev didn't populate by-name links
3. SELinux / AppArmor blocking → no, neither is installed

Debug:
```bash
ssh root@10.55.0.1 'fw_setenv bootcount 0 && fw_printenv bootcount'
# If this fails with "Cannot access MTD device ...", fw_env.config is wrong.
# Fix: copy stock's fw_env.config and rebuild.
```

### Last-resort recovery — UART U-Boot console

If the printer is unreachable on all paths:
1. UART cable on J65 (115200 8N1)
2. Power-cycle, interrupt U-Boot
3. `setenv boot_partition bootA; setenv root_partition rootfsA; saveenv; reset`
4. Printer comes up on stock.

---

## Build instructions (for the next iteration)

```bash
# In WSL:
LINUX_OVERRIDE_SRCDIR=$HOME/linux-6.6 \
    <workspace>/rootfs/scripts/br_make.sh

# Output:
~/buildroot-creality-hi-out/images/creality-hi-v2.swu
~/buildroot-creality-hi-out/images/creality-hi-v2-kernel-only.swu
```

To rebuild just one piece:
- Kernel only: `br_make.sh linux-rebuild`
- Rootfs+packages only: touch any source, then `br_make.sh`
- Re-run finalize+image hooks only: `br_make.sh world` (incremental, ~30 s if nothing changed)

To change the embedded cmdline, edit `KERNEL_CMDLINE` in `rootfs/board/creality/hi/scripts/make-swu.sh` and rebuild.
