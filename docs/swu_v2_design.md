# creality-hi.swu v2 — design + build plan

**Version:** 1.1 — 2026-05-28
**Status:** Build infrastructure in place — features 1, 2, 4 implemented in tools/rootfs. Feature 3 (recovery initramfs) deferred to v2.1 pending hardware-on-hand. Feature 5 (AIC8800) deferred to Phase 2.6 (separate task). Target: ready to flash on Creality replacement board (expected Friday).

**Changes since v1.0:**
- Feature 1 (multi-UART console) → implemented via `make-swu.sh` passing `--cmdline` to `mkbootimg_creality.py`. Order rearranged to ttyS3,ttyS4,ttyS5,ttyS0 so ttyS0 ends up as the active console for getty (last-one-wins).
- Feature 2 (U-Boot watchdog) → implemented as `kernel-and-rootfs-watchdog` mode in `mkswu.sh`; rootfs-overlay ships `gitstonelabs-bootcount-reset.{sh,service}`.
- Feature 4 (bed-MCU heartbeat) → implemented as `gitstonelabs-heartbeat.{sh,service}` in rootfs-overlay; auto-yields when Klipper takes over ttyS3.
- post-build.sh enables both new services and chmod +x's both scripts.
- Feature 3 split out: recovery initramfs is more complex (busybox+dropbear+fw_setenv as static, GPIO probe at /init, CDC ACM gadget bringup before rootfs mount) — will land as v2.1 after the simpler v2 features are validated on the replacement board.

---

## Why v2

v1 (`creality-hi.swu`, ~39 MB, flashed 2026-05-26) installed successfully but the printer became unreachable post-flash and we couldn't determine whether the custom kernel was alive. Without working UART or accessible OTG, we had no diagnostic channel.

v2 fixes that by **building diagnostic and recovery into the firmware itself** so that even in failure cases we have a path back. The goal: if the printer powers on after a v2 flash and our kernel is alive in any state, we have a way to talk to it. If our kernel can't even boot, we have a way back to stock.

---

## Features

### 1. Multi-UART kernel console

**Problem v2 solves:** v1 had `console=ttyS0,115200` baked into the cmdline. ttyS0's GPIO mapping in stock vs. our DTS could differ. If our DTS maps ttyS0 to a different pin pair than where the physical J65 header actually lands, the user sees nothing on serial — even though the kernel is happily printing.

**v2 fix:** emit boot messages to **all five available UARTs simultaneously**:
```
console=ttyS0,115200 console=ttyS3,115200 console=ttyS4,115200 console=ttyS5,115200
```

Linux supports multiple `console=` parameters — output is duplicated to each. If ANY of them is physically wired and at 115200 8N1, the user sees boot output. ttyS2 deliberately omitted because Klipper-stock uses it for the nozzle MCU and we don't want to confuse that link if for some reason we boot back into stock.

**Cost:** negligible — kernel writes the same bytes to multiple UARTs. No extra hardware. No baud changes.

**Where to change:** in our `mkbootimg_creality.py` or U-Boot env (we currently inherit cmdline from U-Boot which inherits from the stock env). Easiest: set our own cmdline override in the bootimg header.

### 2. U-Boot watchdog auto-rollback (bootcount / bootlimit / altbootcmd)

**Problem v2 solves:** stock U-Boot has no automatic rollback. Setting `boot_partition=bootB` and then having our kernel panic on first boot → printer is bricked from a user perspective even though stock is still on bootA / rootfsA.

**v2 fix:** use mainline U-Boot's standard `bootcount` mechanism. The chain:

```
fw_setenv bootcount 0
fw_setenv bootlimit 3
fw_setenv altbootcmd 'fw_setenv boot_partition bootA; fw_setenv root_partition rootfsA; saveenv; run setargs_nand boot_normal'
fw_setenv bootcmd 'fw_setenv bootcount $((${bootcount:-0} + 1)); saveenv; run setargs_nand boot_normal'
```

On every boot, U-Boot increments `bootcount`. If our kernel reaches userspace, our `gitstonelabs-bootcount-reset.service` resets `bootcount` to 0 via `fw_setenv`. If our kernel **fails to boot** N times (N=`bootlimit`=3), U-Boot runs `altbootcmd` which flips env back to bootA/rootfsA and boots stock.

