# Research: GPL Compliance Analysis and Kernel Porting

This document describes the investigation behind this repository. It covers the
binary analysis that identified the scope of Creality's GPL violation, the
methodology used to reverse engineer each proprietary module, and the kernel
porting work that underpins the custom OS build.

## The compliance problem

The Creality Hi ships firmware version CR4NU200360C20_ota_img_V1.1.0.65. It runs
a Creality-forked version of Klipper, which is licensed GPL-3.0. The firmware
bundles six compiled Python extension modules alongside the Klipper source. These
modules are `.cpython-39.so` files built for ARMv7 and placed in
`/usr/share/klipper/klippy/extras/` on the printer. GPL-3.0 Section 6 conditions
the right to distribute object code on making the corresponding source available.
Creality has not done this for any of the six modules.

The six modules and their sizes:

| Module | Size | Function |
|--------|------|----------|
| prtouch_v3_wrapper.cpython-39.so | 1.2 MB | Strain gauge bed leveling (Hi-specific) |
| box_wrapper.cpython-39.so | 1.9 MB | CFS filament box control |
| motor_control_wrapper.cpython-39.so | 865 KB | Motor control and cutter |
| serial_485_wrapper.cpython-39.so | 141 KB | RS485 communications |
| filament_rack_wrapper.cpython-39.so | 177 KB | Filament rack management |
| steer_wrapper.cpython-39.so | 104 KB | Tool steering |

Total proprietary binary volume: 5.3 MB.

Creality's own repository (`CrealityOfficial/K1_Series_Klipper`) contains the
source for ProTouch v1 (2,274 lines, GPL-3.0) and ProTouch v2 (2,202 lines,
GPL-3.0). They released source for two prior generations of the same module,
then shipped v3 as a closed binary. This is not a case of uncertainty about
license obligations. A formal source request was submitted to Creality twice.
Neither received a response.

## Binary analysis methodology

Each `.so` was analyzed using the following approach:

**ELF symbol extraction.** `readelf -Ws` against each binary yields the dynamic
symbol table: undefined symbols (external dependencies), defined symbols (exported
API), and the `PyInit_` entry point confirming the Python C extension structure.
All six modules import from the standard CPython 3.9 C API and define a
`PyInit_<module>` entry point. None link against each other.

**String extraction.** `strings` against each binary yields class names, method
names, error strings, and embedded constant labels. For the CFS modules
(`box_wrapper`, `serial_485_wrapper`) this confirmed RS485 frame constants and
command mnemonics that matched the live traffic captures. For `motor_control_wrapper`
it confirmed the FOC servo command structure.

**Cython decompilation.** The modules are compiled Cython; their Python-level
class structure, method signatures, argument names, and default values are
reconstructable from the embedded `PyMethodDef` and `PyTypeObject` tables.
Each module's API surface is documented in the `agent-findings/` directory of
the companion reverse-engineering workspace.

**Live RS485 capture.** For the CFS modules, a USB-RS485 sniffer on the bus
during tool changes and filament operations produced byte-level capture files.
These are the authoritative source for the protocol implementation in
`creality-cfs-klipper`. The motor controller buses (X and Y are FOC servos on
their own RS485 segments) were captured separately during homing and motion.

## Replacement status

`prtouch_v3_wrapper.so` has been replaced with a clean-room Python implementation
that passes Klipper startup and produces a valid bed mesh on the physical Hi. The
replacement boots Klipper clean and logs "ProTouch v3 ready."

`box_wrapper.so` and `serial_485_wrapper.so` are replaced by the CFS Klipper
module in the companion repository (`gitstonelabs/creality-cfs-klipper`), which
is hardware-validated across load, retract, and multi-slot tool change sequences.

`motor_control_wrapper.so` is partially analyzed. The cutting mechanism and
calibration sequence have been decoded from live captures. A Python reimplementation
is in progress.

`filament_rack_wrapper.so`, `steer_wrapper.cpython-39.so`, and
`external_material_wrapper.cpython-39.so` have had their API surfaces documented
from ELF and string analysis. Python reimplementations are deferred pending
additional hardware captures.

## Kernel porting work

The Creality Hi runs a stock OS built on OpenWrt 21.02 with a vendor-patched
Linux 5.4.61 kernel. The kernel is built from the Allwinner T113-S3 (sun8iw20p1)
vendor BSP. This repository ports the printer to mainline Linux 6.6 as a step
toward running a fully open software stack.

The porting work consists of three parts:

**Device tree.** `kernel/dts/sun8i-t113s-creality-hi.dts` is a new device tree
written for the Hi's specific hardware configuration: the T113-S3 SoC, the RS485
buses on UART2 and UART5, the nozzle MCU on UART3, the AIC8800 WiFi module, the
7-inch MIPI-DSI touchscreen, the EMMC and NAND flash layout, and the A/B boot
partition arrangement. Pin assignments were derived from continuity tracing and
the vendor DTS in the BSP.

**Driver ports.** Three driver subsystems required vendor BSP code brought
forward to 6.6: the pinctrl driver, two clock control units (CCUs), and the
display subsystem initialization. The 5.4 vendor implementations were compared
against the 6.6 mainline equivalents and ported where the kernel API changed.

**Build integration.** The kernel is built against a `BR2_EXTERNAL` Buildroot
tree that produces a squashfs rootfs with Klipper, Moonraker, Fluidd, and the
open `.so` replacements. The rootfs and kernel are packaged as an Android bootimg
v2 (Creality's boot format) inside a swupdate `.swu` for A/B installation.

The custom kernel builds cleanly. Boot on hardware has not been confirmed.
KNOWN-GAPS.md documents the remaining blockers: the AIC8800 WiFi driver does not
build against 6.6's cfg80211 API, the debug console UART has not been verified,
and U-Boot on stock hardware has no A/B rollback, so FEL recovery is the only
fallback if the first boot attempt fails.

## Goal

The intended output is a printer that runs on publicly auditable source from
kernel to application layer, with no compiled blobs in the Klipper plugin
directory. Every module Creality shipped as a binary will have a documented
open replacement. The complete stack, including the kernel, rootfs, and Klipper
plugins, will be published under GPL for community use.
