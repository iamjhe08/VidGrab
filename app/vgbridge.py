"""VidGrab engine bridge.

Runs yt-dlp inside the app. The Objective-C side calls fetch() and download()
and gets JSON strings back. Progress, cancel and JavaScript are provided by the
native module `vgnative`, which the app registers before Python starts.
"""
import copy
import json
import math
import os
import re
import traceback

import vgnative
import yt_dlp
from yt_dlp.utils import DownloadCancelled

_infos = {}
_ANSI = re.compile(r'\x1b\[[0-9;]*m')
_PHOTOS_V = ('avc', 'h264', 'hvc', 'hev', 'h265', 'bytevc1')


# --------------------------------------------------------------------------
# JavaScript for YouTube, solved with Apple's JavaScriptCore via vgnative.
# --------------------------------------------------------------------------
def _register_jsc():
    try:
        from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP
        from yt_dlp.extractor.youtube.jsc.provider import (
            JsChallengeProviderError, register_preference, register_provider)
        from yt_dlp.extractor.youtube.pot._provider import BuiltinIEContentProvider
    except Exception:
        return False

    @register_provider
    class JavaScriptCoreJCP(EJSBaseJCP, BuiltinIEContentProvider):
        PROVIDER_NAME = 'javascriptcore'
        JS_RUNTIME_NAME = 'javascriptcore'

        def is_available(self, /):
            return True

        def _run_js_runtime(self, stdin, /):
            ok, out = vgnative.run_js(stdin)
            if not ok:
                raise JsChallengeProviderError(f'JavaScriptCore error: {out}')
            return out

    @register_preference(JavaScriptCoreJCP)
    def _pref(provider, requests):
        return 1000

    return True


_HAS_JS = _register_jsc()


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
class _Logger:
    def __init__(self):
        self.errors = []

    def debug(self, msg):
        pass

    def info(self, msg):
        pass

    def warning(self, msg):
        pass

    def error(self, msg):
        self.errors.append(_ANSI.sub('', str(msg)))


def _clean(msg):
    msg = _ANSI.sub('', str(msg)).strip()
    msg = re.sub(r'^ERROR:\s*', '', msg)
    msg = re.sub(r'^\[[^\]]+\]\s*[^:\s]*:\s*', '', msg)
    msg = re.sub(r'\s*\(caused by .*\)\s*$', '', msg, flags=re.S)
    low = msg.lower()
    if 'http error 404' in low:
        return "That page wasn't found. Check the link and try again."
    if 'http error 403' in low or 'http error 429' in low:
        return 'The site blocked the request. Wait a minute and try again, or update the engine in Settings.'
    if 'unable to download' in low or 'timed out' in low or 'urlopen error' in low or 'name or service' in low:
        return "Couldn't reach the site. Check your internet connection and try again."
    if 'Unsupported URL' in msg:
        return "This site isn't supported, or the link isn't a video page."
    if 'Sign in' in msg or 'login' in msg.lower() or 'private' in msg.lower():
        return 'This video needs an account to view (private or login only), so it can\'t be downloaded.'
    return msg or 'Something went wrong.'


def _params(cache_dir, **extra):
    p = {
        'quiet': True,
        'no_warnings': True,
        'noprogress': True,
        'noplaylist': True,
        'logger': _Logger(),
        'cachedir': cache_dir,
        'color': {'stdout': 'no_color', 'stderr': 'no_color'},
        'fixup': 'never',
        'socket_timeout': 20,
        'retries': 5,
        'fragment_retries': 10,
    }
    p.update(extra)
    return p


def _none(c):
    return c in (None, 'none')


def _photos_v(f):
    return (f.get('vcodec') or '').lower().startswith(_PHOTOS_V)


def _m4a(f):
    return (f.get('acodec') or '').lower().startswith('mp4a') or f.get('ext') == 'm4a'


def _hls(f):
    return 'm3u8' in (f.get('protocol') or '')


def _height(f):
    return f.get('height') or 0


def _short(f):
    h, w = f.get('height') or 0, f.get('width') or 0
    return min(h, w) if h and w else h


def _rank(f):
    return (_height(f), f.get('fps') or 0, f.get('tbr') or 0, f.get('filesize') or 0)


def _size(f, duration):
    s = f.get('filesize') or f.get('filesize_approx')
    if not s and f.get('tbr') and duration:
        s = f['tbr'] * 1000 / 8 * duration
    return s or 0


