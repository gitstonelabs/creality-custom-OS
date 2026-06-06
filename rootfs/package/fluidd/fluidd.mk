################################################################################
#
# fluidd — Klipper web UI (static SPA)
#
# Distributed as a pre-built .zip on GitHub releases. We just unzip it
# into /var/www/fluidd on the target. The nginx config in our rootfs
# overlay points at this path.
#
################################################################################

FLUIDD_VERSION = v1.30.1
FLUIDD_SOURCE = fluidd.zip
FLUIDD_SITE = https://github.com/fluidd-core/fluidd/releases/download/$(FLUIDD_VERSION)
FLUIDD_LICENSE = GPL-3.0
FLUIDD_LICENSE_FILES =

# Pre-built .zip — no compilation needed. We use the host's /usr/bin/unzip
# (Buildroot 2022.02 doesn't ship a host-unzip package, and unzip is a
# standard tool on any Linux build host).
FLUIDD_INSTALL_STAGING = NO
FLUIDD_INSTALL_TARGET = YES

# Override extract since the zip has no top-level directory
define FLUIDD_EXTRACT_CMDS
	$(shell command -v unzip) -q -o $(FLUIDD_DL_DIR)/$(FLUIDD_SOURCE) -d $(@D)
endef

define FLUIDD_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/var/www/fluidd
	cp -a $(@D)/. $(TARGET_DIR)/var/www/fluidd/
endef

$(eval $(generic-package))
