#!/usr/bin/env python3
"""Offline tests: local TLS and simulated resource ownership only; never ADB."""
import importlib.util
import json
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import http.client

SPEC = importlib.util.spec_from_file_location(
    "public_clock", Path(__file__).with_name("session-clock-public.py")
)
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)
TLS = Path.home() / ".config/lineup-android/fixture-ca"


def status(case, *, a1=-10500000):
    adjustment = -10500000 if case == "zero" else -11250000
    clock = (
        {
            "state": "unavailable",
            "reason": "discontinuity",
            "diagnosticCode": "clock_unavailable",
        }
        if case == "discontinuity"
        else {"state": "ready", "adjustmentUs": adjustment}
    )
    samples = []
    for i in range(26 if case == "zero" else 17):
        position = i / 4 if i < 17 else 6 + (i - 17) / 4
        samples.append(
            {
                "elapsedMs": i * 250,
                "positionSeconds": position,
                "clockState": clock["state"],
                **(
                    {"adjustmentUs": a1 if case == "zero" and i >= 17 else adjustment}
                    if clock["state"] == "ready"
                    else {}
                ),
            }
        )
    return {
        "version": 1,
        "case": case,
        "nonce": "0123456789abcdef",
        "status": "complete",
        "failure": None,
        "eventCount": 70,
        "playingObserved": True,
        "videoWidth": 1920,
        "videoHeight": 1080,
        "durationSeconds": 40.0,
        "clocks": [{"elapsedMs": 0, "state": "pending"}, {"elapsedMs": 1, **clock}]
        + (
            [
                {"elapsedMs": 4050, "state": "pending"},
                {"elapsedMs": 4100, "state": "ready", "adjustmentUs": a1},
            ]
            if case == "zero"
            else []
        ),
        "samples": samples,
        "seekIssued": case == "zero",
        "seekClock": (
            {
                "a0Us": adjustment,
                "a1Us": a1,
                "deltaUs": a1 - adjustment,
                "pendingObserved": True,
                "readyObserved": True,
                "readyAdjustmentsUs": [adjustment, a1],
                "clockRebasedObserved": False,
            }
            if case == "zero"
            else None
        ),
        "stopConfirmed": True,
        "disposed": True,
        "renderedDisplayClaimed": False,
        "accountOrPlexAccess": False,
    }


