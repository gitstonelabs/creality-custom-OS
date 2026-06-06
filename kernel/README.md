# Kernel workspace

Outputs and per-board configuration for the Linux 6.6 kernel port.
Full source trees are **per-machine** and NOT synced (they're huge):

| Tree | WSL location | Size |
|---|---|---|
| Linux 6.6 (our work) | `~/linux-6.6` | 2.1 GB |
| Vendor BSP donor sun8iw20p1 | `~/linux_kernel_aw_t113` | 1.4 GB |

To rebuild from source on WSL:
```bash
cd ~/linux-6.6
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
make creality_sunxi_defconfig
make -j4 zImage dtbs modules
```
Then copy the new outputs into `build-output/`.
