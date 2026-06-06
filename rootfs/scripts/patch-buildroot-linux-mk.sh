#!/bin/bash
# patch-buildroot-linux-mk.sh — apply a one-line patch to Buildroot's linux.mk
# so the kernel build gets MAKEFLAGS=-rR injected into its environment.
#
# Why: Buildroot 2022.02 with Linux 6.6 hits "m2c: command not found" because
# GNU make's built-in `%.o: %.mod` implicit rule matches kbuild's `.cmd.mod`
# dependency-tracking files. The kernel's own `MAKEFLAGS += -rR` (in its
# top-level Makefile) sets this for sub-makes but doesn't override the
# Buildroot-level make invocation that calls into the kernel. Adding
# MAKEFLAGS=-rR to LINUX_MAKE_ENV forces the kernel make to start with -rR.
#
# Idempotent — re-running has no effect if patch is already applied.

set -e

BR_LINUX_MK="${BR_LINUX_MK:-$HOME/buildroot-yuzuki/buildroot/linux/linux.mk}"
MARKER="# gitstonelabs: force -rR for Linux 6.x m2c workaround"

if [ ! -f "$BR_LINUX_MK" ]; then
    echo "ERROR: $BR_LINUX_MK not found" >&2
    exit 1
fi

if grep -qF "$MARKER" "$BR_LINUX_MK"; then
    echo "Patch already applied to $BR_LINUX_MK"
    exit 0
fi

# Insert the MAKEFLAGS line after the LINUX_MAKE_ENV definition starts.
# The existing block looks like:
#     LINUX_MAKE_ENV = \
#         $(HOST_MAKE_ENV) \
#         BR_BINARIES_DIR=$(BINARIES_DIR)
#
# We insert MAKEFLAGS=-rR after the opening so it becomes:
#     LINUX_MAKE_ENV = \
#         MAKEFLAGS=-rR \      # gitstonelabs: force -rR for Linux 6.x m2c workaround
#         $(HOST_MAKE_ENV) \
#         BR_BINARIES_DIR=$(BINARIES_DIR)

cp "$BR_LINUX_MK" "$BR_LINUX_MK.bak.$(date +%s)"

python3 - "$BR_LINUX_MK" "$MARKER" <<'PY'
import sys, re

path, marker = sys.argv[1], sys.argv[2]
with open(path, 'r') as f:
    src = f.read()

# Anchor: the original `LINUX_MAKE_ENV = \\\n\t$(HOST_MAKE_ENV) \\`
pattern = re.compile(r'^LINUX_MAKE_ENV = \\\n\t\$\(HOST_MAKE_ENV\) \\', re.MULTILINE)

# Replacement: insert the marker as its own comment line BEFORE the
# assignment so we don't have to deal with comment-inside-continuation
# parsing ambiguity. Then add MAKEFLAGS=-rR as the first env var.
replacement_text = (
    marker + "\n"
    "LINUX_MAKE_ENV = \\\n"
    "\tMAKEFLAGS=-rR \\\n"
    "\t$(HOST_MAKE_ENV) \\"
)

new_src, n = pattern.subn(lambda _m: replacement_text, src, count=1)
if n != 1:
    sys.exit("ERROR: could not find LINUX_MAKE_ENV anchor in linux.mk")

with open(path, 'w') as f:
    f.write(new_src)

print("Patched " + path + ": injected MAKEFLAGS=-rR into LINUX_MAKE_ENV")
PY
