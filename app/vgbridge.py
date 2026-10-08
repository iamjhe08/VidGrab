"""VidGrab engine bridge.

Runs yt-dlp inside the app. The Objective-C side calls fetch() and download()
and gets JSON strings back. Progress, cancel and JavaScript are provided by the
native module `vgnative`, which the app registers before Python starts.
"""
import copy
import hashlib
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


def _pick_option(info, want):
    """Turns a playlist-wide choice ('best', 'mp3', or a height like '1080') into this video's option."""
    opts = _options(info)
    ids = [o['id'] for o in opts]
    if want == 'mp3':
        return 'mp3' if 'mp3' in ids else ('audio' if 'audio' in ids else (ids[0] if ids else 'best'))
    videos = [o for o in opts if not o['audio']]
    if not videos:
        return ids[0] if ids else 'best'
    if want == 'best':
        return videos[0]['id']
    try:
        limit = int(want)
    except ValueError:
        return videos[0]['id']
    for o in videos:                       # sorted from highest to lowest
        if o['id'].startswith('h:') and int(o['id'][2:]) <= limit:
            return o['id']
    return videos[-1]['id']


# --------------------------------------------------------------------------
# Links the in-app browser caught while a page was playing (or direct media links).
# The app sends the page's own request details (Referer, cookies, browser name) as a JSON
# string called "extra", so the site hands over the stream the same way it does to the player.
# --------------------------------------------------------------------------
def _extra(extra_json):
    try:
        d = json.loads(extra_json) if extra_json else {}
    except (TypeError, ValueError):
        d = {}
    return d if isinstance(d, dict) else {}


def _apply_extra(params, extra):
    h = extra.get('headers')
    if isinstance(h, dict) and h:
        params['http_headers'] = {str(k): str(v) for k, v in h.items() if v}


def _sniff(ydl, url, headers):
    """Looks at the first bytes of a link. Returns (kind, ext): kind is 'hls', 'dash' or 'file', or None."""
    from yt_dlp.networking import Request
    h = {str(k): str(v) for k, v in (headers or {}).items()}
    h['Range'] = 'bytes=0-4095'
    resp = ydl.urlopen(Request(url, headers=h))
    try:
        head = resp.read(4096)
        ct = (resp.headers.get('Content-Type') or '').lower()
    finally:
        try:
            resp.close()
        except Exception:
            pass
    if head.startswith(b'#EXTM3U') or 'mpegurl' in ct:
        return 'hls', 'mp4'
    if b'<MPD' in head[:1024] or 'dash+xml' in ct:
        return 'dash', 'mp4'
    if len(head) > 189 and head[0:1] == b'G' and head[188:189] == b'G':
        return 'file', 'ts'
    if head[4:8] == b'ftyp':
        return 'file', 'mp4'
    if head[:4] == b'\x1a\x45\xdf\xa3':
        return 'file', 'webm' if b'webm' in head[:64] else 'mkv'
    if head[:3] == b'FLV':
        return 'file', 'flv'
    if ct.startswith('video/'):
        return 'file', 'mp4'
    return None, None


def _direct_info(ydl, url, extra):
    """Builds the video information for a stream link yt-dlp has no extractor for, using the
    request details the browser saw. HLS playlists and DASH manifests are read for their qualities."""
    headers = dict(extra.get('headers') or {})
    kind = extra.get('kind') or None
    ext = 'mp4'
    if kind in (None, 'file'):
        k, e = _sniff(ydl, url, headers)
        if k:
            kind, ext = k, e
        elif kind is None:
            return None
    kind = kind or 'file'
    vid = hashlib.md5(url.encode('utf-8')).hexdigest()[:12]
    ie = ydl.get_info_extractor('Generic')
    if kind == 'hls':
        formats = ie._extract_m3u8_formats(url, vid, 'mp4', m3u8_id='hls', headers=headers, fatal=True)
    elif kind == 'dash':
        formats = ie._extract_mpd_formats(url, vid, mpd_id='dash', headers=headers, fatal=True)
    else:
        formats = [{'url': url, 'format_id': 'file', 'ext': ext, 'protocol': 'https' if url.startswith('https') else 'http'}]
    if not formats:
        return None
    for f in formats:
        if headers:
            f.setdefault('http_headers', dict(headers))
    title = (extra.get('title') or '').strip()
    if not title:
        m = re.match(r'https?://([^/]+)', url)
        title = m.group(1) if m else 'Video'
    return {
        'id': vid,
        'title': title,
        'formats': formats,
        'http_headers': headers,
        'extractor': 'direct',
        'extractor_key': 'Direct',
        'webpage_url': extra.get('page') or url,
    }


