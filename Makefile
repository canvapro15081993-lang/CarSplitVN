TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CarSplitVN

CarSplitVN_FILES = Tweak.x
CarSplitVN_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
CarSplitVN_LDFLAGS = -undefined dynamic_lookup

CarSplitVN_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreLocation CarPlay
# Dùng weak_framework ?? tránh b?t bu?c ph?i có file v?t lý lúc compile
CarSplitVN_WEAK_FRAMEWORKS = FrontBoardServices SpringBoardServices CarKit

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += app prefs
include $(THEOS_MAKE_PATH)/aggregate.mk