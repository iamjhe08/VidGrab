#!/bin/bash
# Rebuilds the FFmpeg static libraries VidGrab links (iOS arm64, iOS 15+) and installs them into /root/ffmpeg-ios.
#
# Needs:
#   - Theos with the iOS 16.5 SDK at /root/theos
#   - FFmpeg 7.1.1:  git clone --branch n7.1.1 https://github.com/FFmpeg/FFmpeg.git /root/ffmpeg-src
#   - The LAME MP3 encoder already in /root/ffmpeg-ios (include/lame/lame.h and lib/libmp3lame.a); it is left untouched.
#
# What is in the build (everything else is switched off to keep the app small):
#   decoders: vp9 vp8 h264 hevc opus vorbis aac aac_latm mp3float mp3 flac  + ac3 eac3 mp2float (sound from TS/HLS)
#   encoders: aac libmp3lame      demuxers: matroska mpegts mov flv mp3 aac ogg wav flac
#   muxers: mp4 ipod mov mp3      bitstream filters: aac_adtstoasc vp9_superframe_split + extract_extradata
#   No MPEG-2 on purpose (mpeg2video decoder + mpegvideo parser would add about 165 KB; see HANDOFF.md).
set -euo pipefail
T=${THEOS:-/root/theos}/toolchain/linux/iphone/bin
SDK=${THEOS:-/root/theos}/sdks/iPhoneOS16.5.sdk
SRC=${FFMPEG_SRC:-/root/ffmpeg-src}
DEST=${FFMPEG_DEST:-/root/ffmpeg-ios}
BUILD=$(mktemp -d /tmp/ffmpeg-ios-build.XXXXXX)
STAGE=$BUILD/stage
LAME=$BUILD/lame
mkdir -p "$LAME/include" "$LAME/lib"
cp -a "$DEST/include/lame" "$LAME/include/"       # a private copy, so the old FFmpeg headers in $DEST can't leak into the build
cp "$DEST/lib/libmp3lame.a" "$LAME/lib/"

cd "$BUILD"
"$SRC/configure" --prefix="$STAGE" --enable-cross-compile --target-os=darwin --arch=aarch64 \
  --cc=$T/clang --ar=$T/ar --ranlib=$T/ranlib --nm=$T/nm --strip=$T/strip --sysroot="$SDK" \
  --extra-cflags="-target arm64-apple-ios15.0 -isysroot $SDK -O3 -I$LAME/include" \
  --extra-ldflags="-target arm64-apple-ios15.0 -isysroot $SDK -fuse-ld=$T/ld -L$LAME/lib" \
  --disable-everything --disable-programs --disable-doc --disable-avdevice --disable-swscale --disable-postproc --disable-avfilter \
  --disable-network --disable-debug --enable-static --disable-shared --enable-pthreads --enable-swresample \
  --disable-videotoolbox --disable-audiotoolbox --disable-iconv --disable-zlib --disable-bzlib --disable-lzma --disable-securetransport \
  --disable-xlib --disable-sdl2 --disable-libxcb --enable-libmp3lame \
  --enable-decoder='vp9,vp8,h264,hevc,opus,vorbis,aac,aac_latm,mp3float,mp3,flac,ac3,eac3,mp2float' \
  --enable-encoder='aac,libmp3lame' \
  --enable-demuxer='matroska,mpegts,mov,flv,mp3,aac,ogg,wav,flac' \
  --enable-muxer='mp4,ipod,mov,mp3' \
  --enable-parser='h264,hevc,aac,aac_latm,vp9,vp8,opus,vorbis,mpegaudio,av1,flac' \
  --enable-bsf='aac_adtstoasc,vp9_superframe_split,extract_extradata' \
  --enable-protocol=file
make -j8
make install

cp "$STAGE"/lib/libavcodec.a "$STAGE"/lib/libavformat.a "$STAGE"/lib/libavutil.a "$STAGE"/lib/libswresample.a "$DEST/lib/"
cp "$STAGE"/lib/pkgconfig/*.pc "$DEST/lib/pkgconfig/"
for d in libavcodec libavformat libavutil libswresample; do rm -rf "$DEST/include/$d"; cp -a "$STAGE/include/$d" "$DEST/include/$d"; done
echo "FFmpeg installed into $DEST. Now rebuild the app from scratch: make clean && make FINALPACKAGE=1"
