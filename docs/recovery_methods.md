# Recovery / flashing methods — Creality Hi

**Version:** 2.0 — 2026-05-31
**Status:** **Full stock recovery of a v1-`.swu`-bricked board CONFIRMED end-to-end on hardware** (2026-05-31) via the RTC-flag → vendor-fastboot path below. This is the canonical recovery and supersedes the "mainline U-Boot via sunxi-fel" idea (that path is a confirmed dead end — see note).

Several ways to put firmware on / recover the printer, ranked by safety. Use as a stack — start safest, escalate only when needed.

> ### ⭐⭐ 2026-05-31 — STOCK RECOVERY PROVEN: RTC boot-mode flag → vendor fastboot → flash env
> A board soft-bricked by a bad A/B flash (kernel won't boot) is fully recoverable **as long as boot0 + the on-eMMC boot-package U-Boot are intact** (they survive any `.swu`/`fw_setenv` mishap). No RMA, no console hacking.
>
> **Why it works:** boot0 reads a boot-mode byte from **RTC GPR[6] = `0x07090118`** (RTC base `0x07090000` + GPR block `0x100` + index 6×4; index confirmed by the live device DTS `gpr_cur_pos=0x06` and the T113 vendor BSP `rtc-sunxi.c`). The RTC is in the always-on domain, so a **warm** reset preserves the byte. boot0 honors it and clears it (one-shot).
> **Flag values:** efex/FEL `0x5A`, recovery `0x5C`, **fastboot `0x5F`**.
>
> **Procedure (recover to stock):**
> ```bash
> # 1. Enter FEL: hold LOAD at power-on (front USB-A = USB0, data-only A-A cable to a Jetson host port)
> X=~/xfel/xfel                       # patched xfel (xboot), works on T113
> sudo $X version                     # AWUSBFEX ID=0x00185900(R528/T113)
> sudo $X write32 0x07090118 0x5F     # arm vendor fastboot
> sudo $X reset                       # WARM reset (preserves RTC) -> boot0 -> U-Boot -> fastboot
> # 2. board now enumerates as 1f3a:1010 "Allwinner ... fastboot mode"; `fastboot devices` shows it
> # 3. flash a correct STOCK env (boot_partition=bootA, root_partition=rootfsA) to BOTH copies:
> fastboot flash env        recovery_env_redund.img
> fastboot flash env-redund recovery_env_redund.img
> fastboot reboot                     # boots stock Tina/OpenWrt
> ```
> **Building the env image** (`recovery/recovery_env.txt` holds the exact stock vars):
> `u-boot-2024.10/tools/mkenvimage -r -s 0x20000 -o recovery_env_redund.img recovery_env.txt`
> (redundant format → header is `CRC + flags=0x01 ACTIVE`; size 0x20000; flash to **both** `env` p2 + `env-redund` p3 so a stale copy can't win the redundant selection.) This stripped fastboot has **no `oem setenv`/`getvar all`**, so flashing the env image is the way; `max-download-size = 0x02000000` (32 MB).
>
> **FEL access details (still valid):** hold **LOAD** at power-on → BootROM enters FEL (silent UART, waits for USB). Port = **front USB-A = USB0/DRD** (T113 ball **B7→D+, C7→D−**); VBUS there is a host load-switch output that doesn't reach the SoC, so use a **data-only A-to-A cable** into a Jetson USB-A host port; printer stays on its own 24 V. `sudo xfel version` confirms the link.
>
> **xfel capabilities (banked primitives):** reads/writes **all** MMIO + RAM, execs code, warm-reset. **DRAM-init-over-FEL works** with a patched `xfel ddr t113-s3` (the Hi's exact `dram_para`). Useful for future low-level work, but **not needed** for stock recovery.
>
> **⚠ Confirmed dead ends (do not retry):** FEL-booting **mainline U-Boot** (SPL via `sunxi-fel uboot`, or proper via `xfel exec`) — both *execute* (ARM entry verified) but die **pre-console**, every variant. And driving the **debug UART by hand via `xfel write32`** never transmits despite provably-correct registers (DesignWare busy-detect + floating RX + boot0's `fix vccio` IO-domain step that FEL skips). The vendor's own fastboot, above, sidesteps all of it.

---

## Method 1: `swupdate` `.swu` package (production path)

The printer ships with [swupdate v2019.11.0](https://github.com/sbabic/swupdate) at `/sbin/swupdate`. We use it the same way Creality's OTA does.

**Builder script:** [`tools/mkswu.sh`](../tools/mkswu.sh) — already tested, built a sample `.swu` at `kernel-workspace/build-output/creality_hi_test.swu`.

**Three modes** offered by the builder:

| Mode | What it writes | Touches boot env? | Risk |
|---|---|---|---|
| `kernel-only-B` | Just the kernel to `bootB` partition | **NO** — `boot_partition` stays `bootA` | **Zero** — printer keeps booting stock until you manually `fw_setenv` |
| `kernel` | Kernel to bootB + sets `boot_partition=bootB` + `swu_next=reboot` | YES | Medium — commits to new kernel on next boot, no auto-rollback |
| `kernel-and-rootfs` | Kernel to bootB + rootfs to rootfsB + env update | YES | Medium — full A/B swap |

**Usage example (safest path):**

```bash
# Build a kernel-only-B .swu (in WSL or Jetson)
bash tools/mkswu.sh kernel-only-B \
    kernel-workspace/build-output/creality_hi_custom_boot_ttyS4.img \
    kernel-workspace/build-output/test.swu

# Deploy
scp kernel-workspace/build-output/test.swu hi:/mnt/UDISK/
ssh root@<printer-ip> 'swupdate -i /mnt/UDISK/test.swu -e stable,kernel_only_B -l 4'
# (-l 4 = verbose; bumps swupdate log level)
```

After that runs, bootB has your new kernel. Printer boots stock on next reboot until you commit:

```bash
ssh root@<printer-ip> 'fw_setenv boot_partition bootB; reboot'
# (If anything goes wrong, recover with: fw_setenv boot_partition bootA, then power-cycle)
```

**Note on the script's shebang:** Because `/mnt/c/` is NTFS, Linux may ignore the `+x` bit. Always run via `bash tools/mkswu.sh ...` rather than `./tools/mkswu.sh`.

---

## Method 2: Fastboot — Android-style USB flashing

Your U-Boot environment confirms fastboot is compiled in:
```
boot_fastboot=fastboot
```

That means the U-Boot binary on this printer can enter Android fastboot mode. Once in fastboot, the printer exposes itself as a USB device, and the host runs the standard `fastboot` CLI to flash partitions.

**Entering fastboot — two paths:**

1. **From running Linux** (preferred — no UART needed):
   ```bash
   ssh root@<printer-ip> 'reboot fastboot'
   ```
   The kernel's reboot syscall passes the "fastboot" argument to U-Boot, which then enters fastboot mode instead of normal boot. **Works only if the printer's running kernel supports reboot-with-cmd-args** (it should — stock 5.4 has this).

2. **From U-Boot console** (needs UART access):
   ```
   sun8iw20p1# fastboot
   ```

Once the printer is in fastboot, on the host:

```bash
sudo apt-get install -y fastboot android-tools  # Linux
# OR: download Android platform-tools from developer.android.com (cross-platform)

fastboot devices              # confirm printer enumerated
fastboot getvar all           # see what variables U-Boot exposes
fastboot flash bootB /path/to/creality_hi_custom_boot_ttyS4.img
fastboot reboot               # back to normal boot
```

**Open questions to investigate when first trying fastboot:**

- **Which USB port to use**: the printer has a USB-A host port (for thumb drives). T113-S3's `usbc0@` is the OTG controller — typically the SAME port supports both host AND device modes. Need to confirm by `lsusb` from the host while printer is in fastboot.
- **VID/PID**: Allwinner U-Boot fastboot usually presents as `1f3a:1010` or similar. Add a udev rule if `fastboot devices` returns nothing.
- **Which partition names work**: try `fastboot getvar partitions` first. Creality may have customized the partition mapping. The names we know (`bootA`, `bootB`, `rootfsA`, `rootfsB`) are from GPT labels and should match what fastboot exposes.

**Why fastboot wins for risky tests:**

The printer is in fastboot **regardless of whether the kernel works**. If you flash a broken kernel and reboot, the printer attempts to boot it → fails → you don't have working SSH anymore — BUT you can `reboot fastboot` was already a one-shot, so to retry you'd need power-cycle-into-fastboot. That last step needs:

- Either UART access to U-Boot (we lose this protection if UART debug is the original problem)
- OR a hardware FEL trigger (next method)
- OR holding a fastboot button at power-on (which the Hi may not have)

So fastboot is **better than dd** for active flashing but still **requires a working kernel to enter fastboot from**. Pair with FEL as the bottom safety net.

---

## Method 3: FEL recovery mode — the brick-proof bottom (CONFIRMED PATH FOUND)

All Allwinner SoCs have a BootROM-implemented USB recovery protocol called **FEL** (or EFEX). It's literally in the SoC's mask ROM — you cannot brick this. As long as the SoC is alive and you can get it into FEL mode, you can write anything to RAM/eMMC.

**Tool**: [`sunxi-tools`](https://github.com/linux-sunxi/sunxi-tools), specifically `sunxi-fel`. Available in Ubuntu's `universe` repo:

```bash
sudo apt-get install -y sunxi-tools
```

⚠ **Build sunxi-fel from git, not the apt package** — the packaged version predates T113/R528 (sun8iw20) and won't recognize SoC ID `0x1859`:
```bash
sudo apt install -y libusb-1.0-0-dev libfdt-dev pkg-config build-essential git
git clone https://github.com/linux-sunxi/sunxi-tools && cd sunxi-tools && make
```

### Entering FEL — hardware method (CONFIRMED, works on a DEAD board) ✅✅

This is the method proven on the bricked board 2026-05-28, and it needs **no working OS, no SSH, no UART**:

1. Power the board OFF completely.
2. **Hold the LOAD button**, then apply 24 V power (keep holding ~2 s).
3. The BootROM enters FEL: **UART0 stays silent** (no `HELLO! BOOT0` banner) — that silence is the confirmation it's in FEL, not booting.
4. Connect a **data-only A-to-A cable** (VBUS/5 V wire cut) from the front USB-A jack to a Jetson **USB-A** port (not USB-C — that port is device/recovery-mode on the Orin Nano).
5. On the host: `sudo ./sunxi-fel ver` → expect `AWUSBFEX soc=00001859(R528)`.

The LOAD button is wired to the BootROM's FEL strap. Releasing it after power-on is fine — FEL persists until a host drives it or you power-cycle.

### Entering FEL — software RTC flag (secondary; requires a WORKING OS) ✅

The vendor RTC driver (`rtc-sunxi.c` in the vendor BSP) accepts named flags via a sysfs file. The flag is stored in battery-backed RTC RAM and consumed by BROM at next power-on:

```bash
# Write to this path on the printer:
/sys/devices/platform/soc@3000000/7090000.rtc/flag

# Accepted values:
echo debug             # 0x59 — debug mode
echo efex              # 0x5A — FEL / EFEX (full BROM recovery, USB-attached)
echo boot-resignature  # 0x5B
echo recovery          # 0x5C — recovery partition boot
echo sysrecovery       # 0x5D
echo usb-recovery      # 0x5E — USB-driven recovery
echo bootloader        # 0x5F — stay in U-Boot (likely fastboot-accessible)
echo uboot             # 0x60 — same as bootloader
```

**Triggering FEL on the live printer:**

```bash
ssh root@<printer-ip> 'echo efex > /sys/devices/platform/soc@3000000/7090000.rtc/flag; reboot'
# Now power-cycle (sometimes the soft reboot doesn't fully reset to BROM — pull power)
# Plug a USB cable: Jetson/WSL host ↔ printer's USB-A host port
sunxi-fel version
# Expect: "AWUSBFEX soc=0x00185900 ..."  (T113-S3's SoC ID)
```

The RTC flag is auto-consumed by BROM and cleared by U-Boot (Allwinner-standard behavior), so you exit FEL by issuing a normal `sunxi-fel exe` of a known-good boot image — or just power-cycling after the FEL session ends (BROM falls through to eMMC if no FEL host is talking to it within a few seconds).

### Other entry methods (backup)

- **Hardware button / pad short**: not yet identified on the Hi mainboard. Possible candidate is a small SMD button visible in your earlier mainboard photo — please send a close-up of the area around the SoC if curious.
- **Brick fallback**: BROM checks boot devices in order (SD → eMMC → NAND → USB-FEL). If BROM can't read a valid bootloader signature, falls through to FEL automatically. Listed for completeness — DO NOT deliberately corrupt the bootloader.
- **Allwinner LiveSuit / PhoenixSuit**: Windows GUI tools that wrap FEL. Useful if `sunxi-fel` CLI is hard.

### What you can do in FEL mode

```bash
# Detect the device
sunxi-fel version
sunxi-fel sid                    # read the SoC's unique ID

# RAM execution (no eMMC write — perfect for kernel testing!)
sunxi-fel write 0x40008000 our_zImage
sunxi-fel writel 0x...  ...      # set up DTB address etc.
sunxi-fel exe 0x40008000

# Boot a fresh U-Boot from FEL (gives you a normal U-Boot console via UART)
sunxi-fel uboot u-boot-sunxi-with-spl.bin
# Now you have a fresh U-Boot — can do mmc, env operations to repair eMMC

# Or read raw memory / partitions
sunxi-fel read 0x00000000 4096 dump.bin
```

**FEL is the unconditional brick-proof bottom layer.** Even if eMMC is corrupted, BROM is locked, U-Boot is missing — you can still recover via FEL.

### Confirmed recovery flow (2026-05-28) — U-Boot via FEL → console → eMMC

DRAM is **not** initialized in raw FEL (only the SRAM scratchpad at 0x45000), so the first move is to push a DRAM-capable U-Boot into the chip:

```bash
# Build once on WSL (toolchain already present):
#   U-Boot 2024.10, mangopi_mq_r_defconfig  (T113-s3 ARM, MACH_SUN8I_R528)
#   Its DRAM config already matches the Hi: CONFIG_DRAM_CLK=792, CONFIG_DRAM_ZQ=0x7b7bfb
#   (host deps: swig python3-dev bison flex libssl-dev)
make CROSS_COMPILE=arm-linux-gnueabihf- mangopi_mq_r_defconfig
make CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)     # -> u-boot-sunxi-with-spl.bin

# Then, board in FEL (LOAD held, 24 V, data-only A-to-A to Jetson USB-A):
sudo ./sunxi-fel uboot u-boot-sunxi-with-spl.bin       # SPL trains DRAM, runs U-Boot in RAM
# Console comes out on UART0 (CH340 @ 115200) — the interactive prompt Creality stripped.
# This is RAM-only; it does NOT touch the eMMC. If DRAM mistrains, just power-cycle and retry.
```

From that RAM U-Boot console:
```
mmc dev 2 ; mmc rescan ; mmc part        # enumerate eMMC partitions
# then EITHER expose the whole eMMC to the host as a USB block device:
ums 0 mmc 2                              # Jetson sees a block dev -> dd factory images back, or write v2
# OR write directly / fix the boot env:
#   mmc write <addr> <blk> <cnt>   /   setenv boot_partition bootA ; saveenv
```

While in that console, **dump the real vendor boot0 from eMMC** — it carries the exact `dram_para` (which is NOT in any OTA package, only on the eMMC) for a perfect permanent SPL later. Same flow pre-flashes the RMA board without swupdate.

### Pre-flight safety setup (do this BEFORE you need it)

Before running anything risky (like flipping `boot_partition=bootB`), install + verify sunxi-fel works on your host:

```bash
# On Jetson AND WSL:
sudo apt-get install -y sunxi-tools

# udev rule for FEL device (sometimes needed for non-root access)
sudo tee /etc/udev/rules.d/99-sunxi-fel.rules <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="1f3a", ATTR{idProduct}=="efe8", MODE="0664", GROUP="dialout"
EOF
sudo udevadm control --reload-rules

# Confirm tool runs
sunxi-fel --help
```

Then **as a dry test** (no actual flashing, no risk):

```bash
# On the printer:
ssh root@<printer-ip> 'echo efex > /sys/devices/platform/soc@3000000/7090000.rtc/flag'
# DO NOT reboot yet — just check the flag persists:
ssh root@<printer-ip> 'cat /sys/devices/platform/soc@3000000/7090000.rtc/flag'
# Should now show 0x5A
# To cancel (don't actually go into FEL):
ssh root@<printer-ip> 'echo > /sys/devices/platform/soc@3000000/7090000.rtc/flag'
# Or echo 0:
ssh root@<printer-ip> 'cat /sys/devices/platform/soc@3000000/7090000.rtc/flag'
# Should show 0x0
```

Once you've verified you can set/clear the flag and that sunxi-fel is installed, you have FEL recovery available on demand.

---

## Recommended workflow for Phase 1.3

Given everything we've learned:

1. **First test: `mkswu.sh kernel-only-B` + `dd`** (what we've been doing) — writes to inactive partition, zero risk. We've done this. ✓

2. **Phase 1.3 attempt: `swupdate -e stable,kernel_only_B` + manual UART-console boot via U-Boot interactive `bootm`** — needs UART working. Currently blocked.

3. **Bed-MCU UART workaround (next step)** — disconnect bed MCU, use ttyS4-console bootimg already built (`creality_hi_custom_boot_ttyS4.img`). Try the boot test via that.

4. **If bed-MCU UART works**: confirm kernel boots, then `fw_setenv boot_partition bootB` to commit. If anything goes wrong, set back to `bootA` from SSH.

5. **If bed-MCU UART also fails**: pivot to fastboot. From WSL/Jetson:
   ```bash
   ssh root@<printer-ip> 'reboot fastboot'
   # then from the host with USB cable to printer:
   fastboot flash bootB creality_hi_custom_boot_ttyS4.img
   fastboot reboot
   ```
   No UART debug = trust the kernel's behavior. If it doesn't boot, repeat: `reboot fastboot` from a recovery procedure (need to confirm what to do here).

6. **FEL is the catchall** — investigate the trigger BEFORE you actually need it, so when you need it you're not panic-Googling.

---

## TL;DR for the next session

- ✅ `tools/mkswu.sh` works — `.swu` packages can be built any time
- 🟨 Fastboot: confirmed compiled into U-Boot, but path-to-entry from a non-working kernel isn't verified yet
- ✅ **FEL: CONFIRMED working on a bricked board.** Trigger = hold **LOAD** at power-on; port = **front USB-A (USB0/DRD)**, data-only A-to-A cable to a Jetson USB-A port; `sunxi-fel ver` → `soc=00001859(R528)`. Build sunxi-fel from git (apt version too old for T113).
- ⏭ Next: build `u-boot-sunxi-with-spl.bin` from `mangopi_mq_r_defconfig` (DRAM already matches: CLK=792, ZQ=0x7b7bfb), `sunxi-fel uboot` it → real console → `ums`/`mmc write` to recover. Build needs host pkgs `swig python3-dev`.

The brick-proof bottom is no longer theoretical — it's been driven end-to-end through `ver` + `sid`. The only remaining step is the U-Boot binary, which is a pure build task.
