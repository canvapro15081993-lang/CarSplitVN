TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = CarSplitVN

CarSplitVN_FILES = main.m CSMainViewController.m
CarSplitVN_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
CarSplitVN_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
CarSplitVN_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
