#!/bin/sh
# Builds a throwaway "old version" IPA (given version, no iOS 15 fix) for testing in-app updates,
# then puts the source back the way it was. Usage: tools/make_update_test.sh 1.0.7 /path/out.ipa
set -e
cd "$(dirname "$0")/.."
VER="$1"; OUT="$2"
python3 - "$VER" <<'PY'
import sys
p='Sources/VGBrowserViewController.m'; s=open(p).read()
a=s.index('    // Tell sites the real iOS version'); b=s.index('cfg.websiteDataStore')
s=s[:a]+'    cfg.applicationNameForUserAgent = @"Version/17.0 Mobile/15E148 Safari/604.1";\n    '+s[b:]
a=s.index('    // On iOS 15 and 16, add the newer'); b=s.index('    [ucc addUserScript:[[WKUserScript alloc] initWithSource:kOverlayJS')
s=s[:a]+s[b:]; open(p,'w').write(s)
import re
p='Resources/Info.plist'; s=open(p).read()
s=re.sub(r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*', r'\g<1>'+sys.argv[1], s); open(p,'w').write(s)
PY
rm -f Resources/polyfills.js .theos/obj/VidGrab.app/polyfills.js
make -j8 FINALPACKAGE=1 >/dev/null && python3 assemble.py >/dev/null && cp VidGrab.ipa "$OUT"
git checkout -- Sources Resources
make -j8 FINALPACKAGE=1 >/dev/null && python3 assemble.py >/dev/null
