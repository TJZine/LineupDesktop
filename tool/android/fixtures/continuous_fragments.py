"""Give generated second fMP4 segments continuous decode timestamps.

FFmpeg's empty_moov muxer reset the probe's second-segment timestamps despite
output_ts_offset. Keep those original parser controls; this helper supplies an
additional actual second-segment render control. It is never used by playback.
"""
import json
import struct
import subprocess
from fractions import Fraction


def shifted_segment(source, seconds):
    streams = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_streams', '-of', 'json', str(source)
    ]))['streams']
    shifts = {int(s['id'], 0): int(Fraction(seconds) / Fraction(s['time_base'])) for s in streams}
    data = bytearray(source.read_bytes())

    def boxes(start, end):
        position = start
        while position < end:
            if end - position < 8:
                raise ValueError('incomplete_fixture_box')
            size, kind = struct.unpack_from('>I4s', data, position)
            if size < 8 or position + size > end:
                raise ValueError('unsupported_fixture_box')
            yield kind, position + 8, position + size
            position += size

    patched = 0
    for kind, start, end in boxes(0, len(data)):
        if kind != b'moof':
            continue
        for child, traf_start, traf_end in boxes(start, end):
            if child != b'traf':
                continue
            entries = list(boxes(traf_start, traf_end))
            track = next(struct.unpack_from('>I', data, a + 4)[0] for t, a, _ in entries if t == b'tfhd')
            for entry, a, _ in entries:
                if entry == b'tfdt':
                    encoding = '>Q' if data[a] == 1 else '>I'
                    value = struct.unpack_from(encoding, data, a + 4)[0]
                    struct.pack_into(encoding, data, a + 4, value + shifts[track])
                    patched += 1
    if not patched:
        raise ValueError('missing_fixture_decode_times')
    return bytes(data)
