# Kbuild fragment for the AIC8800 vendor driver tree.
#
# When invoked by Buildroot's kernel-module infrastructure as
#   make -C $(KSRC) M=$(PWD) modules
# kbuild reads this file, sees obj-* += subdir/, and recurses into the
# wanted subdirs to build each module.
#
# Symbol selection happens via make args in aic8800-driver.mk:
#   CONFIG_AIC_WLAN_SUPPORT=m       -> aic8800_bsp/
#   CONFIG_AIC8800_WLAN_SUPPORT=m   -> aic8800_fdrv/
# (BT modules deliberately disabled — not needed for first-boot SSH.)

obj-$(CONFIG_AIC8800_BTLPM_SUPPORT) += aic8800_btlpm/
obj-$(CONFIG_AIC8800_BTUSB_SUPPORT) += aic8800_btusb/
obj-$(CONFIG_AIC8800_WLAN_SUPPORT) += aic8800_fdrv/
obj-$(CONFIG_AIC_WLAN_SUPPORT)     += aic8800_bsp/
