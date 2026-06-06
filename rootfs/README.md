# Phase 2: Custom rootfs build

Buildroot-based custom rootfs for Creality Hi (and future K1/K2). Replaces stock Creality's stripped OpenWrt 21.02 fork.

---

## Status

| Item | State | Phase |
|---|---|---|
| Template chosen | mangopi_mq_dual_mainline_defconfig (Yuzuki Buildroot, T113-S3) | Phase 2.0 ✅ |
| Hi defconfig drafted | [`configs/creality_hi_defconfig`](configs/creality_hi_defconfig) | Phase 2.0 ✅ |
| Board scaffold | `board/creality/{common,hi}/` populated | Phase 2.0 ✅ |
| DTS | Copied from kernel-workspace into `board/creality/hi/devicetree/linux/` | Phase 2.2 ✅ |
| BR2_EXTERNAL wiring | `external.desc` + `Config.in` + `external.mk` + 5 package Config.in stubs | Phase 2.2 ✅ |
| Defconfig load test | 51 wanted symbols → all present in `.config` (287 auto-deps added) | Phase 2.1 ✅ |
| Build wrapper | `scripts/br_make.sh`: sanitizes WSL/Windows PATH contamination | Phase 2.2 ✅ |
| post-build / post-image | Hooks staged at `board/creality/hi/scripts/` | Phase 2.2 ✅ |
| Toolchain build | Bootlin arm-glibc external toolchain builds clean | Phase 2.3 ✅ |
| Linux 6.6 build from BR | Builds via `LINUX_OVERRIDE_SRCDIR=$HOME/linux-6.6` (BR 2022.02 has no LOCAL_DIRECTORY symbol) | Phase 2.3 ✅ |
| Klipper / Moonraker / CFS packages | `.mk` recipes exist and build: `package/klipper/klipper.mk`, `package/moonraker/moonraker.mk`, `package/fluidd/fluidd.mk`, `package/creality-cfs-klipper/creality-cfs-klipper.mk`. All four enabled in the defconfig (`BR2_PACKAGE_KLIPPER`, `_MOONRAKER`, `_FLUIDD`, `_CREALITY_CFS_KLIPPER`). | Phase 2.4 ✅ |
| AIC8800 driver + firmware | `.mk` recipes exist (`package/aic8800-driver/aic8800-driver.mk`, `package/aic8800-firmware/aic8800-firmware.mk`). Driver does NOT build against 6.6 cfg80211, so `CONFIG_WLAN` is off and the driver is not pulled in. Firmware blobs intentionally excluded. See KNOWN-GAPS.md. | Phase 2.5 🟡 |
| swupdate .swu packaging | Implemented and builds. Post-image hook `board/creality/hi/scripts/make-swu.sh` calls `tools/mkbootimg_creality.py` then `tools/mkswu.sh`, producing `creality-hi-v2.swu` and `creality-hi-v2-kernel-only.swu`. | Phase 2.6 ✅ |
| Boot on hardware | UNVERIFIED. The OS has never been confirmed to boot. The 2026-05-26 flash lost all comms and was recovered via FEL. See KNOWN-GAPS.md. | Phase 1.3 ❌ |

The actual Buildroot tree lives at `~/buildroot-yuzuki/buildroot/` on WSL (BR2_VERSION 2022.02.2). This `rootfs/` folder in the workspace is the **external tree**, the Hi-specific overlay on top of Yuzuki's upstream Buildroot. That tree, `linux-6.6`, and the T113 vendor BSP are per-machine and not stored in this repo, so the build is not yet reproducible from this repo alone (see KNOWN-GAPS.md).

### Defconfig drops we hit and fixed (2026-05-24)

| Symbol attempted | Outcome | Fix |
|---|---|---|
| `BR2_LINUX_KERNEL_CUSTOM_LOCAL_DIRECTORY` / `_LOCAL_PATH` | Doesn't exist in BR 2022.02 | Switched to `BR2_LINUX_KERNEL_CUSTOM_GIT` + `_REPO_URL`/`_REPO_VERSION` pointing at v6.6.140; use `LINUX_OVERRIDE_SRCDIR` env var at build time to rsync local tree |
| `BR2_PACKAGE_PYTHON_PYSERIAL` | Renamed | `BR2_PACKAGE_PYTHON_SERIAL` |
| `BR2_PACKAGE_DROPBEAR_SMALL=n` | Invalid defconfig syntax | Removed (default is already full dropbear) |
| `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_MDEV` | Conflicts with `BR2_INIT_SYSTEMD` | Removed (systemd ships its own udev) |

---

## What this gives us vs stock

