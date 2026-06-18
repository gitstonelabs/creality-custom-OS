# Ground truth: the stock Hi target contract

This is the authoritative reference for what a custom OS must match to install and boot on a stock Creality Hi via the same A/B swupdate path. Every value here was verified against the official V1.1.0.50 images (OTA plus IMAGEWTY `uart0`): the bootimg v2 header, the decompiled DTB, the squashfs rootfs, the IMAGEWTY `sys_partition.fex`, and the boot0 DRAM struct. It carries no Creality blob, only the extracted facts.

Where a value is not yet confirmed on the *live* device (as opposed to the factory image), it is flagged as an open item, not stated as fact. See [KNOWN-GAPS.md](../KNOWN-GAPS.md) for the broader gap list.

## SoC and base

| Item | Value |
|---|---|
| SoC | Allwinner T113-S3 (sun8iw20p1), ARM32 dual Cortex-A7 |
| FEL SoC ID | `0x00185900` (R528/T113) |
| Stock kernel | Linux **5.4.61** (Allwinner BSP LTS), Linaro GCC 5.3, `#1 SMP PREEMPT Tue Jul 29 2025` |
| Stock rootfs | Tina 5.0 / OpenWrt 21.02-SNAPSHOT, squashfs v4.0 gzip, glibc + BusyBox, Python 3.9 |
| Bootloader | U-Boot **2018.07** + OP-TEE, delivered as a `sunxi-package` (boot_package), flashed via swupdate `awuboot` |

Our port targets mainline **6.6**, a different base. Drivers are ported, not transplanted.

## Partition table (from IMAGEWTY sys_partition.fex, 512 B sectors, 16 MB MBR)

| Partition | Size | Notes |
|---|---|---|
| boot-resource | 8 MB | logo / resources |
| env | 1 MB | U-Boot env (primary) |
| env-redund | 1 MB | U-Boot env (redundant copy) |
| bootA | 16 MB | A-slot kernel (Android bootimg v2) |
| bootB | 16 MB | B-slot kernel |
| rootfsA | 300 MB | A-slot rootfs (squashfs) |
| rootfsB | 300 MB | B-slot rootfs |
| dsp0 | 1 MB | HiFi4 DSP firmware partition |
| private | 16 MB | per-unit data (MAC / serial / keybox); do not overwrite |
| rootfs_data | 256 MB | overlay / user data |
| UDISK | fill | remaining eMMC |

A and B slots are byte-identical in size. Addressed by GPT / by-name (`/dev/by-name/bootA`, etc.). The OTA contains partition **names and sizes** but not absolute byte offsets; offsets come from this `sys_partition.fex` or a live `mmc part` / `sgdisk -p`.

## Boot contract (Android bootimg v2)

A custom kernel must be packed to match the stock bootimg v2 contract:

| Field | Value |
|---|---|
| header_version | 2 |
| page_size | 2048 |
| board name | `sun8i_arm` |
| kernel load | `0x40008000` |
| tags addr | `0x40000100` |
| ramdisk_size / second_size | 0 / 0 |
| dtb_addr (v2 dtb section) | `0x41114800` |
| cmdline | **EMPTY** (root= and console come from the U-Boot env at runtime; do not hardcode root= in the bootimg) |

**Open item, DTB placement.** The V1.1.0.50 OTA/IMAGEWTY payload puts the DTB in the bootimg **v2 dtb section** (no `d00dfeed` appended inside the zImage). This repo's `tools/mkbootimg_creality.py` currently **appends** the DTB Creality-style instead. Both layouts boot under Allwinner U-Boot `bootm`, but the live on-eMMC `boota.bin` layout has not been dumped and confirmed. Verify a live boot slot before assuming either layout is required. Recorded so the packer choice is a known decision, not an accident.

## DTB identity

| Item | Value |
|---|---|
| model | `sun8iw20` |
| compatible | `allwinner,t113_i` + `arm,sun8iw20p1` |
| stock bootargs (in DTB /chosen) | `earlyprintk=sunxi-uart,0x2500000 loglevel=8 initcall_debug=0 console=ttyS0 init=/init` (no `root=`, no baud, no `panic=`) |
| memreserve | `0x41b00000` + `0x100000` |
| notable nodes | `dsp_rproc@0` (HiFi4), `rpbuf_controller` / `rpbuf_sample` (DSP IPC), `can@0x0` / `can@0x1`, `mailbox_heartbeat` |

## Out-of-tree modules the 6.6 port must reproduce

Stock 5.4.61 ships exactly four out-of-tree `.ko` under `/lib/modules/5.4.61`:

| Module | Size | Function |
|---|---|---|
| `aic8800_bsp.ko` | 83,636 | AICSemi WiFi BSP (the slow-power-cycle quirk lives here) |
| `aic8800_fdrv.ko` | 444,552 | AICSemi WiFi full driver |
| `gt9xxnew_ts.ko` | 50,576 | Goodix touch controller |
| `tlsc6x.ko` | 71,580 | TLSC touch controller |

The AIC8800 driver is the long pole; it does not build against 6.6 cfg80211 yet (see [KNOWN-GAPS.md](../KNOWN-GAPS.md)). Two touch controllers are carried because the live tree carries alternate chip nodes; which one the hardware uses is unconfirmed.

## DRAM training parameters (DDR3 at 792 MHz, select_mode = 0)

From the boot0 SPL struct (offset `0x38`) and `sys_config dram_para`, in agreement. DDR3 (type 3) is the live table; the LPDDR4 type-7 table in the same image is dead. These are SoC and board-level constants, not per-unit data.

| Field | Value | Field | Value |
|---|---|---|---|
| `dram_clk` | 792 | `dram_tpr0` | `0x004A2195` |
| `dram_type` | 3 | `dram_tpr1` | `0x02423190` |
| `dram_zq` | `0x7b7bfb` | `dram_tpr2` | `0x0008B061` |
| `dram_odt_en` | `0x1` | `dram_tpr3` | `0xB4787896` |
| `dram_para1` | `0x000010d2` | `dram_tpr5` | `0x48484848` |
| `dram_para2` | `0x0` | `dram_tpr6` | `0x48` |
| `dram_mr0` | `0x1c70` | `dram_tpr7` | `0x1620121e` |
| `dram_mr1` | `0x042` | `dram_tpr11` | `0x00770000` |
| `dram_mr2` | `0x18` | `dram_tpr12` | `0x2` |
| `dram_mr3` | `0x0` | `dram_tpr13` | `0x34050100` |

The same table, with build guidance, lives in the recovery repo at `reference/dram-params-t113-hi.md`. For a permanent SPL, confirm these against a `boot0` dump from your own board first.

## A/B install safety (no rollback)

The stock `sw-description` installs to the **inactive** slot and only flips the env selector after a successful write. There is **no** kernel-side auto-rollback in the U-Boot bootcmd, so a bad kernel in the **active** slot soft-bricks. Always write the inactive slot and confirm before flipping `boot_partition`. FEL (hold LOAD at power-on) is the only safety net. See the companion [creality-hi-recovery](https://github.com/gitstonelabs/creality-hi-recovery) repo.

## Provenance

All values verified against the official V1.1.0.50 release images on 2026-06-17. The OTA cpio members were MD5-verified against the package's own `cpio_item_md5` manifest (for example kernel `ed382f1c0d93070e504986165be587fc`, rootfs `48e24fb3720758a326eb4b55a906d206`). No Creality blob is stored in this repo, only the extracted contract above.
