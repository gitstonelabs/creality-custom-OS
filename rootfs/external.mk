# gitStoneLabs external tree — make fragment
#
# Buildroot automatically picks up every package/*/*.mk under this tree,
# but the explicit include is required for packages that live outside
# the package/ directory.

include $(sort $(wildcard $(BR2_EXTERNAL_GITSTONELABS_PATH)/package/*/*.mk))
