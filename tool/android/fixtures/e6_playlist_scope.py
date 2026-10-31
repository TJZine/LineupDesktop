"""Offline mirror of E6Config.playlist's existing strict scope; never echo input.

The RFC 8216 section 4.3 tag list is a diagnostic vocabulary, not an allowlist
expansion. A rejected playlist is never rewritten or handed to the device.
"""
import re
import unicodedata
from urllib.parse import urljoin, urlsplit, quote

TAGS = frozenset(('EXTM3U', 'EXT-X-VERSION', 'EXTINF', 'EXT-X-BYTERANGE', 'EXT-X-DISCONTINUITY',
    'EXT-X-KEY', 'EXT-X-MAP', 'EXT-X-PROGRAM-DATE-TIME', 'EXT-X-DATERANGE', 'EXT-X-TARGETDURATION',
    'EXT-X-MEDIA-SEQUENCE', 'EXT-X-DISCONTINUITY-SEQUENCE', 'EXT-X-ENDLIST', 'EXT-X-PLAYLIST-TYPE',
    'EXT-X-I-FRAMES-ONLY', 'EXT-X-MEDIA', 'EXT-X-STREAM-INF', 'EXT-X-I-FRAME-STREAM-INF',
    'EXT-X-SESSION-DATA', 'EXT-X-SESSION-KEY', 'EXT-X-INDEPENDENT-SEGMENTS', 'EXT-X-START'))
REASONS = frozenset(('unknown_tag', 'missing_media_sequence', 'extinf_format', 'bom_or_whitespace',
    'map_position', 'target_mismatch', 'start_mismatch', 'duration_mismatch', 'reference_scope',
    'utf8_format', 'header_format', 'duplicate_tag', 'media_sequence_mismatch', 'map_format',
    'start_format', 'endlist_format', 'version_format', 'segment_structure', 'reference_changed'))


class ScopeFailure(Exception):
    def __init__(self, reason, *, tag=None, index=None):
        self.reason = reason if reason in REASONS else 'segment_structure'
        self.tag = tag if tag in TAGS or tag == 'other_tag' else None
        self.index = index if self.reason == 'duration_mismatch' and isinstance(index, int) and 0 <= index <= 10000 else None
        super().__init__('playlist_scope')

    def facts(self):
        return {'playlistScopeReason': self.reason, 'playlistScopeTag': self.tag, 'playlistScopeIndex': self.index}


def reference(raw, variant):
    if (not raw or len(raw.encode('utf-16-le')) // 2 > 4096 or any(ord(c) <= 32 or c in '\\%' for c in raw)
            or '#' in raw or '?' in raw or any(p in ('.', '..') for p in raw.split('/'))):
        raise ScopeFailure('reference_scope')
    try:
        # OkHttp treats two OR MORE leading slashes as an authority delimiter.
        resolved_raw = '//' + raw.lstrip('/') if raw.startswith('//') else raw
        base, uri = urlsplit(variant), urlsplit(urljoin(variant, resolved_raw))
        namespace = base.path.rsplit('/', 1)[0] + '/'
        if (uri.port == 0 or uri.scheme != 'https' or uri.hostname != base.hostname or (443 if uri.port is None else uri.port) != (443 if base.port is None else base.port)
                or uri.username or uri.password or not uri.path.startswith(namespace)
                or '/' in uri.path[len(namespace):] or uri.path == base.path):
            raise ScopeFailure('reference_scope')
        # HttpUrl canonicalizes a bare authority's path and non-ASCII path bytes.
        # Approved references have a single filename; avoid leaking it in facts.
        return (uri.scheme, uri.hostname, 443 if uri.port is None else uri.port, quote(uri.path, safe="/!$&'()*+,;=:@-._~"))
    except ValueError:
        raise ScopeFailure('reference_scope') from None


def _integer(text, bits, reason):
    # Kotlin toInt/LongOrNull: optional sign, BMP decimal digits, no whitespace.
    digits = text[1:] if text[:1] in ('+', '-') else text
    if not digits or any(ord(c) > 65535 or unicodedata.category(c) != 'Nd' for c in digits):
        raise ScopeFailure(reason)
    compact = ''.join(str(unicodedata.decimal(c)) for c in digits).lstrip('0') or '0'
    if len(compact) > 19: raise ScopeFailure(reason)
    value = int(('-' if text.startswith('-') else '') + compact)
    if not -(1 << (bits - 1)) <= value < (1 << (bits - 1)): raise ScopeFailure(reason)
    return value


def _micros(text, reason):
    whole, _, fraction = text.partition('.')
    compact = whole.lstrip('0') or '0'
    if len(compact) > 13: raise ScopeFailure(reason)
    value = int(compact) * 1000000 + int((fraction + '000000')[:6])
    if not -(1 << 63) <= value < (1 << 63): raise ScopeFailure(reason)
    return value


