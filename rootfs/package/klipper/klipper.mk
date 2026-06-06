################################################################################
#
# klipper — 3D printer firmware host (Python)
#
################################################################################

KLIPPER_VERSION = v0.12.0
KLIPPER_SITE = https://github.com/Klipper3d/klipper
KLIPPER_SITE_METHOD = git
KLIPPER_LICENSE = GPL-3.0
KLIPPER_LICENSE_FILES = COPYING

# Klipper is pure Python — no build step, just install
KLIPPER_INSTALL_STAGING = NO
KLIPPER_INSTALL_TARGET = YES
KLIPPER_DEPENDENCIES = python3 python-serial python-greenlet

# Where klipper lives on the target
KLIPPER_TARGET_DIR = /opt/klipper

define KLIPPER_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)$(KLIPPER_TARGET_DIR)
	# Copy the klippy/ tree (the host-side Python — the actual MCU firmware
	# is built per-board out of $(@D)/src/ but we don't ship that in rootfs)
	cp -a $(@D)/klippy $(TARGET_DIR)$(KLIPPER_TARGET_DIR)/
	cp -a $(@D)/config $(TARGET_DIR)$(KLIPPER_TARGET_DIR)/
	cp -a $(@D)/scripts $(TARGET_DIR)$(KLIPPER_TARGET_DIR)/
	cp -a $(@D)/docs $(TARGET_DIR)$(KLIPPER_TARGET_DIR)/ 2>/dev/null || true
	cp $(@D)/COPYING $(TARGET_DIR)$(KLIPPER_TARGET_DIR)/COPYING
	# Klipper config directory (printer.cfg lives here at runtime)
	mkdir -p $(TARGET_DIR)/etc/klipper
	# Klipper log directory
	mkdir -p $(TARGET_DIR)/var/log/klipper
	# Klipper user (Klipper runs as 'klipper' — added below in users)
endef

# Drop in a systemd unit if systemd is selected
define KLIPPER_INSTALL_INIT_SYSTEMD
	mkdir -p $(TARGET_DIR)/usr/lib/systemd/system
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_GITSTONELABS_PATH)/package/klipper/klipper.service \
		$(TARGET_DIR)/usr/lib/systemd/system/klipper.service
	mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
	ln -sf ../../../../usr/lib/systemd/system/klipper.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/klipper.service
endef

# Klipper runs as its own user
define KLIPPER_USERS
	klipper -1 klipper -1 * /opt/klipper /bin/sh - Klipper 3D printer firmware host
endef

$(eval $(generic-package))