def _fmt_size(n):
    if not n:
        return None
    for unit in ('B', 'KB', 'MB', 'GB'):
        if n < 1000 or unit == 'GB':
            return f'{n:.0f} {unit}' if unit in ('B', 'KB') else f'{n:.1f} {unit}'.replace('.0 ', ' ')
        n /= 1000


def _kinds(info):
    fmts = info.get('formats') or [info]
    combined, video, audio, other = [], [], [], []
    for f in fmts:
        vn, an = _none(f.get('vcodec')), _none(f.get('acodec'))
        if f.get('format_note') == 'storyboard' or (f.get('ext') == 'mhtml'):
            continue
        if not vn and not an:
            # Some sites don't report codecs; treat as combined.
            (combined if (f.get('ext') == 'mp4' and not _hls(f)) else other).append(f)
        elif f.get('vcodec') is None and f.get('acodec') is None:
            (combined if (f.get('ext') == 'mp4' and not _hls(f)) else other).append(f)
        elif not vn:
            video.append(f)
        elif not an:
            audio.append(f)
    return combined, video, audio, other


def _audio_key(f):
    """Original-language sound first (YouTube marks it 10, default 5, dubbed -1,
    audio description -10), then the best bitrate."""
    lp = f.get('language_preference')
    return (lp if isinstance(lp, (int, float)) else 0, f.get('abr') or f.get('tbr') or 0)


def _plan(info, max_h):
    """Pick the formats for a target height. Returns (kind, [formats], photos_ok)."""
    combined, video, audio, other = _kinds(info)
    lim = (lambda f: _height(f) <= max_h) if max_h else (lambda f: True)

    good_c = [f for f in combined if lim(f) and (f.get('vcodec') is None or _photos_v(f))]
    good_v = [f for f in video if lim(f) and f.get('ext') == 'mp4' and _photos_v(f) and not _hls(f)]
    good_a = [f for f in audio if _m4a(f) and not _hls(f)]

    c = max(good_c, key=_rank, default=None)
    v = max(good_v, key=_rank, default=None)
    a = max(good_a, key=_audio_key, default=None)

    best_ready = max(_height(v) if (v and a) else 0, _height(c) if c else 0)

    # Higher qualities (1440p, 4K) usually exist only as VP9. If so, download the
    # VP9 stream and let the app convert it to HEVC so Photos can open it.
    if a and _CAN_CONVERT:
        vp9 = [f for f in video if lim(f) and _is_vp9(f) and not _hls(f)
               and (f.get('dynamic_range') in (None, 'SDR'))]
        x = max(vp9, key=_rank, default=None)
        if x and _height(x) > best_ready:
            return 'convert', [x, a], True

    if v and a and (not c or _height(v) > _height(c)):
        return 'merge', [v, a], True

    # Streaming sites (HLS) often send picture and sound as separate streams. Download both
    # and let the app join them (works for H.264/HEVC, or when the site doesn't list codecs).
    if _CAN_CONVERT and audio:
        hv = [f for f in video if lim(f) and (not f.get('vcodec') or _photos_v(f))]
        v2 = max(hv, key=_rank, default=None)
        a2 = max(audio, key=_audio_key, default=None)
        if v2 and a2 and _height(v2) > best_ready:
            return 'merge', [v2, a2], True

    if c:
        return 'single', [c], True

    # Nothing Photos-friendly: take the best single file that has sound.
    rest = [f for f in combined + other if lim(f)] or combined + other
    if rest:
        f = max(rest, key=_rank)
        return 'single', [f], False
    if video:
        f = max([f for f in video if lim(f)] or video, key=_rank)
        return 'single', [f], False
    return None, [], False


def _is_vp9(f):
    return (f.get('vcodec') or '').lower().startswith(('vp9', 'vp09'))


_CAN_CONVERT = bool(getattr(vgnative, 'can_convert', lambda: False)())


def _audio_plan(info):
    combined, _, audio, other = _kinds(info)
    good = [f for f in audio if _m4a(f) and not _hls(f)]
    if good:
        return [max(good, key=_audio_key)], True
    if audio:
        return [max(audio, key=_audio_key)], False
    if _CAN_CONVERT:
        # No sound-only stream: take the smallest file that has (or may have) sound;
        # the app pulls the sound out of it.
        rest = [f for f in combined + other if f.get('acodec') != 'none']
        if rest:
            return [min(rest, key=lambda f: (_height(f), f.get('tbr') or 0, f.get('filesize') or 0))], False
    return [], False


