"""Focused server/checker controls; no libmpv or Windows playback claim.

Run with Python 3 and openssl on PATH. Uses ephemeral loopback listeners and
certificates, exercising the same Server and Handler as the 56-case campaign.
"""

import contextlib
import http.client
import importlib.util
import json
import os
import pathlib
import shutil
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
import unittest
from unittest import mock


SOURCE = pathlib.Path(__file__).with_name("authenticated-reference-test.py")
SPEC = importlib.util.spec_from_file_location("authenticated_reference", SOURCE)
fixture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixture)


class ObservedServer(fixture.Server):
    def __init__(self, *args):
        super().__init__(*args)
        self.error_observed = threading.Event()

    def handle_error(self, *args):
        try:
            super().handle_error(*args)
        finally:
            self.error_observed.set()

    def get_request(self):
        try:
            return super().get_request()
        except Exception:
            self.error_observed.set()
            raise


class FaultHandler(fixture.Handler):
    def do_GET(self):
        if self.path == "/runtime-fault":
            raise RuntimeError(fixture.TOKEN + " https://private.invalid/path")
        super().do_GET()

    def end_headers(self):
        super().end_headers()
        if self.path == "/write-fault":
            def fail_write(_):
                raise OSError(5, fixture.TOKEN + " private path")
            self.wfile.write = fail_write