def validate(data, *, variant, offset_us, target, durations_us):
    """Return in-memory refs/durations or a fixed first rejection; 1 MiB bound."""
    if len(data) > 1024 * 1024: raise ValueError('response_byte_cap')
    try: text = data.decode('utf-8')
    except UnicodeDecodeError: raise ScopeFailure('utf8_format') from None
    lines = [line for line in re.split(r'\r\n|\n|\r', text) if line]
    def lexical(line):
        c = line[0]
        # java Character.isWhitespace || isSpaceChar (Kotlin Char.isWhitespace).
        if c == '\ufeff' or c in '\t\n\v\f\r\x1c\x1d\x1e\x1f' or unicodedata.category(c) in ('Zs', 'Zl', 'Zp'):
            raise ScopeFailure('bom_or_whitespace')
    if lines: lexical(lines[0])
    if not lines or lines[0] != '#EXTM3U': raise ScopeFailure('header_format')
    init = actual_target = sequence = start = pending = None
    end = False
    durations, refs = [], []
    for line in lines[1:]:
        lexical(line)
        if line.startswith('#EXT-X-TARGETDURATION:'):
            if actual_target is not None: raise ScopeFailure('duplicate_tag')
            actual_target = _integer(line.split(':', 1)[1], 32, 'target_mismatch')
        elif line.startswith('#EXT-X-MEDIA-SEQUENCE:'):
            if sequence is not None: raise ScopeFailure('duplicate_tag')
            sequence = _integer(line.split(':', 1)[1], 64, 'media_sequence_mismatch')
        elif line.startswith('#EXT-X-MAP:'):
            match = re.fullmatch(r'#EXT-X-MAP:URI="([^"]+)"', line)
            if not match: raise ScopeFailure('map_format')
            if init is not None: raise ScopeFailure('duplicate_tag')
            init = reference(match[1], variant)
        elif line.startswith('#EXT-X-START:'):
            if start is not None: raise ScopeFailure('duplicate_tag')
            match = re.fullmatch(r'#EXT-X-START:TIME-OFFSET=([0-9]+(?:\.[0-9]{1,6})?)', line)
            if not match: raise ScopeFailure('start_format')
            start = _micros(match[1], 'start_format')
        elif line.startswith('#EXTINF:'):
            if pending is not None or end: raise ScopeFailure('segment_structure')
            match = re.fullmatch(r'#EXTINF:([0-9]+(?:\.[0-9]{1,6})?),', line)
            if not match: raise ScopeFailure('extinf_format')
            pending = _micros(match[1], 'extinf_format')
        elif line == '#EXT-X-ENDLIST':
            if end or pending is not None: raise ScopeFailure('endlist_format')
            end = True
        elif line.startswith('#EXT-X-VERSION:'):
            if not 1 <= _integer(line.split(':', 1)[1], 32, 'version_format') <= 10: raise ScopeFailure('version_format')
        elif line in ('#EXT-X-PLAYLIST-TYPE:VOD', '#EXT-X-INDEPENDENT-SEGMENTS'): pass
        elif line.startswith('#'):
            tag = line.split(':', 1)[0][1:]
            raise ScopeFailure('unknown_tag', tag=tag if tag in TAGS else 'other_tag')
        else:
            if pending is None: raise ScopeFailure('segment_structure')
            if init is None: raise ScopeFailure('map_position')
            if pending <= 0 or pending > 120000000 or end or len(durations) >= 10000: raise ScopeFailure('segment_structure')
            uri = reference(line, variant)
            if uri == init or uri in refs: raise ScopeFailure('reference_scope')
            refs.append(uri); durations.append(pending); pending = None
    if not end or init is None or pending is not None: raise ScopeFailure('segment_structure')
    if actual_target is None or not 1 <= actual_target <= 120 or target is not None and actual_target != target: raise ScopeFailure('target_mismatch')
    if sequence is None: raise ScopeFailure('missing_media_sequence')
    if sequence != 0: raise ScopeFailure('media_sequence_mismatch')
    if (start or 0) != offset_us: raise ScopeFailure('start_mismatch')
    if durations_us is not None and durations != durations_us:
        first = next(i for i in range(max(len(durations), len(durations_us)))
                     if (durations[i] if i < len(durations) else None) != (durations_us[i] if i < len(durations_us) else None))
        raise ScopeFailure('duration_mismatch', index=first)
    return {'init': init, 'media': refs, 'durations_us': durations, 'start_us': start or 0, 'start_present': start is not None,
            'target': actual_target, 'media_sequence': sequence}
