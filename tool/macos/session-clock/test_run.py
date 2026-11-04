"""Offline harness boundary controls; no native media load or TLS server start."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import ssl
import urllib.request
import unittest

SPEC = importlib.util.spec_from_file_location('production_session_clock_runner', Path(__file__).with_name('run.py'))
r = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(r)


def snapshot():
    return {'P': .083416, 'D': 12.002, 'audioPts': .1, 'duration': 1300.,
        'decodedWidth': 96., 'decodedHeight': 54., 'outputWidth': 96., 'outputHeight': 54.,
        'voConfigured': True, 'paused': False, 'seeking': False, 'rebase': True,
        'formatWhitelist': True, 'protocolWhitelist': True, 'lavfSelected': True, 'referenceAccess': True, 'redirectZero': True, 'tlsVerify': True,
        'pictureType': 1, 'elapsedSeconds': 1., 'qualified': True}


def restoration(reason='stop'):
    item = {name + suffix: True for name in ('references', 'redirects', 'demuxer', 'lavf') for suffix in ('Checked', 'Restored')}
    item.update(endFenceSeen=True, endReason=reason, idleChecked=True, idle=True,
        playlistCountChecked=True, playlistCount=0)
    return {'immediate': copy.deepcopy(item), 'final': item, 'complete': True,
        'waitSeconds': .1, 'maximumWaitSeconds': 1, 'timedOut': False}


def output():
    value = {key: False for key in ('canaryLeak', 'globalForceHls', 'workerFailed', 'rejected', 'operatorStopped', 'structuralFailure')}
    value.update({key: True for key in ('pass', 'initialized', 'loadAccepted', 'complete', 'playing',
        'loadMapExact', 'stopAccepted', 'disposed', 'nativeDestroyed', 'runtimeBound',
        'formatWhitelistObserved', 'protocolWhitelistObserved', 'lavfSelectedObserved', 'referenceAccessObserved', 'redirectZeroObserved', 'tlsVerifyObserved', 'stopConfirmed', 'policyChecked', 'policyRestored')})
    value['policyHandshakeWritten'] = False
    value['restoration'] = restoration()
    value.update(restartCount=1, endFileErrorCount=0, structuralFailureCode='none', nestedForbiddenCount=0, curlRedirectRefusedCount=0, redirectCount=0, loadCommands=1, seekCommands=0, elapsedSeconds=8.,
        fileLoaded=snapshot(), firstRestart=snapshot(), productionDemuxerEvents=[{'value': None, 'loadId': 1, 'elapsedSeconds': .1},
        {'value': 12.002, 'loadId': 1, 'elapsedSeconds': .9}], samples=[])
    value['productionPositionEvents'] = [{'value': .083416, 'loadId': 1, 'elapsedSeconds': 1.},
        {'value': 6.083416, 'loadId': 1, 'elapsedSeconds': 7.}]
    for index in range(25):
        item = snapshot(); item.update(P=.083416 + index * .25, sampleIndex=index,
            sampleAgeSeconds=.01, observationSeconds=index * .25, elapsedSeconds=1 + index * .25,
            productionP=.083416 + index * .25, productionD=12.002, productionPAgeSeconds=.01, productionDAgeSeconds=index * .25)
        value['samples'].append(item)
    return value


def proof():
    return {'cases': [{'mode': 'copy', 'x': 10, 'fragment': {'independent_ffprobe': [
        {'role': 'video', 'minimum_pts': '12.085416', 'first_decode_pts': '12.085416'},
        {'role': 'audio', 'minimum_pts': '12.002', 'first_decode_pts': '12.002'}]}}]}


class Boundaries(unittest.TestCase):
    def test_closed_native_shape_accepts_only_numeric_observations(self):
        self.assertIs(r.native_shape(output())['pass'], True)
        for change in ('extra', 'nan', 'string', 'wrong_load'):
            value = output()
            if change == 'extra': value['rawURL'] = 'sensitive'
            if change == 'nan': value['samples'][0]['P'] = float('nan')
            if change == 'string': value['samples'][0]['D'] = 'not a clock'
            if change == 'wrong_load': value['productionDemuxerEvents'][1]['loadId'] = 2
            with self.assertRaisesRegex(r.HarnessFailure, 'native_output_shape'):
                r.native_shape(value)

    def test_actual_messenger_demuxer_clock_is_required_and_matches_snapshot(self):
        good = r.analyze_native(output(), 'copy', 10, proof())
        self.assertTrue(good['pass'])
        self.assertAlmostEqual(good['workingSource'], 2.085416)
        self.assertAlmostEqual(good['naiveMinusWorking'], 7.998)
        bad = output(); bad['productionDemuxerEvents'] = []
        self.assertFalse(r.analyze_native(bad, 'copy', 10, proof())['pass'])
        bad = output(); bad['productionPositionEvents'] = []
        self.assertIn('missing_production_position_clock', r.analyze_native(bad, 'copy', 10, proof())['fixedReasons'])
        bad = output()
        for sample in bad['samples']: sample['productionP'] = .083416
        self.assertIn('production_live_clock_disagrees', r.analyze_native(bad, 'copy', 10, proof())['fixedReasons'])
        bad = output(); bad['productionDemuxerEvents'][1]['value'] += .25
        self.assertIn('production_clock_disagrees', r.analyze_native(bad, 'copy', 10, proof())['fixedReasons'])

    def test_negative_requires_child_io_marker_and_zero_sentinel_contacts(self):
        class Sentinel:
            rows = []
            accepted_connections = 0
        native = output()
        native['pass'] = False
        native['rejected'] = True
        native['workerFailed'] = True
        native['restoration'] = restoration('error')
        native['nestedForbiddenCount'] = 1
        native['endFileErrorCount'] = 1
        native['policyHandshakeWritten'] = True
        self.assertTrue(r.analyze_negative(native, Sentinel, 'nested_hls_negative')['pass'])
        native['curlRedirectRefusedCount'] = 0
        self.assertIn('curl_redirect_blocker_not_exercised', r.analyze_negative(native, Sentinel, 'child_redirect_negative')['fixedReasons'])
        native['curlRedirectRefusedCount'] = 1
        self.assertTrue(r.analyze_negative(native, Sentinel, 'child_redirect_negative')['pass'])
        native['nestedForbiddenCount'] = 0
        self.assertIn('nested_child_io_blocker_not_exercised', r.analyze_negative(native, Sentinel, 'nested_hls_negative')['fixedReasons'])
        native['nestedForbiddenCount'] = 1
        Sentinel.accepted_connections = 1
        self.assertIn('off_origin_sentinel_contacted', r.analyze_negative(native, Sentinel, 'nested_hls_negative')['fixedReasons'])

    def test_structural_failure_or_interruption_cannot_pass_expected_negative(self):
        class Sentinel:
            rows = []
            accepted_connections = 0
        baseline = output()
        baseline['restoration'] = restoration('error')
        baseline.update({'pass': False, 'rejected': True, 'workerFailed': True,
            'nestedForbiddenCount': 1, 'curlRedirectRefusedCount': 1,
            'endFileErrorCount': 1, 'policyHandshakeWritten': True})
        for kind in ('nested_hls_negative', 'child_redirect_negative'):
            self.assertTrue(r.analyze_negative(baseline, Sentinel, kind)['pass'])
            for code in r.STRUCTURAL_CODES - {'none'}:
                mutated = copy.deepcopy(baseline)
                mutated.update(structuralFailure=True, structuralFailureCode=code)
                self.assertIn('native_structural_failure', r.analyze_negative(mutated, Sentinel, kind)['fixedReasons'])
            stopped = copy.deepcopy(baseline); stopped['operatorStopped'] = True
            self.assertIn('operator_stop', r.analyze_negative(stopped, Sentinel, kind)['fixedReasons'])
            missing_error = copy.deepcopy(baseline); missing_error['endFileErrorCount'] = 0
            self.assertIn('expected_end_file_error_missing', r.analyze_negative(missing_error, Sentinel, kind)['fixedReasons'])
        positive = output(); positive['operatorStopped'] = True
        self.assertIn('operator_stop', r.analyze_native(positive, 'copy', 10, proof())['fixedReasons'])
        positive = output(); positive.update(structuralFailure=True, structuralFailureCode='event_queue_overflow')
        self.assertIn('native_structural_failure', r.analyze_native(positive, 'copy', 10, proof())['fixedReasons'])

    def test_structural_failure_enum_is_closed_and_consistent(self):
        for code, flag in (('raw exception detail', True), ('event_queue_overflow', False), ('none', True)):
            bad = output(); bad.update(structuralFailure=flag, structuralFailureCode=code)
            with self.assertRaisesRegex(r.HarnessFailure, 'native_output_shape'):
                r.native_shape(bad)

    def test_restoration_wait_is_correlated_complete_and_within_same_deadline(self):
        good = restoration()
        self.assertTrue(r.restoration_accepted(good, 'stop'))
        self.assertFalse(r.restoration_accepted(good, 'error'))
        for name in ('references', 'redirects', 'demuxer', 'lavf'):
            for suffix in ('Checked', 'Restored'):
                bad = copy.deepcopy(good); bad['final'][name + suffix] = False
                self.assertFalse(r.restoration_accepted(bad, 'stop'))
                # Initial options can still be private; final restored values are required.
                delayed = copy.deepcopy(good); delayed['immediate'][name + suffix] = False
                delayed['waitSeconds'] = .9
                self.assertTrue(r.restoration_accepted(delayed, 'stop'))
        for key, value in (('endFenceSeen', False), ('endReason', 'none'), ('endReason', 'eof'),
                           ('idleChecked', False), ('idle', False), ('playlistCountChecked', False), ('playlistCount', 1)):
            bad = copy.deepcopy(good); bad['final'][key] = value
            self.assertFalse(r.restoration_accepted(bad, 'stop'))
        for elapsed in (1.000001, float('nan')):
            bad = copy.deepcopy(good); bad['waitSeconds'] = elapsed
            self.assertFalse(r.restoration_accepted(bad, 'stop'))
        bad = copy.deepcopy(good); bad.update(complete=False, timedOut=True, waitSeconds=1.01)
        self.assertFalse(r.restoration_accepted(bad, 'stop'))
        native = output(); native['restoration'] = bad
        self.assertIn('stop_restoration_fence', r.analyze_native(native, 'copy', 10, proof())['fixedReasons'])
        for key, value in (('endReason', 'raw text'), ('idle', 'true'), ('playlistCount', 'zero')):
            native = output(); native['restoration']['final'][key] = value
            with self.assertRaisesRegex(r.HarnessFailure, 'native_output_shape'):
                r.native_shape(native)

    def test_third_schedule_is_only_five_positives_under_reduced_caps(self):
        self.assertEqual(r.SCHEDULE, (('copy', 10), ('copy', 21), ('copy', 605), ('encode', 10), ('encode', 605)))
        self.assertEqual(r.MAX_HTTP, 5 * 64)
        self.assertEqual(r.MAX_BYTES, 5 * 32 * 1024 * 1024)

    def test_no_seek_no_global_force_and_exact_load_map_are_obligations(self):
        for key, value in (('seekCommands', 1), ('globalForceHls', True), ('loadMapExact', False), ('loadCommands', 2), ('policyRestored', False), ('stopConfirmed', False)):
            bad = output(); bad[key] = value
            self.assertFalse(r.analyze_native(bad, 'copy', 10, proof())['pass'])

    def test_qualified_video_and_progress_are_required(self):
        for key in ('formatWhitelist', 'protocolWhitelist', 'lavfSelected', 'referenceAccess', 'redirectZero', 'tlsVerify'):
            bad = output(); bad['samples'][3][key] = False
            self.assertFalse(r.analyze_native(bad, 'copy', 10, proof())['pass'])
        for key in ('sampleAgeSeconds', 'productionPAgeSeconds'):
            bad = output(); bad['samples'][3][key] = .501
            self.assertIn('clock_sample_stale', r.analyze_native(bad, 'copy', 10, proof())['fixedReasons'])
        bad = output(); bad['samples'][3]['productionPAgeSeconds'] = None
        self.assertIn('production_sample_clock_missing', r.analyze_native(bad, 'copy', 10, proof())['fixedReasons'])
        bad = output(); bad['samples'][5]['outputWidth'] = None
        self.assertFalse(r.analyze_native(bad, 'copy', 10, proof())['pass'])
        bad = output()
        for item in bad['samples']: item['P'] = .083416
        self.assertIn('no_live_progress', r.analyze_native(bad, 'copy', 10, proof())['fixedReasons'])

    def test_canary_scan_includes_raw_and_json_escaped_output(self):
        canary = 'https://127.0.0.1:1234/private-child.m4s'
        for value in (canary.encode(), canary.replace('/', '\\/').encode(), json.dumps(canary).encode(), b'#EXTM3U\n'):
            self.assertTrue(r.scan_output(value, b'', [canary])['canaryLeak'])
        safe = r.scan_output(json.dumps(output()).encode(), b'[lineup-player] libmpv initialized client-api=123\n', [canary])
        self.assertFalse(safe['canaryLeak'])
        self.assertEqual(safe['redactedStderr'], '[lineup-player] libmpv initialized client-api=123')
        hidden = r.scan_output(b'{}', b'arbitrary diagnostic details\n', [canary])
        self.assertEqual(hidden['redactedStderr'], '[REDACTED_NATIVE_LINE]')

    def test_preflight_rejects_changed_frozen_input_before_any_resource(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); fixture = root / 'fixture'; fixture.mkdir()
            files = {}
            for name in ('harness', 'cert', 'ca', 'key', 'identity', 'list', 'review', 'source'):
                p = root / name; p.write_text(name); files[name] = p
            files['identity'].write_text(json.dumps({'harness': str(files['harness']), 'harnessSha256': r.sha(files['harness']),
                'inputs': {str(files['source']): r.sha(files['source'])}}))
            freeze = {'version': 1, 'inputs': {str(files['source']): r.sha(files['source'])},
                'harness': str(files['harness']), 'harnessSha256': r.sha(files['harness']),
                'certificatePath': str(files['cert']), 'certificateSha256': r.sha(files['cert']),
                'clientCaPath': str(files['ca']), 'clientCaSha256': r.sha(files['ca']),
                'privateKeyPath': str(files['key']), 'identityPath': str(files['identity']),
                'identitySha256': r.sha(files['identity']), 'listPath': str(files['list']),
                'listSha256': r.sha(files['list']), 'reviewPath': str(files['review']),
                'reviewSha256': r.sha(files['review']), 'fixtureDir': str(fixture),
                'schedule': r.SCHEDULE, 'maximumHTTP': r.MAX_HTTP, 'maximumBytes': r.MAX_BYTES}
            p = root / 'freeze.json'; p.write_text(json.dumps(freeze))
            out = root / 'out'
            self.assertEqual(r.preflight(p, out)['version'], 1)
            for field in ('clientCaPath', 'clientCaSha256'):
                missing = dict(freeze); missing.pop(field)
                p.write_text(json.dumps(missing))
                with self.assertRaisesRegex(r.HarnessFailure, 'incomplete_reviewed_freeze'):
                    r.preflight(p, out)
            p.write_text(json.dumps(freeze))
            files['ca'].write_text('changed-client-root-ca')
            with self.assertRaisesRegex(r.HarnessFailure, 'frozen_input_changed'):
                r.preflight(p, out)
            files['ca'].write_text('ca')
            (out / 'cell-1-policy-ready.status').write_bytes(b'policy_ready\n')
            with self.assertRaisesRegex(r.HarnessFailure, 'policy_status_already_exists'):
                r.preflight(p, out)
            (out / 'cell-1-policy-ready.status').unlink()
            (out / 'cycle-claim.json').write_text('{}')
            with self.assertRaisesRegex(r.HarnessFailure, 'cycle_already_claimed'):
                r.preflight(p, out)
            (out / 'cycle-claim.json').unlink()
            files['source'].write_text('modified')
            with self.assertRaisesRegex(r.HarnessFailure, 'frozen_input_changed'):
                r.preflight(p, out)
            self.assertFalse((out / 'cycle-claim.json').exists())

    def test_tls_server_keeps_exact_public_bytes_and_namespace_mapping(self):
        directory = Path('/Users/tristan/Software/LineupDesktop/build/transcoding-t0/mpv-synthetic')
        cert = Path('/Users/tristan/.config/lineup-android/fixture-ca/localhost.crt')
        key = cert.with_suffix('.key')
        if not directory.is_dir() or not cert.is_file() or not key.is_file():
            self.skipTest('prepared public corpus/TLS fixture unavailable')
        _media, server_module = r.load_fixture(directory)
        class PublicBytes:
            data = {'copy': (b'public-init-bytes',)}
            def fragment(self, mode, index): return b'public-media-bytes'
        server = r.server_class(server_module.Server)(PublicBytes(), cert, key).start()
        try:
            url = server.begin('copy', 21, 'test')
            base = url.rsplit('/', 1)[0]
            context = ssl.create_default_context(cafile=cert.with_name('ca.crt'))
            with urllib.request.urlopen(base + '/init.mp4', context=context, timeout=3) as response:
                self.assertEqual(response.read(), b'public-init-bytes')
            request = urllib.request.Request(base + '/2.m4s', headers={'Range': 'bytes=0-'})
            with urllib.request.urlopen(request, context=context, timeout=3) as response:
                self.assertEqual(response.read(), b'public-media-bytes')
            self.assertEqual([row['kind'] for row in server.rows], ['init', 'media'])
            self.assertEqual(server.rows[1]['segment_index'], 2)
            self.assertEqual(sum(row['empty_prestart'] for row in server.rows), 0)
            try:
                urllib.request.urlopen(f'https://127.0.0.1:{server.http.server_port}/cell/1/init.mp4', context=context, timeout=3)
                self.fail('private alias must be refused')
            except urllib.error.HTTPError as error:
                error.close()
            self.assertEqual(server.rows[-1]['kind'], 'unlisted')
            self.assertEqual(server.fatal, 'unlisted_reference')
            self.assertTrue(server.end())
        finally:
            self.assertTrue(server.close())

    def test_existing_authenticated_fixture_migrates_required_session_payload(self):
        tools = r.reference_tools()
        class Server:
            files = {}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = b'#EXTM3U\n#EXT-X-MAP:URI="session-init.mp4"\n#EXTINF:1,\nsession-0.m4s\n#EXT-X-ENDLIST\n'
            (root / 'session.m3u8').write_bytes(original)
            (root / 'session-init.mp4').write_bytes(b'public-init')
            (root / 'session-0.m4s').write_bytes(b'public-media')
            variant, payload, prefix = tools.configure_session_fixture(root, Server)
            self.assertEqual(payload.read_bytes(), original)
            self.assertEqual(variant, prefix + '/index.m3u8')
            self.assertEqual(Server.files[prefix + '/session-init.mp4'][0], b'public-init')
            self.assertEqual(Server.files[prefix + '/session-0.m4s'][0], b'public-media')
            self.assertTrue(prefix.startswith('/video/:/transcode/universal/session/'))

    def test_new_fixture_manifest_flattens_uris_without_changing_timing(self):
        directory = Path('/Users/tristan/Software/LineupDesktop/build/transcoding-t0/mpv-synthetic')
        cert = Path('/Users/tristan/.config/lineup-android/fixture-ca/localhost.crt')
        if not directory.is_dir() or not cert.is_file(): self.skipTest('prepared public fixture unavailable')
        media, server_module = r.load_fixture(directory)
        corpus = media.Corpus()
        server = r.server_class(server_module.Server)(corpus, cert, cert.with_suffix('.key'))
        try:
            base = 'https://127.0.0.1:443/video/:/transcode/universal/session/synthetic/base'
            original = corpus.playlist('copy', 21, base)
            adapted = server.corpus.playlist('copy', 21, base)
            self.assertEqual(adapted, original.replace((base + '/media/').encode(), (base + '/').encode()))
            self.assertNotIn(b'/media/', adapted)
            before = [line for line in original.splitlines() if line.startswith(b'#')]
            after = [line for line in adapted.splitlines() if line.startswith(b'#')]
            self.assertEqual(before, after)
            self.assertEqual(server.corpus.fragment('copy', 2), corpus.fragment('copy', 2))
        finally:
            # The listener was bound, but no server thread or media client ran.
            server.http.server_close()

    def test_oversize_initialization_is_refused_before_listener_creation(self):
        cert = Path('/Users/tristan/.config/lineup-android/fixture-ca/localhost.crt')
        if not cert.is_file(): self.skipTest('prepared TLS fixture unavailable')
        class Corpus:
            data = {'copy': (b'x' * (r.MAX_RESPONSE + 1),)}
        calls = []
        class Base:
            def __init__(self, *_): calls.append('bound')
        with self.assertRaisesRegex(r.HarnessFailure, 'initialization_response_byte_cap'):
            r.server_class(Base)(Corpus(), cert, cert.with_suffix('.key'))
        self.assertEqual(calls, [])

    def test_policy_barrier_is_fresh_owned_exact_and_bounded(self):
        class Clock:
            def __init__(self): self.value = 0.
            def now(self): return self.value
            def sleep(self, _): self.value += .5
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for payload in (None, b'policy_', b'wrong\n', b'policy_ready\n'):
                path = root / 'cell-1-policy-ready.status'
                if path.exists(): path.unlink()
                clock = Clock()
                gate = r.PolicyBarrier(path, root, 1, now=clock.now, sleep=clock.sleep)
                if payload is not None: path.write_bytes(payload)
                passed = gate.wait(lambda: False)
                self.assertEqual(passed, payload == b'policy_ready\n')
                if payload in (None, b'policy_'): self.assertEqual(gate.failure, 'timeout')
                if payload == b'wrong\n': self.assertEqual(gate.failure, 'invalid_marker')
                self.assertLessEqual(clock.value, 5)
            with self.assertRaisesRegex(r.HarnessFailure, 'policy_status_ownership'):
                r.PolicyBarrier(path, root, 1)
            path.unlink()
            path.symlink_to(root / 'not-a-status')
            with self.assertRaisesRegex(r.HarnessFailure, 'policy_status_ownership'):
                r.PolicyBarrier(path, root, 1)
            path.unlink()
            with self.assertRaisesRegex(r.HarnessFailure, 'policy_status_ownership'):
                r.PolicyBarrier(root / 'other.status', root, 1)

    def test_nested_map_prefix_and_media_form_exact_nonempty_hls_probe(self):
        import io
        import threading
        class Base:
            pass
        class Ready:
            def wait(self, _): return True
        class Handler:
            command = 'GET'
            headers = {}
            close_connection = False
            def __init__(self): self.wfile = io.BytesIO(); self.response_headers = {}
            def send_response(self, status): self.status = status
            def send_header(self, key, value): self.response_headers[key] = value
            def end_headers(self): pass
        kind = r.server_class(Base)
        server = kind.__new__(kind)
        server.lock = threading.Lock()
        server.active = {'variant': 'nested_hls_negative', 'id': 1, 'mode': 'copy',
            'offset': 0, 'requests': 0, 'reserved': 0, 'retire_event': threading.Event()}
        server.rows, server.inflight, server.fatal = [], 0, None
        server.policy_barrier = Ready()
        sentinel = 'https://127.0.0.1:443/owned-sentinel.m3u8'
        server.arm_attack(sentinel)
        initialization, media = Handler(), Handler()
        server.serve_attack(initialization, True)
        server.serve_attack(media, False)
        self.assertEqual(initialization.wfile.getvalue(), b'#EXTM3U\n')
        self.assertEqual(int(initialization.response_headers['Content-Length']), 8)
        expected = ('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:1\n'
            '#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:1,\n' + sentinel + '\n#EXT-X-ENDLIST\n').encode()
        assembled = initialization.wfile.getvalue() + media.wfile.getvalue()
        self.assertEqual(assembled, expected)
        self.assertEqual(assembled.count(b'#EXTM3U'), 1)
        self.assertTrue(all(row['reserved_bytes'] > 0 and row['write_complete'] for row in server.rows))
        self.assertIsNone(server.fatal)
        self.assertEqual(server.inflight, 0)

    def test_adversarial_guard_reserves_no_refused_response_bytes(self):
        import threading
        class Base:
            pass
        class Handler:
            command = 'GET'
            headers = {}
            close_connection = False
            def send_response(self, *_): raise AssertionError('guard must not send headers')
        kind = r.server_class(Base)
        for count, reserved in ((15, 0), (0, 1024 * 1024 - 1)):
            server = kind.__new__(kind)
            server.lock = threading.Lock()
            retired = threading.Event(); retired.set()
            server.active = {'variant': 'nested_hls_negative', 'id': 1, 'mode': 'copy',
                'offset': 0, 'requests': count, 'reserved': reserved, 'retire_event': retired}
            server.attack_payload = b'xx'
            server.rows, server.inflight, server.fatal = [], 0, None
            handler = Handler()
            server.serve_attack(handler, False)
            self.assertEqual(server.fatal, 'adversarial_request_guard')
            self.assertEqual(server.rows[0]['reserved_bytes'], 0)
            self.assertEqual(server.rows[0]['written_bytes'], 0)
            self.assertIsNone(server.rows[0]['status'])
            self.assertEqual(server.active['reserved'], reserved)
            self.assertEqual(server.inflight, 0)
            self.assertTrue(handler.close_connection)

    def test_bad_tls_identity_fails_before_listener_constructor(self):
        calls = []
        class Base:
            def __init__(self, *args): calls.append('listener_bound')
        with self.assertRaises((OSError, ssl.SSLError)):
            r.server_class(Base)(None, '/nonexistent/public-cert', '/nonexistent/public-key')
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
