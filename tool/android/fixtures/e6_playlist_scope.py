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
    ignored_lines = 0
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
            match = re.fullmatch(r'#EXTINF:([0-9]+(?:\.[0-9]{1,6})?),[^\r\n]*', line)
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
            if tag in TAGS: raise ScopeFailure('unknown_tag', tag=tag)
            ignored_lines += 1
            if ignored_lines > 16 or len(line.encode('utf-8')) > 256:
                raise ScopeFailure('unknown_tag', tag='other_tag')
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


# Repeated segment/rendition tags are not duplicate declarations. These are the
# singleton declarations in this finite fixture, including MAP (one init only).
SHAPE_SINGLETONS = frozenset(('EXTM3U', 'EXT-X-VERSION', 'EXT-X-TARGETDURATION',
    'EXT-X-MEDIA-SEQUENCE', 'EXT-X-MAP', 'EXT-X-START', 'EXT-X-ENDLIST',
    'EXT-X-PLAYLIST-TYPE', 'EXT-X-INDEPENDENT-SEGMENTS'))
EXTINF_CLASSES = frozenset(('integer', 'decimal_le_6', 'decimal_gt_6', 'has_title'))


def inspect_shape(data, *, variant, offset_us, target, durations_us):
    """Value-free non-short-circuit observation, never an authorization parser.

    Formatting defects do not hide later tags/defects. Strip BOM/leading space
    only in this observation pass to recognize their shape, never for validate.
    Unparseable fields do not invent numeric/timing comparison results.
    """
    if len(data) > 1024 * 1024: raise ValueError('response_byte_cap')
    failures = set()
    try: validate(data, variant=variant, offset_us=offset_us, target=target, durations_us=durations_us)
    except ScopeFailure as error: failures.add(error.reason)
    try: text = data.decode('utf-8')
    except UnicodeDecodeError:
        failures.add('utf8_format')
        text = data.decode('utf-8', errors='replace')

    def whitespace(c):
        return c in '\t\n\v\f\r\x1c\x1d\x1e\x1f' or unicodedata.category(c) in ('Zs', 'Zl', 'Zp')

    def number(raw, bits, reason):
        try: return _integer(raw, bits, reason)
        except ScopeFailure:
            failures.add(reason)
            return None

    def uri(raw):
        try: return reference(raw, variant)
        except ScopeFailure:
            failures.add('reference_scope')
            return None

    lines = [line for line in re.split(r'\r\n|\n|\r', text) if line]
    tag_counts, names, formats = {}, set(), set()
    other_count = 0
    bom = '\ufeff' in text
    leading = False
    map_seen = map_tag_seen = sequence_seen = first_media = ended = pending = False
    map_before = False
    init_refs, media_refs, durations = set(), set(), []
    targets, starts = [], []
    duration_known = True
    first_content = True
    for original in lines:
        line = original
        # Preserve the defect flags, then keep observing the rest of the line.
        prefix = 0
        while prefix < len(line) and (line[prefix] == '\ufeff' or whitespace(line[prefix])):
            if whitespace(line[prefix]): leading = True
            failures.add('bom_or_whitespace')
            prefix += 1
        line = line[prefix:]
        if not line: continue
        if first_content:
            if line != '#EXTM3U': failures.add('header_format')
            first_content = False
        if line.startswith('#'):
            tag = line.split(':', 1)[0][1:]
            if tag in TAGS:
                names.add(tag)
                tag_counts[tag] = tag_counts.get(tag, 0) + 1
                if tag == 'EXT-X-MEDIA-SEQUENCE': sequence_seen = True
                if tag == 'EXT-X-MAP': map_tag_seen = True
            else:
                other_count += 1
        else:
            if not pending: failures.add('segment_structure')
            if not map_seen: failures.add('map_position')
            if ended or len(durations) >= 10000: failures.add('segment_structure')
            if not first_media:
                map_before = map_tag_seen
                first_media = True
            value = uri(line)
            if value is not None:
                if value in init_refs or value in media_refs: failures.add('reference_scope')
                media_refs.add(value)
            pending = False
            continue

        if line == '#EXTM3U' and tag_counts['EXTM3U'] == 1:
            continue
        if line.startswith('#EXT-X-TARGETDURATION:'):
            value = number(line.split(':', 1)[1], 32, 'target_mismatch')
            if value is not None:
                targets.append(value)
                if not 1 <= value <= 120 or target is not None and value != target:
                    failures.add('target_mismatch')
        elif line.startswith('#EXT-X-MEDIA-SEQUENCE:'):
            sequence_seen = True
            value = number(line.split(':', 1)[1], 64, 'media_sequence_mismatch')
            if value is not None:
                if value != 0: failures.add('media_sequence_mismatch')
        elif line.startswith('#EXT-X-MAP:'):
            map_seen = True
            match = re.fullmatch(r'#EXT-X-MAP:URI="([^"]+)"', line)
            if not match: failures.add('map_format')
            else:
                value = uri(match[1])
                if value is not None:
                    if value in media_refs: failures.add('reference_scope')
                    init_refs.add(value)
        elif line.startswith('#EXT-X-START:'):
            match = re.fullmatch(r'#EXT-X-START:TIME-OFFSET=([0-9]+(?:\.[0-9]{1,6})?)', line)
            if not match: failures.add('start_format')
            else:
                try:
                    value = _micros(match[1], 'start_format')
                    starts.append(value)
                    if value != offset_us: failures.add('start_mismatch')
                except ScopeFailure: failures.add('start_format')
        elif line.startswith('#EXTINF:'):
            if pending or ended: failures.add('segment_structure')
            pending = True
            value, comma, title = line[len('#EXTINF:'):].partition(',')
            if comma and title: formats.add('has_title')
            if re.fullmatch(r'[0-9]+', value): formats.add('integer')
            elif re.fullmatch(r'[0-9]+\.[0-9]+', value):
                formats.add('decimal_le_6' if len(value.split('.', 1)[1]) <= 6 else 'decimal_gt_6')
            match = re.fullmatch(r'#EXTINF:([0-9]+(?:\.[0-9]{1,6})?),[^\r\n]*', line)
            if not match:
                failures.add('extinf_format')
                duration_known = False
            else:
                try:
                    value = _micros(match[1], 'extinf_format')
                    durations.append(value)
                    if not 0 < value <= 120000000: failures.add('segment_structure')
                except ScopeFailure:
                    failures.add('extinf_format')
                    duration_known = False
        elif line == '#EXT-X-ENDLIST':
            if ended or pending: failures.add('endlist_format')
            ended = True
        elif line.startswith('#EXT-X-VERSION:'):
            value = number(line.split(':', 1)[1], 32, 'version_format')
            if value is not None and not 1 <= value <= 10: failures.add('version_format')
        elif line in ('#EXT-X-PLAYLIST-TYPE:VOD', '#EXT-X-INDEPENDENT-SEGMENTS'): pass
        elif tag in TAGS or other_count > 16 or len(original.encode('utf-8')) > 256:
            failures.add('unknown_tag')

    if first_content: failures.add('header_format')
    if not ended or not map_seen or pending: failures.add('segment_structure')
    if not targets: failures.add('target_mismatch')
    if not sequence_seen: failures.add('missing_media_sequence')
    if not starts and offset_us != 0 and tag_counts.get('EXT-X-START', 0) == 0:
        failures.add('start_mismatch')
    if duration_known and durations_us is not None and durations != durations_us:
        failures.add('duration_mismatch')
    if any(tag_counts.get(tag, 0) > 1 for tag in ('EXT-X-TARGETDURATION', 'EXT-X-MEDIA-SEQUENCE', 'EXT-X-MAP', 'EXT-X-START')):
        failures.add('duplicate_tag')
    return {'failing_reasons': sorted(failures), 'tag_names': sorted(names),
            'other_tag_count': other_count, 'media_sequence_present': sequence_seen,
            'map_before_first_segment': map_before, 'bom_present': bom,
            'leading_whitespace_present': leading, 'extinf_format_classes': sorted(formats),
            'duplicate_tag_count': sum(max(0, tag_counts.get(tag, 0) - 1) for tag in SHAPE_SINGLETONS)}
