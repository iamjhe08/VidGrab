#!/usr/bin/env python3
"""Packs the built VidGrab.app (from assemble.py) into jailbreak .deb files.

Makes three packages from the same app, one per jailbreak type:
  rootful   iphoneos-arm      app in /Applications
  rootless  iphoneos-arm64    app in /var/jb/Applications
  roothide  iphoneos-arm64e   app in /Applications inside roothide's jbroot

Everything VidGrab needs is inside the app, so the packages have no dependencies.
Usage: python3 tools/make_debs.py <out_dir>
"""
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(HERE, 'stage', 'Payload', 'VidGrab.app')
LDID = '/root/theos/toolchain/linux/iphone/bin/ldid'
PACKAGE = 'com.t4mag0.vidgrab'

SCHEMES = {
    'rootful': ('iphoneos-arm', ''),
    'rootless': ('iphoneos-arm64', '/var/jb'),
    'roothide': ('iphoneos-arm64e', ''),
}

# Jailbreak apps live outside the normal app folder, so ask iOS for a private data folder
# (Documents, Caches) the same way App Store apps get one.
ENTITLEMENTS = {
    'application-identifier': PACKAGE,
    'com.apple.private.security.container-required': True,
}

POSTINST = '''#!/bin/sh
APP="{prefix}/Applications/VidGrab.app"
if command -v jbroot >/dev/null 2>&1; then APP="$(jbroot /Applications/VidGrab.app)"; fi
if command -v uicache >/dev/null 2>&1; then uicache -p "$APP" >/dev/null 2>&1 || uicache >/dev/null 2>&1; fi
exit 0
'''

POSTRM = '''#!/bin/sh
if command -v uicache >/dev/null 2>&1; then uicache >/dev/null 2>&1; fi
exit 0
'''


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else HERE
    with open(os.path.join(APP, 'Info.plist'), 'rb') as f:
        version = plistlib.load(f)['CFBundleShortVersionString']
    size_kb = sum(os.path.getsize(os.path.join(r, n)) for r, _, fs in os.walk(APP) for n in fs) // 1024

    for scheme, (arch, prefix) in SCHEMES.items():
        root = tempfile.mkdtemp()
        dest = os.path.join(root, prefix.lstrip('/'), 'Applications', 'VidGrab.app')
        shutil.copytree(APP, dest, symlinks=True)
        ent = os.path.join(root, 'ent.plist')
        with open(ent, 'wb') as f:
            plistlib.dump(ENTITLEMENTS, f)
        subprocess.run([LDID, '-S' + ent, os.path.join(dest, 'VidGrab')], check=True)
        os.remove(ent)

        debian = os.path.join(root, 'DEBIAN')
        os.makedirs(debian)
        with open(os.path.join(debian, 'control'), 'w') as f:
            f.write(f'''Package: {PACKAGE}
Name: VidGrab
Version: {version}
Architecture: {arch}
Description: Download videos from YouTube and other sites. Paste a link or use the built-in browser.
Maintainer: T4MAG0
Author: T4MAG0
Section: Utilities
Homepage: https://github.com/iamjhe08/VidGrab
Installed-Size: {size_kb}
''')
        for name, body in (('postinst', POSTINST.format(prefix=prefix)), ('postrm', POSTRM)):
            p = os.path.join(debian, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)

        out = os.path.join(out_dir, f'{PACKAGE}_{version}_{arch}.deb')
        subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-b', root, out], check=True,
                       stdout=subprocess.DEVNULL)
        shutil.rmtree(root)
        print(f'{scheme:9s} {out} {os.path.getsize(out) / 1e6:.1f} MB')


if __name__ == '__main__':
    main()
