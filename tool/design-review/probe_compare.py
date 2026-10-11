"""Compare drawn text geometry between two capture configs.

Usage: probe_compare.py BASE TARGET FACTOR
"""
import argparse
import collections
import json
import math
from pathlib import Path

_FIELDS = ('x', 'y', 'w', 'h', 'fontSize', 'letterSpacing')
_TOLERANCE = 0.5
_DEFAULT_MAX_DIAGNOSTICS = 40


def _args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base', type=Path, help='base capture directory')
    parser.add_argument('target', type=Path, help='target capture directory')
    parser.add_argument('factor', type=float, help='expected target/base geometry scale')
    parser.add_argument(
        '--max-diagnostics',
        type=int,
        default=_DEFAULT_MAX_DIAGNOSTICS,
        help='maximum mismatch details to print (default: %(default)s)',
    )
    args = parser.parse_args()
    if not math.isfinite(args.factor) or args.factor <= 0:
        parser.error('factor must be a finite number greater than zero')
    if args.max_diagnostics < 0:
        parser.error('--max-diagnostics must not be negative')
    return args


def _load_capture_directory(path):
    if not path.is_dir():
        raise ValueError(f'capture directory is missing: {path.name}')
    files = sorted(path.glob('*.json'))
    if not files:
        raise ValueError(f'capture directory has no JSON probes: {path.name}')
    captures = {}
    for file in files:
        try:
            data = json.loads(file.read_text())
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError(f'invalid JSON probe: {file.name}') from error
        if not isinstance(data, list):
            raise ValueError(f'JSON probe is not a list: {file.stem}')
        captures[file.stem] = data
    # Text-free scenes such as the buffering arc are valid. A wholly empty
    # directory cannot establish any text geometry and must still fail.
    if not any(captures.values()):
        raise ValueError('capture directory has no text geometry')
    return captures


def _flatten(probes):
    """Yield paragraph and nested text-run geometry without shortening identity."""
    for probe in probes:
        if not isinstance(probe, dict):
            raise ValueError('probe entry is not an object')
        yield ('paragraph', probe)
        runs = probe.get('runs', [])
        if not isinstance(runs, list):
            raise ValueError('probe runs are not a list')
        for run in runs:
            if not isinstance(run, dict):
                raise ValueError('nested probe entry is not an object')
            yield ('span', run)


def _keyed(probes):
    seen = collections.Counter()
    result = {}
    for kind, probe in _flatten(probes):
        text = probe.get('text')
        if not isinstance(text, str):
            raise ValueError('probe text identity is missing or not a string')
        identity = (kind, text)
        key = (*identity, seen[identity])
        seen[identity] += 1
        if key in result:
            raise ValueError('duplicate probe identity')
        result[key] = probe
    return result


def _number(probe, field):
    value = probe.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f'probe field {field} is missing or not finite')
    return float(value)


def _display_key(key):
    kind, text, occurrence = key
    preview = text if len(text) <= 80 else text[:77] + '...'
    return f'{kind} {preview!r} ({occurrence})'


def _compare(base, target, factor, max_diagnostics):
    base_names = set(base)
    target_names = set(target)
    diagnostics = []
    if base_names != target_names:
        for name in sorted(base_names - target_names):
            diagnostics.append(f'missing target scene: {name}')
        for name in sorted(target_names - base_names):
            diagnostics.append(f'unmatched target scene: {name}')

    compared = 0
    unmatched = 0
    differences = 0
    for name in sorted(base_names & target_names):
        base_probes = _keyed(base[name])
        target_probes = _keyed(target[name])
        for key in sorted(base_probes, key=repr):
            if key not in target_probes:
                unmatched += 1
                diagnostics.append(f'{name}: missing target {_display_key(key)}')
                continue
            compared += 1
            base_probe = base_probes[key]
            target_probe = target_probes[key]
            for field in _FIELDS:
                expected = _number(base_probe, field) * factor
                actual = _number(target_probe, field)
                delta = actual - expected
                if abs(delta) > _TOLERANCE:
                    differences += 1
                    diagnostics.append(
                        f'{name}: {_display_key(key)} {field} '
                        f'expected {expected:.3f}, actual {actual:.3f}, delta {delta:+.3f}'
                    )
        for key in sorted(set(target_probes) - set(base_probes), key=repr):
            unmatched += 1
            diagnostics.append(f'{name}: unmatched target {_display_key(key)}')

    for line in diagnostics[:max_diagnostics]:
        print(f'  {line}')
    if len(diagnostics) > max_diagnostics:
        print(f'  ... {len(diagnostics) - max_diagnostics} more diagnostics omitted')

    print(
        f'Compared {compared} geometry entries across {len(base_names & target_names)} scenes; '
        f'factor={factor:g}, absolute tolerance=±{_TOLERANCE:g}px.'
    )
    if differences or unmatched or base_names != target_names:
        print(f'FAILED: {differences} field differences, {unmatched} unmatched entries.')
        return 1
    print('PASSED: all geometry fields are within the absolute tolerance.')
    return 0


def main():
    args = _args()
    try:
        base = _load_capture_directory(args.base)
        target = _load_capture_directory(args.target)
        return _compare(base, target, args.factor, args.max_diagnostics)
    except ValueError as error:
        print(f'FAILED: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
