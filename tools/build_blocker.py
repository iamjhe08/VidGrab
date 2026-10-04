#!/usr/bin/env python3
"""Builds VidGrab's ad-block rules from the lists uBlock Origin Lite uses by default.

Lists: uBlock filters (+ privacy, unbreak, quick fixes, uBO Lite extras), EasyList,
EasyPrivacy and Peter Lowe's list. They are converted to WebKit content-blocker JSON
(the format iOS uses), keeping only what WebKit can express. Output goes to
Resources/blocker/ as several smaller files so one bad rule can't disable everything.
"""
import json
import os
import re
import sys

import soupsieve

UASSETS = '/root/uAssets'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Resources', 'blocker')

LISTS = [
    ('uBlock filters', 'filters/filters.txt'),
    ('uBlock filters - Privacy', 'filters/privacy.txt'),
    ('uBlock filters - Unbreak', 'filters/unbreak.txt'),
    ('uBlock filters - Quick fixes', 'filters/quick-fixes.txt'),
    ('uBlock Origin Lite filters', 'filters/ubol-filters.txt'),
    ('EasyList', 'thirdparties/easylist/easylist.txt'),
    ('EasyPrivacy', 'thirdparties/easylist/easyprivacy.txt'),
]
PGL = 'thirdparties/pgl.yoyo.org/as/serverlist'

# Same environment uBO Lite reports on Safari/iOS.
ENV_TRUE = {'env_mobile', 'env_safari', 'ext_ubol', 'env_mv3'}

TYPE_MAP = {
    'script': 'script', 'image': 'image', 'stylesheet': 'style-sheet', 'css': 'style-sheet',
    'font': 'font', 'media': 'media', 'xmlhttprequest': 'raw', 'xhr': 'raw', 'subdocument': 'document',
    'frame': 'document', 'ping': 'ping', 'websocket': 'websocket', 'other': 'other', 'popup': 'popup',
    'object': 'other', 'beacon': 'ping',
}
IGNORED_OPTS = {'important', 'all', 'match-case'}
PROCEDURAL = (':has-text(', ':upward(', ':xpath(', ':matches-', ':min-text-length(', ':others(', ':remove(',
              ':style(', ':watch-attr(', ':-abp-', ':if(', ':if-not(', ':remove-attr(', ':remove-class(',
              ':nth-ancestor(', ':has(', ':matches-path(', ':shadow', '::')
URL_FILTER_OK = re.compile(r'^[A-Za-z0-9\-._~:/?#\[\]@!&\'*+,;=%^$\\().]*$')
DOMAIN_OK = re.compile(r'^[a-z0-9.-]+$')

stats = {'network': 0, 'exceptions': 0, 'skipped': 0, 'cosmetic_generic': 0, 'cosmetic_specific': 0}


# ---------------------------------------------------------------- reading

def eval_cond(expr):
    tokens = re.split(r'(\s+|&&|\|\||!|\(|\))', expr)
    py = []
    for t in tokens:
        t = t.strip()
        if not t:
            continue
        py.append({'&&': ' and ', '||': ' or ', '!': ' not ', '(': '(', ')': ')'}.get(t, str(t in ENV_TRUE)))
    try:
        return bool(eval(''.join(py), {'__builtins__': {}}))
    except Exception:
        return False


def read_list(path, seen=None):
    """Yields filter lines, honouring !#if / !#else / !#endif and !#include."""
    seen = seen or set()
    full = os.path.join(UASSETS, path)
    if full in seen or not os.path.exists(full):
        return
    seen.add(full)
    stack = []
    with open(full, encoding='utf-8', errors='replace') as f:
        for raw in f:
            line = raw.strip()
            if line.startswith('!#if '):
                stack.append(eval_cond(line[5:]))
                continue
            if line.startswith('!#else'):
                if stack:
                    stack[-1] = not stack[-1]
                continue
            if line.startswith('!#endif'):
                if stack:
                    stack.pop()
                continue
            if not all(stack):
                continue
            if line.startswith('!#include '):
                yield from read_list(os.path.join(os.path.dirname(path), line.split(None, 1)[1]), seen)
                continue
            if not line or line.startswith(('!', '[')):
                continue
            yield line


# ---------------------------------------------------------------- domains

def split_domains(text, sep):
    inc, exc = [], []
    for d in text.split(sep):
        d = d.strip().lower()
        if not d:
            continue
        neg = d.startswith('~')
        d = d.lstrip('~')
        if d.endswith('.*') or '*' in d or '/' in d or not DOMAIN_OK.match(d):
            return None  # entity wildcards and regex domains can't be expressed
        (exc if neg else inc).append('*' + d)
    return inc, exc


def with_domains(trigger, inc, exc):
    if inc and exc:
        return False
    if inc:
        trigger['if-domain'] = sorted(set(inc))
    elif exc:
        trigger['unless-domain'] = sorted(set(exc))
    return True