def _label(short_side, fps):
    if short_side >= 2000:
        s = f'4K'
    elif short_side >= 1400:
        s = f'2K'
    else:
        s = f'{short_side}p'
    if fps and fps > 30:
        s += f' {int(round(fps))}fps'
    return s


def _options(info):
    duration = info.get('duration') or 0
    _, video, _, _ = _kinds(info)
    heights = sorted({_height(f) for f in (info.get('formats') or [info]) if _height(f) >= 144}, reverse=True)

    opts, seen = [], set()

    def add(oid, plan, title=None):
        kind, fmts, photos = plan
        if not fmts:
            return
        main = fmts[0]
        res = _short(main)
        label = _label(res, main.get('fps')) if res else 'Original'
        if not title:
            if label in seen:
                return
            seen.add(label)
        size = sum(_size(f, duration) for f in fmts)
        bits = []
        if title:
            bits.append(label)
        if size:
            bits.append(_fmt_size(size))
        bits.append('MP4' if photos else ('TS file' if _hls(main) else (main.get('ext') or 'video').upper()))
        if kind == 'single' and not photos and _CAN_CONVERT:
            vc = (main.get('vcodec') or '').lower()
            if not vc or vc == 'none' or vc.startswith(_PHOTOS_V):
                photos = True            # H.264/HEVC in TS, FLV, MKV...: repackaged to MP4 in seconds
            elif vc.startswith(('vp9', 'vp09', 'vp8')):
                photos, kind = True, 'convert'   # re-encoded to HEVC on the phone
        fmt = 'MP4' if photos else ('TS' if _hls(main) else (main.get('ext') or 'video').upper())
        if kind == 'convert':
            # HEVC output is usually a bit smaller than the VP9 source; keep the estimate honest.
            size = size * 0.9
        opts.append({
            'id': oid,
            'convert': kind == 'convert',
            'title': title or label,
            'res': label,
            'detail': ' · '.join(bits),
            'size_text': _fmt_size(size) or '',
            'fmt': fmt,
            'photos': photos,
            'audio': False,
            'size': size,
        })

    for h in heights:
        add(f'h:{h}', _plan(info, h))
    if not opts:
        # Sites that don't report a resolution: offer the original file.
        add('best', _plan(info, None))

    afmts, aphotos = _audio_plan(info)
    if afmts:
        a = afmts[0]
        size = _size(a, duration)
        m4a = aphotos or _CAN_CONVERT
        ext = 'M4A' if m4a else (a.get('ext') or 'audio').upper()
        opts.append({
            'id': 'audio',
            'title': 'Audio',
            'res': 'Audio',
            'detail': ' · '.join(x for x in (_fmt_size(size), ext) if x),
            'size_text': _fmt_size(size) or '',
            'fmt': ext,
            'convert': False,
            'photos': False,
            'audio': True,
            'size': size,
        })
        if _CAN_CONVERT:
            mp3_size = 256000 / 8 * duration if duration else 0
            opts.append({
                'id': 'mp3',
                'title': 'MP3',
                'res': 'MP3',
                'detail': ' · '.join(x for x in (_fmt_size(mp3_size), 'MP3 256 kbps') if x),
                'size_text': _fmt_size(mp3_size) or '',
                'fmt': 'MP3 · 256 KBPS',
                'convert': False,
                'photos': False,
                'audio': True,
                'size': mp3_size,
            })
    return opts


# --------------------------------------------------------------------------
# Entry points (called from Objective-C, always return a JSON string)
# --------------------------------------------------------------------------
def version():
    return json.dumps({'ytdlp': yt_dlp.version.__version__, 'js': _HAS_JS})


def _cookie_params(cookiefile, youtube):
    # Browser sign-ins help sites like Instagram and Facebook. For YouTube they are
    # only used as a last resort (see download), since logged-out access is safer.
    if cookiefile and os.path.exists(cookiefile) and not youtube:
        return {'cookiefile': cookiefile}
    return {}


def _has_youtube_login(cookiefile):
    try:
        with open(cookiefile, encoding='utf-8') as f:
            text = f.read()
        return 'youtube.com' in text and ('SAPISID' in text or 'LOGIN_INFO' in text)
    except (OSError, TypeError):
        return False


