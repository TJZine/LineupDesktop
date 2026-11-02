#!/usr/bin/env python3
"""Production macOS adapter session-clock proof using a frozen local corpus only.

No account lookup, Plex endpoint, system trust change or direct ctypes player is
used. Preparation builds the actual adapter/core executable; primary execution
requires a separately reviewed exact-list freeze and an exclusive one-cycle claim.
"""
import argparse
from fractions import Fraction
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import signal
import socket
import stat
import ssl
import subprocess
import sys
import threading
import time
import urllib.parse

REPO = Path(__file__).resolve().parents[3]
SCHEDULE = (('copy', 10), ('copy', 21), ('copy', 605), ('encode', 10), ('encode', 605))
MAX_CAPTURE = 256 * 1024
MAX_INPUT = 2 * 1024 * 1024
MAX_RESPONSE = 2 * 1024 * 1024
MAX_HTTP = 320
MAX_BYTES = 160 * 1024 * 1024
STRUCTURAL_CODES = frozenset(('none', 'event_queue_overflow', 'event_bound', 'status_write_failed',
    'core_correlation', 'core_command', 'core_unknown_failure', 'command_rejected', 'event_shape', 'clock_event_shape',
    'invalid_load_map', 'global_selector', 'unexpected_seek'))


class HarnessFailure(RuntimeError):
    pass


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def reference_tools():
    return module(REPO / 'tool/macos/authenticated-reference/run.py', 'session_clock_reference_tools')


def clean_environment():
    return reference_tools().clean_environment()


def load_fixture(directory):
    directory = Path(directory).resolve(strict=True)
    # These are independently frozen earlier fixture modules, never regenerated.
    sys.path.insert(0, str(directory))
    sys.path.insert(0, str(directory.parent))
    media = module(directory / 'synthetic_media.py', 'session_clock_synthetic_media')
    server = module(directory / 'synthetic_server.py', 'session_clock_synthetic_server')
    server.MAX_TOTAL_HTTP = MAX_HTTP
    server.MAX_CELL_HTTP = 64
    server.MAX_TOTAL_BYTES = MAX_BYTES
    return media, server


def manifest(corpus, mode, x, base):
    if mode in ('child_redirect_negative', 'nested_hls_negative'):
        child = '/attack.m3u8' if mode == 'nested_hls_negative' else '/redirect.m4s'
        return ('#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-PLAYLIST-TYPE:VOD\n'
            '#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:0\n'
            '#EXT-X-MAP:URI="' + base + '/init.mp4"\n#EXTINF:1,\n' + base + child + '\n#EXT-X-ENDLIST\n')
    return corpus.playlist(mode, x, base).decode().replace(base + '/media/', base + '/')


def prepare(runtime, flutter, fixture, output):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    tools = reference_tools()
    tools.DEADLINE = time.monotonic() + 600
    tools.OUTPUT = output
    runtime, flutter = Path(runtime).resolve(strict=True), Path(flutter).resolve(strict=True)
    identity = tools.validate_runtime(runtime, flutter)
    cmake = tools.tool('cmake')
    build = output / 'build'
    tools.run([cmake, '-S', str(Path(__file__).parent), '-B', str(build),
        '-DCMAKE_BUILD_TYPE=Debug', '-DCMAKE_OSX_ARCHITECTURES=arm64',
        '-DCMAKE_CXX_COMPILER=/usr/bin/clang++', '-DCMAKE_OBJCXX_COMPILER=/usr/bin/clang++',
        '-DLINEUP_MPV_RUNTIME=' + str(runtime), '-DFLUTTER_ROOT=' + str(flutter)], timeout=90, label='configure')
    tools.run([cmake, '--build', str(build), '--parallel', '2'], timeout=120, label='build')
    harness = build / 'session-clock'
    test = tools.run([str(harness), '--self-test'], timeout=10, label='self-test')
    if test != b'self_test=pass\n':
        raise HarnessFailure('self_test_failed')
    media, _server = load_fixture(fixture)
    corpus = media.Corpus()
    parse_checks = 0
    for mode, offset in SCHEDULE:
        variant = 'https://127.0.0.1:443/video/:/transcode/universal/session/synthetic-parse/base/index.m3u8'
        base = variant.rsplit('/', 1)[0]
        text = manifest(corpus, mode, offset, base)
        payload = {'load': {'kind': 'plexSession', 'uri': variant, 'loadId': 1, 'startPaused': True,
            'sessionPlaylist': {'text': text, 'offsetMicroseconds': offset * 1000000}},
            'canaries': [text, variant, base + '/init.mp4']}
        checked = subprocess.run([str(harness), '--validate-playlist'], input=json.dumps(payload).encode(),
            capture_output=True, timeout=10, env=clean_environment())
        if checked.returncode or checked.stdout != b'playlist_validation=pass\n' or checked.stderr:
            raise HarnessFailure('native_playlist_parse_failed')
        parse_checks += 1
    sources = [*Path(__file__).parent.glob('*.*'),
        REPO / 'tool/macos/authenticated-reference/run.py',
        REPO / 'tool/macos/authenticated-reference/session_policy_test.h',
        Path(fixture).resolve().parent / 'e7c_fragment_timing.py',
        *[REPO / 'macos/Runner/NativePlayer' / name for name in
          ('LineupNativePlayer.h', 'LineupNativePlayer.mm', 'FoundationValueConversion.h',
           'FoundationValueConversion.mm', 'VideoGeometry.h', 'VideoGeometry.mm')],
        *(REPO / 'native/player_core').glob('*.h'),
        *[REPO / 'native/player_core' / name for name in
          ('player_core.cpp', 'session_playlist.cpp', 'subtitle_cues.cpp', 'libmpv_operations.cpp', 'platform_arguments.cpp', 'track_list_encoder.cpp')]]
    source_hashes = {str(path.resolve()): sha(path) for path in sources if path.is_file()}
    runtime_inputs = [runtime / 'BUILD-INFO.txt', runtime / 'include/mpv/client.h', runtime / 'include/mpv/stream_cb.h',
        REPO / 'tool/macos/mpv-runtime.lock', REPO / 'tool/flutter_version.json']
    runtime_inputs += sorted((runtime / 'lib').glob('*.dylib'))
    framework = flutter / 'bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64/FlutterMacOS.framework'
    runtime_inputs += [framework / 'FlutterMacOS'] + sorted((framework / 'Headers').glob('*.h'))
    for path in runtime_inputs:
        source_hashes[str(path.resolve())] = sha(path)
    for path in Path(fixture).glob('*.py'):
        source_hashes[str(path.resolve())] = sha(path)
    for path in (Path(fixture) / 'media').iterdir():
        if path.is_file(): source_hashes[str(path.resolve())] = sha(path)
    for name in ('freeze.json', 'corpus-proof.json'):
        path = Path(fixture) / name
        source_hashes[str(path.resolve())] = sha(path)
    value = {'kind': 'production-path synthetic preparation; zero media loads',
        'runtime': identity, 'runtimePath': str(runtime), 'flutterRoot': str(flutter),
        'fixtureDir': str(Path(fixture).resolve()), 'harness': str(harness),
        'harnessSha256': sha(harness), 'inputs': source_hashes, 'selfTestPassed': True, 'nativePlaylistParses': parse_checks,
        'sourceHead': tools.run(['git', '-C', str(REPO), 'rev-parse', 'HEAD'], label='source-head').decode().strip()}
    with (output / 'identity.json').open('x') as handle:
        json.dump(value, handle, indent=2); handle.write('\n')
    return value


