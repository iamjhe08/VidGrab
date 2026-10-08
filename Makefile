TARGET := iphone:clang:16.5:15.0
ARCHS = arm64

PYFW_DIR ?= $(PWD)/vendor/ios-arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = VidGrab

VidGrab_FILES = $(wildcard Sources/*.m) Sources/vgconvert.c whisper/ggml.c whisper/ggml-alloc.c whisper/ggml-backend.c whisper/ggml-quants.c whisper/whisper.cpp
VidGrab_FRAMEWORKS = Accelerate PhotosUI UIKit Foundation AVFoundation AVKit CoreMedia Photos JavaScriptCore CoreVideo WebKit LocalAuthentication MediaPlayer UserNotifications Security AudioToolbox UniformTypeIdentifiers
VidGrab_CFLAGS = -fobjc-arc -F$(PYFW_DIR) -Wno-deprecated-declarations -Wno-unused-function -I/root/ffmpeg-ios/include -Iwhisper -DGGML_USE_ACCELERATE -DNDEBUG -O3
VidGrab_LDFLAGS = -F$(PYFW_DIR) -framework Python -Wl,-rpath,@executable_path/Frameworks -L/root/ffmpeg-ios/lib -lavformat -lavcodec -lswresample -lavutil -lmp3lame -lc++
VidGrab_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/application.mk
