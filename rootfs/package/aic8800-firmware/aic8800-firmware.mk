################################################################################
#
# aic8800-firmware — firmware blobs for AIC8800 WiFi+BT chipsets
#
# These are vendor blobs pulled from the Creality stock image
# (/lib/firmware/aic8800{D80,dc}/). They're not redistributable under
# a permissive license — track only — but Creality already shipped them
# on the printer, so reproducing them here for the same printer is fine.
#
################################################################################

AIC8800_FIRMWARE_VERSION = creality-hi-stock
AIC8800_FIRMWARE_SITE = $(BR2_EXTERNAL_GITSTONELABS_PATH)/package/aic8800-firmware
AIC8800_FIRMWARE_SITE_METHOD = local
AIC8800_FIRMWARE_LICENSE = proprietary
AIC8800_FIRMWARE_LICENSE_FILES =

AIC8800_FIRMWARE_INSTALL_TARGET = YES
AIC8800_FIRMWARE_INSTALL_STAGING = NO

# Plain rsync of the entire lib/firmware/ tree from our source into target.
# Buildroot's $(@D) ends up being the rsync'd copy of the SITE, so the
# firmware tree is at $(@D)/lib/firmware/.
define AIC8800_FIRMWARE_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/lib/firmware/aic8800D80
	mkdir -p $(TARGET_DIR)/lib/firmware/aic8800dc
	cp -a $(@D)/lib/firmware/aic8800D80/. $(TARGET_DIR)/lib/firmware/aic8800D80/
	cp -a $(@D)/lib/firmware/aic8800dc/.  $(TARGET_DIR)/lib/firmware/aic8800dc/
endef

$(eval $(generic-package))