def preflight(freeze_path, output):
    freeze = json.loads(Path(freeze_path).read_text())
    required = ('inputs', 'harness', 'harnessSha256', 'fixtureDir', 'certificatePath',
        'certificateSha256', 'clientCaPath', 'clientCaSha256', 'privateKeyPath', 'identityPath', 'identitySha256',
        'listPath', 'listSha256', 'reviewPath', 'reviewSha256')
    if freeze.get('version') != 1 or any(not freeze.get(key) for key in required):
        raise HarnessFailure('incomplete_reviewed_freeze')
    pairs = [(freeze['harness'], freeze['harnessSha256']), (freeze['certificatePath'], freeze['certificateSha256']),
        (freeze['clientCaPath'], freeze['clientCaSha256']),
        (freeze['identityPath'], freeze['identitySha256']), (freeze['listPath'], freeze['listSha256']),
        (freeze['reviewPath'], freeze['reviewSha256'])]
    pairs += list(freeze['inputs'].items())
    for path, expected in pairs:
        if sha(path) != expected: raise HarnessFailure('frozen_input_changed')
    identity = json.loads(Path(freeze['identityPath']).read_text())
    expected_inputs = identity.get('inputs')
    if (not isinstance(expected_inputs, dict) or not expected_inputs or
        identity.get('harness') != freeze['harness'] or identity.get('harnessSha256') != freeze['harnessSha256'] or
        any(freeze['inputs'].get(path) != expected for path, expected in expected_inputs.items())):
        raise HarnessFailure('prepared_identity_not_frozen')
    if not Path(freeze['privateKeyPath']).is_file(): raise HarnessFailure('fixture_tls_key_missing')
    if tuple(tuple(x) for x in freeze.get('schedule', ())) != SCHEDULE:
        raise HarnessFailure('schedule_mismatch')
    if freeze.get('maximumHTTP') != MAX_HTTP or freeze.get('maximumBytes') != MAX_BYTES:
        raise HarnessFailure('freeze_budget_mismatch')
    if not isinstance(freeze['inputs'], dict) or not freeze['inputs']:
        raise HarnessFailure('empty_frozen_inputs')
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    if (output / 'cycle-claim.json').exists() or (output / 'result.json').exists():
        raise HarnessFailure('cycle_already_claimed')
    if any(os.path.lexists(output / f'cell-{ordinal}-policy-ready.status') for ordinal in (1, 2)):
        raise HarnessFailure('policy_status_already_exists')
    return freeze


def scan_output(stdout, stderr, canaries):
    markers = [b'#EXTM3U', b'#EXT-X-']
    for canary in canaries:
        raw = canary.encode()
        markers.extend((raw, raw.replace(b'/', b'\\/'), json.dumps(canary)[1:-1].encode()))
    leaked = any(marker and marker in stream for marker in markers for stream in (stdout, stderr))
    leaked |= any(re.search(rb'[A-Za-z][A-Za-z0-9+.-]*:(?:/|\\/){2}', stream) is not None for stream in (stdout, stderr))
    lines = []
    for line in stderr.splitlines():
        if re.fullmatch(rb'\[lineup-player\] libmpv initialized client-api=[0-9]+', line):
            lines.append(line.decode('ascii'))
        elif line:
            lines.append('[REDACTED_NATIVE_LINE]')
    return {'canaryLeak': bool(leaked), 'stdoutBytes': len(stdout), 'stderrBytes': len(stderr),
        'stderrLineCount': len(stderr.splitlines()), 'redactedStderr': '\n'.join(lines)}


