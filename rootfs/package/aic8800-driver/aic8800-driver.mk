################################################################################
#
# aic8800-driver — AIC8800 WiFi (and optionally BT) out-of-tree kernel driver
#
# Source: vendor BSP (Yuzuki collection), pulled into our external tree at
#   package/aic8800-driver/aic8800_{bsp,fdrv,btlpm,btusb}/
#
# We bundle only the WiFi half (bsp + fdrv). BT skipped for first-boot
# minimality — can be added later if anyone wants bluetooth-LE on the
# printer.
#
################################################################################

# Match the version printed by the stock driver. (For pure local sources
# Buildroot still wants a version string for cache-key stability.)
AIC8800_DRIVER_VERSION = 6.4.3.0-creality

# Local-tree source — sits inside our BR2_EXTERNAL_GITSTONELABS_PATH
AIC8800_DRIVER_SITE = $(BR2_EXTERNAL_GITSTONELABS_PATH)/package/aic8800-driver
AIC8800_DRIVER_SITE_METHOD = local

AIC8800_DRIVER_LICENSE = GPL-2.0
AIC8800_DRIVER_LICENSE_FILES =

# Kbuild fragment selectors:
#   CONFIG_AIC_WLAN_SUPPORT       -> aic8800_bsp/   (board support, SDIO/USB glue)
#   CONFIG_AIC8800_WLAN_SUPPORT   -> aic8800_fdrv/  (fullmac driver)
# Plus the interface selector inside aic8800_bsp/Makefile:
#   CONFIG_AIC_INTF_SDIO=y        -> SDIO transport (the Creality Hi wiring)
#
# The vendor source has -Wimplicit-fallthrough warnings in switch statements
# that the kernel's default -Werror treats as fatal. Demote them so the
# driver actually compiles. (The warnings are legit but harmless — we're not
# fixing vendor source as part of this build.)
AIC8800_DRIVER_MODULE_MAKE_OPTS = \
	CONFIG_AIC_WLAN_SUPPORT=m \
	CONFIG_AIC8800_WLAN_SUPPORT=m \
	CONFIG_AIC_INTF_SDIO=y \
	KCFLAGS="-Wno-error=implicit-fallthrough -Wno-implicit-fallthrough -Wno-error"

$(eval $(kernel-module))
$(eval $(generic-package))
