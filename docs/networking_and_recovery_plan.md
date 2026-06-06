# Networking & recovery plan for the Creality Hi custom kernel

The Hi has **no Ethernet** — only WiFi + USB. To make a custom kernel usable without UART access, we need *some* way to reach the printer over the network. Three independent paths, ranked by effort:

| Path | Effort | Reliability | Verdict |
|---|---|---|---|
| **USB Ethernet gadget** (RNDIS/ECM) | Low — config already exists in stock | High once configured | Best first option |
| **WiFi auto-connect on first boot** | Medium — AIC8800 driver port needed | High once working | Long-term answer |
| **USB stick first-boot config** | Low | Medium (depends on init flow) | Backup, easy fallback |

---

## 1. USB Ethernet gadget — SSH over USB cable

### What we found on stock

The printer **already has the framework** for this. Stock OpenWrt runs ADB-over-USB via:
- `/sys/class/udc/4100000.udc-controller` — the USB OTG/UDC hardware
- `/sys/kernel/config/usb_gadget/g1` — gadget configfs already enabled in kernel
- `/etc/init.d/adbd` — the boot script that configures the gadget

Currently it FAILS at boot (`failed to start g1: -22` = EINVAL) because the gadget config is incomplete by the time adbd binds — but that's a stock-OS problem, not a hardware problem.

Key DT properties of the OTG controller:
```
status         = "okay"
usb_port_type  = 2     (OTG — can be host OR device)
usb_id_gpio    = PG7   (OTG ID detection — wired to PG7)
rndis_wceis    = 1     (RNDIS Windows compat enabled — intentional!)
```

The hardware is ready for either ADB OR RNDIS gadget. Our kernel already has `CONFIG_USB_GADGET=y`, `CONFIG_USB_CONFIGFS=y`, `CONFIG_USB_CONFIGFS_RNDIS=y`, `CONFIG_USB_CONFIGFS_ACM=y` enabled (from Phase 0b).

### Where is the OTG port physically?

We have 2 USB controllers:
- **`usbc0` (OTG, at MMIO 0x4100000)** — this is the gadget-capable port
- **`usbc1` (host only, at MMIO 0x4101000/0x4101400)** — this is the front USB-A for thumb drives

`usbc0` is wired to a different physical port than the front USB-A. **It's somewhere on the mainboard — you'll need to physically inspect.** Most likely candidates:
- An internal USB-Micro near the SoC
- A 4-pin header labeled "USB", "ADB", "DEBUG", or unmarked near the SoC
- Possibly a USB-A near the WiFi module or eMMC

If you find a USB-Micro connector you've never used, that's almost certainly it. Once you've identified it, an OTG-Micro-to-Type-A cable (the kind that came with old Android phones for using thumb drives) plugged into Jetson would give us the network path.

### Implementation for our custom rootfs

Drop a systemd service into our rootfs overlay that builds a working RNDIS+ECM (dual-mode for Windows + Mac/Linux) gadget at boot:

```bash
# /etc/systemd/system/usb-ether-gadget.service
[Unit]
Description=USB Ethernet gadget (RNDIS/ECM)
After=sysinit.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/usb-ether-gadget.sh

[Install]
WantedBy=multi-user.target
```

```bash
#!/bin/sh
# /usr/local/bin/usb-ether-gadget.sh
set -e
mount | grep -q configfs || mount -t configfs none /sys/kernel/config
mkdir -p /sys/kernel/config/usb_gadget/g1
cd /sys/kernel/config/usb_gadget/g1

echo 0x1d6b > idVendor       # Linux Foundation
echo 0x0104 > idProduct      # Multifunction Composite
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

mkdir -p strings/0x409
echo gitStoneLabs > strings/0x409/manufacturer
echo "Creality Hi"  > strings/0x409/product
echo CRHI001        > strings/0x409/serialnumber

mkdir -p configs/c.1
echo 0xc0 > configs/c.1/bmAttributes
echo 500  > configs/c.1/MaxPower

# RNDIS (Windows-native)
mkdir -p functions/rndis.usb0
ln -sf functions/rndis.usb0 configs/c.1/rndis.usb0

# ECM (Mac/Linux-native — bonus, second config for compatibility)
mkdir -p functions/ecm.usb1
ln -sf functions/ecm.usb1 configs/c.1/ecm.usb1

# Bind to the controller
echo 4100000.udc-controller > UDC

# Bring up usb0 with a fixed IP
sleep 0.5
ip addr add 192.168.42.1/24 dev usb0
ip link set usb0 up

# DHCP server for the host
udhcpd /etc/udhcpd.conf &
```

After boot, plug a USB cable from the printer's OTG port to your Jetson/PC. The host sees a new network interface (`usb0` on Linux), DHCP assigns the host `192.168.42.2`, and `ssh root@192.168.42.1` works.

**Bonus**: this works for both Windows (via RNDIS) and Linux/Mac (via ECM) simultaneously.

---

## 2. AIC8800 WiFi driver — port to mainline 6.6

### What we found

The Hi uses **AIC8800** WiFi+BT combo (NOT XR829 as initially suspected). Three pieces needed:

| Component | Location |
|---|---|
| **Kernel driver source** | `~/linux_kernel_aw_t113/drivers/net/wireless/aic8800/` (4 sub-modules) |
| **Firmware blobs** | `/lib/firmware/aic8800D80/` on the printer (also in `printer-artifacts/firmware-extracted/`) |
| **Module load order** | `aic8800_bsp` first, then `aic8800_fdrv`, then `aic8800_btusb` (for BT) |

