#!/bin/bash
# pin-python39.sh — pin Buildroot's python3 package to CPython 3.9.25.
#
# WHY (deep-dive item 19 / FLEET_POLICY ABI caveat):
#   Buildroot 2022.02.2 ships exactly ONE python3 version, hardcoded in
#   package/python3/python3.mk as PYTHON3_VERSION = 3.10.4. There is NO
#   Kconfig knob to choose the version (python3 is a single-version package
#   in this BR release). So a defconfig line cannot pin it.
#
#   Creality's withheld klippy extension modules are *.cpython-39.so — the
#   "cpython-39" ABI tag only imports on a CPython 3.9 interpreter. A 3.10
#   rootfs rejects them ("module was compiled for Python 3.9"). The transition
#   image must keep loading at least one stock .so until the GPL rewrites
#   land, so the rootfs interpreter MUST be 3.9. glibc is already satisfied
#   (the .so need only GLIBC_2.4; any modern glibc rootfs provides it).
#
#   3.9.25 (released 2025-10-31) is the FINAL 3.9 series release; the branch
#   is EOL/security-only/source-only. That is acceptable here: the goal is the
#   frozen cpython-39 ABI the vendor .so were built against, not ongoing
#   upstream support. This pin is a TRANSITION measure; remove it once the
#   GPL replacements eliminate every stock .so (then revert to 3.10 and drop
#   the ABI caveat).
#
#   This recipe drives BOTH host-python3 and target python3, so the pin moves
#   the host byte-compiler and the target interpreter together (host must
#   match target major to emit correct target .pyc). Cross-built extension
#   modules (e.g. python-greenlet) then carry the cpython-39 tag too.
#
# WHAT it does (idempotent):
#   1. Rewrites PYTHON3_VERSION_MAJOR -> 3.9 and PYTHON3_VERSION -> 3.9.25 in
#      package/python3/python3.mk.
#   2. Rewrites package/python3/python3.hash with the 3.9.25 tarball + LICENSE
#      sha256 (locally computed; md5 matches python.org for 3.9.25).
#   3. Leaves a marker comment so re-running is a no-op.
#   Backs up both files with a timestamp before touching them.
#
# HOW TO VERIFY (requires the deliberate rebuild, OUT OF SCOPE for the pin):
#   ./scripts/br_make.sh python3-dirclean && ./scripts/br_make.sh python3-rebuild
#   then on the target:  python3 --version  -> Python 3.9.25
#   and:  ls /usr/lib/python3.9/lib-dynload/  (extension tags say cpython-39)
#   Drop a stock *.cpython-39.so on the target and `import` it.
#
# HOW TO REVERT:
#   Restore the .bak_pin39_* files this script created, OR re-run upstream's
#   git checkout package/python3/python3.mk package/python3/python3.hash.
#
# RISK / OPEN GATE (must be settled at rebuild time, not here):
#   Buildroot 2022.02's python3 patch series (0001-0033 in package/python3/)
#   was refreshed for 3.10.x. Most are version-agnostic infra patches and the
#   same lineage shipped with 3.9 in BR 2021.02/2021.08, but a few touch
#   setup.py / Lib/sysconfig.py / configure.ac which differ between 3.9 and
#   3.10. If `make python3-extract` reports a patch hunk failure, lift the
#   python3/*.patch series from the Buildroot 2021.08 release (which natively
#   carried 3.9) into package/python3/ and re-run. This script does NOT change
#   the patch series; that gate is verified only by the rebuild.

set -euo pipefail

PY_DIR="${PY_DIR:-$HOME/buildroot-yuzuki/buildroot/package/python3}"
MK="$PY_DIR/python3.mk"
HASH="$PY_DIR/python3.hash"
MARKER="# gitstonelabs: pinned to 3.9.25 for cpython-39 ABI (item 19)"

NEW_MAJOR="3.9"
NEW_VERSION="3.9.25"
# Locally computed; md5 d56b945105f1ea8dc67df8ec78fd13e6 matches python.org.
TARBALL_SHA256="00e07d7c0f2f0cc002432d1ee84d2a40dae404a99303e3f97701c10966c91834"
LICENSE_SHA256="0bcd0ed8d17aed30c8487847c5d92d153471dba38520e81b15312cb432c44852"

if [ ! -f "$MK" ] || [ ! -f "$HASH" ]; then
    echo "ERROR: python3.mk or python3.hash not found under $PY_DIR" >&2
    exit 1
fi

if grep -qF "$MARKER" "$MK"; then
    echo "Already pinned to ${NEW_VERSION} (marker present in python3.mk) — no-op."
    exit 0
fi

# Sanity: confirm we are starting from the expected stock 3.10.4 lines so we
# fail loudly rather than silently mangling an unexpected recipe.
if ! grep -qE '^PYTHON3_VERSION_MAJOR = 3\.10$' "$MK"; then
    echo "ERROR: expected 'PYTHON3_VERSION_MAJOR = 3.10' in $MK — refusing to edit." >&2
    echo "       The recipe is not in the known stock state; pin by hand." >&2
    exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
cp -v "$MK"   "$MK.bak_pin39_$TS"
cp -v "$HASH" "$HASH.bak_pin39_$TS"

# 1. Version lines in python3.mk
sed -i \
    -e "s/^PYTHON3_VERSION_MAJOR = 3\.10\$/${MARKER}\nPYTHON3_VERSION_MAJOR = ${NEW_MAJOR}/" \
    -e "s/^PYTHON3_VERSION = \$(PYTHON3_VERSION_MAJOR)\.4\$/PYTHON3_VERSION = \$(PYTHON3_VERSION_MAJOR).25/" \
    "$MK"

# 2. Rewrite the hash file
cat > "$HASH" <<EOF
${MARKER}
# From https://www.python.org/downloads/release/python-3925/
md5  d56b945105f1ea8dc67df8ec78fd13e6  Python-${NEW_VERSION}.tar.xz
# Locally computed
sha256  ${TARBALL_SHA256}  Python-${NEW_VERSION}.tar.xz
sha256  ${LICENSE_SHA256}  LICENSE
EOF

# Verify the edits landed.
echo "=== python3.mk version lines now ==="
grep -nE '^PYTHON3_VERSION' "$MK" | head -3
echo "=== python3.hash now ==="
cat "$HASH"

echo
echo "Pinned python3 to ${NEW_VERSION}. Backups: *.bak_pin39_$TS"
echo "Rebuild to verify: ./scripts/br_make.sh python3-dirclean && ./scripts/br_make.sh python3-rebuild"
