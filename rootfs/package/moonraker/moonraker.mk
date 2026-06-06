################################################################################
#
# moonraker — HTTP/WebSocket API server for Klipper
#
################################################################################

MOONRAKER_VERSION = v0.9.1
MOONRAKER_SITE = https://github.com/Arksine/moonraker
MOONRAKER_SITE_METHOD = git
MOONRAKER_LICENSE = GPL-3.0
MOONRAKER_LICENSE_FILES = LICENSE

MOONRAKER_INSTALL_STAGING = NO
MOONRAKER_INSTALL_TARGET = YES
MOONRAKER_DEPENDENCIES = klipper python3

MOONRAKER_TARGET_DIR = /opt/moonraker

define MOONRAKER_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)$(MOONRAKER_TARGET_DIR)
	cp -a $(@D)/moonraker $(TARGET_DIR)$(MOONRAKER_TARGET_DIR)/
	cp -a $(@D)/scripts $(TARGET_DIR)$(MOONRAKER_TARGET_DIR)/
	cp $(@D)/LICENSE $(TARGET_DIR)$(MOONRAKER_TARGET_DIR)/LICENSE
	mkdir -p $(TARGET_DIR)/etc/moonraker
	mkdir -p $(TARGET_DIR)/var/log/moonraker
endef

define MOONRAKER_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_GITSTONELABS_PATH)/package/moonraker/moonraker.service \
		$(TARGET_DIR)/usr/lib/systemd/system/moonraker.service
	mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
	ln -sf ../../../../usr/lib/systemd/system/moonraker.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/moonraker.service
endef

define MOONRAKER_USERS
	moonraker -1 moonraker -1 * /opt/moonraker /bin/sh - Moonraker API server
endef

$(eval $(generic-package))