def _extract(ydl, url, extra):
    """Normal lookup. Links the browser caught play-first go straight to the direct route; a link
    yt-dlp doesn't recognise gets one more chance by looking at what the address really serves."""
    if extra.get('kind'):
        info = _direct_info(ydl, url, extra)
        if not info:
            raise yt_dlp.utils.ExtractorError('This link has no downloadable video.', expected=True)
        return info
    try:
        return ydl.extract_info(url, download=False)
    except DownloadCancelled:
        raise
    except Exception as e:
        if 'Unsupported URL' not in str(e):
            raise
        try:
            info = _direct_info(ydl, url, extra)
        except Exception:
            info = None
        if info:
            return info
        raise


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


_PLAYLIST_MAX = 500


def _entry_url(e):
    u = e.get('webpage_url') or e.get('url') or ''
    if u and not u.startswith('http'):
        if (e.get('ie_key') or '').lower().startswith('youtube') and re.fullmatch(r'[\w-]{11}', u):
            u = 'https://www.youtube.com/watch?v=' + u
    return u


def _entry_thumb(e):
    thumbs = [t for t in (e.get('thumbnails') or []) if t.get('url')]
    if thumbs:
        wide = [t for t in thumbs if (t.get('width') or 0) >= 320]
        return (min(wide, key=lambda t: t.get('width') or 0) if wide else thumbs[-1])['url']
    return e.get('thumbnail')


def _playlist_json(info):
    """A playlist or channel: its videos, without looking each one up (fast)."""
    entries = []
    for e in info.get('entries') or []:
        if not e:
            continue
        u = _entry_url(e)
        if not u:
            continue
        entries.append({'url': u, 'title': e.get('title') or 'Untitled video',
                        'duration': e.get('duration') or 0, 'thumbnail': _entry_thumb(e)})
        if len(entries) >= _PLAYLIST_MAX:
            break
    return {
        'playlist': True,
        'title': info.get('title') or 'Playlist',
        'uploader': info.get('uploader') or info.get('channel') or '',
        'site': info.get('extractor_key') or '',
        'thumbnail': (entries[0]['thumbnail'] if entries else None) or _entry_thumb(info),
        'count': len(entries),
        'entries': entries,
    }


def _looks_like_tabs(entries):
    """A YouTube channel link lists its tabs (Videos, Shorts, Live) instead of videos."""
    urls = [_entry_url(e) for e in entries[:6]]
    return bool(urls) and all(re.search(r'/(videos|shorts|streams|live|playlists|featured)/?$', u or '') for u in urls)


def fetch(url, cache_dir, cookiefile='', extra=''):
    try:
        ex = _extra(extra)
        params = _params(cache_dir, **_cookie_params(cookiefile, _is_youtube(url, None)))
        params['extract_flat'] = 'in_playlist'     # playlists: list the videos without opening each one
        _apply_extra(params, ex)
        with yt_dlp.YoutubeDL(params) as ydl:
            info = _extract(ydl, url, ex)
            if info and info.get('_type') == 'playlist':
                entries = [e for e in (info.get('entries') or []) if e]
                if entries and _looks_like_tabs(entries):
                    tab = next((e for e in entries if re.search(r'/videos/?$', _entry_url(e))), entries[0])
                    sub = ydl.extract_info(_entry_url(tab), download=False)
                    if sub and sub.get('_type') == 'playlist':
                        sub.setdefault('title', info.get('title'))
                        info, entries = sub, [e for e in (sub.get('entries') or []) if e]
                if len(entries) > 1:
                    return json.dumps(_playlist_json(info))
                if not entries:
                    return json.dumps({'error': 'No video found at that link.'})
                info = ydl.extract_info(_entry_url(entries[0]), download=False)
        if not info:
            return json.dumps({'error': 'No video found at that link.'})
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


# --------------------------------------------------------------------------
# Streaming: pick links the built-in player can play right away (no download).
# --------------------------------------------------------------------------
def _stream_headers(f, info):
    h = {}
    h.update(info.get('http_headers') or {})
    h.update(f.get('http_headers') or {})
    return {str(k): str(v) for k, v in h.items() if v}


