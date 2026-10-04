# VidGrab 1.0.0

Download videos on iPhone by pasting a link or by browsing to a video and tapping Download.

By T4MAG0 · https://github.com/iamjhe08

## Features
- Paste a link and pick the quality, up to 4K when the site offers it
- Built-in browser with a Download button on playing videos and an ad blocker
- Up to 10 downloads at the same time, with progress on every screen
- Saves as MP4 that plays on iPhone and goes into Photos; MP3 or M4A for sound only
- YouTube downloads keep the original audio language
- Editable favorites, cache cleaning, Fix playback and Video info tools

## Requirements
- iOS 15.0 or later, arm64
- Installed with TrollStore or any sideloading method (no jailbreak needed)

## Built with
- yt-dlp (Unlicense)
- Python 3.14 for iOS, BeeWare Python-Apple-support (PSF License)
- FFmpeg 7.1.1 (LGPL 2.1 or later), built from unmodified source as static libraries
- LAME 3.100 (LGPL)
- certifi (MPL 2.0), requests and urllib3 (Apache 2.0 / MIT), idna (BSD), charset-normalizer (MIT), websockets (BSD)
- Ad-block filter lists from uBlock Origin Lite defaults (GPLv3) and Peter Lowe's list (free for non-commercial use)

## Install
Download VidGrab.ipa from the Releases page and install it with TrollStore or your sideloading app.

## Building from source
Built on Linux or macOS with Theos (iOS 16.5 SDK, targets iOS 15.0, arm64).

You also need:
- Python.xcframework from BeeWare Python-Apple-support (3.14), with the ios-arm64 Python.framework copied to `vendor/ios-arm64`
- FFmpeg 7.1.1 and LAME 3.100 built as static iOS libraries (decoders, demuxers and muxers listed in the Makefile flags)
- yt-dlp and the Python packages listed above, installed for iOS into an app_packages folder

Paths to these are set at the top of `Makefile` and `assemble.py`. Then run:

```
make FINALPACKAGE=1
python3 assemble.py
```

This produces `VidGrab.ipa`.

## License
VidGrab's own code is released under the GNU GPL v3 (see LICENSE). Bundled parts keep their own licenses as listed above.

Please respect each site's terms and only download videos you have the right to save.
