# Two-step flash plan: getting the custom .swu onto the Creality Hi

**Goal:** install `creality-hi.swu` (kernel + rootfs + CFS Klipper + WiFi-ready) onto the printer without UART access, with verifiable safety at each step.

**Hardware state:** UART debug header is parked. Stock OS at bootA still works and is reachable via `ssh root@<printer-ip>` (root@<printer-ip>). U-Boot has **no automatic rollback** — if bootB's kernel panics with `boot_partition=bootB`, the printer soft-bricks until FEL/USB recovery.

**Comm strategy after install:**

⚠ **WiFi DEFERRED:** the AIC8800 vendor driver (~2022 vintage) doesn't compile cleanly against kernel 6.6's cfg80211 API — a handful of callback signatures changed (notably `tdls_mgmt` gained an `int link_id` parameter for WiFi 7 multi-link). Porting is doable but ~hours of work; deferred since the user is going to replace the mainboard anyway (which may swap the WiFi chip).

For first boot, the comm path is **USB Ethernet gadget only**:

1. **USB Ethernet gadget at `10.55.0.1/24`** — *primary, only path that works first-boot*
   - Plug USB-C cable from PC to printer's OTG port
   - Printer side: usb0 (RNDIS for Win/Linux) + usb1 (ECM for Mac/Linux) both at 10.55.0.1
   - PC side: appears as a new network interface — set static IP `10.55.0.2/24` on that interface
   - SSH: `ssh root@10.55.0.1`
2. WiFi to "<your SSID> " — *not working until AIC8800 is ported* (config is staged, kernel modules just don't compile)
3. mDNS via avahi — would work for `creality-hi.local` once any comm path is up

**Still need to physically identify the OTG port on the mainboard.** It's NOT the front USB-A (that's host-only at MMIO 0x4101000). The OTG controller `usbc0` at 0x4100000 is wired elsewhere — likely a header or a USB-C labeled "OTG" / "DEBUG". Inspect the board before flashing.

---

## Pre-flight checks (do these BEFORE flashing)

```bash
# 1. Confirm the .swu is built and inspectable
ls -la ~/buildroot-creality-hi-out/images/creality-hi.swu
cpio -t < ~/buildroot-creality-hi-out/images/creality-hi.swu
# Expected output: 'sw-description', 'kernel', 'rootfs'

# 2. Confirm stock printer is reachable
ssh root@<printer-ip> 'uname -a; cat /proc/cmdline'
# Expected: OpenWrt 21.02-SNAPSHOT kernel, cmdline mentioning bootA + rootfsA

# 3. Snapshot stock partitions BEFORE doing anything (in case of disaster)
ssh root@<printer-ip> 'dd if=/dev/by-name/bootA   | gzip > /mnt/UDISK/factory_bootA.img.gz   bs=1M'
ssh root@<printer-ip> 'dd if=/dev/by-name/rootfsA | gzip > /mnt/UDISK/factory_rootfsA.img.gz bs=1M'
scp hi:/mnt/UDISK/factory_*.gz ~/printer-backups/

# 4. Confirm current U-Boot env so we know what to restore if it goes wrong
ssh root@<printer-ip> 'fw_printenv | grep -E "^(boot_partition|root_partition|bootcmd|altbootcmd|bootlimit|bootcount)"'
# Expected: boot_partition=bootA, root_partition=rootfsA
```

If any of those fail, stop and resolve before proceeding.

---

## Step 1 — Install KERNEL-ONLY to slot B (safe; bootA still active)

This writes our kernel to bootB without touching the env. Printer keeps booting stock OS as before.

```bash
# Build the kernel-only .swu (one of the modes mkswu.sh supports)
~/Documents/gitstonelabs/tools/mkswu.sh kernel-only-B \
    ~/buildroot-creality-hi-out/images/boot.img \
    ~/buildroot-creality-hi-out/images/creality-hi-kernel-only.swu

scp ~/buildroot-creality-hi-out/images/creality-hi-kernel-only.swu hi:/mnt/UDISK/

ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/creality-hi-kernel-only.swu -e stable,kernel_only_B -l 4'
# Expect: swupdate writes ~7 MB to /dev/by-name/bootB and exits 0.
# Does NOT flip boot_partition. Printer still boots bootA on next reboot.
```

### Step 1 verify

```bash
# Confirm bootB now contains our kernel (size + magic check)
ssh root@<printer-ip> 'ls -la /dev/by-name/bootB && \
        head -c 8 /dev/by-name/bootB | xxd && \
        ls -la /dev/by-name/bootA && \
        head -c 8 /dev/by-name/bootA | xxd'
# Expect: bootA still starts with "ANDROID!" (stock) and bootB also "ANDROID!" but different size

# Confirm env still points at bootA — we have NOT committed yet
ssh root@<printer-ip> 'fw_printenv boot_partition root_partition'
# Expect: boot_partition=bootA, root_partition=rootfsA
```

**If anything is off, stop. Don't proceed to Step 2.** Worst case at this point is bootB is bad but bootA is untouched — power-cycle the printer, you're back to stock.

---

## Step 2 — Write rootfs to slot B + commit env flip (one-shot reboot)

