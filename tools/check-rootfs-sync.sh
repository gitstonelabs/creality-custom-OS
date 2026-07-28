#!/bin/bash
# check-rootfs-sync.sh — guard against the published rootfs/ drifting from the
# tree images are actually built from.
#
# The Buildroot external tree exists in two places: the private build tree
# (where builds actually run) and this repo (what the public sees). They drifted
# once already, and the drift hid a real hardware bug for weeks. This script is
# the gate that stops it happening silently again.
#
# It checks three things:
#   1. The two trees are identical apart from an explicit allowlist.
#   2. No package/*.hash file is a comment-only placeholder. Buildroot treats
#      "hash file exists but has no hash for this file" as a HARD ERROR
#      (check-hash exit 3), while a missing hash file is only a warning. So a
#      placeholder hash file is strictly worse than none and breaks
#      `make <pkg>-source` outright.
#   3. No private data (real paths, MACs, SSIDs, PSKs) leaked into the repo.
#
# Usage:
#   tools/check-rootfs-sync.sh [BUILD_TREE]
#   BUILD_TREE=/path/to/build/rootfs tools/check-rootfs-sync.sh
#
# BUILD_TREE defaults to ../../rootfs relative to the repo root, which is where
# it sits in the maintainer's workspace. Pass it explicitly anywhere else.
#
# Exit 0 = in sync. Exit 1 = drift or a banned pattern; nothing is modified.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_TREE="$REPO_ROOT/rootfs"
BUILD_TREE="${1:-${BUILD_TREE:-$REPO_ROOT/../../rootfs}}"

# Paths that are SUPPOSED to exist only in the build tree. Anything differing
# outside this list is drift and fails the check. Keep this list short and
# justify every entry.
ALLOWED_BUILD_ONLY=(
    # Vendor firmware blobs: redistribution terms are murky and the driver does
    # not build against 6.6 anyway. Excluded on purpose. See NOTICES.md.
    "package/aic8800-firmware/lib/firmware"
)

fail=0
note() { printf '%s\n' "$*"; }
# Both go to stdout so the report reads in order; the exit code carries the
# pass/fail signal.
bad()  { printf 'FAIL: %s\n' "$*"; fail=1; }

if [ ! -d "$REPO_TREE" ]; then
    bad "repo tree not found: $REPO_TREE"
    exit 1
fi
if [ ! -d "$BUILD_TREE" ]; then
    note "SKIP: build tree not present at $BUILD_TREE"
    note "      (pass its path as \$1 to compare, or run this on the build host)"
    exit 0
fi

note "repo tree : $REPO_TREE"
note "build tree: $BUILD_TREE"
note ""

# --- 1. tree comparison ------------------------------------------------------
is_allowed() {
    local path="$1" allow
    for allow in "${ALLOWED_BUILD_ONLY[@]}"; do
        case "$path" in
            "$allow"|"$allow"/*) return 0 ;;
        esac
    done
    return 1
}

note "== tree comparison =="
while IFS= read -r line; do
    case "$line" in
        "Only in $BUILD_TREE"*)
            # "Only in <dir>: <name>" -> reconstruct the tree-relative path
            rest="${line#Only in }"
            dir="${rest%%: *}"
            name="${rest##*: }"
            rel="${dir#$BUILD_TREE}"
            rel="${rel#/}"
            [ -n "$rel" ] && rel="$rel/$name" || rel="$name"
            if is_allowed "$rel"; then
                note "  ok (allowlisted, build-tree only): $rel"
            else
                bad "present only in the build tree, not published: $rel"
            fi
            ;;
        "Only in $REPO_TREE"*)
            rest="${line#Only in }"
            dir="${rest%%: *}"
            name="${rest##*: }"
            rel="${dir#$REPO_TREE}"
            rel="${rel#/}"
            [ -n "$rel" ] && rel="$rel/$name" || rel="$name"
            bad "present only in the repo, missing from the build tree: $rel"
            ;;
        "Files "*" differ")
            rest="${line#Files }"
            bad "content differs: ${rest%% and *}"
            ;;
    esac
done < <(diff -rq "$BUILD_TREE" "$REPO_TREE" 2>/dev/null)
[ "$fail" -eq 0 ] && note "  trees match (allowlist applied)"
note ""

# --- 2. placeholder hash files ----------------------------------------------
# A .hash file with no uncommented hash line makes Buildroot fail the download
# with "ERROR: No hash found for <file>". Having no .hash file at all is fine.
#
# Exception: packages with BR2 SITE_METHOD = local never download. Buildroot
# turns that into an OVERRIDE_SRCDIR rsync (pkg-generic.mk), so the hash check
# never runs and a comment-only .hash file next to them is harmless.
#
# Only the repo tree is scanned; a bad hash file in the build tree alone would
# already be caught above as drift.
note "== placeholder hash files =="
checked=0
while IFS= read -r hashfile; do
    pkgdir="$(dirname "$hashfile")"
    mk="$pkgdir/$(basename "$hashfile" .hash).mk"
    if [ -f "$mk" ] && grep -qE '^[A-Z0-9_]+_SITE_METHOD[[:space:]]*=[[:space:]]*local[[:space:]]*$' "$mk"; then
        note "  skip (local site method, never downloads): ${hashfile#$REPO_TREE/}"
        continue
    fi
    checked=$((checked + 1))
    if ! grep -qE '^[[:space:]]*(md5|sha1|sha224|sha256|sha384|sha512)[[:space:]]' "$hashfile"; then
        bad "comment-only hash file will break the build: ${hashfile#$REPO_TREE/}"
    else
        note "  ok (carries real hashes): ${hashfile#$REPO_TREE/}"
    fi
done < <(find "$REPO_TREE" -name '*.hash' -path '*/package/*' 2>/dev/null | sort)
[ "$checked" -eq 0 ] && note "  no downloading package carries a hash file (correct)"
note ""

# --- 3. private data in the repo --------------------------------------------
# Real MACs, SSIDs, PSKs and absolute personal paths must never be published.
# Placeholders (YOUR_WIFI_SSID, AA:BB:CC:DD:EE:FF, 00:00:00:00:00:00) are fine.
note "== private data in the repo =="
leaks=$(grep -rInE \
    '/(home|mnt/c/Users|Users)/[A-Za-z0-9._-]+/|psk="[^"]+"|ssid="[^"]+"|([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' \
    "$REPO_TREE" 2>/dev/null \
  | grep -vE 'YOUR_WIFI_(SSID|PASSWORD)|AA:BB:CC:DD:EE:FF|(00:){5}00|/home/\$USER|\$HOME' \
  | grep -vE '/package/aic8800-driver/' )
if [ -n "$leaks" ]; then
    while IFS= read -r l; do bad "possible private data: $l"; done <<<"$leaks"
else
    note "  clean"
fi
note ""

if [ "$fail" -ne 0 ]; then
    note "RESULT: drift detected. Reconcile before publishing."
    exit 1
fi
note "RESULT: in sync."
exit 0