# ---------------------------------------------------------------- network

def pattern_to_regex(p):
    if not p.isascii():
        return None
    anchor_domain = p.startswith('||')
    if anchor_domain:
        p = p[2:]
    start = p.startswith('|') and not anchor_domain
    if start:
        p = p[1:]
    end = p.endswith('|')
    if end:
        p = p[:-1]
    if p.endswith('^'):
        p = p[:-1]   # trailing separator also matches end of URL; drop it
        trailing_sep = True
    else:
        trailing_sep = False
    out = []
    for ch in p:
        if ch == '*':
            out.append('.*')
        elif ch == '^':
            out.append('[/:?=&]')
        elif ch in '.?+()[]{}\\$|':
            out.append('\\' + ch)
        else:
            out.append(ch)
    body = ''.join(out)
    if anchor_domain:
        rx = '^[^:]+://+([^:/]+\\.)?' + body
        if trailing_sep:
            rx += '([/:?=&].*)?$' if False else ''  # WebKit lacks alternation; prefix match is enough
    elif start:
        rx = '^' + body
    else:
        rx = body or '.*'
    if end:
        rx += '$'
    while rx.startswith('.*.*'):
        rx = rx[2:]
    if rx in ('', '.*') or not URL_FILTER_OK.match(rx) or '{' in rx or '|' in rx.replace('\\|', ''):
        return None if rx != '.*' else '.*'
    return rx


def parse_network(line):
    """Returns (is_exception, rule) or None."""
    exception = line.startswith('@@')
    if exception:
        line = line[2:]
    pattern, opts = line, ''
    if '$' in line and not (line.startswith('/') and line.rstrip('/').count('/') > 1 and line.endswith('/')):
        idx = line.rfind('$')
        pattern, opts = line[:idx], line[idx + 1:]
    if pattern.startswith('/') and pattern.endswith('/') and len(pattern) > 2:
        return None  # regex filters: skip
    trigger, types = {}, []
    inc = exc = None
    special = set()
    for o in filter(None, opts.split(',')):
        o = o.strip()
        key, _, val = o.partition('=')
        k = key.lower()
        if k in ('third-party', '3p'):
            trigger['load-type'] = ['third-party']
        elif k in ('~third-party', 'first-party', '1p', '~3p'):
            trigger['load-type'] = ['first-party']
        elif k in ('domain', 'from'):
            r = split_domains(val, '|')
            if r is None:
                return None
            inc, exc = r
        elif k in TYPE_MAP:
            types.append(TYPE_MAP[k])
        elif k in ('document', 'doc'):
            special.add('document')
        elif k in ('elemhide', 'ehide', 'generichide', 'ghide', 'specifichide', 'shide'):
            special.add('elemhide')
        elif k == 'match-case':
            trigger['url-filter-is-case-sensitive'] = True
        elif k in IGNORED_OPTS:
            continue
        else:
            return None  # redirect, removeparam, csp, negated types, etc.
    if special:
        if not exception:
            return None
        m = re.match(r'^\|\|([a-z0-9.-]+)\^?$', pattern)
        if not m:
            return None
        return ('domain-exception', (m.group(1), special))
    rx = pattern_to_regex(pattern)
    if rx is None:
        return None
    if rx == '.*' and not (inc or exc or types or 'load-type' in trigger):
        return None
    trigger['url-filter'] = rx
    if types:
        trigger['resource-type'] = sorted(set(types))
    if inc is not None and not with_domains(trigger, inc, exc):
        return None
    action = {'type': 'ignore-previous-rules' if exception else 'block'}
    return (exception, {'trigger': trigger, 'action': action})


# ---------------------------------------------------------------- cosmetic

_selector_ok_cache = {}


def selector_ok(sel):
    if sel in _selector_ok_cache:
        return _selector_ok_cache[sel]
    ok = bool(sel) and sel.isascii() and not any(p in sel for p in PROCEDURAL) and not sel.startswith(('+js', '^'))
    if ok:
        try:
            soupsieve.compile(sel)
        except Exception:
            ok = False
    _selector_ok_cache[sel] = ok
    return ok


# ---------------------------------------------------------------- main

