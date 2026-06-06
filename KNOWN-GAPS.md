# Known gaps

This is a work in progress. The list below is what is broken, unverified, or incomplete as of this publish. Read it before flashing or building.

## Boot and recovery

- **No boot proof-of-life.** The OS has never been confirmed to boot. The 2026-05-26 flash reported swupdate success, flipped the env to `bootB`/`rootfsB`, then lost all communication with zero captured console output. The board was recovered to stock via FEL on 2026-05-31. Whether the custom kernel started, panicked, or booted with no reachable network is unknown.
- **No working debug console.** The J65 UART header was identified but a signal was never confirmed to pass through it at a known baud. The `usbc0` OTG controller pins are not broken out to any accessible header on this board, so there is no OTG fallback console either. Without a console, every boot failure is opaque.
- **U-Boot has no rollback.** Stock U-Boot on a fresh board has no `bootcount`, `bootlimit`, or `altbootcmd` in its env. Committing `boot_partition=bootB` is one-way. FEL is the only safety net.
- **The v2 watchdog is inert on stock U-Boot.** The `kernel-and-rootfs-watchdog` swupdate mode writes `bootcount=0`, `bootlimit=3`, and `altbootcmd` env vars, but if vendor U-Boot does not honor `CONFIG_BOOTCOUNT_LIMIT`, none of that fires. The v2 safety build has never been hardware-tested.

## Networking

- **WiFi does not work.** The AIC8800 vendor driver (around 2022 vintage) does not compile against kernel 6.6's cfg80211 API. Several callback signatures changed, including `tdls_mgmt` gaining an `int link_id` parameter. Porting is deferred. `CONFIG_WLAN` is off, so the kernel builds without it. The vendor source is kept under `rootfs/package/aic8800-driver` for the future port, but it does not build today.

## Configuration and packaging defects

- **`fw_env.config` was wrong and is now corrected.** An earlier version guessed `/dev/by-name/env0` and `/dev/by-name/env1`. The fresh-board probe showed the real layout is `/dev/by-name/env` plus `/dev/by-name/env-redund` (a redundant pair, 0x20000 each). `rootfs/board/creality/hi/rootfs-overlay/etc/fw_env.config` now uses the corrected values. This has not been re-tested on hardware.
- **`now_B_next_B` is referenced but does not exist.** `rootfs/board/creality/hi/scripts/make-swu.sh` and `docs/two_step_flash_plan.md` mention a swupdate mode `now_B_next_B`. `tools/mkswu.sh` does not define it. The modes that actually exist are `now_A_next_B`, `now_B_next_A`, `kernel_only_B`, and the `kernel-and-rootfs-watchdog` mode (which emits `now_A_next_B` and `now_B_next_A` blocks). Use one of those.

## Klipper and hardware definition

- **`printer.cfg` is a non-functional placeholder.** `rootfs/board/creality/hi/rootfs-overlay/etc/klipper/printer.cfg` sets `kinematics: none`, comments out the `[mcu]` section, and gives no MCU firmware path. It drives no hardware. It exists so Klipper can come up clean in Fluidd to verify the host stack, not to print.
- **DTS `can0`/`can1` nodes are disabled placeholders.** Both CAN nodes in `kernel/dts/sun8i-t113s-creality-hi.dts` are `status = "disabled"`.
- **Two touch controllers are carried, one guessed.** The DTS carries both `touch_goodix` (ctp@14, enabled) and `touch_tlsc6x` (ctp@2e, disabled) because the live tree carries alternate chip nodes. Which one the hardware actually uses is not confirmed; one is a guess.
- **Userspace `.so` replacements are partial stubs.** `box.py`, `filament_rack.py`, and `motor_control.py` are partial stubs. Completing them needs hardware traces that have not been captured.

## Reproducibility

- **Not reproducible from this repo alone.** The build depends on per-machine source trees that are not stored here: `linux-6.6`, the T113 vendor BSP (`linux_kernel_aw_t113`), and the Yuzuki Buildroot 2022.02.2 checkout. Without those, the build cannot run. Pinning or vendoring them is future work.