def _stream_pick(info, max_h, audio_only):
    """Returns a list of formats the player can play: one (picture and sound together)
    or two (picture, then sound, which the player joins on the fly)."""
    combined, video, audio, other = _kinds(info)
    lim = (lambda f: _height(f) <= max_h) if max_h else (lambda f: True)
    if audio_only:
        good = [f for f in audio if _m4a(f)] or audio
        if good:
            return [max(good, key=_audio_key)]
        rest = [f for f in combined + other if lim(f)]
        return [min(rest, key=lambda f: (_height(f), f.get('tbr') or 0))] if rest else []
    ok_c = [f for f in combined + other if lim(f) and f.get('url')
            and (_hls(f) or f.get('ext') in ('mp4', 'm4v', 'mov'))]
    c = max(ok_c, key=_rank, default=None)
    gv = [f for f in video if lim(f) and f.get('ext') == 'mp4' and _photos_v(f) and not _hls(f) and f.get('url')]
    ga = [f for f in audio if _m4a(f) and not _hls(f) and f.get('url')]
    v = max(gv, key=_rank, default=None)
    a = max(ga, key=_audio_key, default=None)
    if v and a and (not c or _height(v) > _height(c)):
        return [v, a]
    if c:
        return [c]
    anyf = [f for f in combined + other if f.get('url')]
    if anyf:
        return [max([f for f in anyf if lim(f)] or anyf, key=_rank)]
    return []


def _hls_master(info):
    """(playlist link, format) of the main HLS playlist (all qualities), when the video has one."""
    for f in (info.get('formats') or []):
        m = f.get('manifest_url')
        if m and _hls(f) and str(m).startswith('http'):
            return m, f
    return None


def _variants(info):
    """Every quality the player can switch to at once, worked out now so changing quality needs no new lookup:
    {height: {items, hls, height}} where each entry plays exactly that height."""
    out = {}
    try:
        heights = sorted({int(f.get('height') or 0) for f in (info.get('formats') or []) if f.get('height')})
        for h in heights:
            if h < 100 or h > 2160:
                continue
            pk = _stream_pick(info, h, False)
            if not pk or abs(_height(pk[0]) - h) > 8:
                continue
            out[str(h)] = {'items': [{'url': f['url'], 'headers': _stream_headers(f, info)} for f in pk],
                           'hls': _hls(pk[0]), 'height': _height(pk[0])}
    except Exception:
        pass
    return out


def stream(url, cache_dir, cookiefile='', extra='', max_h=0, audio_only=0):
    try:
        ex = _extra(extra)
        info = _infos.get(url)
        if not info:
            params = _params(cache_dir, **_cookie_params(cookiefile, _is_youtube(url, None)))
            _apply_extra(params, ex)
            with yt_dlp.YoutubeDL(params) as ydl:
                info = _extract(ydl, url, ex)
            if info and info.get('_type') == 'playlist':
                return json.dumps({'error': 'Pick one video to stream.'})
        if not info:
            return json.dumps({'error': 'No video found at that link.'})
        audio_only = str(audio_only).lower() in ('1', 'true')
        req = int(float(max_h or 0))
        alt = None
        if not audio_only and not req:
            # Nothing asked for: open as fast as possible. A main playlist lets the player choose by itself;
            # otherwise the best single-file stream (picture and sound together) starts at once.
            m = _hls_master(info)
            if m:
                return json.dumps({'items': [{'url': m[0], 'headers': _stream_headers(m[1], info)}],
                                   'hls': True, 'master': True, 'audio': False, 'height': 0, 'exact': True,
                                   'variants': _variants(info)})
            combined, _v, _a, other = _kinds(info)
            ok_c = [f for f in combined + other if f.get('url') and (_hls(f) or f.get('ext') in ('mp4', 'm4v', 'mov'))]
            if ok_c:
                f = max(ok_c, key=_rank)
                return json.dumps({'items': [{'url': f['url'], 'headers': _stream_headers(f, info)}],
                                   'hls': _hls(f), 'audio': False, 'height': _height(f), 'exact': True,
                                   'variants': _variants(info)})
        # A quality was chosen: play that exact one, never a playlist that picks for itself.
        best = None
        for src in ([alt] if alt else []) + [info]:
            pk = _stream_pick(src, req, audio_only)
            if not pk:
                continue
            h = _height(pk[0])
            if best is None or h > best[1]:
                best = (pk, h, src)
        if not best:
            return json.dumps({'error': "This link can't be streamed. Try Download instead."})
        picked, h, src = best
        out = [{'url': f['url'], 'headers': _stream_headers(f, src)} for f in picked]
        main = picked[0]
        return json.dumps({
            'items': out,
            'hls': _hls(main),
            'audio': audio_only,
            'height': h,
            'exact': (not req) or audio_only or abs(h - req) <= 8,
            'variants': {} if audio_only else _variants(src),
        })
    except DownloadCancelled:
        return json.dumps({'error': 'Cancelled.'})
    except Exception as e:
        _remember(e)
        return json.dumps({'error': _clean(e)})