The AICSemi driver is open-source. The vendor BSP version targets Linux 5.4. For mainline 6.6, we'd need:
- Adjust to current `cfg80211` API (mac80211 changed substantially between 5.4 and 6.6)
- Adjust to current `device_node` parsing API
- Possibly use a newer AIC8800 driver from upstream — the chip vendor occasionally pushes updates

Estimate: 1-2 weekends to port + smoke-test.

### Path forward

**Stage 1**: build AIC8800 as **out-of-tree modules** against our 6.6 kernel. Cleaner than in-tree port — no risk of breaking other drivers, easier to update if vendor pushes a newer driver.

```
# In our buildroot package list:
BR2_PACKAGE_AIC8800=y      # to be added as out-of-tree package in rootfs/package/
```

**Stage 2**: bake the firmware into our rootfs at `/lib/firmware/aic8800D80/`.

**Stage 3**: WiFi connection auto-setup on first boot — see below.

---

## 3. First-boot WiFi setup — three options

### Option A (simplest): bake user's WiFi creds into the image

In `rootfs/board/creality/hi/rootfs-overlay/etc/wpa_supplicant/wpa_supplicant.conf`:

```
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel
network={
    ssid="YOUR_WIFI_SSID"
    psk="YOUR_WIFI_PASSWORD"
    key_mgmt=WPA-PSK
}
```

Plus a systemd service to start `wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf && dhcpcd wlan0`. First boot, printer auto-connects.

**Pro**: simplest. **Con**: WiFi creds are in the image — fine for personal use, awkward for distribution.

### Option B (user-friendly): USB stick first-boot config

On first boot, the rootfs init checks `/mnt/UDISK/firstboot.conf` (or a USB stick mounted at `/media/`). If found, reads SSID/password from it and writes `/etc/wpa_supplicant/wpa_supplicant.conf`, then connects.

User flow:
1. Plug a thumb drive with a `firstboot.conf` file into the printer's USB-A port before powering on
2. First boot reads the file
3. WiFi connects automatically
4. User unplugs thumb drive, can SSH next boot

The firstboot.conf is human-editable:
```
ssid=MyHomeWiFi
psk=mySuperSecretPassword
```

Init script reads it, expands into wpa_supplicant config, kicks WiFi, deletes the firstboot.conf so creds aren't persisted on the thumb drive.

**Pro**: usable by anyone, supports multiple installs (different printers each with their own config). **Con**: requires the user to make the thumb drive file first.

### Option C (most polished): captive-portal AP mode

On first boot, if no WiFi configured, the printer becomes a **WiFi access point itself** with SSID "creality-hi-setup". User connects to it from their phone, gets a webpage, types their real WiFi credentials, printer reboots into STA mode.

**Pro**: zero technical knowledge required from end user. **Con**: significantly more work — needs hostapd + dnsmasq + a tiny web server.

### Recommendation

Build A and B in parallel. A is the quick win for development (your printer specifically). B is the path for community distribution. C is v2.0 polish.

---

## 4. USB stick recovery prep

If everything else fails, a USB stick with a recovery payload + sunxi-tools host machine is the catch-all. The stick contains:

```
recovery_stick/
├── README.txt               ← human instructions
├── kernel_stock.img         ← backup of the original bootA bootimg
├── kernel_custom_ttyS4.img  ← our custom bootimg (ttyS4 console variant)
├── kernel_custom_ttyS0.img  ← our custom bootimg (ttyS0 console variant)
├── flash_normal.sh          ← restore stock from running printer
├── flash_custom.sh          ← install our custom kernel  
└── recover_fel.sh           ← steps for FEL recovery via Jetson
```

The user plugs the stick into the printer's USB-A port (mounted automatically at `/mnt/UDISK` or similar), then SSHes in and runs the appropriate script. Or, in FEL mode, the stick goes into the Jetson and `recover_fel.sh` walks through sunxi-fel commands.

### What I can build now

```bash
mkdir -p <workspace>/recovery-stick/
cp <workspace>/printer-artifacts/partition-dumps/boota.bin \
   <workspace>/recovery-stick/kernel_stock.img
cp <workspace>/kernel-workspace/build-output/creality_hi_custom_boot.img \
   <workspace>/recovery-stick/kernel_custom_ttyS0.img
cp <workspace>/kernel-workspace/build-output/creality_hi_custom_boot_ttyS4.img \
   <workspace>/recovery-stick/kernel_custom_ttyS4.img
```

I'll create the actual `flash_*.sh` scripts in a separate commit once this plan is approved. The user can then format a USB stick FAT32 and copy this `recovery-stick/` folder onto it.

---

## Suggested implementation order

1. **Find the OTG port physically** — once we know where it is, USB Ethernet gives us network in 5 min.
2. **Build the USB recovery stick** — backup safety net, even if you never need it.
3. **Port the AIC8800 driver as out-of-tree** — gives us WiFi in our custom kernel.
4. **Bake option-A WiFi config into rootfs** for your specific printer (Phase 2 task).
5. **Later: option B (USB stick first-boot config) for the published distro.**

---

## Open questions

1. **Where is the OTG port on the Hi mainboard?** — Need physical inspection. Could be USB-Micro or 4-pin header.
2. **Does the stock USB-A port (front) work with USB cables in BOTH directions?** — If usbc1 (front USB-A) is configurable for device mode via dr_mode override in our custom DTS, we could maybe re-purpose it for OTG without finding a separate connector. (Risky — would break thumb drives, but it's an option.)
3. **AIC8800 variant exact**: D80 vs DC vs DW? — Confirmed `aic8800D80` from `/lib/firmware/`. Driver should auto-detect.
4. **WiFi 2.4 GHz only, or 5 GHz too?** — AIC8800D80 supports both per the datasheet. Useful to know for `wpa_supplicant.conf` settings.