def fetch(url, cache_dir, cookiefile=''):
    try:
        with yt_dlp.YoutubeDL(_params(cache_dir, **_cookie_params(cookiefile, _is_youtube(url, None)))) as ydl:
            info = ydl.extract_info(url, download=False)
        if not info:
            return json.dumps({'error': 'No video found at that link.'})
        if info.get('_type') == 'playlist':
            entries = [e for e in (info.get('entries') or []) if e]
            if not entries:
                return json.dumps({'error': 'No video found at that link.'})
            info = entries[0]
        _infos[url] = info
        thumbs = info.get('thumbnails') or []
        best_thumb = info.get('thumbnail')
        if thumbs:
            wide = [t for t in thumbs if t.get('url') and (t.get('width') or 0) >= 480]
            if wide:
                best_thumb = min(wide, key=lambda t: t.get('width') or 0)['url']
        opts = _options(info)
        if not opts:
            return json.dumps({'error': 'This link has no downloadable video.'})
        return json.dumps({
            'title': info.get('title') or 'Untitled video',
            'uploader': info.get('uploader') or info.get('channel') or info.get('extractor_key'),
            'site': info.get('extractor_key'),
            'thumbnail': best_thumb,
            'duration': info.get('duration') or 0,
            'options': opts,
        })
    except DownloadCancelled:
        return json.dumps({'error': 'Cancelled.'})
    except Exception as e:
        _remember(e)
        return json.dumps({'error': _clean(e)})


_last_raw = ''

# YouTube sometimes blocks a connection mode (HTTP 403) while experimenting with
# token requirements. When that happens we retry with modes that don't need tokens.
_YT_CLIENT_FALLBACKS = [None, ['visionos', 'web_embedded', 'mweb'], ['android'], ['tv_simply', 'web_safari']]
# (clients, use_cookies)


def _remember(e, logger=None):
    global _last_raw
    parts = [_ANSI.sub('', str(e)).strip()]
    if logger is not None:
        parts += [m for m in logger.errors if m not in parts[0]]
    _last_raw = '\n'.join(p for p in parts if p)


def _blocked(msg):
    low = msg.lower()
    return any(k in low for k in ('403', 'forbidden', '429', 'too many requests', 'confirm you', 'not a bot',
                                  'requested format is not available', 'only images are available'))


def _is_youtube(url, info):
    if info and (info.get('extractor_key') or '').lower().startswith('youtube'):
        return True
    return bool(re.search(r'(youtube\.com|youtu\.be|youtube-nocookie\.com)', url, re.I))


def _clear_dir(d):
    for n in os.listdir(d):
        try:
            os.remove(os.path.join(d, n))
        except OSError:
            pass


