#!/usr/bin/env python3
"""Bounded local-only public SessionHlsClock integration driver.

Import, --freeze and --preflight-only perform no ADB or network operations.
The explicit authorized actions are for the integration controller only.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import signal
import socket
import ssl
import subprocess
import threading
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
CASES = ("zero", "offset21", "discontinuity")
SERIAL = "emulator-5560"
AVD = "lineup_tv_media"
PACKAGE = "com.tjzine.lineup"
PORT = 18443
STATUS = "cache/session-hls-clock-public-v1.json"
MAX_STATUS = 64 * 1024
# Matches publicClockEventLimit in fixtures/session_clock_contract.dart.
MAX_EVENTS = 1000
MAX_BODY = 2 * 1024 * 1024
MAX_BYTES = 16 * 1024 * 1024


class Failure(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_new(path, value):
    with Path(path).open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def category(stderr):
    if not stderr:
        return "empty"
    return "daemon_start" if b"daemon" in stderr.lower() else "other"


def selected_present(stdout):
    return any(
        line.split()[:1] == [SERIAL]
        for line in stdout.decode("utf-8", "strict").splitlines()
    )


def playlist(case):
    if case not in CASES:
        raise Failure("case_invalid")
    lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:7",
        "#EXT-X-PLAYLIST-TYPE:VOD",
        "#EXT-X-TARGETDURATION:12",
        "#EXT-X-MEDIA-SEQUENCE:0",
        "#EXT-X-START:TIME-OFFSET=" + ("21" if case == "offset21" else "0"),
        '#EXT-X-MAP:URI="init.mp4"',
    ]
    for index in range(4):
        if case == "discontinuity" and index == 2:
            lines.append("#EXT-X-DISCONTINUITY")
        lines.extend(["#EXTINF:10,", f"{index}.m4s"])
    return ("\n".join(lines + ["#EXT-X-ENDLIST"]) + "\n").encode()


class PublicServer:
    """Finite static TLS namespace; all accepted connections belong to this object."""

    def __init__(self, corpus, cert, key, *, port=PORT, case_limit=20, total_limit=60):
        folder = Path(corpus)
        self.bodies = {"/session/init.mp4": (folder / "init.mp4").read_bytes()}
        self.bodies.update(
            {f"/session/{i}.m4s": (folder / f"{i}.m4s").read_bytes() for i in range(4)}
        )
        if any(len(body) > MAX_BODY for body in self.bodies.values()):
            raise Failure("public_body_bound")
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(cert), str(key))
        self.lock = threading.RLock()
        self.rows = []
        self.active = None
        self.fatal = None
        self.connections = set()
        self.handlers = set()
        self.accepted = 0
        self.admissions = 0
        self.unparsed_connections = 0
        self.guarded_admissions = 0
        self.case_limit = case_limit
        self.total_limit = total_limit
        self.reserved_bytes = 0
        self.retiring = threading.Event()
        self.case_retire = threading.Event()
        self.closed = False
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def handle_one_request(self):
                self.clock_row_recorded = False
                admitted, retirement = owner.admit()
                try:
                    if admitted:
                        super().handle_one_request()
                    else:
                        retirement.wait(65)
                        self.close_connection = True
                finally:
                    owner.finish_admission(self.clock_row_recorded)

            def send_error(self, *_args, **_kwargs):
                # Do not let malformed input produce an unledgered error walk.
                with owner.lock:
                    owner.fatal = owner.fatal or "malformed_request"
                    retirement = owner.case_retire
                retirement.wait(65)
                self.close_connection = True

            def do_GET(self):
                owner.serve(self)

            def __getattr__(self, name):
                if name.startswith("do_"):
                    return lambda: owner.serve(self)
                raise AttributeError(name)

            def log_message(self, *_args):
                pass

        class Server(ThreadingHTTPServer):
            allow_reuse_address = False
            # Queue a connection burst for the admission guard instead of letting
            # the default backlog of 5 drop it before admission (Linux drops SYNs).
            request_queue_size = 64
            daemon_threads = True
            block_on_close = False

            def get_request(self):
                connection, address = super().get_request()
                connection.settimeout(5)
                wrapped = context.wrap_socket(
                    connection, server_side=True, do_handshake_on_connect=False
                )
                with owner.lock:
                    owner.connections.add(wrapped)
                    owner.accepted += 1
                return wrapped, address

            def process_request_thread(self, connection, address):
                thread = threading.current_thread()
                with owner.lock:
                    owner.handlers.add(thread)
                try:
                    super().process_request_thread(connection, address)
                finally:
                    with owner.lock:
                        owner.handlers.discard(thread)

            def shutdown_request(self, connection):
                try:
                    super().shutdown_request(connection)
                finally:
                    with owner.lock:
                        owner.connections.discard(connection)

            def handle_error(self, *_args):
                # TLS cancellation and consumer closure carry no raw diagnostic.
                pass

        try:
            self.server = Server(("127.0.0.1", port), Handler)
        except OSError:
            raise Failure("listener_unavailable") from None
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.started = False

    def start(self):
        self.thread.start()
        self.started = True

    def begin(self, case):
        if case not in CASES:
            raise Failure("case_invalid")
        with self.lock:
            if self.active is not None or self.connections or self.handlers:
                raise Failure("previous_case_not_drained")
            self.case_retire = threading.Event()
            self.active = {
                "case": case,
                "requests": 0,
                "admissions": 0,
                "unparsed_start": self.unparsed_connections,
                "guarded_start": self.guarded_admissions,
                "rows_start": len(self.rows),
            }

    def admit(self):
        """Reserve before request-line/header/TLS reads; cap slots never parse."""
        with self.lock:
            self.admissions += 1
            active = self.active
            if active:
                active["admissions"] += 1
            reason = None
            if active is None or self.retiring.is_set():
                reason = "request_outside_case"
            elif (
                active["admissions"] >= self.case_limit
                or self.admissions >= self.total_limit
            ):
                reason = "request_budget_guard"
            if reason:
                self.fatal = self.fatal or reason
                self.guarded_admissions += 1
            return reason is None, self.case_retire

    def finish_admission(self, parsed):
        if not parsed:
            with self.lock:
                self.unparsed_connections += 1
                self.fatal = self.fatal or "incomplete_http_exchange"

    def serve(self, handler):
        held = False
        with self.lock:
            handler.clock_row_recorded = True
            active = self.active
            row = {
                "method": "GET" if handler.command == "GET" else "other",
                "case": active["case"] if active else None,
                "ordinal": len(self.rows) + 1,
                "kind": "unlisted",
                "mediaIndex": None,
                "status": None,
                "reservedBytes": 0,
                "writtenBytes": 0,
                "writeComplete": False,
                "consumerClosed": False,
                "range": "absent",
            }
            self.rows.append(row)
            if active:
                active["requests"] += 1
            if active is None or self.retiring.is_set():
                self.fatal = self.fatal or "request_outside_case"
                held = True
            elif handler.command != "GET":
                self.fatal = self.fatal or "unexpected_method"
                held = True
            path = handler.path
            data = b""
            if not held:
                if path == f"/session/clock-{active['case']}.m3u8":
                    row["kind"] = "variant"
                    data = playlist(active["case"])
                elif path in self.bodies:
                    row["kind"] = "init" if path.endswith("init.mp4") else "media"
                    row["mediaIndex"] = (
                        int(path.rsplit("/", 1)[1][:-4])
                        if row["kind"] == "media"
                        else None
                    )
                    data = self.bodies[path]
                else:
                    self.fatal = self.fatal or "unlisted_reference"
                    held = True
            status, start, end, length = 200, 0, len(data) - 1, len(data)
            raw_range = handler.headers.get("Range")
            if not held and raw_range is not None:
                match = re.fullmatch(r"bytes=([0-9]{1,9})-([0-9]{0,9})", raw_range)
                if not match:
                    self.fatal = self.fatal or "invalid_range"
                    held = True
                else:
                    start = int(match[1])
                    end = min(
                        int(match[2]) if match[2] else len(data) - 1, len(data) - 1
                    )
                    if not 0 <= start <= end < len(data):
                        self.fatal = self.fatal or "invalid_range"
                        held = True
                    else:
                        data = data[start : end + 1]
                        status = 206
                        row["range"] = "zero" if start == 0 else "nonzero"
            if not held and self.reserved_bytes + len(data) > MAX_BYTES:
                self.fatal = self.fatal or "response_byte_guard"
                held = True
            if not held:
                row["status"] = status
                row["reservedBytes"] = len(data)
                self.reserved_bytes += len(data)
            else:
                row["heldGuard"] = self.fatal
        if held:
            self.case_retire.wait(65)
            handler.close_connection = True
            return
        try:
            handler.send_response(status)
            handler.send_header(
                "Content-Type",
                (
                    "application/vnd.apple.mpegurl"
                    if row["kind"] == "variant"
                    else "video/mp4"
                ),
            )
            handler.send_header("Content-Length", str(len(data)))
            handler.send_header("Connection", "close")
            handler.send_header("Accept-Ranges", "bytes")
            if status == 206:
                handler.send_header("Content-Range", f"bytes {start}-{end}/{length}")
            handler.end_headers()
            for offset in range(0, len(data), 65536):
                block = data[offset : offset + 65536]
                written = handler.wfile.write(block)
                row["writtenBytes"] += len(block) if written is None else written
            handler.wfile.flush()
            row["writeComplete"] = row["writtenBytes"] == len(data)
        except (OSError, TimeoutError):
            row["consumerClosed"] = True
        finally:
            handler.close_connection = True

    def drain(self):
        until = time.monotonic() + 5
        while time.monotonic() < until:
            with self.lock:
                connections, handlers = list(self.connections), list(self.handlers)
            if not connections and not handlers:
                return True
            for connection in connections:
                try:
                    connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                connection.close()
            for thread in handlers:
                thread.join(min(0.05, max(0, until - time.monotonic())))
            time.sleep(0.005)
        return False

    def end(self):
        self.case_retire.set()
        clean = self.drain()
        with self.lock:
            active, self.active = self.active, None
            rows = list(self.rows[active["rows_start"] :]) if active else []
        return {
            "handlersDrained": clean,
            "requests": len(rows),
            "admissions": active["admissions"] if active else 0,
            "unparsedConnections": (
                self.unparsed_connections - active["unparsed_start"] if active else 0
            ),
            "guardedAdmissions": (
                self.guarded_admissions - active["guarded_start"] if active else 0
            ),
            "requestCountAcceptanceComplete": (
                active is not None
                and self.unparsed_connections == active["unparsed_start"]
                and self.guarded_admissions == active["guarded_start"]
                and self.fatal is None
            ),
            "firstMediaIndex": next(
                (r["mediaIndex"] for r in rows if r["kind"] == "media"), None
            ),
            "rows": rows,
            "fatal": self.fatal,
        }

    def close(self):
        if self.closed:
            return {
                "serverStopped": True,
                "handlersDrained": not self.handlers and not self.connections,
            }
        self.closed = True
        self.retiring.set()
        self.case_retire.set()
        if self.started:
            self.server.shutdown()
        self.server.server_close()
        if self.started:
            self.thread.join(5)
        clean = self.drain()
        return {
            "serverStopped": not self.started or not self.thread.is_alive(),
            "handlersDrained": clean,
            "acceptedConnections": self.accepted,
            "connectionAdmissions": self.admissions,
            "unparsedConnections": self.unparsed_connections,
            "guardedAdmissions": self.guarded_admissions,
            "requestCountAcceptanceComplete": (
                self.unparsed_connections == 0
                and self.guarded_admissions == 0
                and self.fatal is None
            ),
            "receivedHttpRequests": len(self.rows),
            "reservedBytes": self.reserved_bytes,
            "writtenBytesAreCompletedWritesOnly": True,
        }


def validate_status(data, case, nonce):
    if len(data) > MAX_STATUS:
        raise Failure("status_bound")
    try:
        value = json.loads(data)
    except (ValueError, UnicodeError):
        raise Failure("status_schema") from None
    if not isinstance(value, dict):
        raise Failure("status_schema")
    if (
        value.get("version") != 1
        or value.get("case") != case
        or value.get("nonce") != nonce
    ):
        return None  # Another launch may have left an older status schema.
    keys = {
        "version",
        "case",
        "nonce",
        "status",
        "failure",
        "eventCount",
        "playingObserved",
        "videoWidth",
        "videoHeight",
        "durationSeconds",
        "clocks",
        "samples",
        "seekIssued",
        "seekClock",
        "stopConfirmed",
        "disposed",
        "renderedDisplayClaimed",
        "accountOrPlexAccess",
    }
    if set(value) != keys:
        raise Failure("status_schema")
    if (
        value["status"] not in ("running", "complete", "failed")
        or not isinstance(value["clocks"], list)
        or not isinstance(value["samples"], list)
    ):
        raise Failure("status_schema")
    if (
        type(value["eventCount"]) is not int
        or not 0 <= value["eventCount"] <= MAX_EVENTS
        or len(value["samples"]) > 40
        or len(value["clocks"]) > 20
    ):
        raise Failure("status_schema")
    if (
        value["renderedDisplayClaimed"] is not False
        or value["accountOrPlexAccess"] is not False
    ):
        raise Failure("status_schema")
    for key in ("playingObserved", "seekIssued", "stopConfirmed", "disposed"):
        if type(value[key]) is not bool:
            raise Failure("status_schema")
    duration = value["durationSeconds"]
    if duration is not None and (
        type(duration) not in (int, float) or not 0 <= duration <= 86400
    ):
        raise Failure("status_schema")
    failures = {
        "clock_schema",
        "event_bound",
        "event_schema",
        "stop_failed",
        "player_failed",
        "terminal_clock_reversed",
        "ready_adjustment_changed",
        "numeric_property",
        "sample_unqualified",
        "status_bound",
        "readiness_timeout",
        "no_progress",
        "seek_no_progress",
        "seek_clock_unqualified",
        "native_command_failed",
        "stop_unconfirmed",
        "dispose_unconfirmed",
    }
    if value["failure"] is not None and value["failure"] not in failures:
        raise Failure("status_schema")
    seek = value["seekClock"]
    if seek is not None:
        if (
            case != "zero"
            or not isinstance(seek, dict)
            or set(seek)
            != {
                "a0Us",
                "a1Us",
                "deltaUs",
                "pendingObserved",
                "readyObserved",
                "readyAdjustmentsUs",
                "clockRebasedObserved",
            }
            or type(seek["a0Us"]) is not int
            or seek["a0Us"] != -10500000
            or any(
                seek[key] is not None
                and (
                    type(seek[key]) is not int
                    or abs(seek[key]) > (2 * 10**12 if key == "deltaUs" else 10**12)
                )
                for key in ("a1Us", "deltaUs")
            )
            or any(
                type(seek[key]) is not bool
                for key in ("pendingObserved", "readyObserved", "clockRebasedObserved")
            )
            or not isinstance(seek["readyAdjustmentsUs"], list)
            or len(seek["readyAdjustmentsUs"]) > 20
            or any(
                type(adjustment) is not int or abs(adjustment) > 10**12
                for adjustment in seek["readyAdjustmentsUs"]
            )
        ):
            raise Failure("status_schema")
    previous_clock = None
    ready_adjustments = []
    ready_times = []
    rebase_pending_times = []
    rebased_observed = False
    last_elapsed = -1
    for clock in value["clocks"]:
        if (
            not isinstance(clock, dict)
            or type(clock.get("elapsedMs")) is not int
            or clock["elapsedMs"] < max(0, last_elapsed)
        ):
            raise Failure("clock_schema")
        state = clock.get("state")
        expected = (
            {"elapsedMs", "state"}
            if state == "pending"
            else (
                {"elapsedMs", "state", "adjustmentUs"}
                if state == "ready"
                else {"elapsedMs", "state", "reason", "diagnosticCode"}
            )
        )
        if set(clock) != expected and not (
            state == "ready"
            and set(clock) == expected | {"diagnosticCode"}
            and clock["diagnosticCode"] == "clock_rebased"
        ):
            raise Failure("clock_schema")
        if state == "ready" and (
            type(clock["adjustmentUs"]) is not int
            or abs(clock["adjustmentUs"]) > 10**12
        ):
            raise Failure("clock_schema")
        if state == "unavailable" and (
            clock["reason"]
            not in (
                "discontinuity",
                "period_mismatch",
                "ambiguous_adjuster",
                "invalid_timestamp",
            )
            or clock["diagnosticCode"] != "clock_unavailable"
        ):
            raise Failure("clock_schema")
        if state not in ("pending", "ready", "unavailable"):
            raise Failure("clock_schema")
        current_clock = {key: item for key, item in clock.items() if key != "elapsedMs"}
        if previous_clock is not None:
            if (
                previous_clock["state"] == "unavailable"
                and current_clock != previous_clock
            ):
                raise Failure("public_clock_mismatch")
            if (
                previous_clock["state"] == "ready"
                and state == "ready"
                and clock["adjustmentUs"] != previous_clock["adjustmentUs"]
            ):
                raise Failure("public_clock_mismatch")
            if (
                previous_clock["state"] == "ready"
                and state == "pending"
                and case != "zero"
            ):
                raise Failure("public_clock_mismatch")
            if previous_clock["state"] == "ready" and state == "pending":
                rebase_pending_times.append(clock["elapsedMs"])
        if state == "ready":
            if previous_clock is None or previous_clock["state"] != "ready":
                ready_adjustments.append(clock["adjustmentUs"])
                ready_times.append(clock["elapsedMs"])
            rebased_observed |= clock.get("diagnosticCode") == "clock_rebased"
        previous_clock = current_clock
        last_elapsed = clock["elapsedMs"]
    for sample in value["samples"]:
        if not isinstance(sample, dict) or set(sample) not in (
            {"elapsedMs", "positionSeconds", "clockState"},
            {"elapsedMs", "positionSeconds", "clockState", "adjustmentUs"},
        ):
            raise Failure("status_schema")
        if (
            type(sample["elapsedMs"]) is not int
            or sample["elapsedMs"] < 0
            or type(sample["positionSeconds"]) not in (int, float)
            or not 0 <= sample["positionSeconds"] <= 86400
        ):
            raise Failure("status_schema")
        if sample["clockState"] not in ("ready", "unavailable"):
            raise Failure("status_schema")
        if sample["clockState"] == "ready" and (
            type(sample.get("adjustmentUs")) is not int
            or abs(sample["adjustmentUs"]) > 10**12
        ):
            raise Failure("status_schema")
    if value["status"] == "complete":
        if (
            value["failure"] is not None
            or not all(
                value[k] is True
                for k in ("playingObserved", "stopConfirmed", "disposed")
            )
            or value["videoWidth"] != 1920
            or value["videoHeight"] != 1080
        ):
            raise Failure("public_case_failed")
        expected_a = -10500000 if case == "zero" else -11250000
        if case == "zero":
            if (
                seek is None
                or type(seek["a1Us"]) is not int
                or type(seek["deltaUs"]) is not int
                or seek["deltaUs"] != seek["a1Us"] - seek["a0Us"]
                or seek["pendingObserved"] is not True
                or seek["readyObserved"] is not True
                or seek["readyAdjustmentsUs"] != [seek["a0Us"], seek["a1Us"]]
                or ready_adjustments != seek["readyAdjustmentsUs"]
                or seek["clockRebasedObserved"] is not rebased_observed
                or len(rebase_pending_times) != 1
                or previous_clock["state"] != "ready"
            ):
                raise Failure("public_seek_clock_mismatch")
        elif seek is not None:
            raise Failure("status_schema")
        if case == "discontinuity":
            if not any(
                c.get("state") == "unavailable" and c.get("reason") == "discontinuity"
                for c in value["clocks"]
            ) or any(c.get("state") == "ready" for c in value["clocks"]):
                raise Failure("public_clock_mismatch")
        elif not any(
            c.get("state") == "ready" and c.get("adjustmentUs") == expected_a
            for c in value["clocks"]
        ) or any(c.get("state") == "unavailable" for c in value["clocks"]):
            raise Failure("public_clock_mismatch")
        if (
            len(value["samples"]) < 17
            or value["samples"][16]["positionSeconds"]
            - value["samples"][0]["positionSeconds"]
            < 2
        ):
            raise Failure("public_progress_failed")
        expected_samples = 26 if case == "zero" else 17
        if (
            len(value["samples"]) != expected_samples
            or not 39.5 <= (value["durationSeconds"] or 0) <= 40.5
        ):
            raise Failure("public_sample_count_or_duration")
        expected_state = "unavailable" if case == "discontinuity" else "ready"
        if any(
            sample["clockState"] != expected_state
            or (
                expected_state == "ready"
                and sample.get("adjustmentUs")
                != (seek["a1Us"] if case == "zero" and index >= 17 else expected_a)
            )
            for index, sample in enumerate(value["samples"])
        ):
            raise Failure("public_clock_mismatch")
        if case == "zero" and (
            len(ready_times) != 2
            or value["samples"][17]["elapsedMs"] < ready_times[1]
            or value["samples"][16]["elapsedMs"] > rebase_pending_times[0]
            or value["samples"][17]["positionSeconds"] < 5.5
            or value["samples"][-1]["positionSeconds"]
            - value["samples"][17]["positionSeconds"]
            < 1
        ):
            raise Failure("public_seek_mismatch")
        if value["seekIssued"] is not (case == "zero"):
            raise Failure("public_seek_mismatch")
    return value


class Device:
    def __init__(
        self,
        sdk,
        *,
        runner=subprocess.run,
        launcher=subprocess.Popen,
        now=time.monotonic,
        sleep=time.sleep,
    ):
        self.sdk = Path(sdk)
        self.adb = str(self.sdk / "platform-tools/adb")
        self.runner, self.launcher, self.now, self.sleep = runner, launcher, now, sleep
        self.process = None
        self.verified_owned = False
        self.ownership_lost = False
        self.reverse_owned = False
        self.install_attempted = False
        self.fixture_installed = False
        self.fixture_launch_attempted = False
        self.fixture_launched = False
        self.operations = []
        self.cleanup_deadline = None

    def command(self, args, *, timeout=5, allowed=(0,), limit=MAX_STATUS):
        if self.cleanup_deadline is not None:
            remaining = self.cleanup_deadline - self.now()
            if remaining <= 0:
                raise Failure("owned_cleanup_deadline")
            timeout = min(timeout, remaining)
        try:
            result = self.runner(
                [self.adb, *args], capture_output=True, timeout=timeout, check=False
            )
        except Exception:
            raise Failure("adb_command_failed") from None
        self.operations.append(
            {
                "operation": (
                    args[2] if args[:1] == ["-s"] else args[0] if args else "empty"
                ),
                "returncode": result.returncode,
                "stderrCategory": category(result.stderr),
            }
        )
        if (
            result.returncode not in allowed
            or len(result.stdout) > limit
            or len(result.stderr) > 8192
        ):
            raise Failure("adb_command_failed")
        return result

    def target(self, *args, identity_check=False, **kwargs):
        # A matching serial is not ownership: the launcher must still be alive.
        if self.process is None or self.process.poll() is not None:
            self.ownership_lost = self.process is not None
            raise Failure("owned_emulator_not_live")
        if not self.verified_owned and not (
            identity_check and args == ("emu", "avd", "name")
        ):
            raise Failure("owned_emulator_not_verified")
        return self.command(["-s", SERIAL, *args], **kwargs)

    def present(self, *, timeout=5):
        return selected_present(self.command(["devices"], timeout=timeout).stdout)

    def prepare(self, apk):
        if self.present():
            raise Failure("selected_emulator_already_present")
        config = Path.home() / ".android/avd" / f"{AVD}.avd/config.ini"
        values = dict(
            tuple(part.strip() for part in line.split("=", 1))
            for line in config.read_text().splitlines()
            if "=" in line
        )
        if (
            values.get("abi.type") != "arm64-v8a"
            or values.get("hw.lcd.width") != "1920"
            or values.get("hw.lcd.height") != "1080"
            or values.get("hw.ramSize") not in ("2048", "2G")
        ):
            raise Failure("assigned_avd_configuration_changed")
        args = [
            str(self.sdk / "emulator/emulator"),
            "-avd",
            AVD,
            "-port",
            "5560",
            "-no-window",
            "-no-snapshot-load",
            "-no-snapshot-save",
            "-no-audio",
            "-gpu",
            "swiftshader_indirect",
        ]
        self.process = self.launcher(
            args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        until = self.now() + 120

        def boot_timeout():
            remaining = until - self.now()
            if remaining <= 0:
                raise Failure("owned_emulator_startup_timeout")
            return min(5, remaining)

        while self.now() < until:
            if self.process.poll() is not None:
                raise Failure("owned_emulator_exited")
            if self.present(timeout=boot_timeout()):
                name = (
                    self.target(
                        "emu",
                        "avd",
                        "name",
                        identity_check=True,
                        timeout=boot_timeout(),
                    )
                    .stdout.decode()
                    .splitlines()
                )
                if not name or name[0] != AVD:
                    raise Failure("selected_emulator_identity_changed")
                self.verified_owned = True
                # The selected transport can appear before adbd exposes shell.
                # Only this boot readiness read admits rc1 as not ready.
                boot = self.target(
                    "shell",
                    "getprop",
                    "sys.boot_completed",
                    allowed=(0, 1),
                    timeout=boot_timeout(),
                )
                if boot.returncode == 0 and boot.stdout.strip() == b"1":
                    break
            self.sleep(min(0.5, max(0, until - self.now())))
        else:
            raise Failure("owned_emulator_startup_timeout")
        if (
            self.target("shell", "getprop", "ro.build.version.sdk").stdout.strip()
            != b"31"
            or self.target("shell", "getprop", "ro.product.cpu.abi").stdout.strip()
            != b"arm64-v8a"
        ):
            raise Failure("selected_emulator_platform_changed")
        existing = self.target("reverse", "--list").stdout.decode().splitlines()
        if any("tcp:18443" in line.split() for line in existing):
            raise Failure("reverse_already_present")
        self.install_attempted = True
        installed = self.target(
            "install", "-r", "--no-streaming", str(apk), timeout=60, allowed=(0, 1)
        )
        if installed.returncode:
            raise Failure(
                "fixture_install_signature_conflict"
                if b"INSTALL_FAILED_UPDATE_INCOMPATIBLE"
                in installed.stdout + installed.stderr
                else "fixture_install_failed"
            )
        self.fixture_installed = True
        self.target("reverse", "tcp:18443", "tcp:18443")
        self.reverse_owned = True

    def stop_case(self):
        self.target("shell", "am", "force-stop", PACKAGE)
        if self.target("shell", "pidof", PACKAGE, allowed=(0, 1)).stdout.strip():
            raise Failure("public_process_stop_unconfirmed")

    def observe(self, case, nonce, fatal):
        self.stop_case()
        self.fixture_launch_attempted = True
        self.target(
            "shell",
            "am",
            "start",
            "-n",
            PACKAGE + "/.MainActivity",
            "--esal",
            "dart_entrypoint_args",
            f"'--case={case},--nonce={nonce}'",
        )
        self.fixture_launched = True
        until = self.now() + 60
        startup = self.now() + 30
        started = False
        while self.now() < until:
            if fatal():
                raise Failure("public_http_guard")
            read = self.target(
                "shell", "run-as", PACKAGE, "cat", STATUS, allowed=(0, 1)
            )
            if read.returncode == 0:
                value = validate_status(read.stdout, case, nonce)
                if value is not None:
                    started = True
                    if value["status"] in ("complete", "failed"):
                        return value
            if not started and self.now() > startup:
                raise Failure("public_status_startup_timeout")
            self.sleep(0.1)
        raise Failure("public_status_timeout")

    def close(self):
        until = self.now() + 60
        self.cleanup_deadline = until
        live = self.process is not None and self.process.poll() is None
        if self.process is not None and not live:
            self.ownership_lost = True
        package_stop_required = self.install_attempted or self.fixture_launch_attempted
        result = {
            "packageStopped": not self.ownership_lost,
            "reverseRemoved": not self.reverse_owned,
            "selectedEmulatorAbsent": False,
            "launcherExited": self.process is None,
            "ownershipLost": self.ownership_lost,
            "launcherTerminateUsed": False,
            "installAttempted": self.install_attempted,
            "fixtureInstalled": self.fixture_installed,
            "fixtureLaunchAttempted": self.fixture_launch_attempted,
            "fixtureLaunched": self.fixture_launched,
            "packageStopRequired": package_stop_required,
        }
        kill_failed = False
        if self.verified_owned and live:
            if package_stop_required:
                try:
                    self.stop_case()
                except Failure:
                    result["packageStopped"] = False
            if self.reverse_owned:
                try:
                    self.target("reverse", "--remove", "tcp:18443")
                    result["reverseRemoved"] = True
                    self.reverse_owned = False
                except Failure:
                    pass
            try:
                self.target("emu", "kill")
            except Failure:
                kill_failed = True
        if self.process is None:
            try:
                result["selectedEmulatorAbsent"] = not self.present()
            except Failure:
                pass
        if self.process is not None:
            if self.process.poll() is None and (not self.verified_owned or kill_failed):
                self.process.terminate()
                result["launcherTerminateUsed"] = True
            fallback_at = min(until, self.now() + 10)
            while self.now() < until:
                if self.process.poll() is not None:
                    try:
                        if not self.present():
                            result["selectedEmulatorAbsent"] = True
                            break
                    except Failure:
                        break
                if (
                    self.process.poll() is None
                    and self.now() >= fallback_at
                    and not result["launcherTerminateUsed"]
                ):
                    self.process.terminate()
                    result["launcherTerminateUsed"] = True
                self.sleep(min(0.25, max(0, until - self.now())))
            result["launcherExited"] = self.process.poll() is not None
            if not result["selectedEmulatorAbsent"] and self.now() < until:
                try:
                    result["selectedEmulatorAbsent"] = not self.present()
                except Failure:
                    pass
        result["ownershipLost"] = self.ownership_lost
        if self.ownership_lost:
            result["packageStopped"] = False
        self.cleanup_deadline = None
        return result


def freeze(args):
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    corpus = args.corpus.resolve()
    dependencies = [
        Path(__file__).resolve(),
        Path(__file__).with_name("test-session-clock-public.py").resolve(),
        ROOT / "tool/android/fixtures/session_clock_contract.dart",
        args.apk.resolve(),
        args.cert.resolve(),
        args.manifest.resolve(),
        ROOT / "android/app/src/debug/res/raw/fixture_ca.crt",
        ROOT / "android/app/src/debug/res/xml/network_security_config.xml",
        ROOT / "android/app/src/debug/AndroidManifest.xml",
        ROOT / "android/app/src/main/AndroidManifest.xml",
        ROOT / "android/app/build.gradle.kts",
    ]
    dependencies.extend(sorted((ROOT / "android/app/src/main/kotlin").rglob("*.kt")))
    dependencies.extend(
        corpus / name for name in ("init.mp4", "0.m4s", "1.m4s", "2.m4s", "3.m4s")
    )
    # Normalize explicitly; never include private-key contents or credentials.
    dependencies = list(dict.fromkeys(dependencies))
    if not args.key.is_file():
        raise Failure("fixture_tls_key_missing")
    with zipfile.ZipFile(args.apk) as archive:
        if not any(name.startswith("lib/arm64-v8a/") for name in archive.namelist()):
            raise Failure("fixture_apk_not_arm64")
    value = {
        "version": 1,
        "apk": str(args.apk.resolve()),
        "certificate": str(args.cert.resolve()),
        "keyPath": str(args.key.resolve()),
        "corpus": str(corpus),
        "sdk": str(args.sdk.resolve()),
        "dependencies": {str(p): digest(p) for p in dependencies},
        "cases": list(CASES),
    }
    write_new(evidence / "freeze.json", value)
    return value


def preflight(evidence):
    value = json.loads((evidence / "freeze.json").read_text())
    if value["version"] != 1 or value["cases"] != list(CASES):
        raise Failure("freeze_schema")
    if any(
        digest(path) != expected for path, expected in value["dependencies"].items()
    ):
        raise Failure("frozen_input_changed")
    if not Path(value["keyPath"]).is_file():
        raise Failure("fixture_tls_key_missing")
    return value


def run_cycle(evidence, config, *, device_factory=Device, server_factory=PublicServer):
    write_new(
        evidence / "cycle-claim.json",
        {
            "kind": "one public-only cycle",
            "freezeSha256": digest(evidence / "freeze.json"),
        },
    )
    result = {
        "kind": "native session clock public integration",
        "result": "running",
        "cases": [],
        "PlexRequests": 0,
        "accountAccess": False,
        "loads": 0,
    }
    server = device = None
    interrupted = False
    previous = {}

    def once(_number, _frame):
        nonlocal interrupted
        interrupted = True
        for number in (signal.SIGINT, signal.SIGTERM):
            signal.signal(number, signal.SIG_IGN)
        raise KeyboardInterrupt()

    for number in (signal.SIGINT, signal.SIGTERM):
        previous[number] = signal.signal(number, once)
    try:
        server = server_factory(
            config["corpus"], config["certificate"], config["keyPath"]
        )
        server.start()
        device = device_factory(config["sdk"])
        device.prepare(config["apk"])
        for case in CASES:
            record = {"case": case, "result": "running"}
            result["cases"].append(record)
            nonce = secrets.token_hex(8)
            server.begin(case)
            result["loads"] += 1
            try:
                record["status"] = device.observe(case, nonce, lambda: server.fatal)
                if record["status"]["status"] != "complete":
                    raise Failure("public_fixture_failed")
                record["result"] = "passed"
            finally:
                try:
                    device.stop_case()
                finally:
                    record["http"] = server.end()
            if (
                record["http"]["fatal"]
                or not record["http"]["handlersDrained"]
                or not record["http"]["requestCountAcceptanceComplete"]
            ):
                raise Failure("public_http_or_cleanup_failed")
            expected = 2 if case == "offset21" else 0
            if record["http"]["firstMediaIndex"] != expected:
                raise Failure("first_media_index_mismatch")
        result["result"] = "complete"
    except KeyboardInterrupt:
        result.update(result="failed", fixedError="local_interruption")
    except Failure as error:
        result.update(result="failed", fixedError=error.code)
    except Exception:
        result.update(result="failed", fixedError="local_failure")
    finally:
        if server:
            server.retiring.set()
        if device:
            try:
                result["deviceCleanup"] = device.close()
            except Exception:
                result["deviceCleanup"] = {"cleanupFailed": True}
            result["deviceOperations"] = device.operations
        if server:
            try:
                result["serverCleanup"] = server.close()
            except Exception:
                result["serverCleanup"] = {
                    "serverStopped": False,
                    "handlersDrained": False,
                }
        result["ownedCleanupConfirmed"] = bool(
            (
                device is None
                or all(
                    result["deviceCleanup"].get(k) is True
                    for k in (
                        "packageStopped",
                        "reverseRemoved",
                        "selectedEmulatorAbsent",
                        "launcherExited",
                    )
                )
            )
            and (
                server is None
                or (
                    result["serverCleanup"].get("serverStopped")
                    and result["serverCleanup"].get("handlersDrained")
                )
            )
        )
        if not result["ownedCleanupConfirmed"]:
            result["result"] = "failed"
            result.setdefault("fixedError", "owned_cleanup_unconfirmed")
        if server is not None and not result["serverCleanup"].get(
            "requestCountAcceptanceComplete", False
        ):
            result["result"] = "failed"
            result.setdefault("fixedError", "public_request_accounting_incomplete")
        write_new(evidence / "result.json", result)
        for number, handler in previous.items():
            signal.signal(number, handler)
    return result


def later_check(evidence, config, *, runner=subprocess.run):
    write_new(
        evidence / "later-claim.json", {"kind": "one later read-only public check"}
    )
    original = json.loads((evidence / "result.json").read_text())
    receipt = {
        "kind": "one separate later absence observation",
        "PlexRequests": 0,
        "accountAccess": False,
        "originalOwnedCleanupConfirmed": original.get("ownedCleanupConfirmed") is True,
        "diagnostics": [],
    }
    try:
        devices = runner(
            [str(Path(config["sdk"]) / "platform-tools/adb"), "devices"],
            capture_output=True,
            timeout=5,
            check=False,
        )
        listener = runner(
            ["/usr/sbin/lsof", "-nP", "-t", f"-iTCP:{PORT}", "-sTCP:LISTEN"],
            capture_output=True,
            timeout=5,
            check=False,
        )
        receipt["selectedEmulatorAbsent"] = (
            devices.returncode == 0 and not selected_present(devices.stdout)
        )
        receipt["listenerAbsent"] = (
            listener.returncode == 1 and not listener.stdout and not listener.stderr
        )
        receipt["reverseRemovalConfirmedByOriginalReceipt"] = (
            original.get("deviceCleanup", {}).get("reverseRemoved") is True
        )
        receipt["diagnostics"] = [
            {
                "operation": "devices",
                "returncode": devices.returncode,
                "stderrCategory": category(devices.stderr),
            },
            {
                "operation": "listener",
                "returncode": listener.returncode,
                "stderrCategory": category(listener.stderr),
            },
        ]
        receipt["passed"] = all(
            receipt.get(k) is True
            for k in (
                "originalOwnedCleanupConfirmed",
                "selectedEmulatorAbsent",
                "listenerAbsent",
                "reverseRemovalConfirmedByOriginalReceipt",
            )
        )
    except Exception:
        receipt.update(passed=False, fixedError="later_command_failed")
    write_new(evidence / "later.json", receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    for name in (
        "freeze",
        "preflight-only",
        "authorized-public",
        "authorized-post-cycle-check",
    ):
        action.add_argument("--" + name, action="store_true")
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--cert", type=Path)
    parser.add_argument("--key", type=Path)
    parser.add_argument("--corpus", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--sdk", type=Path, default=Path.home() / "Library/Android/sdk")
    args = parser.parse_args()
    try:
        if args.freeze:
            if any(
                getattr(args, key) is None
                for key in ("apk", "cert", "key", "corpus", "manifest")
            ):
                raise Failure("freeze_arguments_missing")
            config = freeze(args)
            print(
                json.dumps(
                    {
                        "freezeSha256": digest(args.evidence / "freeze.json"),
                        "inputs": len(config["dependencies"]),
                    }
                )
            )
            return 0
        config = preflight(args.evidence)
        if args.preflight_only:
            print(
                json.dumps(
                    {"preflightPassed": True, "inputs": len(config["dependencies"])}
                )
            )
            return 0
        result = (
            later_check(args.evidence, config)
            if args.authorized_post_cycle_check
            else run_cycle(args.evidence, config)
        )
        print(
            json.dumps(
                {
                    k: result[k]
                    for k in ("result", "passed", "fixedError", "ownedCleanupConfirmed")
                    if k in result
                }
            )
        )
        return (
            0
            if result.get("result") == "complete" or result.get("passed") is True
            else 1
        )
    except Failure as error:
        print(json.dumps({"fixedError": error.code}))
        return 1
    except Exception:
        print(json.dumps({"fixedError": "local_setup_failed"}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
