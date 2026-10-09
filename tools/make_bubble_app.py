#!/usr/bin/env python3
"""Builds VidGrab-Bubble-<ver>.tipa (the TrollStore helper app). Run after assemble.py (needs hud/.theos/obj/VidGrabHUD)."""
import os, plistlib, shutil, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LDID = '/root/theos/toolchain/linux/iphone/bin/ldid'
out = sys.argv[1]
ver = sys.argv[2] if len(sys.argv) > 2 else '1.3.4'
env = dict(os.environ, THEOS='/root/theos')
subprocess.run(['make', '-C', os.path.join(HERE, 'helper'), 'FINALPACKAGE=1'], check=True, env=env)
src = os.path.join(HERE, 'helper', '.theos', 'obj', 'VidGrabBubble.app')
work = os.path.join(HERE, 'stage-bubble')
shutil.rmtree(work, ignore_errors=True)
app = os.path.join(work, 'Payload', 'VidGrabBubble.app')
os.makedirs(os.path.dirname(app))
shutil.copytree(src, app)
shutil.copy2(os.path.join(HERE, 'hud', '.theos', 'obj', 'VidGrabHUD'), os.path.join(app, 'VidGrabHUD'))
os.chmod(os.path.join(app, 'VidGrabHUD'), 0o755)
subprocess.run([LDID, '-S' + os.path.join(HERE, 'hud', 'entitlements.plist'), os.path.join(app, 'VidGrabHUD')], check=True)
ent = {
    'application-identifier': 'com.t4mag0.vidgrab.bubble',
    'platform-application': True,
    'com.apple.private.security.no-sandbox': True,
    'com.apple.private.security.storage.AppDataContainers': True,
    'com.apple.private.persona-mgmt': True,
    'com.apple.springboard.launchapplications': True,
    'com.apple.springboard.opensensitiveurl': True,
}
ep = os.path.join(work, 'ent.plist')
with open(ep, 'wb') as f: plistlib.dump(ent, f)
subprocess.run([LDID, '-S' + ep, os.path.join(app, 'VidGrabBubble')], check=True)
os.makedirs(out, exist_ok=True)
dest = os.path.join(out, 'VidGrab-Bubble-%s.tipa' % ver)
if os.path.exists(dest): os.remove(dest)
with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as z:
    for r, d, fs in os.walk(os.path.join(work, 'Payload')):
        for fn in fs:
            p = os.path.join(r, fn)
            z.write(p, os.path.relpath(p, work))
print(dest, os.path.getsize(dest))