@contextlib.contextmanager
def listener(context=None, handler=fixture.Handler):
    server = ObservedServer(("127.0.0.1", 0), handler)
    server.failed = False
    server.context = context
    server.authenticated = True
    server.requests = []
    server.range_requests = 0
    server.partial_responses = 0
    server.files = {path: (b"fixture media", "application/octet-stream")
                    for path in ("/media.mp4", "/write-fault")}
    thread = threading.Thread(target=server.serve_forever,
                              kwargs={"poll_interval": 0.02}, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join(3)
        if thread.is_alive():
            raise RuntimeError("test_listener_shutdown_timeout")


def request(server, path="/media.mp4", context=None):
    client = (http.client.HTTPSConnection(*server.server_address, context=context, timeout=3)
              if context else http.client.HTTPConnection(*server.server_address, timeout=3))
    try:
        client.request("GET", path, headers={"X-Plex-Token": fixture.TOKEN, "Range": "bytes=0-6"})
        response = client.getresponse()
        return response.status, response.read()
    finally:
        client.close()


class FixtureControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        openssl = shutil.which("openssl")
        if not openssl:
            raise RuntimeError("openssl_required_for_fixture_controls")
        cls.temporary = tempfile.TemporaryDirectory(prefix="lineup-fixture-controls-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = pathlib.Path(cls.temporary.name)
        cls.tls = fixture.certificate(root, openssl)
        cls.trusted = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        cls.trusted.load_verify_locations(cafile=str(root / "ca.pem"))

    def assert_healthy(self, server, context=None):
        self.assertEqual(request(server, context=context), (206, b"fixture"))
        self.assertFalse(server.failed)
        self.assertTrue(server.requests[-1][1])
        self.assertFalse(server.requests[-1][2])
        self.assertEqual(server.partial_responses, 1)

    def assert_sanitized_failure(self, server, phase, category):
        self.assertTrue(server.failed)
        self.assertTrue(any(entry["phase"] == phase and entry["code"] == "unexpected_error" and
                            entry["exception"] == category for entry in server.errors))
        encoded = json.dumps(server.errors)
        for private in (fixture.TOKEN, "private.invalid", "private path"):
            self.assertNotIn(private, encoded)

    def test_real_peer_reset_does_not_poison_healthy_request(self):
        with listener() as server:
            client = socket.create_connection(server.server_address, timeout=3)
            try:
                # Leave HTTP headers incomplete so the handler is reading when
                # the real client resets the connection.
                client.sendall(b"GET /media.mp4 HTTP/1.1\r\n")
                linger = struct.pack("HH" if os.name == "nt" else "ii", 1, 0)
                client.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, linger)
            finally:
                client.close()
            self.assertTrue(server.error_observed.wait(3))
            self.assert_healthy(server)
            self.assertEqual(server.errors[0]["phase"], "handler")
            self.assertEqual(server.errors[0]["code"], "peer_disconnect")

    def test_real_bad_ca_is_rejected_before_http_then_trusted_request_works(self):
        with listener(self.tls) as server:
            with self.assertRaises(ssl.SSLCertVerificationError):
                request(server, context=ssl.create_default_context())
            self.assertTrue(server.error_observed.wait(3))
            self.assertEqual(server.requests, [])
            self.assertFalse(server.failed)
            self.assertEqual(server.errors[0]["phase"], "tls_accept")
            self.assertEqual(server.errors[0]["code"], "certificate_rejected")
            self.assert_healthy(server, self.trusted)

    def test_handler_runtime_fault_is_sanitized_and_sticky(self):
        with listener(handler=FaultHandler) as server:
            with self.assertRaises(http.client.RemoteDisconnected):
                request(server, "/runtime-fault")
            self.assertTrue(server.error_observed.wait(3))
            self.assert_sanitized_failure(server, "handler", "RuntimeError")
            self.assertEqual(request(server), (206, b"fixture"))
            self.assert_sanitized_failure(server, "handler", "RuntimeError")

    def test_unexpected_body_write_oserror_is_not_hidden(self):
        with listener(handler=FaultHandler) as server:
            with self.assertRaises(http.client.IncompleteRead):
                request(server, "/write-fault")
            self.assertTrue(server.error_observed.wait(3))
            self.assert_sanitized_failure(server, "handler", "OSError")

    def test_unexpected_tls_accept_faults_are_sanitized_and_sticky(self):
        class FaultContext:
            def __init__(self, error):
                self.error = error

            def wrap_socket(self, *_args, **_kwargs):
                raise self.error

        for error, category in ((RuntimeError(fixture.TOKEN), "RuntimeError"),
                                (ssl.SSLError(1, fixture.TOKEN), "SSLError")):
            with self.subTest(category=category), listener(FaultContext(error)) as server:
                with socket.create_connection(server.server_address, timeout=3) as client:
                    self.assertEqual(client.recv(1), b"")
                self.assertTrue(server.error_observed.wait(3))
                self.assertEqual(server.accepted_connections, 1)
                self.assertEqual(server.total_accepted_connections, 1)
                self.assertEqual(server.requests, [])
                self.assert_sanitized_failure(server, "tls_accept", category)
                server.context = None
                self.assertEqual(request(server), (206, b"fixture"))
                self.assertTrue(server.failed)

    def test_diagnostics_are_bounded_and_count_repeated_errors(self):
        class FaultContext:
            error = None

            def wrap_socket(self, *_args, **_kwargs):
                raise self.error

        context = FaultContext()
        with listener(context) as server:
            for number in (*range(18), 0):
                server.error_observed.clear()
                context.error = OSError(100 + number, fixture.TOKEN)
                with socket.create_connection(server.server_address, timeout=3) as client:
                    self.assertEqual(client.recv(1), b"")
                self.assertTrue(server.error_observed.wait(3))
            self.assertTrue(server.failed)
            self.assertEqual(len(server.errors), 16)
            self.assertEqual(server.errors_omitted, 2)
            self.assertEqual(server.errors[0]["count"], 2)
            self.assertNotIn(fixture.TOKEN, json.dumps(server.errors))

    def test_finalization_rejects_tls_fault_recorded_after_clean_snapshot(self):
        record_entered = threading.Event()
        release_record = threading.Event()
        shutdown_entered = threading.Event()
        finalization_done = threading.Event()
        finalization_errors = []

        class FaultContext:
            def wrap_socket(self, *_args, **_kwargs):
                raise RuntimeError(fixture.TOKEN)

        class DelayedServer(fixture.Server):
            def record_error(self, error, phase):
                record_entered.set()
                if not release_record.wait(3):
                    raise RuntimeError("test_error_release_timeout")
                super().record_error(error, phase)

            def shutdown(self):
                shutdown_entered.set()
                super().shutdown()

        server = DelayedServer(("127.0.0.1", 0), fixture.Handler)
        server.context = FaultContext()
        thread = threading.Thread(target=server.serve_forever,
                                  kwargs={"poll_interval": 0.02}, daemon=True)
        thread.start()

        def finalize():
            try:
                fixture.finish_servers([server], [thread])
            except Exception as error:
                finalization_errors.append(error)
            finally:
                finalization_done.set()

        finalizer = threading.Thread(target=finalize, daemon=True)
        try:
            with socket.create_connection(server.server_address, timeout=3) as client:
                self.assertEqual(client.recv(1), b"")
            self.assertTrue(record_entered.wait(3))
            with server.lock:
                snapshot = {"server_error": server.failed}
            self.assertFalse(snapshot["server_error"])
            finalizer.start()
            self.assertTrue(shutdown_entered.wait(3))
            self.assertFalse(finalization_done.is_set())
            release_record.set()
            self.assertTrue(finalization_done.wait(3))
            self.assertEqual(len(finalization_errors), 1)
            self.assertIsInstance(finalization_errors[0], RuntimeError)
            self.assertEqual(finalization_errors[0].args, ("fixture_server_error",))
            self.assertFalse(snapshot["server_error"])
            self.assertTrue(server.failed)
        finally:
            # Release even after an assertion fails, so the actual listener
            # shutdown and the test's coordination cannot strand each other.
            release_record.set()
            if finalizer.ident is not None:
                finalizer.join(3)
            with contextlib.suppress(RuntimeError):
                fixture.finish_servers([server], [thread])

    def test_checker_still_rejects_server_faults_and_token_leaks(self):
        # Checker-only outcomes, not a claim of real media playback.
        result = subprocess.CompletedProcess([], 0, b"", b"")
        fields = dict.fromkeys(("initialized", "initial_paused", "play_released",
                                "landing_confirmed", "progressed"), "1")
        fields.update(dict.fromkeys(("timed_out", "ignored_start", "rejected"), "0"))
        audit = {"A_token": True, "B_token": False, "secondary_A_token": False,
                 "token_in_url": False, "server_error": False}
        self.assertTrue(fixture.media_pass(result, fields, audit, True))
        for key in ("B_token", "secondary_A_token", "token_in_url", "server_error"):
            with self.subTest(key=key):
                self.assertFalse(fixture.media_pass(result, fields, {**audit, key: True}, True))
        for stream in ("stdout", "stderr"):
            with self.subTest(stream=stream):
                output = {"stdout": b"", "stderr": b"", stream: fixture.TOKEN.encode()}
                with self.assertRaisesRegex(RuntimeError, "secret_in_child_output"):
                    fixture.read_outcomes(subprocess.CompletedProcess([], 0, **output), False)

    def test_failure_message_only_exposes_fixed_stage_and_known_codes(self):
        with mock.patch.object(fixture, "STAGE", "session_fixture"):
            for code in fixture.FIXED_FAILURE_CODES:
                self.assertEqual(fixture.failure_message(RuntimeError(code)),
                                 "FAIL: fixture, runtime, or bounded-wait prerequisite "
                                 f"(stage=session_fixture) (code={code})")
            for error in (RuntimeError(fixture.TOKEN + " https://private.invalid/path"),
                          OSError("invalid_session_fixture"), RuntimeError(["private path"])):
                self.assertEqual(fixture.failure_message(error),
                                 "FAIL: fixture, runtime, or bounded-wait prerequisite "
                                 "(stage=session_fixture)")


class SessionPayloadControls(unittest.TestCase):
    playlist = (b"#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:1\n"
                b"#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-MAP:URI=\"session-init.mp4\"\n"
                b"#EXTINF:1.000000,\nsession-0.m4s\n"
                b"#EXTINF:1.000000,\nsession-1.m4s\n#EXT-X-ENDLIST\n")

    def baseline(self, positive=False, restoration=False, stripped=False):
        fields = dict.fromkeys(("initialized",), "1")
        fields.update({"timed_out": "0", "session_progressed": str(int(positive)),
                       "session_rejected": str(int(not positive)),
                       "session_override_removed": str(int(stripped)),
                       "restoration_attempted": str(int(restoration)),
                       "restoration_rejected": "1", "restoration_progressed": "0",
                       "session_options_captured": "1", "nested_forbidden_count": "0",
                       "internal_redirect_count": "0", "end_file_error_count": "0",
                       "session_load_started": "0", "session_structural_failure": "0"})
        fields.update({name + "_restored_" + phase: "1"
                       for name in ("references", "redirects", "demuxer", "lavf_options", "session_options")
                       for phase in ("before", "after")})
        audit = {"root_requested": False, "session_token": False, "token_in_url": False,
                 "server_error": False, "off_origin_requests": 0, "off_origin_connections": 0,
                 "unexpected_requests": 0, "nested_init_complete": False, "nested_media_complete": False,
                 "nested_unexpected_children": 0,
                 "child_requests": 0, "init_requested": False, "media_requests": 0,
                 "redirect_child_requests": 0, "restore_requested": restoration,
                 "restore_child_requests": 0}
        if positive:
            audit.update(child_requests=2, init_requested=True, media_requests=1)
        return subprocess.CompletedProcess([], 0, b"", b""), fields, audit

    def test_payloads_keep_complete_playlist_and_move_redirect_to_init_child(self):
        other = "https://127.0.0.1:12345"
        off_origin, redirect = fixture.session_playlists(self.playlist, other)
        self.assertIn((other + fixture.SESSION_PREFIX + "/session-init.mp4").encode(), off_origin)
        self.assertIn((other + fixture.SESSION_PREFIX + "/session-1.m4s").encode(), off_origin)
        self.assertEqual(redirect, self.playlist.replace(b"session-init.mp4", b"session-redirect-init.mp4"))
        for payload in (off_origin, redirect):
            self.assertEqual(payload.count(b"#EXTINF:"), 2)
            self.assertTrue(payload.endswith(b"#EXT-X-ENDLIST\n"))
            self.assertIn(b"#EXT-X-MEDIA-SEQUENCE:0\n", payload)

    def test_session_namespace_is_token_free_and_only_child_redirects(self):
        with listener() as server:
            init = fixture.SESSION_PREFIX + "/session-init.mp4"
            redirected = fixture.SESSION_PREFIX + "/session-redirect-init.mp4"
            variant = fixture.SESSION_PREFIX + "/index.m3u8"
            server.files[init] = (b"init", "application/octet-stream")
            server.files[variant] = (self.playlist, "application/vnd.apple.mpegurl")
            server.redirect_paths = {redirected}
            server.redirect = "https://127.0.0.1:1" + init
            for path, expected in ((init, 200), (variant, 200), (redirected, 302),
                                   ("/media.mp4", 401)):
                with self.subTest(path=path):
                    client = http.client.HTTPConnection(*server.server_address, timeout=3)
                    try:
                        client.request("GET", path) # No synthetic account credential on session I/O.
                        response = client.getresponse()
                        self.assertEqual(response.status, expected)
                        if path == redirected:
                            self.assertEqual(response.getheader("Location"), server.redirect)
                        response.read()
                    finally:
                        client.close()
            self.assertFalse(any(token for _, token, _ in server.requests))
            self.assertFalse(server.failed)

    def test_positive_requires_memory_variant_children_and_all_restoration_guards(self):
        result, fields, audit = self.baseline(positive=True, restoration=True)
        self.assertTrue(fixture.session_pass(result, fields, audit, True, True, "session-complete"))
        mutations = {"root_requested": True, "session_token": True, "token_in_url": True,
                     "server_error": True, "off_origin_requests": 1, "unexpected_requests": 1,
                     "init_requested": False, "media_requests": 0,
                     "restore_requested": False, "restore_child_requests": 1}
        for key, value in mutations.items():
            with self.subTest(key=key):
                self.assertFalse(fixture.session_pass(result, fields, {**audit, key: value},
                                                     True, True, "session-complete"))
        for key in ("session_progressed", "restoration_rejected", "session_options_captured",
                    *(name + "_restored_" + phase
                      for name in ("references", "redirects", "demuxer", "lavf_options", "session_options")
                      for phase in ("before", "after"))):
            with self.subTest(key=key):
                self.assertFalse(fixture.session_pass(result, {**fields, key: "0"}, audit,
                                                     True, True, "session-complete"))
        self.assertFalse(fixture.session_pass(result, {**fields, "session_rejected": "1"}, audit,
                                             True, True, "session-complete"))

    def test_redirect_requires_child_attempt_but_no_follow_or_media(self):
        result, fields, audit = self.baseline()
        audit.update(child_requests=1, redirect_child_requests=1)
        self.assertTrue(fixture.session_pass(result, fields, audit, False, False, "session-redirect"))
        for key, value in {"redirect_child_requests": 0, "off_origin_requests": 1,
                           "root_requested": True, "media_requests": 1, "child_requests": 2}.items():
            with self.subTest(key=key):
                self.assertFalse(fixture.session_pass(result, fields, {**audit, key: value},
                                                     False, False, "session-redirect"))

    def test_nested_hls_requires_specific_blocker_real_bodies_and_no_sentinel_or_redirect(self):
        result, fields, audit = self.baseline()
        fields.update(nested_forbidden_count="2", end_file_error_count="1", session_load_started="1")
        audit.update(child_requests=2, nested_init_complete=True, nested_media_complete=True)
        self.assertTrue(fixture.session_pass(result, fields, audit, False, False, "session-nested-hls"))
        for name, value in {"nested_forbidden_count": "0", "end_file_error_count": "0",
                            "session_load_started": "0", "session_structural_failure": "1",
                            "internal_redirect_count": "1", "session_rejected": "0",
                            "session_progressed": "1", "demuxer_restored_after": "0",
                            "lavf_options_restored_after": "0"}.items():
            with self.subTest(native=name):
                self.assertFalse(fixture.session_pass(result, {**fields, name: value}, audit,
                                                     False, False, "session-nested-hls"))
        for name, value in {"nested_init_complete": False, "nested_media_complete": False,
                            "child_requests": 1, "nested_unexpected_children": 1,
                            "off_origin_requests": 1, "off_origin_connections": 1}.items():
            with self.subTest(audit=name):
                self.assertFalse(fixture.session_pass(result, fields, {**audit, name: value},
                                                     False, False, "session-nested-hls"))

    def test_nested_map_and_media_are_the_nonempty_concatenated_hls_probe(self):
        origin = "https://127.0.0.1:12345"
        playlist, initialization, media = fixture.nested_hls_input(origin)
        self.assertEqual(initialization, b"#EXTM3U\n")
        self.assertEqual(len(initialization), 8)
        self.assertNotEqual(media, b"")
        combined = initialization + media
        self.assertTrue(combined.startswith(b"#EXTM3U\n#EXT-X-TARGETDURATION:"))
        self.assertEqual(combined.count(b"#EXTM3U"), 1)
        self.assertIn((origin + "/nested-sentinel.m4s").encode(), combined)
        self.assertIn(b'#EXT-X-MAP:URI="nested-init.mp4"', playlist)
        self.assertIn(b"\nattack.m3u8\n", playlist)
        self.assertNotIn(origin.encode(), playlist) # Native outer scope validation succeeds.
        with listener() as server:
            server.track_bodies = True
            bodies = {fixture.SESSION_PREFIX + "/nested-init.mp4": initialization,
                      fixture.SESSION_PREFIX + "/attack.m3u8": media}
            server.whole_body_paths = set(bodies)
            for path, body in bodies.items():
                server.files[path] = (body, "application/octet-stream")
                client = http.client.HTTPConnection(*server.server_address, timeout=3)
                try:
                    client.request("GET", path, headers={"Range": "bytes=0-6"})
                    response = client.getresponse()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.read(), body)
                finally:
                    client.close()
            responses = server.wait_for_responses(bodies, timeout=3)
            self.assertEqual([row["bytes"] for row in responses], [8, len(media)])
            self.assertTrue(all(row["complete"] for row in responses))
            self.assertFalse(any(token for _, token, _ in server.requests))

    def test_response_snapshot_waits_for_bookkeeping_after_client_reads_body(self):
        body_written = threading.Event()
        release_bookkeeping = threading.Event()
        wait_entered = threading.Event()
        snapshot_done = threading.Event()
        snapshots = []

        class DelayedHandler(fixture.Handler):
            def end_headers(self):
                super().end_headers()
                flush = self.wfile.flush

                def delayed_flush():
                    flush()
                    body_written.set()
                    if not release_bookkeeping.wait(3):
                        raise RuntimeError("test_bookkeeping_release_timeout")

                self.wfile.flush = delayed_flush

        with listener(handler=DelayedHandler) as server:
            server.track_bodies = True
            paths = {"/media.mp4"}
            condition_wait = server.responses_finished.wait

            def observed_wait(timeout):
                wait_entered.set()
                return condition_wait(timeout)

            def snapshot():
                try:
                    snapshots.extend(server.wait_for_responses(paths, timeout=3))
                finally:
                    snapshot_done.set()

            waiter = threading.Thread(target=snapshot, daemon=True)
            try:
                self.assertEqual(request(server), (206, b"fixture"))
                self.assertTrue(body_written.wait(3))
                # Deadline expiry returns the pending audit, without raising
                # or turning an unfinished attempt into a successful write.
                pending = server.wait_for_responses(paths, timeout=0)
                self.assertEqual(len(pending), 1)
                self.assertFalse(pending[0]["finished"])
                self.assertFalse(pending[0]["complete"])
                with mock.patch.object(server.responses_finished, "wait", side_effect=observed_wait):
                    waiter.start()
                    self.assertTrue(wait_entered.wait(3))
                    self.assertFalse(snapshot_done.is_set())
                    release_bookkeeping.set()
                    self.assertTrue(snapshot_done.wait(3))
                self.assertEqual(len(snapshots), 1)
                self.assertEqual(snapshots[0]["bytes"], 7)
                self.assertTrue(snapshots[0]["finished"])
                self.assertTrue(snapshots[0]["complete"])
                self.assertFalse(pending[0]["finished"]) # The earlier snapshot is detached.
            finally:
                release_bookkeeping.set()
                if waiter.ident is not None:
                    waiter.join(3)
            self.assertFalse(waiter.is_alive())

    def test_finished_short_or_failed_write_still_fails_nested_gate(self):
        class ShortHandler(fixture.Handler):
            def end_headers(self):
                super().end_headers()
                write = self.wfile.write
                self.wfile.write = lambda payload: write(payload[:-1])

        for handler, written in ((ShortHandler, 6), (FaultHandler, 0)):
            with self.subTest(handler=handler.__name__), listener(handler=handler) as server:
                server.track_bodies = True
                with self.assertRaises(http.client.IncompleteRead):
                    request(server, "/write-fault")
                responses = server.wait_for_responses({"/write-fault"}, timeout=3)
                self.assertEqual(len(responses), 1)
                self.assertTrue(responses[0]["finished"])
                self.assertEqual(responses[0]["bytes"], written)
                self.assertFalse(responses[0]["complete"])
                result, fields, audit = self.baseline()
                fields.update(nested_forbidden_count="1", end_file_error_count="1", session_load_started="1")
                audit.update(child_requests=2, nested_init_complete=responses[0]["complete"],
                             nested_media_complete=True)
                self.assertFalse(fixture.session_pass(result, fields, audit, False, False, "session-nested-hls"))

    def test_fixed_native_counts_are_bounded_and_boolean_fields_remain_boolean(self):
        fields = dict.fromkeys(("initialized", "initial_paused", "play_released", "landing_confirmed",
                                "progressed"), "1")
        fields.update(dict.fromkeys(("timed_out", "ignored_start", "rejected", "start_configured",
                                     "delay_exercised"), "0"))
        fields.update(nested_forbidden_count="2", internal_redirect_count="0", end_file_error_count="1")
        def output(values):
            return subprocess.CompletedProcess([], 0, " ".join(k + "=" + v for k,v in values.items()).encode(), b"")
        self.assertEqual(fixture.read_outcomes(output(fields), False)["nested_forbidden_count"], "2")
        for name, value in (("nested_forbidden_count", "4097"), ("nested_forbidden_count", "-1"),
                            ("initialized", "2")):
            with self.subTest(name=name, value=value):
                with self.assertRaisesRegex(RuntimeError, "invalid_harness_outcome"):
                    fixture.read_outcomes(output({**fields, name: value}), False)

    def test_negative_exits_also_require_all_four_policies_restored(self):
        for mode in ("session-off-origin", "session-redirect", "session-control-no-references", "session-nested-hls"):
            result, fields, audit = self.baseline(stripped=mode == "session-control-no-references")
            if mode == "session-redirect":
                audit.update(child_requests=1, redirect_child_requests=1)
            if mode == "session-nested-hls":
                audit.update(child_requests=2, nested_init_complete=True, nested_media_complete=True)
                fields.update(nested_forbidden_count="1", end_file_error_count="1", session_load_started="1")
            self.assertTrue(fixture.session_pass(result, fields, audit, False, False, mode))
            for name in ("references", "redirects", "demuxer", "lavf_options", "session_options"):
                with self.subTest(mode=mode, policy=name):
                    self.assertFalse(fixture.session_pass(result, {**fields, name + "_restored_after": "0"},
                                                         audit, False, False, mode))

    def test_off_origin_is_rejected_before_any_io_and_removed_reference_control_reaches_filter(self):
        result, fields, audit = self.baseline()
        self.assertTrue(fixture.session_pass(result, fields, audit, False, False, "session-off-origin"))
        for key in ("child_requests", "off_origin_requests", "unexpected_requests"):
            self.assertFalse(fixture.session_pass(result, fields, {**audit, key: 1},
                                                 False, False, "session-off-origin"))
        result, fields, audit = self.baseline(stripped=True)
        self.assertTrue(fixture.session_pass(result, fields, audit, False, False,
                                            "session-control-no-references"))
        self.assertFalse(fixture.session_pass(result, {**fields, "session_override_removed": "0"}, audit,
                                             False, False, "session-control-no-references"))
        self.assertFalse(fixture.session_pass(result, fields, {**audit, "child_requests": 1},
                                             False, False, "session-control-no-references"))


if __name__ == "__main__":
    unittest.main()
