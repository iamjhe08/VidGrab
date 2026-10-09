ARCHS := arm64
TARGET := iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk

APPEX_NAME = VGBubbleStarter
VGBubbleStarter_FILES = VGBubbleStarter.m
VGBubbleStarter_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
VGBubbleStarter_FRAMEWORKS = Foundation
VGBubbleStarter_CODESIGN_FLAGS = -S
VGBubbleStarter_INSTALL_PATH = /Applications/VidGrab.app/PlugIns

include $(THEOS_MAKE_PATH)/appex.mk
