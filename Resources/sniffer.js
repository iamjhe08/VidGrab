// VidGrab: notes the video streams a page asks for while it plays, and tells the app.
// Runs in every frame before the page's own code. It only watches; it never changes what a page loads.
(function () {
  if (window.__vgSniff) return;
  window.__vgSniff = true;

  var seen = {};
  // Which playlist is the one playing right now: the one whose pieces (.ts, .m4s ...) keep being fetched.
  var lists = {};      // playlist or manifest url -> its folder
  var lastSeg = {};    // playlist url -> time of the last piece fetched from its folder
  var activeUrl = '';
  function folder(u) { return u.split('#')[0].split('?')[0].replace(/[^\/]*$/, ''); }
  function segNote(u) {
    try {
      if (!u || !/\.(ts|m4s|aac|cmfv|cmfa|m4a|m4v)(\?|#|$)/i.test(u)) return;
      var best = '', bl = 0, k;
      for (k in lists) { var d = lists[k]; if (d && u.indexOf(d) === 0 && d.length > bl) { best = k; bl = d.length; } }
      if (!best) return;
      lastSeg[best] = Date.now();
      if (best !== activeUrl) {
        activeUrl = best;
        post({ type: 'active', url: best, frame: location.href });
      }
    } catch (e) {}
  }
  var post = function (m) { try { window.webkit.messageHandlers.vidgrab.postMessage(m); } catch (e) {} };

  function absolute(u) {
    try { return new URL(u, location.href).href; } catch (e) { return ''; }
  }

  // Playlists, manifests and whole-file videos. Single pieces of a stream (.ts, .m4s), pictures,
  // subtitles and sound files are ignored, so one video shows up once instead of a hundred times.
  function kindOf(u, type) {
    var path = u.split('#')[0].split('?')[0].toLowerCase();
    type = (type || '').toLowerCase();
    if (/\.(ts|m4s|aac|vtt|srt|jpe?g|png|gif|webp|svg|js|css|json|key)$/.test(path)) return '';
    if (/mpegurl/.test(type) || /\.m3u8$/.test(path)) return 'hls';
    if (/dash\+xml/.test(type) || /\.mpd$/.test(path)) return 'dash';
    if (/^video\//.test(type)) return 'file';
    if (/\.(mp4|m4v|mov|webm|mkv|flv)$/.test(path)) return 'file';
    return '';
  }

  function note(u, type, length, fromVideo) {
    if (!u || u.indexOf('http') !== 0) return;
    var kind = kindOf(u, type);
    if (!kind && fromVideo) kind = /\.m3u8(\?|$)/i.test(u) ? 'hls' : 'file';
    if ((kind === 'hls' || kind === 'dash') && !lists[u]) lists[u] = folder(u);
    if (!kind || seen[u]) return;
    seen[u] = 1;
    post({
      type: 'media', url: u, kind: kind, ctype: type || '', size: parseInt(length, 10) || 0,
      frame: location.href, ua: navigator.userAgent, title: document.title || '',
      top: window === window.top
    });
  }

  try {
    var realFetch = window.fetch;
    if (realFetch) {
      window.fetch = function (input) {
        var p = realFetch.apply(this, arguments);
        try {
          var u = absolute(typeof input === 'string' ? input : (input && input.url));
          p.then(function (r) {
            try { segNote(r.url || u); note(r.url || u, r.headers.get('content-type'), r.headers.get('content-length')); } catch (e) {}
          }, function () {});
        } catch (e) {}
        return p;
      };
    }
  } catch (e) {}

  try {
    var realOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, u) {
      try { this.__vgu = absolute(u); } catch (e) {}
      return realOpen.apply(this, arguments);
    };
    var realSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function () {
      var x = this;
      try {
        x.addEventListener('readystatechange', function () {
          if (x.readyState !== 2) return;
          try { segNote(x.responseURL || x.__vgu); note(x.responseURL || x.__vgu, x.getResponseHeader('content-type'), x.getResponseHeader('content-length')); } catch (e) {}
        });
      } catch (e) {}
      return realSend.apply(this, arguments);
    };
  } catch (e) {}

  // The video element's own address (a plain file, or a stream the page hands the player directly).
  function fromElement(el) {
    try {
      if (!el || el.tagName !== 'VIDEO') return;
      var u = el.currentSrc || el.src;
      if (u) note(absolute(u), '', 0, true);
      var s = el.querySelectorAll ? el.querySelectorAll('source') : [];
      for (var i = 0; i < s.length; i++) if (s[i].src) note(absolute(s[i].src), s[i].type || '', 0, true);
    } catch (e) {}
  }
  ['loadstart', 'loadedmetadata', 'play', 'playing'].forEach(function (ev) {
    document.addEventListener(ev, function (e) { fromElement(e.target); }, true);
  });

  // Anything the page's players fetched that looks like a stream (covers requests made before this ran).
  try {
    var obs = new PerformanceObserver(function (list) {
      list.getEntries().forEach(function (e) {
        var u = e.name || '';
        segNote(u);
        if (e.initiatorType === 'video') note(u, '', 0, true);
        else if (/\.(m3u8|mpd|mp4|m4v|mov|webm)(\?|#|$)/i.test(u)) note(u, '', 0, false);
      });
    });
    obs.observe({ type: 'resource', buffered: true });
  } catch (e) {}
})();