class StatusTests(unittest.TestCase):
    def check(self, value, case="zero"):
        return m.validate_status(json.dumps(value).encode(), case, "0123456789abcdef")

    def test_three_complete_contracts(self):
        for case in m.CASES:
            with self.subTest(case=case):
                self.assertEqual(self.check(status(case), case)["status"], "complete")

    def test_stale_nonce_is_ignored(self):
        value = status("zero")
        value["nonce"] = "fedcba9876543210"
        self.assertIsNone(self.check(value))

    def test_stale_old_schema_is_ignored_but_current_schema_stays_closed(self):
        value = status("zero")
        del value["seekClock"]
        value["nonce"] = "fedcba9876543210"
        self.assertIsNone(self.check(value))
        value["nonce"] = "0123456789abcdef"
        with self.assertRaises(m.Failure):
            self.check(value)

    def test_closed_schema_and_numeric_limits(self):
        for mutate in (
            lambda v: v.update(uri="forbidden"),
            lambda v: v.update(accountOrPlexAccess=True),
            lambda v: v.update(eventCount=201),
            lambda v: v["samples"][0].update(positionSeconds=float("nan")),
            lambda v: v["clocks"][1].update(adjustmentUs=True),
            lambda v: v.update(failure="arbitrary diagnostic"),
            lambda v: v.update(disposed=False),
            lambda v: v["samples"][18].update(adjustmentUs=0),
        ):
            value = status("zero")
            mutate(value)
            with self.assertRaises(m.Failure):
                self.check(value)

    def test_discontinuity_remains_non_player_error(self):
        value = status("discontinuity")
        self.assertIsNone(self.check(value, "discontinuity")["failure"])
        value["clocks"].append({"elapsedMs": 2, "state": "ready", "adjustmentUs": 0})
        with self.assertRaises(m.Failure):
            self.check(value, "discontinuity")

    def test_unavailable_vocabulary_excludes_obsolete_scope_and_adjustment(self):
        for reason in ("unsupported_scope", "adjustment_changed"):
            with self.subTest(reason=reason):
                value = status("discontinuity")
                value["clocks"][-1]["reason"] = reason
                with self.assertRaises(m.Failure):
                    self.check(value, "discontinuity")

    def test_seek_accepts_same_and_changed_adjustment(self):
        for a1 in (-10500000, -12000000, 10**12):
            value = status("zero", a1=a1)
            self.assertEqual(self.check(value)["seekClock"]["a1Us"], a1)

    def test_seek_rejects_stale_ready_missing_pending_and_terminal_reversal(self):
        for mutate in (
            lambda v: v["clocks"].pop(2),
            lambda v: v["clocks"].__setitem__(slice(2, None), []),
            lambda v: v["seekClock"].update(pendingObserved=False),
            lambda v: v["seekClock"].update(readyObserved=False),
            lambda v: v["seekClock"].update(deltaUs=1),
            lambda v: v["clocks"].insert(
                2,
                {
                    "elapsedMs": 4001,
                    "state": "unavailable",
                    "reason": "discontinuity",
                    "diagnosticCode": "clock_unavailable",
                },
            ),
        ):
            value = status("zero", a1=-12000000)
            mutate(value)
            with self.assertRaises(m.Failure):
                self.check(value)

    def test_rebased_diagnostic_exact_whitelist_and_transition_count(self):
        value = status("zero", a1=-12000000)
        value["clocks"][-1]["diagnosticCode"] = "clock_rebased"
        value["seekClock"]["clockRebasedObserved"] = True
        self.check(value)
        value["clocks"].append(
            {"elapsedMs": 4101, "state": "ready", "adjustmentUs": -12000000}
        )
        self.check(value)  # A diagnostic toggle is not another ready transition.
        value["clocks"][-1]["diagnosticCode"] = "unexpected"
        with self.assertRaises(m.Failure):
            self.check(value)

    def test_same_adjustment_stale_ready_cannot_replace_pending_barrier(self):
        value = status("zero")
        value["clocks"].pop(2)
        # Even matching numeric A1 and true summary booleans need wire evidence.
        with self.assertRaises(m.Failure):
            self.check(value)

    def test_initial_running_status_may_have_no_seek_clock(self):
        value = status("zero")
        value.update(status="running", seekIssued=False, seekClock=None)
        value["clocks"] = value["clocks"][:2]
        value["samples"] = []
        self.assertIsNone(self.check(value)["seekClock"])

    def test_seek_samples_require_fresh_adjustment_and_ready_time(self):
        for mutate in (
            lambda v: v["samples"][17].update(adjustmentUs=-10500000),
            lambda v: v["samples"][17].update(elapsedMs=4099),
            lambda v: v["seekClock"].update(clockRebasedObserved=True),
        ):
            value = status("zero", a1=-12000000)
            mutate(value)
            with self.assertRaises(m.Failure):
                self.check(value)


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        folder = Path(self.temp.name)
        for name in ("init.mp4", "0.m4s", "1.m4s", "2.m4s", "3.m4s"):
            (folder / name).write_bytes(b"public fixture" * 100)
        self.server = m.PublicServer(
            folder, TLS / "localhost.crt", TLS / "localhost.key", port=0
        )
        self.server.start()
        self.server.begin("zero")
        self.port = self.server.server.server_address[1]

    def tearDown(self):
        receipt = self.server.close()
        self.assertTrue(receipt["serverStopped"])
        self.assertTrue(receipt["handlersDrained"])
        self.temp.cleanup()

    def connection(self):
        context = ssl.create_default_context(cafile=str(TLS / "localhost.crt"))
        return http.client.HTTPSConnection(
            "localhost", self.port, context=context, timeout=2
        )

    def request(self, path, headers=None):
        connection = self.connection()
        connection.request("GET", path, headers=headers or {})
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def wait_rows(self, count):
        until = time.monotonic() + 2
        while len(self.server.rows) < count and time.monotonic() < until:
            time.sleep(0.005)
        self.assertEqual(len(self.server.rows), count)

    def test_playlist_and_single_ranges(self):
        code, headers, body = self.request("/session/clock-zero.m3u8")
        self.assertEqual(code, 200)
        self.assertEqual(headers["Connection"], "close")
        self.assertEqual(body, m.playlist("zero"))
        code, headers, body = self.request("/session/0.m4s", {"Range": "bytes=3-8"})
        self.assertEqual((code, body), (206, b"lic fi"))
        self.assertEqual(headers["Content-Range"], "bytes 3-8/1400")
        self.assertEqual(self.server.end()["firstMediaIndex"], 0)

    def held_request(self, method, path):
        connection = self.connection()
        connection.request(method, path)
        self.wait_rows(1)
        self.assertIsNone(self.server.rows[0]["status"])
        receipt = self.server.end()
        connection.close()
        self.assertTrue(receipt["handlersDrained"])
        return receipt

    def test_unlisted_route_is_held_and_never_echoed(self):
        receipt = self.held_request("GET", "/private?credential=never-record")
        self.assertEqual(receipt["fatal"], "unlisted_reference")
        self.assertNotIn("credential", json.dumps(receipt))

    def test_unknown_method_is_fixed_category(self):
        receipt = self.held_request("POST", "/session/init.mp4")
        self.assertEqual(receipt["fatal"], "unexpected_method")
        self.assertEqual(receipt["rows"][0]["method"], "other")

    def test_reserved_request_cap_holds_final_slot(self):
        self.server.case_limit = 1
        connection = socket.create_connection(("127.0.0.1", self.port))
        until = time.monotonic() + 2
        while not self.server.admissions and time.monotonic() < until:
            time.sleep(0.005)
        receipt = self.server.end()
        connection.close()
        self.assertEqual(receipt["fatal"], "request_budget_guard")
        self.assertEqual(receipt["requests"], 0)
        self.assertEqual(receipt["unparsedConnections"], 1)
        self.assertEqual(receipt["guardedAdmissions"], 1)
        self.assertFalse(receipt["requestCountAcceptanceComplete"])

    def test_concurrent_tls_burst_cannot_cross_parser_cap(self):
        outcomes = []

        def client():
            connection = self.connection()
            connection.timeout = 1
            try:
                connection.request("GET", "/session/0.m4s")
                response = connection.getresponse()
                outcomes.append(response.status)
                response.read()
            except (OSError, TimeoutError, http.client.HTTPException):
                outcomes.append(None)
            finally:
                connection.close()

        threads = [threading.Thread(target=client) for _ in range(28)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(3)
            self.assertFalse(thread.is_alive())
        receipt = self.server.end()
        self.assertLessEqual(receipt["requests"], 19)
        self.assertLessEqual(len(self.server.rows), 59)
        self.assertGreater(receipt["guardedAdmissions"], 0)
        self.assertGreater(receipt["unparsedConnections"], 0)
        self.assertTrue(receipt["handlersDrained"])
        self.assertTrue(all(outcome in (200, None) for outcome in outcomes))
        self.assertEqual(receipt["fatal"], "request_budget_guard")

    def test_total_admission_cap_survives_case_change(self):
        self.server.total_limit = 4
        self.request("/session/0.m4s")
        self.request("/session/1.m4s")
        self.assertIsNone(self.server.end()["fatal"])
        self.server.begin("offset21")
        self.request("/session/2.m4s")
        connection = socket.create_connection(("127.0.0.1", self.port))
        until = time.monotonic() + 2
        while self.server.admissions < 4 and time.monotonic() < until:
            time.sleep(0.005)
        receipt = self.server.end()
        connection.close()
        self.assertEqual(len(self.server.rows), 3)
        self.assertEqual(receipt["requests"], 1)
        self.assertEqual(receipt["guardedAdmissions"], 1)
        self.assertEqual(receipt["fatal"], "request_budget_guard")

    def test_byte_guard_never_sends_body(self):
        with patch.object(m, "MAX_BYTES", 1):
            receipt = self.held_request("GET", "/session/init.mp4")
        self.assertEqual(receipt["fatal"], "response_byte_guard")
        self.assertEqual(receipt["rows"][0]["writtenBytes"], 0)

    def test_multiple_ranges_are_refused(self):
        connection = self.connection()
        connection.request("GET", "/session/0.m4s", headers={"Range": "bytes=0-1,3-4"})
        self.wait_rows(1)
        receipt = self.server.end()
        connection.close()
        self.assertEqual(receipt["fatal"], "invalid_range")
        self.assertIsNone(receipt["rows"][0]["status"])

    def test_idle_tls_handshake_is_owned_and_drained(self):
        raw = socket.create_connection(("127.0.0.1", self.port))
        until = time.monotonic() + 2
        while self.server.accepted == 0 and time.monotonic() < until:
            time.sleep(0.005)
        self.assertEqual(self.server.accepted, 1)
        receipt = self.server.end()
        self.assertTrue(receipt["handlersDrained"])
        self.assertFalse(receipt["requestCountAcceptanceComplete"])
        raw.close()

    def test_consumer_close_does_not_fatalize_public_server(self):
        connection = self.connection()
        connection.request("GET", "/session/0.m4s")
        connection.getresponse()
        connection.close()
        self.wait_rows(1)
        receipt = self.server.end()
        self.assertIsNone(receipt["fatal"])
        self.assertTrue(receipt["requestCountAcceptanceComplete"])
        self.assertLessEqual(receipt["rows"][0]["writtenBytes"], 1400)


class OwnershipTests(unittest.TestCase):
    def boot_device(self, boots, *, identity=m.AVD, platform=b"31"):
        calls, clock = [], [0]
        process = unittest.mock.Mock()
        process.poll.return_value = None
        devices_reads, boot_reads = 0, 0

        def runner(args, **kwargs):
            nonlocal devices_reads, boot_reads
            calls.append(args)
            code, output, error = 0, b"", b""
            if args[-1] == "devices":
                devices_reads += 1
                output = b"List of devices attached\n"
                if devices_reads > 1 and process.poll() is None:
                    output += b"emulator-5560\tdevice\n"
            elif args[-3:] == ["emu", "avd", "name"]:
                output = identity.encode() + b"\nOK\n"
            elif args[-1] == "sys.boot_completed":
                code, output = boots[min(boot_reads, len(boots) - 1)]
                boot_reads += 1
                error = b"fixed simulated boot diagnostic" if code else b""
            elif args[-1] == "ro.build.version.sdk":
                output = platform
            elif args[-1] == "ro.product.cpu.abi":
                output = b"arm64-v8a"
            elif args[-2:] == ["emu", "kill"]:
                process.poll.return_value = 0
            elif "pidof" in args:
                code = 1
            return subprocess.CompletedProcess(args, code, output, error)

        launcher = unittest.mock.Mock(return_value=process)
        device = m.Device(
            "/unused",
            runner=runner,
            launcher=launcher,
            now=lambda: clock[0],
            sleep=lambda delay: clock.__setitem__(0, clock[0] + delay),
        )
        return device, calls, launcher, clock

    def prepare_boot(self, device):
        config = "abi.type = arm64-v8a\nhw.lcd.width = 1920\nhw.lcd.height = 1080\nhw.ramSize = 2048\n"
        with patch.object(Path, "read_text", return_value=config):
            device.prepare("fixture.apk")

    def test_boot_shell_transitions_wait_then_install_once(self):
        device, calls, launcher, clock = self.boot_device(
            [(1, b""), (0, b"0"), (0, b""), (0, b"1")]
        )
        self.prepare_boot(device)
        self.assertEqual(sum(call[-1] == "sys.boot_completed" for call in calls), 4)
        self.assertEqual(sum("install" in call for call in calls), 1)
        launcher.assert_called_once()
        self.assertEqual(clock[0], 1.5)
        self.assertTrue(device.fixture_installed)
        self.assertFalse(device.fixture_launch_attempted)
        receipt = device.close()
        self.assertTrue(receipt["packageStopRequired"])
        self.assertTrue(receipt["packageStopped"])

    def test_boot_nonready_stays_inside_deadline_without_relaunch(self):
        device, calls, launcher, clock = self.boot_device([(1, b"")])
        with self.assertRaisesRegex(m.Failure, "owned_emulator_startup_timeout"):
            self.prepare_boot(device)
        self.assertEqual(clock[0], 120)
        launcher.assert_called_once()
        self.assertFalse(any("install" in call for call in calls))
        receipt = device.close()
        self.assertFalse(receipt["packageStopRequired"])
        self.assertTrue(receipt["packageStopped"])
        self.assertFalse(any("force-stop" in call for call in calls))
        self.assertTrue(receipt["selectedEmulatorAbsent"])
        self.assertTrue(receipt["launcherExited"])

    def test_identity_and_platform_failures_are_not_boot_retries(self):
        for parameters, code in (
            ({"identity": "foreign"}, "selected_emulator_identity_changed"),
            ({"platform": b"32"}, "selected_emulator_platform_changed"),
        ):
            with self.subTest(parameters=parameters):
                device, calls, launcher, clock = self.boot_device(
                    [(0, b"1")], **parameters
                )
                with self.assertRaisesRegex(m.Failure, code):
                    self.prepare_boot(device)
                launcher.assert_called_once()
                self.assertFalse(any("install" in call for call in calls))
                self.assertLessEqual(
                    sum(call[-1] == "sys.boot_completed" for call in calls), 1
                )

    def test_never_installed_cleanup_does_not_require_app_shell(self):
        device, calls, launcher, clock = self.boot_device([(0, b"1")])
        device.process = launcher.return_value
        device.verified_owned = True
        receipt = device.close()
        self.assertFalse(receipt["installAttempted"])
        self.assertFalse(receipt["fixtureLaunchAttempted"])
        self.assertFalse(receipt["packageStopRequired"])
        self.assertTrue(receipt["packageStopped"])
        self.assertFalse(any("shell" in call for call in calls))
        self.assertTrue(receipt["selectedEmulatorAbsent"])
        self.assertTrue(receipt["launcherExited"])

    def test_unexpected_boot_exit_is_fatal_and_uncertain_install_needs_stop(self):
        device, calls, launcher, clock = self.boot_device([(2, b"")])
        with self.assertRaisesRegex(m.Failure, "adb_command_failed"):
            self.prepare_boot(device)
        self.assertFalse(device.install_attempted)
        self.assertEqual(clock[0], 0)
        # An attempted install with uncertain completion is a different state.
        device.install_attempted = True
        receipt = device.close()
        self.assertTrue(receipt["packageStopRequired"])
        self.assertFalse(receipt["fixtureInstalled"])
        self.assertTrue(any("force-stop" in call for call in calls))

    def test_exited_owner_never_mutates_foreign_replacement(self):
        calls = []

        def runner(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(
                args, 0, b"List of devices attached\nemulator-5560\tdevice\n", b""
            )

        process = unittest.mock.Mock()
        process.poll.return_value = 0
        clock = [0]
        device = m.Device(
            "/unused",
            runner=runner,
            now=lambda: clock[0],
            sleep=lambda duration: clock.__setitem__(0, clock[0] + duration),
        )
        device.process = process
        device.verified_owned = True
        device.reverse_owned = True
        with self.assertRaisesRegex(m.Failure, "owned_emulator_not_live"):
            device.stop_case()
        receipt = device.close()
        self.assertTrue(receipt["ownershipLost"])
        self.assertFalse(receipt["packageStopped"])
        self.assertFalse(receipt["reverseRemoved"])
        self.assertFalse(receipt["selectedEmulatorAbsent"])
        self.assertTrue(all(call[-1] == "devices" for call in calls))
        process.terminate.assert_not_called()
        self.assertLessEqual(clock[0], 60)

    def test_failed_emu_kill_terminates_only_owned_launcher(self):
        calls = []
        process = unittest.mock.Mock()
        process.poll.return_value = None
        process.terminate.side_effect = lambda: setattr(process.poll, "return_value", 0)

        def runner(args, **kwargs):
            calls.append(args)
            code = 1 if args[-2:] == ["emu", "kill"] or "pidof" in args else 0
            output = b"List of devices attached\n" if args[-1] == "devices" else b""
            return subprocess.CompletedProcess(args, code, output, b"")

        device = m.Device("/unused", runner=runner)
        device.process = process
        device.verified_owned = True
        device.reverse_owned = True
        receipt = device.close()
        self.assertTrue(receipt["launcherTerminateUsed"])
        self.assertTrue(receipt["launcherExited"])
        self.assertTrue(receipt["selectedEmulatorAbsent"])
        self.assertTrue(receipt["reverseRemoved"])
        process.terminate.assert_called_once_with()
        self.assertEqual(sum(call[-2:] == ["emu", "kill"] for call in calls), 1)

    def test_hung_emu_kill_also_falls_back_to_owned_launcher(self):
        process = unittest.mock.Mock()
        process.poll.return_value = None
        process.terminate.side_effect = lambda: setattr(process.poll, "return_value", 0)

        def runner(args, **kwargs):
            if args[-2:] == ["emu", "kill"]:
                raise subprocess.TimeoutExpired(args, kwargs["timeout"])
            code = 1 if "pidof" in args else 0
            output = b"List of devices attached\n" if args[-1] == "devices" else b""
            return subprocess.CompletedProcess(args, code, output, b"")

        device = m.Device("/unused", runner=runner)
        device.process = process
        device.verified_owned = True
        receipt = device.close()
        self.assertTrue(receipt["launcherTerminateUsed"])
        self.assertTrue(receipt["selectedEmulatorAbsent"])
        process.terminate.assert_called_once_with()

    def test_existing_selected_emulator_is_refused_without_launch_or_kill(self):
        calls = []

        def runner(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(
                args, 0, b"List of devices attached\nemulator-5560\tdevice\n", b""
            )

        launcher = unittest.mock.Mock()
        device = m.Device("/unused", runner=runner, launcher=launcher)
        with self.assertRaisesRegex(m.Failure, "selected_emulator_already_present"):
            device.prepare("unused.apk")
        receipt = device.close()
        self.assertFalse(receipt["selectedEmulatorAbsent"])
        launcher.assert_not_called()
        self.assertTrue(all(call[-1] == "devices" for call in calls))

    def test_membership_is_exact_and_diagnostics_are_fixed(self):
        self.assertTrue(
            m.selected_present(b"List of devices attached\nemulator-5560\toffline\n")
        )
        self.assertFalse(
            m.selected_present(b"List of devices attached\nemulator-55600\tdevice\n")
        )
        self.assertEqual(m.category(b"arbitrary secret"), "other")

    def test_failed_fixture_still_cleans_and_claim_blocks_second_run(self):
        events = []

        class FakeServer:
            def __init__(self, *_):
                self.retiring = threading.Event()
                self.fatal = None

            def start(self):
                events.append("server-start")

            def begin(self, case):
                events.append("case-start")

            def end(self):
                events.append("case-drain")
                return {"fatal": None, "handlersDrained": True, "firstMediaIndex": 0}

            def close(self):
                events.append("server-close")
                return {"serverStopped": True, "handlersDrained": True}

        class FakeDevice:
            operations = []

            def __init__(self, *_):
                pass

            def prepare(self, *_):
                events.append("prepare")

            def observe(self, *_):
                return {"status": "failed", "failure": "readiness_timeout"}

            def stop_case(self):
                events.append("case-stop")

            def close(self):
                events.append("device-close")
                return dict.fromkeys(
                    (
                        "packageStopped",
                        "reverseRemoved",
                        "selectedEmulatorAbsent",
                        "launcherExited",
                    ),
                    True,
                )

        config = dict.fromkeys(
            ("corpus", "certificate", "keyPath", "sdk", "apk"), "unused"
        )
        with tempfile.TemporaryDirectory() as folder:
            evidence = Path(folder)
            (evidence / "freeze.json").write_text("{}")
            result = m.run_cycle(
                evidence, config, device_factory=FakeDevice, server_factory=FakeServer
            )
            self.assertEqual(result["fixedError"], "public_fixture_failed")
            self.assertTrue(result["ownedCleanupConfirmed"])
            self.assertLess(events.index("case-stop"), events.index("case-drain"))
            self.assertLess(events.index("case-drain"), events.index("device-close"))
            count = len(events)
            with self.assertRaises(FileExistsError):
                m.run_cycle(
                    evidence,
                    config,
                    device_factory=FakeDevice,
                    server_factory=FakeServer,
                )
            self.assertEqual(len(events), count)

    def test_later_check_requires_exact_absence_and_original_receipts(self):
        for present in (False, True):
            with self.subTest(present=present), tempfile.TemporaryDirectory() as folder:
                evidence = Path(folder)
                (evidence / "result.json").write_text(
                    json.dumps(
                        {
                            "ownedCleanupConfirmed": True,
                            "deviceCleanup": {"reverseRemoved": True},
                        }
                    )
                )

                def runner(args, **kwargs):
                    if args[-1] == "devices":
                        output = b"List of devices attached\n" + (
                            b"emulator-5560\tdevice\n" if present else b""
                        )
                        return subprocess.CompletedProcess(args, 0, output, b"")
                    return subprocess.CompletedProcess(args, 1, b"", b"")

                receipt = m.later_check(evidence, {"sdk": "/unused"}, runner=runner)
                self.assertIs(receipt["passed"], not present)
                self.assertNotIn("emulator-5560", json.dumps(receipt))


if __name__ == "__main__":
    unittest.main()