def _attempt(task, url, option_id, out_dir, cache_dir, clients, cookiefile=''):
    """One extract + download in a single session. Returns (result dict, error str, raw str)."""
    files = []
    parts = {}
    logger = _Logger()

    def hook(d):
        if vgnative.cancelled(task):
            raise DownloadCancelled()
        fid = (d.get('info_dict') or {}).get('format_id')
        i, n, stage = parts.get(fid, (0, max(len(parts), 1), 'video'))
        if d.get('status') == 'downloading':
            total = d.get('total_bytes') or d.get('total_bytes_estimate') or 0
            done = d.get('downloaded_bytes') or 0
            frac = done / total if total else 0.0
            if not total and d.get('fragment_count'):
                frac = (d.get('fragment_index') or 0) / d['fragment_count']
            vgnative.progress(task, i, n, min(frac, 1.0), stage, float(d.get('speed') or -1), float(d.get('eta') or -1))
        elif d.get('status') == 'finished':
            files.append(d.get('filename'))
            vgnative.progress(task, i, n, 1.0, stage, -1.0, -1.0)

    # Speed: fetch 8 pieces of a stream at once, and ask for big files in 10 MB slices
    # (sites like YouTube slow down one long request but not many short ones).
    params = _params(cache_dir, logger=logger, progress_hooks=[hook], overwrites=True, hls_prefer_native=True,
                     concurrent_fragment_downloads=8, http_chunk_size=10 * 1024 * 1024,
                     outtmpl={'default': os.path.join(out_dir, '%(title).80B.f%(format_id)s.%(ext)s')})
    if clients:
        params['extractor_args'] = {'youtube': {'player_client': clients}}
    if cookiefile:
        params['cookiefile'] = cookiefile

    try:
        with yt_dlp.YoutubeDL(params) as ydl:
            info = ydl.extract_info(url, download=False)
            if info and info.get('_type') == 'playlist':
                info = next((e for e in (info.get('entries') or []) if e), None)
            if not info:
                return None, 'No video found at that link.', ''

            if option_id in ('audio', 'mp3'):
                fmts, photos = _audio_plan(info)
                kind = 'mp3' if option_id == 'mp3' else 'audio'
            else:
                h = None if option_id == 'best' else int(option_id.split(':', 1)[1])
                kind, fmts, photos = _plan(info, h)
                if kind == 'single' and not photos and _CAN_CONVERT and fmts:
                    vc = (fmts[0].get('vcodec') or '').lower()
                    if not vc or vc == 'none' or vc.startswith(_PHOTOS_V) or vc.startswith(('vp9', 'vp09', 'vp8')):
                        photos = True    # the app converts it to MP4 after downloading
            if not fmts:
                return None, 'requested format is not available', 'requested format is not available'

            for i, f in enumerate(fmts):
                stage = 'audio' if (_none(f.get('vcodec')) and not _none(f.get('acodec'))) else 'video'
                parts[f['format_id']] = (i, len(fmts), stage)
            # Same session, so cookies and connection details from the lookup are reused.
            # yt-dlp builds its format chooser once at start-up, so replace it here; the
            # comma means "download each separately" (the app joins them, no ffmpeg needed).
            spec = ','.join(f['format_id'] for f in fmts)
            for k in ('requested_formats', 'requested_downloads'):
                info.pop(k, None)
            ydl.params['format'] = spec
            ydl.format_selector = ydl.build_format_selector(spec)
            ydl.process_ie_result(info, download=True)
    except DownloadCancelled:
        return None, 'Cancelled.', ''
    except Exception as e:
        if vgnative.cancelled(task):
            return None, 'Cancelled.', ''
        _remember(e, logger)
        return None, _clean(e), _last_raw

    files = [p for p in dict.fromkeys(files) if p and os.path.exists(p)]
    if len(files) < len(fmts):
        found = sorted((os.path.join(out_dir, n) for n in os.listdir(out_dir)
                        if not n.endswith(('.part', '.ytdl')) and '.temp.' not in n),
                       key=os.path.getmtime)
        files = found[-len(fmts):]
    if not files:
        return None, 'The download finished but no file was saved.', ''

    # Keep video first, audio second for joining.
    def order(path):
        m = re.search(r'\.f([^.]+)\.[^.]+$', path)
        return parts.get(m.group(1), (0,))[0] if m else 0
    files.sort(key=order)
    title = info.get('title') or 'video'
    safe = re.sub(r'[\\/:*?"<>|\n\r\t]+', ' ', title).strip()[:80] or 'video'
    return {
        'kind': kind if kind in ('merge', 'convert', 'audio', 'mp3') else 'single',
        'title': info.get('title') or '',
        'uploader': info.get('uploader') or info.get('channel') or '',
        'files': files,
        'photos': photos,
        'name': safe,
        'hls': bool(fmts and _hls(fmts[0])),
    }, None, ''


def download(task, url, option_id, out_dir, cache_dir, cookiefile=''):
    youtube = _is_youtube(url, _infos.get(url))
    if youtube:
        attempts = [(c, '') for c in _YT_CLIENT_FALLBACKS]
        if _has_youtube_login(cookiefile):
            attempts.append((None, cookiefile))  # signed in via the browser: last resort
    else:
        attempts = [(None, _cookie_params(cookiefile, False).get('cookiefile', ''))]
    error = 'Something went wrong.'
    for n, (clients, cookies) in enumerate(attempts):
        if vgnative.cancelled(task):
            return json.dumps({'error': 'Cancelled.'})
        if n:
            vgnative.progress(task, 0, 1, 0.0, 'retry', -1.0, -1.0)
        _clear_dir(out_dir)
        result, error, raw = _attempt(task, url, option_id, out_dir, cache_dir, clients, cookies)
        if result:
            return json.dumps(result)
        if error == 'Cancelled.' or not _blocked(raw or error):
            break
    if _blocked(_last_raw):
        error = ('YouTube blocked this download, even after trying other ways to connect. '
                 'Try again in a few minutes, or tap the gear icon and update the download engine.')
        if youtube and not _has_youtube_login(cookiefile):
            error += ' Signing in to YouTube in the Browse tab can also help.'
    return json.dumps({'error': error})


def last_error():
    return json.dumps({'details': _last_raw or 'No error details recorded.'})


def forget(url):
    _infos.pop(url, None)
    return '{}'


def describe_error():
    return traceback.format_exc()
