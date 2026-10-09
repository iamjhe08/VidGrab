#!/usr/bin/env python3
"""Builds the TrollStore .tipa from stage/ (run after assemble.py): VidGrab.ipa plus the Bubble helper .tipa inside."""
import os, plistlib, shutil, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LDID = '/root/theos/toolchain/linux/iphone/bin/ldid'
dest = sys.argv[1]
work = os.path.join(HERE, 'stage-tipa')
shutil.rmtree(work, ignore_errors=True)
app = os.path.join(work, 'Payload', 'VidGrab.app')
os.makedirs(os.path.dirname(app))
shutil.copytree(os.path.join(HERE, 'stage', 'Payload', 'VidGrab.app'), app)
# Havoc (and TrollStore) want a bundle identifier of their own for the .tipa, different from the .deb / .ipa.
TS_ID = 'com.t4mag0.vidgrab.ts'
def set_id(path, new):
    with open(path, 'rb') as f: d = plistlib.load(f)
    d['CFBundleIdentifier'] = new
    with open(path, 'wb') as f: plistlib.dump(d, f)
set_id(os.path.join(app, 'Info.plist'), TS_ID)
set_id(os.path.join(app, 'PlugIns', 'VGShare.appex', 'Info.plist'), TS_ID + '.share')
shutil.copy2(sys.argv[2], os.path.join(app, 'VidGrabBubble.tipa'))   # the small Bubble app, installed from Settings
for r, ds, fs in os.walk(app):
    for n in ds + fs:
        p = os.path.join(r, n)
        if not os.path.islink(p): os.chmod(p, os.stat(p).st_mode | 0o444 | (0o111 if os.path.isdir(p) else 0))
if os.path.exists(dest): os.remove(dest)
with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for r, d, fs in os.walk(os.path.join(work, 'Payload')):
        for fn in fs:
            p = os.path.join(r, fn)
            zi = zipfile.ZipInfo.from_file(p, os.path.relpath(p, work)); zi.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(zi, open(p,'rb').read(), compresslevel=9)
print(dest, os.path.getsize(dest))