def child(harness, client_ca, payload, stopping, fatal, *, timeout=35):
    raw_input = json.dumps(payload, separators=(',', ':')).encode()
    if len(raw_input) > MAX_INPUT: raise HarnessFailure('native_input_cap')
    process = subprocess.Popen([str(harness), str(client_ca)], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=clean_environment(), bufsize=0)
    streams = {'stdout': bytearray(), 'stderr': bytearray()}
    overflow = threading.Event()
    writer_failed = threading.Event()
    def read(name, pipe):
        try:
            while True:
                block = pipe.read(4096)
                if not block: return
                available = MAX_CAPTURE - len(streams[name])
                streams[name].extend(block[:max(0, available)])
                if len(block) > available: overflow.set()
        finally: pipe.close()
    def write():
        try:
            offset = 0
            while offset < len(raw_input):
                written = process.stdin.write(raw_input[offset:])
                if not written: raise BrokenPipeError()
                offset += written
        except (BrokenPipeError, OSError): writer_failed.set()
        finally:
            try: process.stdin.close()
            except OSError: pass
    readers = [threading.Thread(target=read, args=(name, pipe), daemon=True)
               for name, pipe in (('stdout', process.stdout), ('stderr', process.stderr))]
    writer = threading.Thread(target=write, daemon=True)
    for thread in [*readers, writer]: thread.start()
    deadline = time.monotonic() + timeout
    forced = False
    try:
        while process.poll() is None:
            if stopping() or fatal() or overflow.is_set() or time.monotonic() >= deadline:
                forced = True
                process.terminate()
                try: process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait(timeout=2)
                break
            time.sleep(.01)
    finally:
        if process.poll() is None:
            forced = True
            process.kill(); process.wait(timeout=2)
        for thread in [*readers, writer]: thread.join(2)
    return {'returncode': process.returncode, 'stdout': bytes(streams['stdout']), 'stderr': bytes(streams['stderr']),
        'forced': forced, 'captureOverflow': overflow.is_set(), 'stdinFailed': writer_failed.is_set(),
        'childReaped': process.poll() is not None, 'captureThreadsDrained': all(not t.is_alive() for t in [*readers, writer])}


