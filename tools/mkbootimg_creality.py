#!/usr/bin/env python3
"""
Minimal Android bootimg v2 packer for the Creality Hi (T113-S3).

Layout (page_size = 2048):
  page 0           : header (608 bytes for v0/v1, extended for v2)
  page 1..k        : kernel (with DTB appended Creality-style)
  page k+1..r      : ramdisk (empty for Hi)
  page r+1..s      : second stage (empty)

We only fill the kernel section; ramdisk/second/recovery_dtbo/dtb sections are
empty because the live unit's bootimg has them empty (DTB lives appended to
kernel, not in the v2 dtb-section field).
"""
import argparse
import os
import struct
import sys


PAGE_SIZE = 2048


def pad_to_page(data: bytes, page_size: int = PAGE_SIZE) -> bytes:
    rem = len(data) % page_size
    if rem == 0:
        return data
    return data + b"\x00" * (page_size - rem)


def build_v2_header(
    kernel_size: int,
    kernel_addr: int,
    ramdisk_size: int,
    ramdisk_addr: int,
    second_size: int,
    second_addr: int,
    tags_addr: int,
    page_size: int,
    os_version: int,
    board_name: bytes,
    cmdline: bytes,
    extra_cmdline: bytes,
    recovery_dtbo_size: int,
    recovery_dtbo_offset: int,
    header_size: int,
    dtb_size: int,
    dtb_addr: int,
) -> bytes:
    """Pack an Android bootimg v2 header.

    Field offsets are per AOSP `bootimg.h`:
        0   magic[8]              = "ANDROID!"
        8   kernel_size, kernel_addr
        16  ramdisk_size, ramdisk_addr
        24  second_size, second_addr
        32  tags_addr, page_size
        40  header_version, os_version
        48  board_name[16]
        64  cmdline[512]
        576 id[32]                = zero (signing fields, ignored by U-Boot)
        608 extra_cmdline[1024]
        1632 recovery_dtbo_size (v1+)
        1636 recovery_dtbo_offset (v1+, 8 bytes)
        1644 header_size (v1+)
        1648 dtb_size (v2)
        1652 dtb_addr (v2, 8 bytes)
    Total header consumes ~1660 bytes, padded to page boundary.
    """
    if len(board_name) > 16:
        raise ValueError("board_name too long (max 15 chars + NUL)")
    if len(cmdline) > 512:
        raise ValueError("cmdline too long (max 511 chars + NUL)")
    if len(extra_cmdline) > 1024:
        raise ValueError("extra_cmdline too long (max 1023 chars + NUL)")

    board_name = board_name.ljust(16, b"\x00")
    cmdline = cmdline.ljust(512, b"\x00")
    extra_cmdline = extra_cmdline.ljust(1024, b"\x00")
    id_field = b"\x00" * 32

    header = b""
    header += b"ANDROID!"
    header += struct.pack("<II", kernel_size, kernel_addr)
    header += struct.pack("<II", ramdisk_size, ramdisk_addr)
    header += struct.pack("<II", second_size, second_addr)
    header += struct.pack("<II", tags_addr, page_size)
    header += struct.pack("<II", 2, os_version)          # header_version=2
    header += board_name
    header += cmdline
    header += id_field
    header += extra_cmdline
    # v1 fields
    header += struct.pack("<I", recovery_dtbo_size)
    header += struct.pack("<Q", recovery_dtbo_offset)
    header += struct.pack("<I", header_size)
    # v2 fields
    header += struct.pack("<I", dtb_size)
    header += struct.pack("<Q", dtb_addr)

    return header


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("--kernel", required=True, help="zImage path")
    p.add_argument("--dtb", help="DTB to append AFTER the padded kernel section "
                                 "(stock Creality layout: kernel_size = zImage only, "
                                 "DTB lives in the page block immediately after the kernel)")
    p.add_argument("--ramdisk", help="Optional ramdisk path (rarely needed for Hi)")
    p.add_argument("--base", type=lambda x: int(x, 0), default=0x40000000)
    p.add_argument("--kernel_offset", type=lambda x: int(x, 0), default=0x00008000)
    p.add_argument("--ramdisk_offset", type=lambda x: int(x, 0), default=0x01000000)
    p.add_argument("--second_offset", type=lambda x: int(x, 0), default=0x00f00000)
    p.add_argument("--tags_offset", type=lambda x: int(x, 0), default=0x00000100)
    p.add_argument("--dtb_offset", type=lambda x: int(x, 0), default=0x01100000)
    p.add_argument("--pagesize", type=int, default=PAGE_SIZE)
    p.add_argument("--board", default="sun8i_arm")
    p.add_argument("--cmdline", default="")
    p.add_argument("--header_version", type=int, default=2)
    p.add_argument("-o", "--output", required=True)
    args = p.parse_args(argv)

    if args.header_version != 2:
        sys.exit("Only header_version=2 supported (matches Creality Hi bootimg).")

    with open(args.kernel, "rb") as f:
        kernel = f.read()

    dtb = b""
    if args.dtb:
        with open(args.dtb, "rb") as f:
            dtb = f.read()

    ramdisk = b""
    if args.ramdisk:
        with open(args.ramdisk, "rb") as f:
            ramdisk = f.read()

    kernel_addr = args.base + args.kernel_offset
    ramdisk_addr = args.base + args.ramdisk_offset
    second_addr = args.base + args.second_offset
    tags_addr = args.base + args.tags_offset
    dtb_addr_full = args.base + args.dtb_offset

    header = build_v2_header(
        kernel_size=len(kernel),
        kernel_addr=kernel_addr,
        ramdisk_size=len(ramdisk),
        ramdisk_addr=ramdisk_addr,
        second_size=0,
        second_addr=second_addr,
        tags_addr=tags_addr,
        page_size=args.pagesize,
        os_version=0,
        board_name=args.board.encode(),
        cmdline=args.cmdline.encode(),
        extra_cmdline=b"",
        recovery_dtbo_size=0,
        recovery_dtbo_offset=0,
        header_size=1660,
        dtb_size=0,                    # DTB lives appended in kernel section
        dtb_addr=dtb_addr_full,
    )

    out = pad_to_page(header, args.pagesize)
    out += pad_to_page(kernel, args.pagesize)
    out += pad_to_page(ramdisk, args.pagesize) if ramdisk else b""
    # Stock layout: DTB lives in the page block AFTER the kernel section, NOT
    # included in kernel_size. Allwinner U-Boot's `bootm` for Android images
    # loads the entire post-header bootimg contents to kernel_addr, so the DTB
    # ends up adjacent to the zImage in RAM and the appended-DTB scan in the
    # zImage decompressor finds it.
    out += pad_to_page(dtb, args.pagesize) if dtb else b""

    with open(args.output, "wb") as f:
        f.write(out)

    print(
        f"Wrote {args.output}: "
        f"{len(out):,} bytes "
        f"(kernel={len(kernel):,}, ramdisk={len(ramdisk):,}, "
        f"dtb_post_kernel={len(dtb):,}, "
        f"pages={len(out)//args.pagesize})"
    )


if __name__ == "__main__":
    main(sys.argv[1:])
