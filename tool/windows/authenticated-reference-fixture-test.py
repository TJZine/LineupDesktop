"""Focused server/checker controls; no libmpv or Windows playback claim.

Run with Python 3 and openssl on PATH. Uses ephemeral loopback listeners and
certificates, exercising the same Server and Handler as the 48-case matrix.
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
    # Also support the original fixture for the red comparison.
    server.lock = threading.Lock()
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


if __name__ == "__main__":
    unittest.main()