**Result:** after at most 3 failed power cycles, the printer is back on stock. No physical access required.

**Implementation:**
- Add `gitstonelabs-bootcount-reset.service` to rootfs overlay — runs at the very end of `multi-user.target.wants` (after WiFi, Klipper, etc. all up) and resets bootcount.
- Add `swupdate-bootenv-init.sh` as a post-install hook that sets the bootcount/bootlimit/altbootcmd env vars when first running the .swu.

**Risk:** if stock U-Boot doesn't honor `bootcount` (vendor U-Boot 2018.07 might have stripped it), the safety net doesn't trigger. Test on real hardware before relying on it. Mitigation: still ship a kernel-only-B-without-env-flip `.swu` so the user can install our kernel and only commit after verifying with whatever comm channel they have.

### 3. Button-triggered recovery initramfs

**Problem v2 solves:** if our kernel boots to userspace but Ethernet / WiFi both fail, the user has no SSH access at all.

**v2 fix:** custom initramfs reads the LOAD button GPIO at boot. If pressed during the first 2 seconds of userspace init, fork into recovery mode:
- Mount rootfs read-only
- Start dropbear on USB CDC ACM (so the printer's USB-A jack, even though it's host-only, can fall back to gadget mode in initramfs since the SoC's USB controller can be reconfigured by the kernel after BROM hands off)
- Wait for SSH connection with no network or filesystem mounts attempted
- Print instructions to all UART consoles

This is a deliberate bare-bones recovery shell — no Klipper, no systemd, just a Busybox shell with `dd`, `mount`, `fw_setenv` available.

**Implementation:**
- Create a small initramfs cpio with: busybox-static, dropbear-static, fw_setenv-static
- Embed it in the kernel via `CONFIG_INITRAMFS_SOURCE` so it's always there
- Initramfs `/init` script checks GPIO state, branches:
  - Button NOT pressed → exec the normal Buildroot rootfs init (systemd)
  - Button pressed → start dropbear and wait

**Where the GPIO maps:**
LOAD button = SW3, wired to some PG or PB pin. Need to identify exact pin from device tree analysis. Probably `gpiochip0` line ~100 (PG11 area for limit-switch-style inputs).

### 4. Bed-MCU heartbeat side channel

**Problem v2 solves:** if our kernel is alive but no human-readable output channel exists, we still can't confirm life signs.

**v2 fix:** on first boot, our kernel sends a heartbeat byte every 2 seconds to ttyS3 (the bed-MCU RS232 link). Via ST-Link on J2, we can read the GD32F303's UART RX buffer or watch the bed-MCU's behavior. Even tiny:
- Byte received = our kernel is alive
- No byte = our kernel is dead

**Implementation:**
- Tiny `gitstonelabs-heartbeat.service` that opens `/dev/ttyS3` at 230400 and writes `0x55 0xAA <time_lower_byte>` every 2 seconds.
- Document the protocol so any ST-Link / Black Magic Probe user can run `openocd -c "halt; mdb 0xVVV 1"` on the bed-MCU's UART register and see the byte arrive.

**Cost:** Trivial — a 20-line script and a systemd unit. Doesn't interfere with bed-MCU operation because we send via ttyS3 ONLY when Klipper isn't running (i.e., until the bed-MCU side establishes a real Klipper session, our heartbeat is the only traffic).

### 5. AIC8800 WiFi driver (deferred to a separate phase)

**Problem v2 doesn't solve:** AIC8800 driver porting to mainline 6.6 cfg80211 — this needs ~hours of dedicated work (Phase 2.6, task #37).

**v2 punt:** ship without WiFi. We're using a different external antenna anyway for the new board. Cable Matters USB-Eth adapter (driver built-in) is the primary network path. Phase 2.6 work resumes once we have a known-working board.

---

## Build plan

| Step | What | Status |
|---|---|---|
| 1 | Add `console=ttyS3,115200 console=ttyS4,115200 console=ttyS5,115200 console=ttyS0,115200 loglevel=7 earlyprintk` to bootimg cmdline | **DONE** (`make-swu.sh` `KERNEL_CMDLINE`) |
| 2 | Bootcount-reset systemd service + Buildroot install + sw-description bootenv injection | **DONE** (`rootfs-overlay`, `post-build.sh`, `mkswu.sh kernel-and-rootfs-watchdog`) |
| 3 | Recovery initramfs (busybox+dropbear+fw_setenv) embedded in kernel | DEFERRED to v2.1 |
| 4 | Bed-MCU heartbeat service | **DONE** (`gitstonelabs-heartbeat.{sh,service}`) |
| 5 | Build new `creality-hi-v2.swu` via `br_make.sh` | Pending Buildroot rebuild |
| 6 | Document the .swu install + the recovery procedures | Pending |
| 7 | Test on the replacement Creality board when it arrives | Friday |

### What got built and where (v1.1 implementation map)

| Feature | File(s) | Notes |
|---|---|---|
| Multi-UART cmdline | `rootfs/board/creality/hi/scripts/make-swu.sh` | `KERNEL_CMDLINE` var passed via `--cmdline` to `mkbootimg_creality.py`. ttyS0 last so it wins as `/dev/console`. |
| Watchdog .swu mode | `tools/mkswu.sh` | New `kernel-and-rootfs-watchdog` mode adds `bootcount=0`, `bootlimit=3`, `altbootcmd` to the sw-description `bootenv:` block for both A→B and B→A flips. |
| Bootcount reset (userspace) | `rootfs/board/creality/hi/rootfs-overlay/usr/local/bin/gitstonelabs-bootcount-reset.sh` | Calls `fw_setenv bootcount 0`. Triggered by service after `multi-user.target`. |
| Bootcount reset service | `rootfs/board/creality/hi/rootfs-overlay/etc/systemd/system/gitstonelabs-bootcount-reset.service` | Type=oneshot, RemainAfterExit=yes, After=multi-user.target. Enabled in post-build.sh. |
| Bed-MCU heartbeat | `rootfs/board/creality/hi/rootfs-overlay/usr/local/bin/gitstonelabs-heartbeat.sh` | Emits 3-byte frame `0x55 0xAA <wallclock & 0xFF>` to `/dev/ttyS3` @ 230400 every 2 s. |
| Heartbeat service | `rootfs/board/creality/hi/rootfs-overlay/etc/systemd/system/gitstonelabs-heartbeat.service` | Type=simple, After=systemd-udev-settle.service, Before=klipper.service. Stops when Klipper opens ttyS3 (detected via `lsof`). |
| Service+script enable | `rootfs/board/creality/hi/scripts/post-build.sh` | `enable_unit gitstonelabs-bootcount-reset.service`, `enable_unit gitstonelabs-heartbeat.service`, plus `chmod +x` on both scripts. |
| Final .swu name | `make-swu.sh` | Output renamed `creality-hi-v2.swu` + companion `creality-hi-v2-kernel-only.swu` for low-risk smoke-testing. |

---

## Compatibility with v1

v2 is a drop-in replacement for v1 — same swupdate package format, same `now_A_next_B` flash mode. A user who already has v1 installed can install v2 via:

```bash
ssh root@<v1-IP> 'swupdate -i /mnt/UDISK/creality-hi-v2.swu -e stable,now_B_next_A -l 4 && sync && reboot'
```

(note `now_B_next_A` because we'd be booting from B and writing to A this time — but the swupdate sw-description supports both modes).

---

## Open questions

1. Does stock U-Boot 2018.07 from Creality honor `bootcount`/`bootlimit`/`altbootcmd`? Need to verify by reading `printenv` output post-RMA-board-arrival and looking at the U-Boot binary's symbols for those CMD_CMD entries.
2. What's the exact GPIO line for the LOAD button (SW3)? Likely PG something — we have the pinctrl debugfs from stock but the SW3 mapping isn't in our notes yet. Stock kernel must read it somehow (it triggers FEL in BROM but might also be exposed to userland). Probe post-RMA.
3. Should the heartbeat go to ttyS3 (bed-MCU) or a different ttyS? Whichever we pick, the choice affects ST-Link visibility — ttyS3's other side is the 3PEAK 3232E RS232 transceiver going to the GD32F303 bed-MCU's UART RX. So ST-Link viewer needs to halt the GD32 and read its UART RX register. Doable but needs more setup than just watching bed-MCU's memory.
