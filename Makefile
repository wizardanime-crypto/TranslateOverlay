export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:13.0
export THEOS_PACKAGE_SCHEME = rootless

THEOS ?= /workspaces/theos
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TranslateOverlay

TranslateOverlay_FILES = Tweak.xm
TranslateOverlay_FRAMEWORKS = UIKit Foundation Vision NaturalLanguage QuartzCore
TranslateOverlay_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