def main():
    blocks, exceptions = [], []
    seen_rules = set()
    domain_allow, domain_nocosmetic = set(), set()
    generic, specific, unhide = [], {}, set()

    def add_rule(bucket, rule):
        key = json.dumps(rule, sort_keys=True)
        if key in seen_rules:
            return
        seen_rules.add(key)
        bucket.append(rule)

    sources = []
    for title, path in LISTS:
        n = 0
        for line in read_list(path):
            n += 1
            if '#@#' in line:
                unhide.add(line.split('#@#', 1)[1].strip())
                continue
            if '##' in line and not any(m in line for m in ('#?#', '#$#', '#%#', '#@$#', '#@?#')):
                doms, sel = line.split('##', 1)
                sel = sel.strip()
                if not selector_ok(sel):
                    stats['skipped'] += 1
                    continue
                if not doms:
                    generic.append(sel)
                else:
                    r = split_domains(doms, ',')
                    if r is None:
                        stats['skipped'] += 1
                        continue
                    inc, exc = r
                    if inc and exc:
                        inc = inc  # keep positives; negatives only refine
                        exc = []
                    specific.setdefault((tuple(sorted(inc)), tuple(sorted(exc))), []).append(sel)
                continue
            if '#' in line and re.search(r'#[@?$%]*#', line):
                stats['skipped'] += 1  # scriptlets and procedural filters
                continue
            r = parse_network(line)
            if r is None:
                stats['skipped'] += 1
                continue
            kind, rule = r
            if kind == 'domain-exception':
                dom, special = rule
                (domain_allow if 'document' in special else domain_nocosmetic).add('*' + dom)
            elif kind:
                add_rule(exceptions, rule)
            else:
                add_rule(blocks, rule)
        sources.append(f'{title}: {n} filters read')

    n = 0
    with open(os.path.join(UASSETS, PGL), encoding='utf-8') as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2 and not line.startswith('#') and DOMAIN_OK.match(parts[1]):
                rx = pattern_to_regex('||' + parts[1] + '^')
                add_rule(blocks, {'trigger': {'url-filter': rx}, 'action': {'type': 'block'}})
                n += 1
    sources.append(f"Peter Lowe's list: {n} servers")

    # Site-wide exceptions (e.g. @@||site^$document) apply to every list.
    allow_rules = [{'trigger': {'url-filter': '.*', 'if-domain': sorted(domain_allow)[i:i + 500]},
                    'action': {'type': 'ignore-previous-rules'}} for i in range(0, len(domain_allow), 500)]
    nocos_rules = [{'trigger': {'url-filter': '.*', 'if-domain': sorted(domain_nocosmetic | domain_allow)[i:i + 500]},
                    'action': {'type': 'ignore-previous-rules'}}
                   for i in range(0, len(domain_nocosmetic | domain_allow), 500)]

    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith('.json'):
            os.remove(os.path.join(OUT, f))
    files = []

    # Network: chunks of blocks, each followed by all exceptions so they still apply.
    CH = 20000
    for i in range(0, len(blocks), CH):
        rules = blocks[i:i + CH] + exceptions + allow_rules
        name = f'network-{i // CH + 1}.json'
        json.dump(rules, open(os.path.join(OUT, name), 'w'), separators=(',', ':'))
        files.append((name, len(rules)))
    stats['network'] = len(blocks)
    stats['exceptions'] = len(exceptions)

    # Generic hiding: drop anything a list un-hides somewhere, group 40 selectors per rule.
    gen = sorted(set(s for s in generic if s not in unhide))
    stats['cosmetic_generic'] = len(gen)
    rules = [{'trigger': {'url-filter': '.*'}, 'action': {'type': 'css-display-none', 'selector': ', '.join(gen[i:i + 40])}}
             for i in range(0, len(gen), 40)] + nocos_rules
    json.dump(rules, open(os.path.join(OUT, 'cosmetic-generic.json'), 'w'), separators=(',', ':'))
    files.append(('cosmetic-generic.json', len(rules)))

    # Site-specific hiding, grouped by the same set of sites.
    spec_rules = []
    for (inc, exc), sels in specific.items():
        sels = sorted(set(sels))
        stats['cosmetic_specific'] += len(sels)
        for i in range(0, len(sels), 40):
            trig = {'url-filter': '.*'}
            if not with_domains(trig, list(inc), list(exc)):
                continue
            spec_rules.append({'trigger': trig, 'action': {'type': 'css-display-none', 'selector': ', '.join(sels[i:i + 40])}})
    CH2 = 20000
    for i in range(0, len(spec_rules), CH2):
        name = f'cosmetic-sites-{i // CH2 + 1}.json'
        json.dump(spec_rules[i:i + CH2] + nocos_rules, open(os.path.join(OUT, name), 'w'), separators=(',', ':'))
        files.append((name, len(spec_rules[i:i + CH2]) + len(nocos_rules)))

    import datetime
    version = datetime.datetime.utcnow().strftime('%Y%m%d%H%M')
    manifest = {'version': version, 'files': [f for f, _ in files], 'sources': sources, 'stats': stats}
    json.dump(manifest, open(os.path.join(OUT, 'manifest.json'), 'w'), indent=1)
    for name, n in files:
        print(f'  {name}: {n} rules, {os.path.getsize(os.path.join(OUT, name)) / 1e6:.1f} MB')
    print('\n'.join(sources))
    print(stats)


if __name__ == '__main__':
    sys.exit(main())