| Capability | Stock Creality | This build |
|---|---|---|
| OS base | OpenWrt 21.02-SNAPSHOT (stripped) | Buildroot mainline, glibc |
| Klipper | Vendor fork with .so files | Mainline Klipper + our GPL-3.0 replacements |
| CAN | Missing | gs_usb + can-utils (BTT U2C v2.1 ready) |
| USB serial | Missing | CH341 / CP210X / FTDI / CH343 |
| WiFi | XR829 binary | wpa_supplicant + dhcpcd (driver TBD) |
| Dev tools | None | strace / tcpdump / gdb / perf / nano / vim / htop |
| Remote access | dropbear (limited) | full dropbear + avahi + WireGuard |
| Filesystem | ext4 + squashfs | squashfs (rootfs) + F2FS (UDISK option) + btrfs ready |
| Multi-printer | Hi-only | Hi today, K1/K2 next |

---

## Layout

```
rootfs/
├── README.md                        ← this file
├── configs/
│   ├── creality_hi_defconfig        ← Hi-specific Buildroot config (derived from mangopi)
│   └── UPSTREAM_TEMPLATE.txt        ← copy of upstream mangopi defconfig for reference
├── board/
│   └── creality/
│       ├── common/                  ← shared between all Creality models (TBD)
│       │   └── rootfs-overlay/
│       └── hi/                      ← Hi-specific
│           ├── devicetree/linux/
│           │   └── sun8i-t113s-creality-hi.dts    ← our DTS (copy from kernel-workspace)
│           ├── configs/             ← linux_defconfig if we want to override kernel cfg here
│           ├── rootfs-overlay/      ← printer.cfg, init scripts, Klipper config templates
│           └── scripts/
│               ├── post-build.sh    ← enables services, chmod +x's overlay scripts
│               └── make-swu.sh      ← post-image hook: bootimg + swupdate .swu
└── package/                         ← out-of-tree Buildroot packages (all have .mk recipes)
    ├── klipper/                     ← Klipper v0.12.0
    ├── moonraker/                   ← Moonraker
    ├── fluidd/                      ← Fluidd web UI
    ├── creality-cfs-klipper/        ← gitStoneLabs CFS RS485 module (creality_cfs.py)
    ├── aic8800-driver/              ← AIC8800 vendor driver (does NOT build on 6.6)
    └── aic8800-firmware/            ← firmware recipe (blobs excluded; see NOTICES.md)
```

---

## Build workflow

**All make invocations go through `scripts/br_make.sh`** because WSL inherits Windows' PATH (containing spaces in `C:\Program Files\...`) and Buildroot's dependency check refuses to run with a contaminated PATH. The wrapper resets PATH and calls make with `env -i`.

```bash
# Output goes outside the source tree at $HOME/buildroot-creality-hi-out/
# to keep the upstream Buildroot read-only.

# One-time: load defconfig (also clears the .config first)
./scripts/br_make.sh defconfig

# Optional: tweak interactively
./scripts/br_make.sh menuconfig

# Full build (will take 1-3 hours on first run; downloads ~300 MB of source)
./scripts/br_make.sh

# Build only the cross-toolchain (smallest first probe, ~150 MB download)
./scripts/br_make.sh toolchain

# Rebuild just the kernel against our local linux-6.6 (no kernel.org clone)
LINUX_OVERRIDE_SRCDIR=$HOME/linux-6.6 ./scripts/br_make.sh linux-rebuild

# Outputs end up in $HOME/buildroot-creality-hi-out/images/:
#   - rootfs.squashfs            (this is what goes into rootfsB partition)
#   - sun8i-t113s-creality-hi.dtb (rebuilt from our DTS)
#   - zImage                     (built from our linux-6.6/ source)
#   - boot.img                   (Android bootimg, ready for bootB partition)
#   - creality-hi.swu            (swupdate package for one-shot install)
```

Custom env vars accepted by the wrapper (with sensible defaults):

| Var | Default |
|---|---|
| `BR_SRC` | `$HOME/buildroot-yuzuki/buildroot` |
| `EXT_TREE` | auto-derived from the script location (the BR2_EXTERNAL tree root) |
| `OUT_DIR` | `$HOME/buildroot-creality-hi-out` |

---

## Decision points

Decided:

1. **Init system**: systemd. `BR2_INIT_SYSTEMD=y` in the defconfig. Stock Creality uses procd (OpenWrt); we chose systemd for standard embedded tooling and udev.
2. **Klipper version**: pinned to `v0.12.0` in `package/klipper/klipper.mk`.
3. **Moonraker + Fluidd**: bundled. Both have `.mk` recipes and are enabled in the defconfig.

Still open:

4. **swupdate signing**: not added. Creality's stock setup has no signing. Adding signature verification would be best practice but may interact badly with the A/B fallback chain. Left unsigned for now.
5. **WiFi firmware**: moot until the AIC8800 driver builds against 6.6. The AIC8800 firmware blobs are excluded (see KNOWN-GAPS.md and NOTICES.md). WiFi does not work today.

---

## Status caveat

The Phase 2 build is done in the sense that it produces a `.swu` end-to-end. It is NOT done in the sense of working: boot proof-of-life has never landed (see KNOWN-GAPS.md). The A/B mechanism keeps stock on the A side, so a bad rootfs on the B side is recoverable, but recovery currently means FEL because stock U-Boot has no automatic rollback.
