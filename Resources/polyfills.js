// VidGrab: adds newer JavaScript features that older iOS versions (15.x, 16.x) lack,
// so modern sites like YouTube and Dailymotion don't break on start. Each one is only
// added when the browser doesn't already have it.
(function () {
  'use strict';
  if (window.__vgPoly) return;
  window.__vgPoly = true;

  function def(obj, name, fn) {
    if (!obj || obj[name]) return;
    try { Object.defineProperty(obj, name, { value: fn, writable: true, configurable: true, enumerable: false }); } catch (e) {}
  }
  function toInt(n) { n = Number(n); return isNaN(n) ? 0 : Math.trunc(n); }

  // .at()
  function at(i) {
    var len = this.length >>> 0, k = toInt(i);
    if (k < 0) k += len;
    return k < 0 || k >= len ? undefined : this[k];
  }
  def(Array.prototype, 'at', at);
  def(String.prototype, 'at', function (i) { var s = String(this), v = at.call(s, i); return v; });
  var TA = Object.getPrototypeOf(Int8Array.prototype);
  def(TA, 'at', at);

  // Object.hasOwn
  def(Object, 'hasOwn', function (o, k) { return Object.prototype.hasOwnProperty.call(Object(o), k); });

  // findLast / findLastIndex
  function findLastIndex(fn, self) {
    for (var i = (this.length >>> 0) - 1; i >= 0; i--) if (fn.call(self, this[i], i, this)) return i;
    return -1;
  }
  function findLast(fn, self) { var i = findLastIndex.call(this, fn, self); return i < 0 ? undefined : this[i]; }
  def(Array.prototype, 'findLastIndex', findLastIndex);
  def(Array.prototype, 'findLast', findLast);
  def(TA, 'findLastIndex', findLastIndex);
  def(TA, 'findLast', findLast);

  // Copying array methods
  def(Array.prototype, 'toReversed', function () { return Array.prototype.slice.call(this).reverse(); });
  def(Array.prototype, 'toSorted', function (cmp) { return Array.prototype.slice.call(this).sort(cmp); });
  def(Array.prototype, 'toSpliced', function () {
    var a = Array.prototype.slice.call(this); Array.prototype.splice.apply(a, arguments); return a;
  });
  def(Array.prototype, 'with', function (i, v) {
    var len = this.length >>> 0, k = toInt(i); if (k < 0) k += len;
    if (k < 0 || k >= len) throw new RangeError('Invalid index');
    var a = Array.prototype.slice.call(this); a[k] = v; return a;
  });

  // Grouping
  def(Object, 'groupBy', function (items, fn) {
    var out = Object.create(null), i = 0;
    for (var it of items) { var key = fn(it, i++); (out[key] || (out[key] = [])).push(it); }
    return out;
  });
  def(Map, 'groupBy', function (items, fn) {
    var out = new Map(), i = 0;
    for (var it of items) { var key = fn(it, i++); if (!out.has(key)) out.set(key, []); out.get(key).push(it); }
    return out;
  });

  // Promise.withResolvers
  def(Promise, 'withResolvers', function () {
    var res, rej, p = new this(function (a, b) { res = a; rej = b; });
    return { promise: p, resolve: res, reject: rej };
  });

  // String well-formed checks
  def(String.prototype, 'isWellFormed', function () { return !/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(String(this)); });
  def(String.prototype, 'toWellFormed', function () {
    return String(this).replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|([^\uD800-\uDBFF]|^)[\uDC00-\uDFFF]/g, function (m, pre) {
      return pre !== undefined ? pre + '�' : '�';
    });
  });

  // structuredClone (covers plain data, dates, regexes, maps, sets, typed arrays)
  def(window, 'structuredClone', function (value) {
    var seen = new Map();
    function clone(v) {
      if (v === null || typeof v !== 'object') {
        if (typeof v === 'function' || typeof v === 'symbol') throw new DOMException('Could not be cloned', 'DataCloneError');
        return v;
      }
      if (seen.has(v)) return seen.get(v);
      var out;
      if (v instanceof Date) out = new Date(v.getTime());
      else if (v instanceof RegExp) out = new RegExp(v.source, v.flags);
      else if (v instanceof ArrayBuffer) out = v.slice(0);
      else if (ArrayBuffer.isView(v)) out = new v.constructor(v.buffer.slice(0), v.byteOffset, v.length);
      else if (v instanceof Map) { out = new Map(); seen.set(v, out); v.forEach(function (x, k) { out.set(clone(k), clone(x)); }); return out; }
      else if (v instanceof Set) { out = new Set(); seen.set(v, out); v.forEach(function (x) { out.add(clone(x)); }); return out; }
      else if (typeof Blob !== 'undefined' && v instanceof Blob) out = v.slice();
      else if (Array.isArray(v)) { out = []; seen.set(v, out); for (var i = 0; i < v.length; i++) out[i] = clone(v[i]); return out; }
      else { out = {}; seen.set(v, out); Object.keys(v).forEach(function (k) { out[k] = clone(v[k]); }); return out; }
      seen.set(v, out);
      return out;
    }
    return clone(value);
  });

  // crypto.randomUUID
  if (window.crypto && crypto.getRandomValues) {
    def(Object.getPrototypeOf(crypto), 'randomUUID', function () {
      var b = crypto.getRandomValues(new Uint8Array(16));
      b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
      var h = Array.prototype.map.call(b, function (x) { return (x + 0x100).toString(16).slice(1); }).join('');
      return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
    });
  }

  // AbortSignal.timeout / AbortSignal.any
  if (window.AbortSignal) {
    def(AbortSignal, 'timeout', function (ms) {
      var c = new AbortController();
      setTimeout(function () { c.abort(new DOMException('The operation timed out.', 'TimeoutError')); }, ms);
      return c.signal;
    });
    def(AbortSignal, 'any', function (signals) {
      var c = new AbortController();
      for (var s of signals) {
        if (s.aborted) { c.abort(s.reason); break; }
        s.addEventListener('abort', function () { c.abort(this.reason); }, { once: true });
      }
      return c.signal;
    });
    if (AbortSignal.prototype && !AbortSignal.prototype.throwIfAborted) {
      def(AbortSignal.prototype, 'throwIfAborted', function () { if (this.aborted) throw this.reason || new DOMException('Aborted', 'AbortError'); });
    }
  }

  // requestIdleCallback (Safari never had it)
  def(window, 'requestIdleCallback', function (cb, opts) {
    var start = Date.now();
    return setTimeout(function () {
      cb({ didTimeout: false, timeRemaining: function () { return Math.max(0, 50 - (Date.now() - start)); } });
    }, 1);
  });
  def(window, 'cancelIdleCallback', function (id) { clearTimeout(id); });

  // Element helpers
  if (window.Element) {
    def(Element.prototype, 'checkVisibility', function () {
      var s = getComputedStyle(this);
      return s.display !== 'none' && s.visibility !== 'hidden' && this.getClientRects().length > 0;
    });
  }
  if (window.HTMLFormElement) {
    def(HTMLFormElement.prototype, 'requestSubmit', function (btn) {
      if (btn) { btn.click(); return; }
      var b = document.createElement('input'); b.type = 'submit'; b.hidden = true;
      this.appendChild(b); b.click(); this.removeChild(b);
    });
  }

  // Array.fromAsync
  def(Array, 'fromAsync', async function (items, fn, self) {
    var out = [], i = 0;
    if (items && typeof items[Symbol.asyncIterator] === 'function') {
      for await (var v of items) out.push(fn ? await fn.call(self, v, i++) : v);
    } else {
      for (var w of Array.from(items)) { var x = await w; out.push(fn ? await fn.call(self, x, i++) : x); }
    }
    return out;
  });
})();
