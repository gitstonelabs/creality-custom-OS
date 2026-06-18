# gitStoneLabs Workspace Changelog

Every meaningful change to documents, kernel config, rootfs, or significant project state lands here. Format follows [Keep a Changelog](https://keepachangelog.com/) loosely — newest entries on top.

Document versions are tracked with a header like `Version: X.Y — YYYY-MM-DD` at the top of each `.md` file. When a document is significantly updated, the previous version is copied to `docs/archive/<basename>_vX.Y_YYYY-MM-DD.md` and the new version increments and notes its changes here.

---

## [Unreleased] — work in progress

### Ground-truth reference doc added: stock Hi target contract (2026-06-17)
Verified against the official V1.1.0.50 release images (OTA plus IMAGEWTY uart0). New `docs/ground_truth.md` records the authoritative facts a custom OS must match: the eMMC partition table, the stock kernel (Linux 5.4.61), the Android bootimg v2 boot contract (load `0x40008000`, empty cmdline, v2 dtb section), the DTB compatible (`allwinner,t113_i` / `sun8iw20p1`), the exact DDR3 DRAM training parameters, the four out-of-tree `.ko` the 6.6 port must reproduce, and the no-rollback A/B install rule. No Creality blob is stored, only the extracted contract. Open item flagged: the live on-eMMC DTB placement (appended versus v2-section) is not yet dumped.

### ✅ Privacy lockdown: stock Hi egress restricted to LAN-only (2026-05-31) — Creality cloud cut off
Blocked all off-LAN/Creality communication on the modded-stock OS.
- **Caught phoning home:** an MQTT session `<printer-ip> -> 47.253.214.226:1883` (Alibaba Cloud = Creality Cloud) + `ntpd` to `ntp5.aliyun.com`.
- **No firewall to use:** Creality stripped `iptables`/`nft`/`fw3` entirely. Solution = **blackhole routes** (full iproute2 is present, supports them; box has no IPv6). `0.0.0.0/1` + `128.0.0.0/1` cover all IPv4 and beat the `/0` default; RFC1918 routed via the gateway keeps the LAN working. DNS already goes to the local router (`<router-ip>`), so name resolution survives.
- **Tooling:** `/usr/bin/lan-lockdown {on|off|status}`. Persistence: `/etc/hotplug.d/iface/99-lan-lockdown` (re-apply on ifup = boot + restarts) + `/etc/rc.local` + `/etc/lan-lockdown.on` flag.
- **Verified:** `8.8.8.8`, `47.253.214.226`, `www.creality.com`, aliyun NTP all blocked; gateway + SSH + local services fine; **all external ESTABLISHED connections gone**.
- Trade-offs noted to user: NTP blocked → clock drift (no RTC batt); Creality app/cloud dead (intended); `opkg`/`pip` need `lan-lockdown off` first. Setup script: `~/setup-lockdown.sh`. Backstopped by fastboot recovery.

### ✅ Entware package manager live on the stock Hi (2026-05-31) — undoes Creality's stripped opkg/busybox
Restored full "install software" capability that Creality removed (no `opkg`, dead/musl-incompatible feeds, cut-down busybox), without touching the stock rootfs.
- **Diagnosis:** `opkg` binary deleted; configured feeds dead (custom target URL 404 + official feed is *musl* while system is *glibc 2.29 armhf*); no `wget`/`curl`/`uclient-fetch` at all. Present: `python3`, `pip3`, `strace`, `tar`. 5 GB free on `/mnt/UDISK`.
- **Fix = Entware** (`armv7sf-k3.2`, self-contained glibc-2.27 in `/opt`, independent of the system libc). Installed to **`/opt` → `/mnt/UDISK/entware`** (UDISK-backed). Bootstrap hurdle (no downloader on board) solved with a **python3 `wget` shim**; the static bootstrap `opkg` then installed the real Entware `opkg` + base, then `wget-ssl`/`git-http`/`nano`/`htop`/`openssh-sftp-server` (35 pkgs). `/opt/bin/wget` later repointed shim→real `wget-ssl`.
- **Verified by running binaries:** opkg 2025.11, git 2.50.1, nano 8.7.1, htop 3.4.1, wget 1.25.0 — proving the Entware environment runs cleanly on the hard-float system.
- **Persistence:** `/opt` symlink + UDISK partition + `/etc/profile` PATH + `/etc/init.d/entware` (S99, rc.unslung). **`scp` into the board fixed** (`/usr/libexec/sftp-server` → Entware's). Reversible (`rm -rf /mnt/UDISK/entware /opt …`). Scripts in `~` (install-entware.sh, configure-entware.sh, fix-wget2.sh).
- Now two install paths for the user: `opkg` (system tools/libs/compilers) + `pip3` (Python/Klipper).

### ✅ CAN + USB-serial added to the STOCK kernel as loadable modules (2026-05-31) — no reflash, reboot-persistent
Enabled the drivers Creality compiled out, **without** replacing the kernel — confirmed live + auto-loading across a real reboot.
- **Stock kernel = 5.4.61**, `CONFIG_MODULES=y`, **`MODVERSIONS` off** → modules only need a matching *vermagic* (`5.4.61 SMP preempt mod_unload ARMv7 p2v8`), no symbol CRCs. Stock `.config` came from the board's own `/proc/config.gz` (`CONFIG_IKCONFIG_PROC=y`).
- **Already on stock (surprise):** `CONFIG_USB_SERIAL=y` + `CONFIG_USB_SERIAL_CH341=y` — CH340/CH341 work out of the box. The plan's "no CH341" note was wrong.
- **Built 11 `.ko`** against the vendor BSP `linux_kernel_aw_t113` (5.4.61): `can/can-raw/can-dev/gs_usb/slcan/vcan` (CAN, incl. BTT U2C) + `cdc-acm/cp210x/ftdi_sio` (USB-serial). Build gotchas recorded: `KCFLAGS=-march=armv7-a` (GCC-13 `cc-option` fell back to armv5t → `strex` assembler error), disable the GCC-13-incompatible vendor drivers (`AIC_WLAN_SUPPORT`, `AIC8800_*`, `CRYPTO_DEV_SUNXI`, `TOUCHSCREEN_GT9XXNEW_TS`) so the global modpost can run, and `touch .scmversion` to drop the `+` localversion suffix.
- **Deployed live** to <printer-ip> (`ssh root@<printer-ip>`, tar-over-ssh since dropbear has no sftp-server) → `install_hi_modules.sh` copies to `/lib/modules/5.4.61/`, insmods in dep order, writes `/etc/modules.d/{can,usb-serial-extra}`. **Reboot test passed:** board back in ~27 s (uptime 0 min), all common modules auto-loaded via `/sbin/kmodloader` (same mechanism as stock WiFi/touch; OpenWrt has no `depmod` — `kmodloader` resolves deps from `.ko` modinfo). `slcan`/`vcan` left for on-demand `modprobe` (no-ops until configured).
- Reusable recipe + artifacts in `recovery/stock-modules/`. Reversible (`rmmod`), backstopped by the fastboot recovery.

### 📦 Community repos assembled (unpublished) — `creality-hi-recovery` + `creality-hi-toolkit` (2026-05-31)
Two self-contained, shareable repos in the workspace (built locally; **nothing pushed**, per the don't-publish-until-tested rule):
- **`creality-hi-recovery/`** (MIT) — un-brick a Hi to stock over USB. Full README + `scripts/recover.sh` + `env/{recovery_env.txt,recovery_env_redund.img,build-env.sh}` + `docs/{fel-access,rtc-bootmode,how-it-works}.md`.
- **`creality-hi-toolkit/`** (GPL-2.0) — CAN + USB-serial on the stock kernel. README + prebuilt `modules/5.4.61/*.ko` + `install_hi_modules.sh` + `modules/BUILD.md` (full from-source recipe). LICENSE notes to paste the canonical GPL-2.0 text before publishing.

### ✅✅✅ BRICKED HI FULLY RECOVERED TO STOCK (2026-05-31) — RTC-flag → vendor fastboot → env flash
The v1-`.swu`-bricked mainboard is **back to 100% stock** (`Creality Hi-5109 login`, Tina 5.0 / OpenWrt 21.02, WiFi up). The winning path — proven end-to-end on hardware — was far simpler than the FEL/U-Boot/UART rabbit hole:

- **Root cause confirmed:** the v1 `.swu` only set `boot_partition=bootB` + `root_partition=rootfsB` and wrote custom images to the B side. Stock **bootA/rootfsA were always intact**; boot0 + the boot-pkg U-Boot were never touched. Recovery = put the env's selector back to the A side.
- **THE canonical Hi recovery procedure now:**
  1. Enter FEL (hold LOAD at power-on).
  2. `xfel write32 0x07090118 0x5F` — set the **RTC boot-mode flag** to *fastboot*. (RTC GPR[6] = base `0x07090000` + `0x100` + 6×4; index 6 confirmed by the live device DTS `gpr_cur_pos=0x06` and the T113 vendor BSP `rtc-sunxi.c`.)
  3. `xfel reset` — **warm** reset preserves the RTC always-on domain.
  4. Vendor boot0/U-Boot reads the flag → enters **fastboot** (`lsusb` → `1f3a:1010 Allwinner … fastboot mode`).
  5. `fastboot flash env recovery_env_redund.img` + `fastboot flash env-redund …` + `fastboot reboot` → **stock boot.**
  - Flag values (one-shot; boot0 clears after read): **efex/FEL `0x5A`, recovery `0x5C`, fastboot `0x5F`.** This is a **general soft-brick safety net** for any Hi whose boot0 + boot-pkg are intact.
- **The env image:** reconstructed the fresh board's exact stock `fw_printenv` (already `boot_partition=bootA`/`root_partition=rootfsA`) → `u-boot-2024.10/tools/mkenvimage -r -s 0x20000` (redundant, header `CRC + flags=0x01 active`). Flashed to **both** `env` (p2) and `env-redund` (p3) so neither stale copy wins the redundant-selection. Artifacts: `recovery/recovery_env.txt`, `recovery_env_redund.img` (+ `_plain.img` fallback).
- **Residual (harmless):** bootB/rootfsB still hold the dormant v1 custom images; inactive since the board boots the A side. A Creality OTA or a deliberate fastboot re-flash would refresh them.
- **Dead ends (recorded so we don't repeat them):** FEL-booting mainline U-Boot (SPL via sunxi-fel + proper via xfel) — both *execute* (ARM entry confirmed) but die pre-console; and raw UART0 TX via `xfel write32` never transmitted despite perfect register config (DesignWare busy-detect + floating RX + boot0's `fix vccio` IO-domain step that FEL skips). Still-useful primitives banked: xfel reads/writes **all** MMIO+RAM and execs code; **DRAM-init-over-FEL works** (patched `xfel ddr t113-s3`). None were needed for the actual fix.

### ⭐⭐ FEL DRAM-init recovery PROVEN via xfel — bricked-board recovery ~90% (2026-05-31 bench)
- **Fresh never-powered Hi board** booted stock (READ-ONLY) and gave the missing pieces:
  - **Exact vendor `dram_para`** (from boot0 hexdump @ eMMC 8 KB): clk=792, DDR3, zq=0x7b7bfb, **odt_en=1**, **para1=0x10f2**, **para2=0x02000000**, mr0=0x1c70 / mr1=0x42 / mr2=0x18 / mr3=0, tpr0–10 standard, **tpr11=0x770000**, **tpr12=0x2**, **tpr13=0xb4056103**.
  - `fw_printenv`: **NO bootcount/bootlimit/altbootcmd** → the v2 `.swu` watchdog is INERT on stock U-Boot (FEL is the real safety net). bootcmd=`run setargs_nand boot_normal`, bootdelay=0, fastboot present, version=1.1.0.47, board=CR4NU200360C20.
  - Real `fw_env.config`: **`/dev/by-name/env` + `/dev/by-name/env-redund`** (mmcblk0p2/p3, 0x20000) — NOT the `env0/env1` the v2 design guessed (v2 rootfs fw_env.config needs this fix).
  - Full partition map (p1 boot-resource … p11 UDISK) + the 6 proprietary `.so` confirmed (box / filament_rack / motor_control / serial_485 / prtouch_v2 / prtouch_v3).
- **sunxi-fel can't run the T113 SPL** (executes but no serial, no FEL-return). Pivoted to **xfel** (xboot) — purpose-built for D1/T113/R528.
- xfel's built-in `ddr` profiles (t113-s3 / r528-s3 / t113-s4) HANG training — they carry the generic MangoPi params (the same wrong values as mainline U-Boot). **Patched xfel `chips/r528_t113.c` t113-s3 preset with the Hi's exact `dram_para`** (`patch_xfel_ddr.py`), rebuilt xfel on the Jetson → **`xfel ddr t113-s3` trains DRAM; `read32 0x42e00000` = `0xdeadbeef`. FEL DRAM-init CONFIRMED WORKING.**
- **Bricked board recoverable to STOCK with NO re-flash**: stock bootA/rootfsA are intact; only the boot selector points at the broken bootB. Recovery = flip `boot_partition=bootA` in the vendor env. No Creality/button shortcut (wipe_all needs the OS, which is why it failed).
- **Remaining step (PAUSED):** get a U-Boot console via FEL to write the env. `xfel exec u-boot.bin` (loaded to DRAM 0x42e00000) runs (CPU leaves FEL) but is silent — U-Boot *proper* standalone lacks the SPL's `clock_init` (UART clock wrong / early crash), and the SPL can't be xfel-run as-linked (0x20060 clobbers the live FEL; FEL stack ~0x21400; xfel's own payloads load at 0x28000). Resume options in task #50: (1) CONFIG_DEBUG_UART diagnostic, (2) relink SPL to 0x28060 + chain to pre-loaded U-Boot, (3) FEL bootscript `setenv boot_partition bootA`.
- New artifacts in `recovery/uboot-fel/` (synced to Jetson): `u-boot.bin` (DT console → UART0/PF2/PF4), `u-boot-sunxi-with-spl.bin`, `sunxi-spl.bin`, `patch_xfel_ddr.py`, `patch_uboot_dt.py`. Patched **xfel** at `~/xfel` on the Jetson; **sunxi-tools** at `~/sunxi-tools`.
- Tooling fixed this session: CH340 on Jetson (built `ch341.ko` out-of-tree for L4T 5.15, removed `brltty`); confirmed front USB-A = USB0/DRD (B7→D+, C7→D−); LOAD button = FEL strap.

### ⭐ FEL recovery breakthrough (2026-05-28 session, hardware)
- **Confirmed FEL (BootROM USB recovery) works on the bricked Hi board with no OS.** Trigger = hold **LOAD button** at power-on (BootROM strap → board goes silent on UART, waits for USB). Port = **front USB-A jack**, which is physically wired to **USB0 / DRD** — confirmed by lifting the T113 on the sacrificial board and buzzing **B7 (USB0-DP) → D+** / **C7 (USB0-DM) → D−**.
- USB-A VBUS is a host load-switch output (5-pin switch + ESD array) and does **not** reach the SoC → FEL uses a **data-only A-to-A cable (VBUS/5 V wire cut)** into a Jetson **USB-A** host port (NOT USB-C — device/recovery on Orin Nano); printer self-powered on 24 V.
- `sudo sunxi-fel ver` → `AWUSBFEX soc=00001859(R528)` (sun8iw20p1; R528 = T113 sibling, same silicon). `sunxi-fel sid` → `93403400:4c004814:0104d908:18561215` (eFUSE read OK).
- Built `sunxi-tools` from git (v1.4.2-205-g3035186) on the Jetson — the apt package is too old to know SoC ID 0x1859. Needed `libfdt-dev` to compile the `sunxi-fel` target.
- Also fixed CH340 USB-serial on the Jetson (JetPack 6.2 / L4T R36.5, kernel 5.15.185-tegra strips `ch341`): built `ch341.ko` out-of-tree against `nvidia-l4t-kernel-oot-headers`, and **removed `brltty`** (it was hijacking the CH340 / would hijack FTDI too). UART0 console now confirmed via CH340 @ 115200 — captured full BOOT0→OP-TEE→"Starting kernel" log; Creality's U-Boot has its interactive console stripped (no prompt, key presses only logged).
- **Net result:** the "bricked" board is recoverable without RMA, and every future flash is backstopped by FEL. `swu_v2_design.md` open-question #1 (U-Boot watchdog) is moot for recovery — FEL is the real safety net.

### U-Boot-via-FEL build (built)
- Downloaded U-Boot **2024.10** to WSL `~/u-boot-2024.10`. `mangopi_mq_r_defconfig` is the **T113-s3 ARM** variant (`CONFIG_ARM=y`, `CONFIG_MACH_SUN8I_R528=y`, DT `sun8i-t113s-mangopi-mq-r-t113`) and its DRAM config **already matches the Hi**: `CONFIG_DRAM_CLK=792`, `CONFIG_DRAM_ZQ=8092667 (0x7b7bfb)`. ODT differs (MangoPi `ODT_EN=0` vs Hi boot-log ODT 0x42) — to revisit only if training is flaky.
- Established that `dram_para` is **NOT** in any artifact we have: `boota.bin` = kernel bootimg; the OTA `.img` files are cpio (newc, magic `070702`) carrying only kernel/rootfs/second-stage uboot; boot0 lives only on the eMMC (OTA never reflashes it). So the bootstrap plan is MangoPi config → FEL → console → dump real boot0 from eMMC for exact params.
- **Built `u-boot-sunxi-with-spl.bin`** (469,804 bytes, sha256 `74491c43…842efb`; DT `sun8i-t113s-mangopi-mq-r-t113`) after adding host deps `swig python3-dev uuid-dev libgnutls28-dev libssl-dev` (U-Boot 2024.10 `tools` target needed pylibfdt+swig, then uuid/gnutls for `mkeficapsule`). Staged to `recovery/uboot-fel/` with `README.md` + `SHA256SUMS`. Next: sync to the Jetson, `sunxi-fel uboot` it → real U-Boot console on UART0 (CH340) → `ums`/`mmc` recover the eMMC.

### Modified (2026-05-28 session, docs)
- `docs/recovery_methods.md` → v1.0 (added version header; replaced stale "FEL trigger unknown" content with the confirmed LOAD-button + front-USB-A method, the git-build note for sunxi-tools, and the U-Boot-via-FEL recovery flow; updated TL;DR). Pre-versioning copy archived as `docs/archive/recovery_methods_v0_pre-versioning_2026-05-28.md`.


### Added (2026-05-28 session, late)
- `reverse-engineering/proprietary-replacements/auto_addr.py` v1.0 — clean GPL-3.0 translation of `auto_addr_wrapper.py` (696 lines → ~600 lines clean Python). CFS auto-addressing protocol for MB (CFS box), CLM (S42C closed-loop motor), BTM (belt-tension motor). Function codes 0xA0/A1/A2/A3/0x0B. Three-method allocation: UID match → first free slot → override offline mismatched. Bug-fix vs source: variable-shadowing in `set_addr_table`. Persistent UID storage in printer.cfg `[auto_addr]` section.
- `reverse-engineering/proprietary-replacements/prtouch_v3.py` v1.0 — finalized from device-extras `protouch_v3.py` (324 → 480 lines). All 4 cleanup items from prtouch_v3_analysis.md applied: dropped unused `math`/`socket` imports, made `get_temp_compensate` an explicit alias of `get_temperature_compensate`, DRY'd placeholder G-codes via `_make_placeholder_handler`, made `pres_clk_pin` configurable (was hardcoded `'PC15'`). Proper `logging.getLogger(__name__)` instead of printf-style `[PRTOUCH_V3]`.
- `reverse-engineering/proprietary-replacements/archive/prtouch_v3_v0.8_2026-05-28.py` — preserved pre-cleanup version.
- `docs/swu_v2_design.md` v1.1 — bumped from v1.0 with implementation-status table reflecting features 1/2/4 done, feature 3 deferred to v2.1, feature 5 still Phase 2.6. Implementation map added showing which file ships which feature.
- `docs/archive/swu_v2_design_v1.0_2026-05-28.md` — preserved pre-implementation design.
- `rootfs/board/creality/hi/rootfs-overlay/usr/local/bin/gitstonelabs-bootcount-reset.sh` — userspace half of the U-Boot watchdog rollback. Calls `fw_setenv bootcount 0` after multi-user.target.
- `rootfs/board/creality/hi/rootfs-overlay/etc/systemd/system/gitstonelabs-bootcount-reset.service` — oneshot Type=oneshot RemainAfterExit=yes.
- `rootfs/board/creality/hi/rootfs-overlay/usr/local/bin/gitstonelabs-heartbeat.sh` — bed-MCU side-channel heartbeat. Emits `0x55 0xAA <wallclock & 0xFF>` to `/dev/ttyS3` @ 230400 every 2 s. Yields when Klipper opens the port.
- `rootfs/board/creality/hi/rootfs-overlay/etc/systemd/system/gitstonelabs-heartbeat.service` — Type=simple, After=systemd-udev-settle.service, Before=klipper.service, Restart=on-failure.

### Modified (2026-05-28 session, late)
- `rootfs/board/creality/hi/scripts/post-build.sh` — added `enable_unit` calls for the two new gitstonelabs services and `chmod +x` for both shell scripts.
- `rootfs/board/creality/hi/scripts/make-swu.sh` — v2 changes: (1) added `KERNEL_CMDLINE` with `console=ttyS3,115200 console=ttyS4,115200 console=ttyS5,115200 console=ttyS0,115200 loglevel=7 earlyprintk` passed via `--cmdline` to mkbootimg, (2) calls new `kernel-and-rootfs-watchdog` mkswu mode, (3) output renamed to `creality-hi-v2.swu`, (4) also builds companion `creality-hi-v2-kernel-only.swu` for safer smoke-testing, (5) bumps `SWU_VERSION` default to `0.2-gitstonelabs-*`.
- `tools/mkswu.sh` — new mode `kernel-and-rootfs-watchdog` that injects `bootcount=0`, `bootlimit=3`, `altbootcmd=<symmetric flip back>` plus `upgrade_available=1` into the swupdate `bootenv:` block, for both `now_A_next_B` and `now_B_next_A` directions. Risk noted in usage: best-effort if vendor U-Boot has stripped `CONFIG_BOOTCOUNT_LIMIT`.
- `rootfs/board/creality/hi/rootfs-overlay/etc/fw_env.config` — NEW. Tells target `fw_setenv` where the U-Boot env partitions live. Best-guess values (`/dev/by-name/env0`/`env1`, 0x20000 size each); doc-noted as unverified pending live-printer probe. Without this, `fw_setenv` silently fails and the bootcount watchdog never resets.
- `rootfs/configs/creality_hi_defconfig` — added `BR2_PACKAGE_UBOOT_TOOLS=y` + `BR2_PACKAGE_UBOOT_TOOLS_FWPRINTENV=y` to ship `fw_setenv`/`fw_printenv` into the target rootfs (required by the bootcount-reset service). Was previously only `BR2_PACKAGE_HOST_UBOOT_TOOLS=y` for host-side build tooling.

### Added (2026-05-28 session, early)
- `docs/CHANGELOG.md` v1.0 — this file
- `docs/archive/` directory for preserved old document versions
- `docs/octopus_v1_1_setup.md` v1.0 — full BTT Octopus + CFS + S42C bringup guide on Jetson Orin Nano (~250 lines)
- `rootfs/board/btt-octopus/printer.cfg.example` v1.0 — Klipper config template with X/Y/Z/Z1 steppers, EBB42 over CAN, CFS, S42C placeholder
- `rootfs/board/btt-octopus/README.md` v1.0 — board pin reference + setup pointer
- `reverse-engineering/proprietary-replacements/archive/steer_v0.0-stub_2026-05-28.py` — preserved stub before v1.0 implementation
- `reverse-engineering/proprietary-replacements/steer.py` v1.0 — full clean GPL-3.0 implementation of `steer_wrapper`, derived from device-extras source, with bug fixes (disable_heartbeat typo, LENGTH_ERR state table extended, is_shutdown initialization, retry counter logic)
- `reverse-engineering/proprietary-replacements/external_material.py` v1.0 — clean GPL-3.0 implementation of the CFS RFID reader from device-extras source
- `docs/swu_v2_design.md` v1.0 — design doc for v2 safety features (multi-UART console, watchdog, recovery initramfs, heartbeat, AIC8800 deferral)

### Discovered + leveraged
- `reverse-engineering/device-extras/` contains the **actual Python source** for several Creality wrapper modules — pulled from the printer's running filesystem during earlier reverse-engineering work:
  - `steer_wrapper.py` (239 lines) — basis for our `steer.py` v1.0
  - `external_material_wrapper.py` (62 lines) — basis for our `external_material.py` v1.0
  - `auto_addr_wrapper.py` (696 lines) — basis for our `auto_addr.py` v1.0
  - `prtouch.py` (818 lines) — basis for `prtouch_v3.py` v1.0

### Built (2026-05-28 session, final stretch)
- **`~/buildroot-creality-hi-out/images/creality-hi-v2.swu`** — 39.5 MB. Full v2 kernel+rootfs+watchdog. SWU_VERSION = `0.2-gitstonelabs-20260528-135021`.
- **`~/buildroot-creality-hi-out/images/creality-hi-v2-kernel-only.swu`** — 7.3 MB. Kernel-only smoke-test (writes bootB only, no env flip).
- Verified inside artifacts: bootimg cmdline = `console=ttyS3,115200 console=ttyS4,115200 console=ttyS5,115200 console=ttyS0,115200 loglevel=7 earlyprintk` (multi-UART, ttyS0 last so it wins as primary). Rootfs ships `/usr/sbin/fw_setenv` + `/usr/sbin/fw_printenv` (symlinked, glibc, ~64 KB each), `/etc/fw_env.config` with best-guess env0/env1 layout, `/etc/systemd/system/gitstonelabs-{bootcount-reset,heartbeat}.service` enabled (multi-user.target.wants/), `/usr/local/bin/gitstonelabs-*.sh` both executable, `/etc/gitstonelabs-release` build-stamp.
- sw-description inside v2.swu has the watchdog bootenv block (bootcount=0, bootlimit=3, altbootcmd=<symmetric flip back>, upgrade_available=1) for both `now_A_next_B` and `now_B_next_A` directions.

### Added (2026-05-28 session, end)
- `docs/v2_flash_quickref.md` v1.0 — one-screen reference for installing v2 once hardware is available. Pre-flight, two-step smoke-test procedure (kernel-only-B first, then full flash), failure-mode debug walkthrough, UART recovery instructions, build/rebuild commands.

### In flight
- v2 hardware test (Task #48) — gated on the Creality RMA replacement board arrival (expected Friday). Pre-flight: snapshot stock partitions, capture stock `/etc/fw_env.config` for comparison with our best-guess, verify vendor U-Boot honors `CONFIG_BOOTCOUNT_LIMIT`.
- Recovery initramfs (Task #49, v2.1) — punted to v2.1. Most complex piece (busybox+dropbear+fw_setenv as static binaries, /init script reading SW3 GPIO, CDC ACM gadget bringup); benefits from validating simpler features first.
- `box.py`, `filament_rack.py`, `motor_control.py` — stubs in place; underlying `.so` source not in device-extras so completion requires actual hardware traces. Possible after Octopus + CFS + S42C is wired.

### Hardware status
- Creality Hi bricked board — work paused, awaiting RMA replacement (expected Friday)
- BTT Octopus V1.1 — ready to wire on Jetson Orin Nano
- Cable Matters USB-Eth adapter — confirmed RTL8152, works on mainline kernel
- Waveshare FT232 USB-TTL — confirmed (saw garbage on J65 at 115200, signal present, baud rate not yet pinned down)
- ST-Link V2 — ready for Phase 4 bed-MCU work (GD32F303 SWD on J2)

---

## 2026-05-26 — Live printer flash attempt

### Status
- Custom kernel + rootfs.swu installed successfully (swupdate reported success, env flipped to bootB/rootfsB)
- Printer rebooted into custom kernel
- Printer never appeared on router DHCP table after reboot — comm lost
- AIC8800 WiFi driver not ported to kernel 6.6, so WiFi unreachable
- Cable Matters USB-Eth adapter present but cannot confirm whether r8152 driver loaded and dhcpcd ran (no comm channel)
- UART debug never established (long story — wrong header chased multiple times, J65 finally identified correctly but signal still not making it through)
- Printer effectively bricked from user-recovery standpoint until Creality RMA or hardware mod
- RMA request submitted to Creality support (separate from GPL ticket)

### Lessons captured
- J65 (top-middle 3-pin header) is the labelled SoC UART — but signal level/buffering not confirmed working
- L-X (top-left 3-pin) is X-limit switch input, NOT UART (corrected mid-session)
- J61 (4 pads behind front USB-A) is a parallel duplicate of the host USB-A jack, NOT OTG breakout
- `usbc0` OTG controller pins are not broken out to any accessible header on this board
- No SPI NAND chip footprint anywhere on the board (cannot use Phase 6 SPI-NAND recovery path)
- No USB MUX / switch IC anywhere near USB-A (Front USB-A is hard-wired to `ehci0` host-only)

### Files
- `docs/two_step_flash_plan.md` — documented procedure used for the flash
- `docs/otg_tp_probe_procedure.md` — backup TP probing procedure (untested, pending new board)
- `docs/board_connector_legend.md` — updated with confirmed pin mappings + chip IDs

---

## 2026-05-24 — Phase 2 Buildroot brought up end-to-end

### Status
- BR2_EXTERNAL tree fully wired
- Bootlin arm-glibc toolchain installs clean
- Linux 6.6 builds via `LINUX_OVERRIDE_SRCDIR`
- Full userspace builds: systemd, dropbear, nginx, klipper, moonraker, fluidd, creality-cfs-klipper
- Resulting `creality-hi.swu` (39.4 MB) drops-in-installable via stock swupdate
- AIC8800 WiFi driver deferred (kernel 6.6 cfg80211 API porting needed)
- 8 Buildroot 2022.02 + glibc 2.39 incompatibilities found and fixed (documented in SESSION_HANDOFF.md)

### Files
- `rootfs/configs/creality_hi_defconfig`
- `rootfs/scripts/br_make.sh`, `patch-buildroot-linux-mk.sh`, `install-udevadm-wrapper.sh`
- `rootfs/patches/host-systemd/0001-dbus-exporter-skip-on-error.patch`
- `~/buildroot-creality-hi-out/images/creality-hi.swu` (built, ready)
- `~/buildroot-creality-hi-out/images/creality-hi-kernel-only.swu` (built)

---

## 2026-05-24 — CFS Klipper repo v1.1.0 follow-up committed locally

### Status
- Commit `60918ca` in `repos/creality-cfs-klipper/` — T0-T3 macros, full CFS_PRINT_END, INSTALL.md, BRAND.md, USB-RS485 wiring docs
- 5 files / 703 insertions
- **NOT PUSHED to origin/main** — pending tested-working before publish per user policy

---

## 2026-05-23 — Phase 0 complete (kernel + DTS + defconfig)

### Status
- pinctrl-sun8iw20 + 3 CCUs ported from vendor BSP into linux-6.6 tree
- sun8i-t113s-creality-hi.dts — 445 lines, builds clean
- creality_sunxi_defconfig — 210 lines, makes clean zImage + DTB + 33 modules
- Android bootimg v2 + swupdate cpio packaging contract reverse-engineered
- Recovery infrastructure: 4-layer plan (swupdate / dd / fastboot / FEL)

### Files
- `kernel-workspace/dts/sun8i-t113s-creality-hi.dts`
- `kernel-workspace/defconfigs/creality_sunxi_defconfig`
- `kernel-workspace/build-output/creality_hi_custom_boot.img` + ttyS4 variant
- `tools/mkbootimg_creality.py`, `tools/mkswu.sh`
- `docs/recovery_methods.md`
- `docs/networking_and_recovery_plan.md`

---

## Versioning rules

For every doc update from this point forward:

1. **Read the current doc**, note its current `Version: X.Y` header
2. **Copy the current file** to `docs/archive/<basename>_v<X.Y>_<YYYY-MM-DD>.md`
3. **Update the live doc** with bumped version `X.Y+0.1` (minor) or `X+1.0` (major), update the date
4. **Add an entry here** in the CHANGELOG under [Unreleased] describing the changes
5. When a logical milestone hits, the [Unreleased] section graduates to a dated section here

If a doc has no `Version:` header yet, the first time we touch it we add `Version: 1.0 — <date>` and archive the pre-versioned copy as `<basename>_v0_pre-versioning_<date>.md`.
