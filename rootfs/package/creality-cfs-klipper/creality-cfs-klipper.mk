################################################################################
#
# creality-cfs-klipper — gitStoneLabs' CFS RS485 module for Klipper
#
################################################################################

CREALITY_CFS_KLIPPER_VERSION = main
CREALITY_CFS_KLIPPER_SITE = https://github.com/gitstonelabs/creality-cfs-klipper
CREALITY_CFS_KLIPPER_SITE_METHOD = git
CREALITY_CFS_KLIPPER_LICENSE = GPL-3.0
CREALITY_CFS_KLIPPER_LICENSE_FILES = LICENSE

CREALITY_CFS_KLIPPER_INSTALL_STAGING = NO
CREALITY_CFS_KLIPPER_INSTALL_TARGET = YES
CREALITY_CFS_KLIPPER_DEPENDENCIES = klipper python3 python-serial

# The module is actually at src/creality_cfs.py in the repo (not extras/).
# To build against your local working copy instead of upstream, set
#   CREALITY_CFS_KLIPPER_OVERRIDE_SRCDIR=/path/to/repo
# before invoking br_make.sh (the wrapper forwards this env var).
define CREALITY_CFS_KLIPPER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/src/creality_cfs.py \
		$(TARGET_DIR)/opt/klipper/klippy/extras/creality_cfs.py
	mkdir -p $(TARGET_DIR)/etc/klipper/macros
	$(INSTALL) -D -m 0644 $(@D)/configs/cfs_macros.cfg \
		$(TARGET_DIR)/etc/klipper/macros/cfs_macros.cfg
	$(INSTALL) -D -m 0644 $(@D)/configs/printer.cfg.example \
		$(TARGET_DIR)/etc/klipper/macros/cfs_printer.cfg.example
	$(INSTALL) -D -m 0644 $(@D)/LICENSE \
		$(TARGET_DIR)/opt/klipper/klippy/extras/creality_cfs.LICENSE
	# Drop in the README + INSTALL guide for traceability
	$(INSTALL) -D -m 0644 $(@D)/README.md \
		$(TARGET_DIR)/opt/klipper/klippy/extras/creality_cfs.README.md
endef

$(eval $(generic-package))
