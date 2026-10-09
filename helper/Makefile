ARCHS := arm64
TARGET := iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = VidGrabBubble
VidGrabBubble_FILES = main.m
VidGrabBubble_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
VidGrabBubble_FRAMEWORKS = UIKit Foundation
VidGrabBubble_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/application.mk
