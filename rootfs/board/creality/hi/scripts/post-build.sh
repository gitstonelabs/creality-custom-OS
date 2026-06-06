#!/bin/sh
# post-build.sh — Buildroot post-build hook for Creality Hi rootfs
#
# Runs after package install but before image creation. Final chance to
# inject files into $TARGET_DIR (the about-to-be-imaged staging tree)
# without bloating any package's overlay.
#
# Buildroot exports:
#   $TARGET_DIR        — staging tree being assembled
#   $BUILD_DIR         — per-package build outputs
#   $HOST_DIR          — host tools built for this build
#   $BINARIES_DIR      — final images
#   $BASE_DIR          — output/ root
#   $BR2_EXTERNAL_GITSTONELABS_PATH — path to our external tree
#
# Currently a no-op stub. Things to add later:
#   - First-boot hostname normalization (board-id → printer-Nxxx)
#   - Pin systemd journal size cap
#   - Bake a build-id file (git rev) into /etc/gitstonelabs-release

set -eu

echo "[gitstonelabs] post-build: target=$TARGET_DIR"

# Bake a release stamp so the printer can self-identify which build it has
if command -v git >/dev/null 2>&1 && [ -d "$BR2_EXTERNAL_GITSTONELABS_PATH/.git" ]; then
    REV=$(git -C "$BR2_EXTERNAL_GITSTONELABS_PATH" rev-parse --short HEAD 2>/dev/null || echo unknown)
else
    REV="dev"
fi

cat > "$TARGET_DIR/etc/gitstonelabs-release" <<EOF
NAME="gitStoneLabs Linux"
BOARD="creality-hi"
SOC="sun8i-t113s"
REVISION="$REV"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

# -----------------------------------------------------------------------------
# Enable systemd services at boot.
# NTFS doesn't preserve symlinks reliably across the WSL/Windows boundary,
# so we create them HERE in post-build (target dir is real ext4-ish) rather
# than in board/.../rootfs-overlay/ (which lives on NTFS).
# -----------------------------------------------------------------------------

mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"

enable_unit() {
    local unit="$1"
    local target_file="$unit"
    # If this is a template instance (foo@bar.service) but only the template
    # (foo@.service) ships in target, look for that instead.
    if echo "$unit" | grep -q '@.\+\.service$'; then
        local template="$(echo "$unit" | sed 's/@[^.]*\.service$/@.service/')"
        if [ ! -f "$TARGET_DIR/usr/lib/systemd/system/$unit" ] && \
           [ -f "$TARGET_DIR/usr/lib/systemd/system/$template" ]; then
            target_file="$template"
        fi
    fi
    if [ -f "$TARGET_DIR/usr/lib/systemd/system/$target_file" ] || \
       [ -f "$TARGET_DIR/etc/systemd/system/$target_file" ]; then
        ln -sf "/usr/lib/systemd/system/$target_file" \
            "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/$unit"
        echo "[gitstonelabs] enabled $unit (-> $target_file)"
    else
        echo "[gitstonelabs] WARNING: $unit (or template $target_file) not present in target, skipping enable"
    fi
}

# WiFi: AIC8800 driver auto-load happens via /etc/modules-load.d/aic8800.conf
# (systemd-modules-load.service handles this — already in multi-user.target).
# wpa_supplicant on wlan0 → template instance.
enable_unit wpa_supplicant@wlan0.service

# DHCP client on every available network interface
enable_unit dhcpcd.service

# SSH daemon (Buildroot ships dropbear)
enable_unit dropbear.service

# USB Ethernet gadget (fallback comm path) — service ships in the overlay
enable_unit usb-gadget.service

# mDNS for `ssh creality-hi.local`
enable_unit avahi-daemon.service

# Klipper + Moonraker (best-effort: only enables if the units exist)
enable_unit klipper.service
enable_unit moonraker.service
enable_unit nginx.service
enable_unit systemd-networkd.service

# v2 safety services
enable_unit gitstonelabs-bootcount-reset.service
enable_unit gitstonelabs-heartbeat.service

# Ensure heartbeat + bootcount-reset scripts are executable
chmod +x "$TARGET_DIR/usr/local/bin/gitstonelabs-bootcount-reset.sh" 2>/dev/null || true
chmod +x "$TARGET_DIR/usr/local/bin/gitstonelabs-heartbeat.sh" 2>/dev/null || true

# nginx site enable — symlink sites-available/fluidd → sites-enabled/
mkdir -p "$TARGET_DIR/etc/nginx/sites-enabled"
ln -sf /etc/nginx/sites-available/fluidd \
    "$TARGET_DIR/etc/nginx/sites-enabled/fluidd"

# Klipper + Moonraker need writable runtime dirs
mkdir -p "$TARGET_DIR/var/log/klipper"
mkdir -p "$TARGET_DIR/var/log/moonraker"
mkdir -p "$TARGET_DIR/var/lib/moonraker"
mkdir -p "$TARGET_DIR/var/lib/klipper"

# Nice login banner so first-time SSH users see the help text
cat > "$TARGET_DIR/etc/motd" <<'BANNER'

╔══════════════════════════════════════════════════════════════╗
║          gitStoneLabs Linux for Creality Hi                  ║
║          (Allwinner T113-S3 / sun8iw20p1)                    ║
╠══════════════════════════════════════════════════════════════╣
║  WiFi:    set SSID/PSK in /etc/wpa_supplicant/              ║
║  USB Eth: 10.55.0.1 (plug USB-C OTG cable to your PC)        ║
║  Web UI:  http://creality-hi.local/  (Fluidd, port 80)       ║
║  SSH:     ssh root@creality-hi.local  (dropbear, port 22)    ║
║  Logs:    journalctl -fu klipper  /  -fu moonraker           ║
║                                                              ║
║  Klipper config:  /etc/klipper/printer.cfg                   ║
║  Build:           cat /etc/gitstonelabs-release              ║
╚══════════════════════════════════════════════════════════════╝

BANNER

echo "[gitstonelabs] post-build done"