This is the irreversible-without-FEL step. After this, the printer boots OUR kernel + OUR rootfs.

```bash
# Method A — use the full .swu via swupdate (handles both partitions + env flip atomically)
scp ~/buildroot-creality-hi-out/images/creality-hi.swu hi:/mnt/UDISK/
ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/creality-hi.swu -e stable,now_B_next_B -l 4 && sync && reboot'

# Method B — manual dd of rootfs only, then env flip (if you want extra control)
# scp ~/buildroot-creality-hi-out/images/rootfs.squashfs hi:/mnt/UDISK/
# ssh root@<printer-ip> 'dd if=/mnt/UDISK/rootfs.squashfs of=/dev/by-name/rootfsB bs=1M && sync'
# ssh root@<printer-ip> 'fw_setenv boot_partition bootB && fw_setenv root_partition rootfsB && sync && reboot'
```

(The mode name `now_B_next_B` doesn't exist in our mkswu.sh yet — likely `now_A_next_B` from the existing modes will need a new variant. Check `mkswu.sh` --help.)

### Step 2 verify (this is the moment of truth)

The printer disconnects from SSH while it reboots. Watch for **first sign of life** on whichever path comes up first:

```bash
# Option A — WiFi (primary)
# From your PC:
ping -c 3 <printer-ip>          # the static-DHCP-ish address from your router
# or
ping -c 3 creality-hi.local     # via mDNS/avahi
# or check your router's DHCP table for MAC <your-wlan0-MAC>

# Option B — USB Ethernet (fallback)
# Plug USB-C cable from PC to printer's OTG port.
# PC: a new network interface appears (usb0 on Linux/Mac, "Remote NDIS" on Windows).
# Set PC's static IP on that interface:
#   Linux:   sudo ip addr add 10.55.0.2/24 dev <iface>; sudo ip link set <iface> up
#   Mac:     System Settings > Network > USB Ethernet adapter > manual 10.55.0.2/24
#   Windows: Network Settings > Change adapter > IPv4 properties > 10.55.0.2/24
ssh root@10.55.0.1
```

**Expected first-boot timing:**
- Kernel boot to userspace: ~3-5s
- AIC8800 driver load + WiFi associate: ~10-30s
- dropbear SSH listening: ~5-15s after userspace
- nginx + Klipper + Moonraker up: ~30-60s

**Total time to "responds to ping":** 15-45 seconds after reboot. Give it 2 minutes before assuming failure.

---

## Step 3 — Once SSH works, validate everything

```bash
ssh root@creality-hi.local
# Or: ssh root@10.55.0.1  (USB Ethernet path)

# Inside the printer:
cat /etc/gitstonelabs-release    # confirms which build is running
ip addr show wlan0               # WiFi MAC, IP
ip addr show usb0                # USB Ethernet (if cable plugged in)
systemctl status klipper moonraker nginx
journalctl -u klipper -n 50      # Klipper should report "Printer is ready" (no MCU connected is OK)

# Open Fluidd:
# In your browser: http://creality-hi.local/  or  http://10.55.0.1/
```

If Klipper says "Printer is ready" and Fluidd loads, **Phase 3 complete.** You can now poke at config, eventually attach an MCU, etc.

---

## Recovery scenarios

| Symptom | Recovery |
|---|---|
| Step 1 failed (bootB write failed in swupdate) | Stock OS still boots. Diagnose via `ssh root@<printer-ip>`. Re-run Step 1. |
| Step 2 booted but no WiFi AND no USB Ethernet | Power-cycle. If still nothing → FEL recovery via OTG port + recovery-stick scripts. If kernel got far enough to mount rootfs, may be just a service start failure — wait full 2 min. |
| Step 2 booted but only USB-Ethernet works (no WiFi) | SSH via USB Ethernet, check `journalctl -u wpa_supplicant@wlan0` and `dmesg | grep -i aic`. Likely driver build issue — rebuild with fixes. |
| Step 2 booted, WiFi works, but Klipper/Moonraker fail | SSH in, fix configs in `/etc/klipper/printer.cfg` and `/etc/moonraker/moonraker.conf`. Reload systemd services. |
| Kernel panic, printer never comes up | This is the bad case. Need FEL recovery. Steps:<br>1. Power printer OFF<br>2. Plug USB cable from PC to printer's OTG port (still need to identify physically!)<br>3. Press-and-hold the "recovery" button (or short the FEL pins) while powering on<br>4. On PC: `sunxi-fel ver` should show device. Then load a recovery U-Boot via FEL.<br>5. Once in recovery U-Boot, dd the factory backup back to bootA.<br>(See `docs/recovery_methods.md` for details.) |

## Rollback to stock (if you want to go back)

```bash
# If kernel works enough to boot to userspace:
ssh root@creality-hi.local 'fw_setenv boot_partition bootA && fw_setenv root_partition rootfsA && sync && reboot'

# If kernel doesn't boot:
# Use FEL recovery and dd the factory backup:
sunxi-fel -p write 0x40000000 ~/printer-backups/factory_bootA.img.gz
# (More involved — see recovery_methods.md.)
```

The factory backup at `~/printer-backups/factory_bootA.img.gz` is your get-out-of-jail card. Keep it forever.