class PolicyBarrier:
    MARKER = b'policy_ready\n'

    def __init__(self, path, directory, ordinal, *, now=time.monotonic, sleep=time.sleep):
        path, directory = Path(path), Path(directory).resolve(strict=True)
        if (ordinal not in (1, 2) or not path.is_absolute() or path.parent != directory or
            path.name != f'cell-{ordinal}-policy-ready.status' or directory.stat().st_uid != os.getuid() or
            os.path.lexists(path)):
            raise HarnessFailure('policy_status_ownership')
        self.path, self.ordinal = path, ordinal
        self.now, self.sleep = now, sleep
        self.started = None
        self.ready_at = None
        self.failure = None
        self.lock = threading.Lock()

    def _read(self):
        descriptor = None
        try:
            descriptor = os.open(self.path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 32:
                return 'invalid'
            data = os.read(descriptor, 33)
            if data == self.MARKER: return 'ready'
            return 'partial' if self.MARKER.startswith(data) else 'invalid'
        except FileNotFoundError:
            return 'absent'
        except OSError:
            return 'invalid'
        finally:
            if descriptor is not None: os.close(descriptor)

    def wait(self, retired):
        with self.lock:
            if self.started is None: self.started = self.now()
            started = self.started
        while self.now() - started < 5:
            if retired():
                self.failure = 'retired'; return False
            state = self._read()
            if state == 'ready':
                with self.lock:
                    if self.ready_at is None: self.ready_at = self.now()
                return True
            if state == 'invalid':
                self.failure = 'invalid_marker'; return False
            self.sleep(.005)
        self.failure = 'timeout'
        return False

    def public(self):
        return {'ordinal': self.ordinal, 'responseReleasedAfterExactMarker': self.ready_at is not None,
            'readyObservedMonotonicNs': None if self.ready_at is None else int(self.ready_at * 1e9),
            'waitSeconds': None if self.started is None else round((self.ready_at or self.now()) - self.started, 9),
            'maximumWaitSeconds': 5, 'fixedFailure': self.failure}


def server_class(base):
    class ProductionServer(base):
        def __init__(self, corpus, cert, key):
            # Validate TLS before the base constructor can bind a listener.
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(cert, key)
            if any(not isinstance(records[0], bytes) or len(records[0]) > MAX_RESPONSE for records in corpus.data.values()):
                raise HarnessFailure('initialization_response_byte_cap')
            owner = self
            class BoundedCorpus:
                data = corpus.data
                def fragment(self, mode, index):
                    body = corpus.fragment(mode, index)
                    if not isinstance(body, bytes) or len(body) > MAX_RESPONSE:
                        owner.fatal = 'response_byte_cap'
                        return b''
                    return body
                def playlist(self, mode, offset, base):
                    body = corpus.playlist(mode, offset, base)
                    if not isinstance(body, bytes) or len(body) > MAX_RESPONSE:
                        owner.fatal = 'response_byte_cap'
                        return b''
                    # New fixture namespace is flat, matching the production
                    # grammar. Timing tags and all generated media stay intact.
                    return body.replace((base + '/media/').encode(), (base + '/').encode())
            super().__init__(BoundedCorpus())
            original_get = self.http.get_request
            def get_request():
                connection, address = original_get()
                try: wrapped = context.wrap_socket(connection, server_side=True, do_handshake_on_connect=False)
                except BaseException:
                    with self.lock: self.connections.discard(connection)
                    connection.close(); raise
                with self.lock:
                    self.connections.discard(connection)
                    self.connections.add(wrapped)
                return wrapped, address
            self.http.get_request = get_request
            self.http.handle_error = lambda *_: setattr(self, 'fatal', 'server_handler_failure')
        def begin(self, mode, x, variant):
            super().begin(mode, x, variant)
            return f'https://127.0.0.1:{self.http.server_port}/video/:/transcode/universal/session/synthetic-canary-{self.cell}/base/index.m3u8'
        def arm_policy_barrier(self, barrier):
            self.policy_barrier = barrier

        def arm_attack(self, sentinel_url):
            self.sentinel_url = sentinel_url
            # FFmpeg rejects an empty initialization read before media probing.
            # read_data concatenates this nonempty prefix and the media body.
            self.attack_init = b'#EXTM3U\n'
            self.attack_payload = ('#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:1\n'
                '#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:1,\n' + sentinel_url + '\n#EXT-X-ENDLIST\n').encode()

        def serve(self, handler):
            with self.lock:
                active = self.active
                prefix = None if active is None else f'/video/:/transcode/universal/session/synthetic-canary-{active["id"]}/base'
                target = None if active is None else f'/cell/{active["id"]}'
            if prefix and handler.path.startswith(prefix + '/'):
                if active.get('variant') in ('nested_hls_negative', 'child_redirect_negative'):
                    # These exact bodies are the single declared adversarial
                    # exception; no generated positive media is changed.
                    suffix = handler.path[len(prefix):]
                    if suffix in ('/init.mp4', '/attack.m3u8', '/redirect.m4s'):
                        self.serve_attack(handler, suffix == '/init.mp4')
                        return
                suffix = handler.path[len(prefix):]
                if suffix in ('/index.m3u8', '/init.mp4'):
                    handler.path = target + suffix
                elif re.fullmatch(r'/[0-9]{1,3}\.m4s', suffix):
                    handler.path = target + '/media' + suffix
                else:
                    handler.path = '/session-clock-unlisted'
            else:
                # Never leave the base fixture's private /cell/N alias reachable.
                handler.path = '/session-clock-unlisted'
            super().serve(handler)

        def serve_attack(self, handler, initialization):
            with self.lock:
                active = self.active
            redirect = active['variant'] == 'child_redirect_negative' and initialization
            if initialization:
                body = b'' if redirect else self.attack_init
            elif active['variant'] == 'child_redirect_negative':
                body = self.corpus.fragment('copy', 0)
            else:
                body = self.attack_payload
            with self.lock:
                row = {'ordinal': len(self.rows) + 1, 'method': handler.command,
                    'path': '/adversarial/' + ('init' if initialization else 'nested-playlist'),
                    'range': handler.headers.get('Range'), 'status': 302 if redirect else 200, 'cell': active['id'],
                    'mode': active['mode'], 'offset': active['offset'], 'variant': active['variant'],
                    'reserved_bytes': len(body), 'written_bytes': 0, 'write_complete': False,
                    'connection_closed': False, 'empty_prestart': False,
                    'kind': 'init' if initialization else 'media', 'segment_index': None if initialization else 0,
                    'request_start_ns': time.monotonic_ns()}
                self.rows.append(row); self.inflight += 1; active['requests'] += 1
                if (handler.command != 'GET' or active['requests'] >= 16 or len(self.rows) >= MAX_HTTP or
                    len(body) > MAX_RESPONSE or active['reserved'] + len(body) > 1024 * 1024):
                    self.fatal = 'adversarial_request_guard'
                    row.update(status=None, held_guard=self.fatal, reserved_bytes=0)
                    hold = True
                else:
                    active['reserved'] += len(body); hold = False
            try:
                if hold:
                    active['retire_event'].wait()
                else:
                    barrier = getattr(self, 'policy_barrier', None)
                    if barrier is None or not barrier.wait(active['retire_event'].is_set):
                        self.fatal = 'policy_status_barrier_failed'
                        row.update(status=None, held_guard=self.fatal)
                        return
                    row['policy_ready_before_response'] = True
                    handler.send_response(302 if redirect else 200)
                    if redirect: handler.send_header('Location', self.sentinel_url)
                    handler.send_header('Content-Type', 'application/vnd.apple.mpegurl' if not initialization else 'video/mp4')
                    handler.send_header('Content-Length', str(len(body)))
                    handler.send_header('Connection', 'close')
                    handler.end_headers(); row['headers_sent_ns'] = time.monotonic_ns()
                    handler.wfile.write(body); handler.wfile.flush()
                    row.update(written_bytes=len(body), write_complete=True)
            except (BrokenPipeError, ConnectionResetError, TimeoutError, OSError):
                row['write_error'] = 'consumer_closed_or_socket_error'
            finally:
                handler.close_connection = True
                row.update(connection_closed=True, end_ns=time.monotonic_ns())
                with self.lock: self.inflight -= 1
    return ProductionServer


def native_shape(value):
    """Accept only the executable's closed numeric/fixed result, never raw logs."""
    boolean_keys = {'pass', 'initialized', 'loadAccepted', 'complete', 'playing', 'rejected',
        'canaryLeak', 'workerFailed', 'loadMapExact', 'globalForceHls', 'stopAccepted', 'disposed',
        'nativeDestroyed', 'runtimeBound', 'operatorStopped', 'stopConfirmed', 'policyChecked', 'policyRestored', 'policyHandshakeWritten', 'structuralFailure', 'formatWhitelistObserved', 'protocolWhitelistObserved', 'lavfSelectedObserved', 'referenceAccessObserved', 'redirectZeroObserved', 'tlsVerifyObserved'}
    count_keys = {'restartCount', 'loadCommands', 'seekCommands', 'nestedForbiddenCount', 'redirectCount', 'curlRedirectRefusedCount', 'endFileErrorCount'}
    other_keys = {'fileLoaded', 'firstRestart', 'samples', 'productionDemuxerEvents', 'productionPositionEvents', 'elapsedSeconds', 'structuralFailureCode', 'restoration'}
    def finite(number):
        return type(number) in (int, float) and math.isfinite(number)
    if not isinstance(value, dict) or set(value) != boolean_keys | count_keys | other_keys:
        raise HarnessFailure('native_output_shape')
    if any(type(value[key]) is not bool for key in boolean_keys): raise HarnessFailure('native_output_shape')
    if type(value['structuralFailureCode']) is not str or value['structuralFailureCode'] not in STRUCTURAL_CODES or value['structuralFailure'] != (value['structuralFailureCode'] != 'none'):
        raise HarnessFailure('native_output_shape')
    if any(type(value[key]) is not int or not 0 <= value[key] <= 4096 for key in count_keys):
        raise HarnessFailure('native_output_shape')
    if not finite(value['elapsedSeconds']) or not 0 <= value['elapsedSeconds'] <= 60:
        raise HarnessFailure('native_output_shape')
    numbers = {'P', 'D', 'audioPts', 'duration', 'decodedWidth', 'decodedHeight', 'outputWidth', 'outputHeight'}
    flags = {'voConfigured', 'paused', 'seeking', 'rebase', 'qualified', 'formatWhitelist', 'protocolWhitelist', 'lavfSelected', 'referenceAccess', 'redirectZero', 'tlsVerify'}
    def snapshot(item, sample=False):
        if item is None and not sample: return
        expected = numbers | flags | {'pictureType', 'elapsedSeconds'}
        if sample: expected |= {'sampleIndex', 'sampleAgeSeconds', 'observationSeconds',
            'productionP', 'productionD', 'productionPAgeSeconds', 'productionDAgeSeconds'}
        if not isinstance(item, dict) or set(item) != expected: raise HarnessFailure('native_output_shape')
        if any(item[key] is not None and not finite(item[key]) for key in numbers): raise HarnessFailure('native_output_shape')
        if any(type(item[key]) is not bool for key in flags): raise HarnessFailure('native_output_shape')
        if type(item['pictureType']) is not int or item['pictureType'] not in (0, 1, 2, 3): raise HarnessFailure('native_output_shape')
        if not finite(item['elapsedSeconds']) or not 0 <= item['elapsedSeconds'] <= 60: raise HarnessFailure('native_output_shape')
        if sample:
            if type(item['sampleIndex']) is not int or not 0 <= item['sampleIndex'] <= 24: raise HarnessFailure('native_output_shape')
            if any(not finite(item[key]) or not 0 <= item[key] <= 60 for key in ('sampleAgeSeconds', 'observationSeconds')):
                raise HarnessFailure('native_output_shape')
            for key in ('productionP', 'productionD', 'productionPAgeSeconds', 'productionDAgeSeconds'):
                if item[key] is not None and not finite(item[key]): raise HarnessFailure('native_output_shape')
    restore = value['restoration']
    if (not isinstance(restore, dict) or set(restore) != {'immediate', 'final', 'complete', 'waitSeconds', 'maximumWaitSeconds', 'timedOut'} or
        type(restore['complete']) is not bool or type(restore['timedOut']) is not bool or
        not finite(restore['waitSeconds']) or not 0 <= restore['waitSeconds'] <= 60 or restore['maximumWaitSeconds'] != 1):
        raise HarnessFailure('native_output_shape')
    for item in (restore['immediate'], restore['final']):
        restore_flags = {name + suffix for name in ('references', 'redirects', 'demuxer', 'lavf') for suffix in ('Checked', 'Restored')} | {'endFenceSeen', 'idleChecked', 'playlistCountChecked'}
        if (not isinstance(item, dict) or set(item) != restore_flags | {'endReason', 'idle', 'playlistCount'} or
            any(type(item[key]) is not bool for key in restore_flags) or
            item['endReason'] not in ('none', 'stop', 'error', 'eof', 'other') or
            (item['idle'] is not None and type(item['idle']) is not bool) or
            (item['playlistCount'] is not None and (type(item['playlistCount']) is not int or not 0 <= item['playlistCount'] <= 1000000)) or
            item['idleChecked'] != (item['idle'] is not None) or item['playlistCountChecked'] != (item['playlistCount'] is not None)):
            raise HarnessFailure('native_output_shape')
    snapshot(value['fileLoaded']); snapshot(value['firstRestart'])
    if not isinstance(value['samples'], list) or len(value['samples']) > 25: raise HarnessFailure('native_output_shape')
    for item in value['samples']: snapshot(item, True)
    for events in (value['productionDemuxerEvents'], value['productionPositionEvents']):
        if not isinstance(events, list) or len(events) > 4096: raise HarnessFailure('native_output_shape')
        for event in events:
            if (not isinstance(event, dict) or set(event) != {'value', 'loadId', 'elapsedSeconds'} or
                (event['value'] is not None and not finite(event['value'])) or
                (event['loadId'] is not None and (type(event['loadId']) is not int or event['loadId'] != 1)) or
                (event['value'] is not None and event['loadId'] != 1) or
                not finite(event['elapsedSeconds']) or not 0 <= event['elapsedSeconds'] <= 60):
                raise HarnessFailure('native_output_shape')
    return value


def restoration_accepted(value, expected_reason):
    if not isinstance(value, dict) or value.get('complete') is not True or value.get('timedOut') is not False:
        return False
    elapsed = value.get('waitSeconds')
    final = value.get('final', {})
    return (type(elapsed) in (int, float) and math.isfinite(elapsed) and 0 <= elapsed <= 1 and
        value.get('maximumWaitSeconds') == 1 and final.get('endFenceSeen') is True and
        final.get('endReason') == expected_reason and final.get('idleChecked') is True and final.get('idle') is True and
        final.get('playlistCountChecked') is True and final.get('playlistCount') == 0 and
        all(final.get(name + suffix) is True for name in ('references', 'redirects', 'demuxer', 'lavf') for suffix in ('Checked', 'Restored')))


def analyze_negative(native, sentinel, kind):
    reasons = []
    if not restoration_accepted(native.get('restoration'), 'error'): reasons.append('stop_restoration_fence')
    if native.get('operatorStopped') is not False: reasons.append('operator_stop')
    if native.get('structuralFailure') is not False or native.get('structuralFailureCode') != 'none':
        reasons.append('native_structural_failure')
    if native.get('endFileErrorCount', 0) < 1: reasons.append('expected_end_file_error_missing')
    if native.get('workerFailed') is not True: reasons.append('expected_worker_failure_missing')
    if native.get('policyHandshakeWritten') is not True: reasons.append('policy_status_not_written')
    if native.get('pass') is not False or native.get('rejected') is not True:
        reasons.append('negative_not_rejected')
    if kind == 'nested_hls_negative' and native.get('nestedForbiddenCount', 0) < 1:
        reasons.append('nested_child_io_blocker_not_exercised')
    if kind == 'child_redirect_negative' and native.get('curlRedirectRefusedCount', 0) < 1:
        reasons.append('curl_redirect_blocker_not_exercised')
    for key in ('nativeDestroyed', 'disposed', 'runtimeBound', 'stopAccepted', 'loadMapExact',
                'formatWhitelistObserved', 'protocolWhitelistObserved', 'lavfSelectedObserved', 'referenceAccessObserved', 'redirectZeroObserved', 'tlsVerifyObserved', 'stopConfirmed', 'policyChecked', 'policyRestored'):
        if native.get(key) is not True: reasons.append(key)
    if native.get('canaryLeak') is not False or native.get('globalForceHls') is not False:
        reasons.append('negative_leak_or_global_force')
    if native.get('loadCommands') != 1 or native.get('seekCommands') != 0 or native.get('redirectCount') != 0:
        reasons.append('negative_command_contract')
    if sentinel.rows or sentinel.accepted_connections:
        reasons.append('off_origin_sentinel_contacted')
    return {'pass': not reasons, 'fixedReasons': reasons,
        'nestedForbiddenCount': native.get('nestedForbiddenCount', 0),
        'curlRedirectRefusedCount': native.get('curlRedirectRefusedCount', 0),
        'sentinelHTTP': len(sentinel.rows), 'sentinelAcceptedConnections': sentinel.accepted_connections}


def analyze_native(native, mode, x, proof):
    reasons = []
    if not restoration_accepted(native.get('restoration'), 'stop'): reasons.append('stop_restoration_fence')
    if native.get('pass') is not True: reasons.append('native_harness_not_pass')
    if native.get('operatorStopped') is not False: reasons.append('operator_stop')
    if native.get('structuralFailure') is not False or native.get('structuralFailureCode') != 'none':
        reasons.append('native_structural_failure')
    if native.get('endFileErrorCount') != 0: reasons.append('unexpected_end_file_error')
    for key in ('canaryLeak', 'globalForceHls', 'workerFailed', 'rejected'):
        if native.get(key) is not False: reasons.append(key)
    for key in ('loadMapExact', 'nativeDestroyed', 'disposed', 'runtimeBound', 'stopAccepted', 'formatWhitelistObserved', 'protocolWhitelistObserved', 'lavfSelectedObserved', 'referenceAccessObserved', 'redirectZeroObserved', 'tlsVerifyObserved', 'stopConfirmed', 'policyChecked', 'policyRestored'):
        if native.get(key) is not True: reasons.append(key)
    if native.get('loadCommands') != 1 or native.get('seekCommands') != 0 or native.get('redirectCount') != 0: reasons.append('command_contract')
    samples = native.get('samples', [])
    if len(samples) != 25: reasons.append('sample_count')
    def good(snapshot):
        return (isinstance(snapshot, dict) and snapshot.get('qualified') is True and
            snapshot.get('formatWhitelist') is True and snapshot.get('protocolWhitelist') is True and snapshot.get('lavfSelected') is True and snapshot.get('referenceAccess') is True and
            snapshot.get('redirectZero') is True and snapshot.get('tlsVerify') is True and
            all(type(snapshot.get(key)) in (int, float) and math.isfinite(snapshot[key]) for key in ('P', 'D')) and
            all(snapshot.get(key) == expected for key, expected in
                (('decodedWidth', 96), ('decodedHeight', 54), ('outputWidth', 96), ('outputHeight', 54))))
    first = native.get('firstRestart')
    if not good(first) or not all(good(s) for s in samples): reasons.append('unqualified_clock_or_video')
    events = native.get('productionDemuxerEvents', [])
    finite_d = [e['value'] for e in events if isinstance(e, dict) and type(e.get('value')) in (int, float) and math.isfinite(e['value']) and e.get('loadId') == 1]
    if not finite_d: reasons.append('missing_production_demuxer_clock')
    position_events = native.get('productionPositionEvents', [])
    finite_p = [e['value'] for e in position_events if isinstance(e, dict) and type(e.get('value')) in (int, float) and math.isfinite(e['value']) and e.get('loadId') == 1]
    if not finite_p: reasons.append('missing_production_position_clock')
    if any(type(s.get(key)) not in (int, float) or s[key] > .5
           for s in samples for key in ('sampleAgeSeconds', 'productionPAgeSeconds')):
        reasons.append('clock_sample_stale')
    if any(type(s.get(key)) not in (int, float) or not math.isfinite(s[key])
           for s in samples for key in ('productionP', 'productionD', 'productionPAgeSeconds', 'productionDAgeSeconds')):
        reasons.append('production_sample_clock_missing')
    result = {'pass': not reasons, 'fixedReasons': reasons}
    if good(first):
        p, d = first['P'], first['D']
        result.update(firstP=p, firstD=d, workingSource=p + d - 10,
            naiveOffsetPlusP=x + p, naiveMinusWorking=x + 10 - d,
            productionDMatchesSnapshot=bool(finite_d) and all(abs(value - d) <= .000001 for value in finite_d))
        if not result['productionDMatchesSnapshot']:
            reasons.append('production_clock_disagrees'); result['pass'] = False
        case = next(c for c in proof['cases'] if c['mode'] == mode and c['x'] == x)
        raw = case['fragment']['independent_ffprobe']
        candidates = [float(Fraction(record[key])) for record in raw for key in ('minimum_pts', 'first_decode_pts')]
        video = float(Fraction(next(record['minimum_pts'] for record in raw if record['role'] == 'video')))
        frame = float(Fraction(1001, 24000) if mode == 'copy' else Fraction(1, 24))
        result.update(rawDemuxerDeltaToEarliest=d - min(candidates), rawVideoDelta=p + d - video,
            referenceVideoPTS=video, frameSeconds=frame)
        if not any(abs(d - value) <= .001 for value in candidates) or not video - frame <= p + d <= video + 2 * frame:
            reasons.append('reference_clock_disagrees'); result['pass'] = False
        if len(samples) >= 2:
            result['progressSeconds'] = samples[-1].get('P', 0) - samples[0].get('P', 0)
            if result['progressSeconds'] < 4:
                reasons.append('no_live_progress'); result['pass'] = False
            if 'production_sample_clock_missing' not in reasons:
                result['productionProgressSeconds'] = samples[-1]['productionP'] - samples[0]['productionP']
                result['maximumProductionPAgeSeconds'] = max(s['productionPAgeSeconds'] for s in samples)
                result['maximumProductionDAgeSeconds'] = max(s['productionDAgeSeconds'] for s in samples)
                if result['productionProgressSeconds'] < 4 or any(abs(s['productionD'] - d) > .000001 for s in samples):
                    reasons.append('production_live_clock_disagrees'); result['pass'] = False
    return result


def run(freeze_path, output, *, stopping_override=None):
    freeze = preflight(freeze_path, output)
    output = Path(output)
    with (output / 'cycle-claim.json').open('x') as handle:
        json.dump({'kind': 'exclusive one-cycle claim before resources', 'freezeSha256': sha(freeze_path)}, handle)
        handle.write('\n')
    result = {'kind': 'actual macOS adapter/PlayerCore/libmpv stream_cb synthetic cycle',
        'plexCalls': 0, 'accountAccess': False, 'emulatorActions': 0, 'freezeSha256': sha(freeze_path), 'cells': []}
    state = {'stop': False, 'retiring': False}
    previous = {}
    def interrupted(_number, _frame):
        if not state['retiring']: state['stop'] = True
    for number in (signal.SIGINT, signal.SIGTERM):
        previous[number] = signal.signal(number, interrupted)
    server = sentinel = None
    sentinel_rows = []
    sentinel_connections = 0
    try:
        if state['stop']: raise HarnessFailure('operator_stop')
        media, fixture_server = load_fixture(freeze['fixtureDir'])
        proof = json.loads((Path(freeze['fixtureDir']) / 'corpus-proof.json').read_text())
        server = server_class(fixture_server.Server)(media.Corpus(), freeze['certificatePath'], freeze['privateKeyPath']).start()
        for mode, x in SCHEDULE:
            row = {'mode': mode, 'x': x, 'native': None, 'cleanup': {}}
            result['cells'].append(row)
            first = len(server.rows)
            url = server.begin(mode, x, 'production_session')
            base = url.rsplit('/', 1)[0]
            text = manifest(server.corpus, mode, x, base)
            canaries = [text, url, base + '/init.mp4', base + '/' + str(x // (10 if mode == 'copy' else 5)) + '.m4s']
            payload = {'load': {'uri': url, 'kind': 'plexSession', 'loadId': 1, 'startPaused': True,
                       'sessionPlaylist': {'text': text, 'offsetMicroseconds': x * 1000000}}, 'canaries': canaries}
            raw = None
            try:
                raw = child(freeze['harness'], freeze['clientCaPath'], payload,
                    stopping_override or (lambda: state['stop']), lambda: server.fatal)
                scan = scan_output(raw['stdout'], raw['stderr'], canaries)
                row['capture'] = {**scan, 'returncode': raw['returncode'], 'forced': raw['forced'],
                    'captureOverflow': raw['captureOverflow'], 'stdinFailed': raw['stdinFailed']}
                if scan['canaryLeak'] or raw['captureOverflow'] or raw['stdinFailed']:
                    raise HarnessFailure('native_output_or_input_guard')
                if len(raw['stdout']) > 128 * 1024: raise HarnessFailure('native_output_cap')
                native = native_shape(json.loads(raw['stdout']))
                row['native'] = native
                row['clockVerdict'] = analyze_native(native, mode, x, proof)
                if raw['returncode'] != 0 or raw['forced'] or not row['clockVerdict']['pass']:
                    raise HarnessFailure('native_case_not_accepted')
            finally:
                row['cleanup']['childReaped'] = bool(raw and raw['childReaped'])
                row['cleanup']['captureThreadsDrained'] = bool(raw and raw['captureThreadsDrained'])
                row['cleanup']['nativeDisposed'] = bool(row['native'] and row['native'].get('disposed') and row['native'].get('nativeDestroyed'))
                row['cleanup']['handlersDrained'] = server.end()
                requests = server.rows[first:]
                row['requests'] = requests
                media_rows = [q for q in requests if q['kind'] == 'media']
                row['counts'] = {'physicalHTTP': len(requests), 'emptyPrestart': sum(q['empty_prestart'] for q in requests),
                    'reservedBytes': sum(q['reserved_bytes'] for q in requests), 'writtenBytes': sum(q['written_bytes'] for q in requests),
                    'variantHTTP': sum(q['kind'] == 'variant' for q in requests)}
                row['firstMediaIndex'] = media_rows[0]['segment_index'] if media_rows else None
            k = x // (10 if mode == 'copy' else 5)
            if row['counts']['variantHTTP'] or row['counts']['emptyPrestart'] or row['firstMediaIndex'] != k:
                raise HarnessFailure('production_manifest_delivery_contract')
            if not all(row['cleanup'].values()) or server.fatal:
                raise HarnessFailure('owned_cleanup_or_server_failure')
            if state['stop']: raise HarnessFailure('operator_stop')
        result['result'] = 'production_matrix_complete'
    except Exception as error:
        result.update(result='production_matrix_stopped', fixedError=str(error) if isinstance(error, HarnessFailure) else 'local_failure')
    finally:
        state['retiring'] = True
        result['cleanup'] = {}
        if sentinel:
            result['cleanup']['sentinelServerStoppedHandlersDrained'] = sentinel.close()
            sentinel_rows = list(sentinel.rows)
            sentinel_connections = sentinel.accepted_connections
        result['sentinelCounts'] = {'HTTP': len(sentinel_rows), 'acceptedConnections': sentinel_connections}
        if server:
            port = server.http.server_port
            result['cleanup']['serverStoppedHandlersDrained'] = server.close()
            sock = socket.socket(); sock.settimeout(.5)
            try: result['cleanup']['ownedListenerAbsent'] = sock.connect_ex(('127.0.0.1', port)) != 0
            finally: sock.close()
            result['counts'] = {'loads': len(result['cells']), 'HTTP': len(server.rows) + len(sentinel_rows),
                'reservedBytes': sum(q['reserved_bytes'] for q in server.rows + sentinel_rows),
                'writtenBytes': sum(q['written_bytes'] for q in server.rows + sentinel_rows)}
            result['serverFixedError'] = server.fatal
        else:
            result['cleanup']['noResourcesStarted'] = True
            result['counts'] = {'loads': 0, 'HTTP': 0}
        result['operatorStopped'] = state['stop']
        with (output / 'result.json').open('x') as handle:
            json.dump(result, handle, indent=2); handle.write('\n')
        for number, handler in previous.items(): signal.signal(number, handler)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--prepare', action='store_true')
    group.add_argument('--authorized-production-session-synthetic', action='store_true')
    parser.add_argument('--runtime', type=Path)
    parser.add_argument('--flutter-root', type=Path)
    parser.add_argument('--fixture-dir', type=Path)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--freeze', type=Path)
    args = parser.parse_args()
    if args.prepare:
        if not all((args.runtime, args.flutter_root, args.fixture_dir)): parser.error('preparation inputs required')
        result = prepare(args.runtime, args.flutter_root, args.fixture_dir, args.output_dir)
        print(json.dumps({'prepared': True, 'harnessSha256': result['harnessSha256'], 'mediaLoads': 0}))
    else:
        if not args.freeze: parser.error('reviewed exact-list freeze required')
        result = run(args.freeze, args.output_dir)
        print(json.dumps({'result': result['result'], 'counts': result['counts'], 'cleanup': result['cleanup'], 'plexCalls': 0}))
        return 0 if result['result'] == 'production_matrix_complete' and all(result['cleanup'].values()) else 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
