ARCHS := arm64
TARGET := iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk

TOOL_NAME = VidGrabHUD
VidGrabHUD_FILES = $(wildcard src/*.mm src/*.m)
VidGrabHUD_CFLAGS = -fobjc-arc -Iheaders -Isrc -include src/prefix.pch -Wno-unguarded-availability-new -Wno-deprecated-declarations
VidGrabHUD_CCFLAGS = -std=c++14
VidGrabHUD_LDFLAGS = -Flibraries -Llibraries
VidGrabHUD_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore IOKit
VidGrabHUD_PRIVATE_FRAMEWORKS = BackBoardServices GraphicsServices SpringBoardServices
VidGrabHUD_CODESIGN_FLAGS = -Sentitlements.plist
VidGrabHUD_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