def link(url, option_id, cache_dir, cookiefile='', extra=''):
    """The link(s) a download of this option would fetch: the same lookup and the same pick as `download`,
    so the copied link is the one that really works for the video chosen. One link, or two when picture and sound are separate."""
    try:
        ex = _extra(extra)
        info = _infos.get(url)
        if not info:
            params = _params(cache_dir, **_cookie_params(cookiefile, _is_youtube(url, None)))
            _apply_extra(params, ex)
            with yt_dlp.YoutubeDL(params) as ydl:
                info = _extract(ydl, url, ex)
            if info and info.get('_type') == 'playlist':
                info = next((e for e in (info.get('entries') or []) if e), None)
        if not info:
            return json.dumps({'error': 'No video found at that link.'})
        if option_id in ('audio', 'mp3'):
            fmts, _ = _audio_plan(info)
        else:
            h = None if option_id in ('', 'best') else int(option_id.split(':', 1)[1])
            _, fmts, _ = _plan(info, h)
        out = [{'url': f['url'], 'headers': _stream_headers(f, info)} for f in fmts if f.get('url')]
        if not out:
            return json.dumps({'error': "Couldn't find a direct link for this video."})
        return json.dumps({'items': out, 'hls': bool(fmts and _hls(fmts[0]))})
    except DownloadCancelled:
        return json.dumps({'error': 'Cancelled.'})
    except Exception as e:
        _remember(e)
        return json.dumps({'error': _clean(e)})


def _link_label(f):
    h = _height(f)
    if _none(f.get('vcodec')) and not _none(f.get('acodec')):
        what = 'Sound only'
    else:
        what = (f'{_short(f)}p' if _short(f) else 'Video')
    proto = 'HLS playlist' if _hls(f) else ('DASH' if 'dash' in (f.get('protocol') or '') else (f.get('ext') or 'file').upper())
    tail = (f.get('url') or '').split('?')[0].rstrip('/').rsplit('/', 1)[-1]
    return f'{what} · {proto}' + (f' · {tail[-28:]}' if tail else '')


def links(url, option_id, cache_dir, cookiefile='', extra=''):
    """Every link worth trying for this video: the one a download of the picked option fetches first,
    then the main playlists (all qualities), then each quality on its own."""
    try:
        ex = _extra(extra)
        info = _infos.get(url)
        if not info:
            params = _params(cache_dir, **_cookie_params(cookiefile, _is_youtube(url, None)))
            _apply_extra(params, ex)
            with yt_dlp.YoutubeDL(params) as ydl:
                info = _extract(ydl, url, ex)
            if info and info.get('_type') == 'playlist':
                info = next((e for e in (info.get('entries') or []) if e), None)
        if not info:
            return json.dumps({'error': 'No video found at that link.'})
        out, seen = [], set()

        def add(label, u, headers):
            if u and u not in seen and len(out) < 30:
                seen.add(u)
                out.append({'label': label, 'url': u, 'headers': headers})

        try:
            if option_id in ('audio', 'mp3'):
                fmts, _ = _audio_plan(info)
            else:
                h = None if option_id in ('', 'best') else int(option_id.split(':', 1)[1])
                _, fmts, _ = _plan(info, h)
            for f in fmts:
                add('Best match · ' + _link_label(f), f.get('url'), _stream_headers(f, info))
        except Exception:
            pass
        fl = [f for f in (info.get('formats') or []) if f.get('url') and f.get('format_note') != 'storyboard' and f.get('ext') != 'mhtml']
        for f in fl:
            m = f.get('manifest_url')
            if m:
                add('Main playlist (all qualities) · ' + m.split('?')[0].rstrip('/').rsplit('/', 1)[-1][-28:], m, _stream_headers(f, info))
        for f in sorted(fl, key=_rank, reverse=True):
            add(_link_label(f), f['url'], _stream_headers(f, info))
        if not out:
            return json.dumps({'error': "Couldn't find a direct link for this video."})
        return json.dumps({'items': out})
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


def _attempt(task, url, option_id, out_dir, cache_dir, clients, cookiefile='', extra=None):
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
    extra = extra or {}
    _apply_extra(params, extra)

    try:
        with yt_dlp.YoutubeDL(params) as ydl:
            info = _extract(ydl, url, extra)
            if info and info.get('_type') == 'playlist':
                info = next((e for e in (info.get('entries') or []) if e), None)
            if not info:
                return None, 'No video found at that link.', ''

            if option_id.startswith('q:'):
                option_id = _pick_option(info, option_id[2:])   # playlist downloads: one quality for all
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


def download(task, url, option_id, out_dir, cache_dir, cookiefile='', extra=''):
    ex = _extra(extra)
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
        result, error, raw = _attempt(task, url, option_id, out_dir, cache_dir, clients, cookies, ex)
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
