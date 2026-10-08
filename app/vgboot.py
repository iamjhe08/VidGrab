"""Startup and engine updates. Must not import yt_dlp at module level."""
import os
import sys


def _ctypes_guard():
    """Some jailbreaks (seen on iOS 15) can't start Python's ctypes part: importing it raises
    MemoryError and takes the whole engine down. Python only needs it to read the iOS version,
    so answer that ourselves and make ctypes a normal "not available" for everything else."""
    if sys.platform != 'ios':
        return
    try:
        import _ctypes  # noqa: F401  (works on most phones; then nothing changes)
        return
    except BaseException:
        pass
    import types
    sys.modules['ctypes'] = None      # later "import ctypes" -> ImportError, which yt-dlp handles
    sys.modules['_ctypes'] = None
    m = types.ModuleType('_ios_support')
    m.get_platform_ios = lambda: (os.environ.get('VG_IOS_NAME') or 'iOS', os.environ.get('VG_IOS_VERSION') or '',
                                  os.environ.get('VG_IOS_MODEL') or 'iPhone', False)
    sys.modules['_ios_support'] = m


_ctypes_guard()

import json
import os
import re
import shutil
import ssl
import sys
import tempfile
import urllib.request
import zipfile

_VER = re.compile(r"__version__\s*=\s*'([^']+)'")


def _version_in(root):
    try:
        with open(os.path.join(root, 'yt_dlp', 'version.py'), encoding='utf-8') as f:
            m = _VER.search(f.read())
            return m.group(1) if m else None
    except OSError:
        return None


def _vtuple(v):
    return tuple(int(x) for x in re.findall(r'\d+', v or '0'))


def setup(engine_dir, bundled_dir):
    """Put the newest yt-dlp (bundled or updated) first on sys.path."""
    os.environ.setdefault('PYTHONIOENCODING', 'utf-8')
    try:
        import certifi
        os.environ['SSL_CERT_FILE'] = certifi.where()
    except Exception:
        pass
    updated, bundled = _version_in(engine_dir), _version_in(bundled_dir)
    if updated and _vtuple(updated) > _vtuple(bundled):
        sys.path.insert(0, engine_dir)
        return updated
    return bundled


def _ctx():
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        return ssl.create_default_context()


def _get(url, timeout=30):
    req = urllib.request.Request(url, headers={'User-Agent': 'VidGrab', 'Accept': 'application/vnd.github+json'})
    return urllib.request.urlopen(req, timeout=timeout, context=_ctx())


def update_engine(engine_dir, current_version):
    try:
        with _get('https://api.github.com/repos/yt-dlp/yt-dlp-nightly-builds/releases/latest') as r:
            latest = json.load(r).get('tag_name', '')
        if latest and _vtuple(latest) <= _vtuple(current_version):
            return json.dumps({'status': 'current', 'version': current_version})

        tmp = tempfile.mkdtemp()
        zpath = os.path.join(tmp, 'yt-dlp.zip')
        with _get('https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp', timeout=120) as r, \
                open(zpath, 'wb') as f:
            shutil.copyfileobj(r, f)

        staging = engine_dir + '.new'
        shutil.rmtree(staging, ignore_errors=True)
        with zipfile.ZipFile(zpath) as z:
            names = [n for n in z.namelist() if n.startswith(('yt_dlp/', 'yt_dlp_ejs/'))]
            if not any(n == 'yt_dlp/version.py' for n in names):
                raise RuntimeError('Downloaded file is not a yt-dlp package')
            for n in names:
                z.extract(n, staging)
        new_version = _version_in(staging)
        shutil.rmtree(engine_dir, ignore_errors=True)
        os.replace(staging, engine_dir)
        shutil.rmtree(tmp, ignore_errors=True)
        return json.dumps({'status': 'updated', 'version': new_version or latest})
    except Exception as e:
        return json.dumps({'status': 'error', 'error': f"Couldn't update the engine: {e}"})
