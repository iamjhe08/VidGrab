TARGET := iphone:clang:16.5:15.0
ARCHS = arm64

PYFW_DIR ?= $(PWD)/vendor/ios-arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = VidGrab

VidGrab_FILES = $(wildcard Sources/*.m) Sources/vgconvert.c
VidGrab_FRAMEWORKS = UIKit Foundation AVFoundation AVKit CoreMedia Photos JavaScriptCore CoreVideo WebKit
VidGrab_CFLAGS = -fobjc-arc -F$(PYFW_DIR) -Wno-deprecated-declarations -Wno-unused-function -I/root/ffmpeg-ios/include
VidGrab_LDFLAGS = -F$(PYFW_DIR) -framework Python -Wl,-rpath,@executable_path/Frameworks -L/root/ffmpeg-ios/lib -lavformat -lavcodec -lswresample -lavutil -lmp3lame
VidGrab_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/application.mk
