# Makefile for theos-based build (jailbreak tweak)
# Install theos from https://github.com/theos/theos

export THEOS_DEVICE_IP = localhost
export THEOS_DEVICE_PORT = 2222

TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = pvz

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PvZHDFix

# Source files for the tweak
PvZHDFix_FILES = Tweak.xm
PvZHDFix_CFLAGS = -fobjc-arc
PvZHDFix_FRAMEWORKS = Foundation SystemConfiguration UIKit WebKit


include $(THEOS_MAKE_PATH)/tweak.mk

# Additional targets for the standalone dylib (for sideloading)
lib_PvZHDFix_SCRIPTS = build_dylib.sh

after-stage::
	@echo "Build complete! Output files:"
	@echo "  - .theos/obj/debug/PvZHDFix.dylib (debug)"
	@echo "  - .theos/obj/PvZHDFix.dylib (release)"
