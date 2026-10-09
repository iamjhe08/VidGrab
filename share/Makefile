ARCHS := arm64
TARGET := iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk

APPEX_NAME = VGShare
VGShare_FILES = VGShareViewController.m
VGShare_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
VGShare_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers MobileCoreServices
VGShare_CODESIGN_FLAGS = -S
VGShare_INSTALL_PATH = /Applications/VidGrab.app/PlugIns

include $(THEOS_MAKE_PATH)/appex.mk
