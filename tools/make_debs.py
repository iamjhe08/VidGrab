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
    # Nothing else: the bubble over other apps is started by the jailbreak's background
    # service (see daemon_plist), so the app itself needs no extra permissions.
}

DAEMON = 'com.t4mag0.vidgrab.hud'

POSTINST = '''#!/bin/sh
APP="{prefix}/Applications/VidGrab.app"
PL="{prefix}/Library/LaunchDaemons/{daemon}.plist"
if command -v jbroot >/dev/null 2>&1; then APP="$(jbroot /Applications/VidGrab.app)"; PL="$(jbroot /Library/LaunchDaemons/{daemon}.plist)"; fi
if command -v uicache >/dev/null 2>&1; then uicache -p "$APP" >/dev/null 2>&1 || uicache >/dev/null 2>&1; fi
# The floating download bubble service (stays hidden until you leave VidGrab with downloads running).
launchctl unload "$PL" >/dev/null 2>&1
launchctl load "$PL" >/dev/null 2>&1
exit 0
'''

PRERM = '''#!/bin/sh
PL="{prefix}/Library/LaunchDaemons/{daemon}.plist"
if command -v jbroot >/dev/null 2>&1; then PL="$(jbroot /Library/LaunchDaemons/{daemon}.plist)"; fi
launchctl unload "$PL" >/dev/null 2>&1
exit 0
'''

POSTRM = '''#!/bin/sh
if command -v uicache >/dev/null 2>&1; then uicache >/dev/null 2>&1; fi
exit 0
'''


def daemon_plist(prefix):
    # Same settings TrollSpeed uses for its jailbreak bubble service.
    return {
        'Label': DAEMON,
        'ProgramArguments': [f'{prefix}/Applications/VidGrab.app/VidGrabHUD', '-daemon'],
        'RunAtLoad': True,
        'KeepAlive': True,
        'ThrottleInterval': 5,
        'UserName': 'root',
        'GroupName': 'wheel',
        'POSIXSpawnType': 'App',
        'ProcessType': 'Interactive',
        'EnablePressuredExit': False,
        'EnableTransactions': False,
        'HighPriorityIO': True,
        'EnvironmentVariables': {'DISABLE_TWEAKS': '1'},
        '_AdditionalProperties': {'RunningBoard': {'Managed': False, 'Reported': False}},
    }


def slim(app):
    """Fewer files for the package manager: keep only the compiled .pyc of each Python file (next to
    where the .py was) and drop the .py sources and __pycache__ folders. Halves the file count, which
    is what makes some converters (roothide, rootless) crawl."""
    removed = 0
    for r, ds, fs in os.walk(app):
        if '__pycache__' in ds:
            cache = os.path.join(r, '__pycache__')
            for n in os.listdir(cache):
                if n.endswith('.cpython-314.pyc') and os.path.exists(os.path.join(r, n.split('.')[0] + '.py')):
                    shutil.move(os.path.join(cache, n), os.path.join(r, n.split('.cpython-314.pyc')[0] + '.pyc'))
                    os.remove(os.path.join(r, n.split('.cpython-314.pyc')[0] + '.py'))
                    removed += 1
            shutil.rmtree(cache)
            ds.remove('__pycache__')
    return removed


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else HERE
    with open(os.path.join(APP, 'Info.plist'), 'rb') as f:
        version = plistlib.load(f)['CFBundleShortVersionString']
    size_kb = 0   # filled per package below

    for scheme, (arch, prefix) in SCHEMES.items():
        root = tempfile.mkdtemp()
        os.chmod(root, 0o755)
        dest = os.path.join(root, prefix.lstrip('/'), 'Applications', 'VidGrab.app')
        shutil.copytree(APP, dest, symlinks=True)
        if os.environ.get('VG_SLIM') == '1':
            print('slimmed', slim(dest), 'python files')
        # Everything must be readable by the phone's normal user (the app doesn't run as root).
        for r, ds, fs in os.walk(dest):
            for n in ds + fs:
                p = os.path.join(r, n)
                if not os.path.islink(p):
                    os.chmod(p, os.stat(p).st_mode | 0o444 | (0o111 if os.path.isdir(p) else 0))
        ent = os.path.join(root, 'ent.plist')
        with open(ent, 'wb') as f:
            plistlib.dump(ENTITLEMENTS, f)
        subprocess.run([LDID, '-S' + ent, os.path.join(dest, 'VidGrab')], check=True)
        os.remove(ent)

        ld = os.path.join(root, prefix.lstrip('/'), 'Library', 'LaunchDaemons')
        os.makedirs(ld)
        with open(os.path.join(ld, DAEMON + '.plist'), 'wb') as f:
            plistlib.dump(daemon_plist(prefix), f)
        os.chmod(os.path.join(ld, DAEMON + '.plist'), 0o644)

        size_kb = sum(os.path.getsize(os.path.join(r, n)) for r, _, fs in os.walk(root) for n in fs) // 1024
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
Section: Applications
Homepage: https://github.com/iamjhe08/VidGrab
Installed-Size: {size_kb}
''')
        for name, body in (('postinst', POSTINST.format(prefix=prefix, daemon=DAEMON)),
                           ('prerm', PRERM.format(prefix=prefix, daemon=DAEMON)), ('postrm', POSTRM)):
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
