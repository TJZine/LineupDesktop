
import argparse
import hashlib
import http.client
import http.server
import json
import pathlib
import re
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse


TOKEN = "lineup-synthetic-reference-test"
SESSION_PREFIX = "/video/:/transcode/universal/session/synthetic-reference/base"
DLL_SHA256 = "4ba364226fd2ea5dd2c6f2333f0118462da549feed92360fb766a3924e313a51"
DEADLINE = time.monotonic() + 150
STAGE = "prerequisites"
FIXED_FAILURE_CODES = {
    "overall test deadline reached", "fixture tool failed", "secret_in_child_output",
    "invalid_harness_outcome", "server termination timed out", "fixture_server_error",
    "ffmpeg, ffprobe and openssl are required", "pinned DLL hash mismatch",
    "unexpected_fixture_keyframes", "incomplete_profile_matrix", "invalid_session_fixture",
    "missing_session_outcomes", "session_sentinel_contacted", "incomplete_session_matrix",
}


def failure_message(error):
    message = f"FAIL: fixture, runtime, or bounded-wait prerequisite (stage={STAGE})"
    if (type(error) is RuntimeError and len(error.args) == 1 and
            isinstance(error.args[0], str) and error.args[0] in FIXED_FAILURE_CODES):
        message += f" (code={error.args[0]})"
    return message


def remaining(timeout):
    seconds = min(timeout, DEADLINE - time.monotonic())
    if seconds <= 0:
        raise RuntimeError("overall test deadline reached")
    return seconds


def run(command, timeout=30):
    result = subprocess.run(command, capture_output=True, timeout=remaining(timeout))
    if result.returncode:
        raise RuntimeError("fixture tool failed")
    return result.stdout


def read_outcomes(result, nonzero_start):
    if TOKEN.encode() in result.stdout or TOKEN.encode() in result.stderr:
        raise RuntimeError("secret_in_child_output")
    fields = dict(field.split("=") for field in result.stdout.decode("ascii").strip().split())
    required = {"initialized", "progressed", "rejected", "timed_out",
                "start_configured", "landing_confirmed", "initial_paused", "play_released",
                "delay_exercised", "ignored_start"}
    counters = {"nested_forbidden_count", "internal_redirect_count", "end_file_error_count"}
    if (required - fields.keys() or
            any((not value.isdecimal() or int(value) > 4096) if name in counters else value not in ("0", "1")
                for name, value in fields.items()) or
            fields["start_configured"] != str(int(nonzero_start))):
        raise RuntimeError("invalid_harness_outcome")
    return fields


def media_pass(result, fields, audit, positive):
    return (result.returncode == 0 and fields["initialized"] == "1" and
            fields["timed_out"] == "0" and audit["A_token"] and not audit["B_token"] and
            not audit["secondary_A_token"] and not audit["token_in_url"] and
            not audit["server_error"] and
            (positive is None or ((fields["initial_paused"] == "1" and fields["play_released"] == "1" and
                                   fields["ignored_start"] == "0" and fields["landing_confirmed"] == "1" and
                                   fields["progressed"] == "1" and fields["rejected"] == "0")
                                  if positive else (fields["progressed"] == "0" and fields["rejected"] == "1"))))


def redirect_pass(result, fields, audit):
    return media_pass(result, fields, audit, False) and audit["B_requests"] == 0


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.lock = threading.Lock()
        self.responses_finished = threading.Condition(self.lock)
        self.failed = False
        self.errors = []
        self.errors_omitted = 0
        self.accepted_connections = 0
        self.total_accepted_connections = 0
        self.response_records = []
        self.track_bodies = False

    def wait_for_responses(self, paths, timeout):
        """Snapshot finished write attempts, or incomplete records at the deadline."""
        with self.responses_finished:
            self.responses_finished.wait_for(
                lambda: all(row["finished"] for row in self.response_records if row["path"] in paths),
                timeout=timeout)
            return [dict(row) for row in self.response_records if row["path"] in paths]

    def record_error(self, error, phase):
        # Keep peer disconnects distinct from fixture faults. In particular,
        # the wrong-CA client can close before sending any HTTP request.
        if isinstance(error, (ConnectionResetError, BrokenPipeError, ssl.SSLEOFError)):
            code = "peer_disconnect"
        elif (phase == "tls_accept" and isinstance(error, ssl.SSLError) and
              getattr(error, "reason", None) in ("TLSV1_ALERT_UNKNOWN_CA", "SSLV3_ALERT_BAD_CERTIFICATE")):
            code = "certificate_rejected"
        else:
            code = "unexpected_error"
        # Never include exception text, arbitrary class names, addresses, or
        # traceback data: these can contain request URLs or credentials.
        classes = (ConnectionResetError, BrokenPipeError, ssl.SSLEOFError,
                   ssl.SSLError, TimeoutError, OSError, RuntimeError, ValueError)
        category = next((kind.__name__ for kind in classes if isinstance(error, kind)), "Exception")
        diagnostic = {"phase": phase, "code": code, "exception": category}
        for name in ("errno", "winerror"):
            value = getattr(error, name, None)
            diagnostic[name] = value if type(value) is int else None
        with self.lock:
            if code == "unexpected_error":
                self.failed = True
            for entry in self.errors:
                if all(entry[key] == value for key, value in diagnostic.items()):
                    entry["count"] += 1
                    break
            else:
                if len(self.errors) < 16:
                    self.errors.append({**diagnostic, "count": 1})
                else:
                    self.errors_omitted += 1

    def handle_error(self, *_):
        self.record_error(sys.exc_info()[1], "handler")

    def get_request(self):
        connection, address = super().get_request()
        with self.lock:
            self.accepted_connections += 1
            self.total_accepted_connections += 1
        connection.settimeout(3)
        if self.context is None:
            return connection, address
        try:
            return self.context.wrap_socket(connection, server_side=True), address
        except Exception as error:
            connection.close()
            self.record_error(error, "tls_accept")
            # BaseServer consumes OSError from get_request, without calling
            # handle_error. Record it above, including unexpected runtime
            # faults, and let the listener continue without a raw traceback.
            raise OSError("fixture_tls_accept_failed") from None
        except BaseException:
            connection.close()
            raise


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.serve_resource(send_body=True)

    def do_HEAD(self):
        self.serve_resource(send_body=False)

    def serve_resource(self, send_body):
        range_header = self.headers.get("Range")
        decoded_path = urllib.parse.unquote(self.path)
        token_url = TOKEN in decoded_path or "x-plex-token" in decoded_path.lower()
        with self.server.lock:
            self.server.requests.append((self.path, any(name.lower() == "x-plex-token" or TOKEN in value
                                                  for name, value in self.headers.items()), token_url))
            if range_header:
                self.server.range_requests = getattr(self.server, "range_requests", 0) + 1
        if (self.server.authenticated and not self.path.startswith(SESSION_PREFIX + "/") and
                self.headers.get("X-Plex-Token") != TOKEN):
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if (self.path.startswith("/redirect") or
                self.path in getattr(self.server, "redirect_paths", ())):
            self.send_response(302)
            self.send_header("Location", self.server.redirect)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body, content_type = self.server.files.get(self.path, (b"", "application/octet-stream"))
        size = len(body)
        first, last = 0, size - 1
        # The adversarial nested probe serves its complete tiny bodies with 200
        # even if a client asks for a range, matching the measured control.
        if self.path in getattr(self.server, "whole_body_paths", ()):
            range_header = None
        partial = bool(range_header and size)
        if partial:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header)
            valid = match is not None and any(match.groups())
            if valid:
                start, end = match.groups()
                if start:
                    first = int(start)
                    last = min(int(end), size - 1) if end else size - 1
                    valid = first < size and first <= last
                else:
                    suffix = int(end)
                    valid = suffix > 0
                    first = max(0, size - suffix)
            if not valid:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            with self.server.lock:
                self.server.partial_responses = getattr(self.server, "partial_responses", 0) + 1
        status = 206 if partial else 200 if body else 404
        response_record = None
        if self.server.track_bodies:
            response_record = {"path": self.path, "method": self.command, "status": status,
                               "bytes": 0, "complete": False, "finished": False}
            with self.server.lock:
                self.server.response_records.append(response_record)
        written, complete = 0, False
        try:
            self.send_response(status)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(last - first + 1 if size else 0))
            if partial:
                self.send_header("Content-Range", f"bytes {first}-{last}/{size}")
            self.end_headers()
            if send_body:
                payload = body[first:last + 1]
                written = self.wfile.write(payload)
                self.wfile.flush()
                complete = written == len(payload)
        finally:
            if response_record is not None:
                with self.server.responses_finished:
                    response_record.update(bytes=written, complete=complete, finished=True)
                    self.server.responses_finished.notify_all()

def certificate(root, openssl):
    config = root / "leaf.cnf"
    config.write_text("[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=localhost\n"
                      "[leaf]\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n"
                      "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\n"
                      "extendedKeyUsage=serverAuth\n", encoding="ascii")
    run([openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
         "-subj", "/CN=Lineup temporary test CA", "-addext", "basicConstraints=critical,CA:TRUE",
         "-addext", "keyUsage=critical,keyCertSign,cRLSign",
         "-keyout", str(root / "ca.key"), "-out", str(root / "ca.pem")])
    run([openssl, "req", "-new", "-newkey", "rsa:2048", "-nodes", "-config", str(config),
         "-keyout", str(root / "leaf.key"), "-out", str(root / "leaf.csr")])
    run([openssl, "x509", "-req", "-in", str(root / "leaf.csr"), "-CA", str(root / "ca.pem"),
         "-CAkey", str(root / "ca.key"), "-CAcreateserial", "-days", "1", "-extfile", str(config),
         "-extensions", "leaf", "-out", str(root / "leaf.pem")])
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(root / "leaf.pem", root / "leaf.key")
    return context


def atom(name, body):
    return struct.pack(">I", len(body) + 8) + name.encode("ascii") + body


def finish_servers(servers, threads):
    for server in servers:
        server.shutdown()
        server.server_close()
    for thread in threads:
        thread.join(timeout=3)
        if thread.is_alive():
            raise RuntimeError("server termination timed out")
    # TLS accept runs on the listener thread and can record an error after
    # the final per-case audit. Its completed sticky failure must still fail
    # the matrix, even if every earlier row had a clean snapshot.
    for server in servers:
        with server.lock:
            if server.failed:
                raise RuntimeError("fixture_server_error")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--harness", required=True, type=pathlib.Path)
    parser.add_argument("--dll", required=True, type=pathlib.Path)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument("--openssl", default=shutil.which("openssl"))
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe"))
    args = parser.parse_args()
    if not args.openssl:
        git_openssl = pathlib.Path("C:/Program Files/Git/usr/bin/openssl.exe")
        if git_openssl.is_file():
            args.openssl = str(git_openssl)
    if not args.ffmpeg or not args.openssl or not args.ffprobe:
        raise RuntimeError("ffmpeg, ffprobe and openssl are required")
    for dll in (args.dll, args.harness.parent / "libmpv-2.dll"):
        if hashlib.sha256(dll.read_bytes()).hexdigest() != DLL_SHA256:
            raise RuntimeError("pinned DLL hash mismatch")
    records = [row for nonzero_start in (False, True)
               for row in matrix(args, nonzero_start)]
    records.extend(session_matrix(args))
    passed = len(records) == 56 and all(row["pass"] for row in records)
    print(json.dumps({"pass": passed, "case_count": len(records)}), flush=True)
    return 0 if passed else 1


def matrix(args, nonzero_start):
    global STAGE
    STAGE = "direct_matrix"
    records = []
    profile = "nonzero-start" if nonzero_start else "omitted-start"
    duration = 6 if nonzero_start else 1

    def record(row):
        row["start_profile"] = profile
        records.append(row)
        print(json.dumps(row), flush=True)

    with tempfile.TemporaryDirectory(prefix="lineup-reference-") as temporary:
        root = pathlib.Path(temporary)
        context = certificate(root, args.openssl)
        mp4 = root / "media.mp4"
        encoder_options = (["-g", "10", "-keyint_min", "10", "-sc_threshold", "0", "-bf", "0"]
                           if nonzero_start else [])
        run([args.ffmpeg, "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x64:r=10",
             "-t", str(duration), "-c:v", "libx264", "-pix_fmt", "yuv420p", *encoder_options,
             "-movflags", "+faststart", str(mp4)])
        frame_index = json.loads(run([
            args.ffprobe, "-v", "error", "-select_streams", "v:0", "-show_frames",
            "-show_entries", "frame=key_frame,best_effort_timestamp_time", "-of", "json", str(mp4)]))
        frames = frame_index["frames"]
        keyframes = [float(frame["best_effort_timestamp_time"])
                     for frame in frames if frame["key_frame"] == 1]
        if nonzero_start and (len(frames) != 60 or keyframes != list(range(6))):
            raise RuntimeError("unexpected_fixture_keyframes")
        fixture_identity = {"start_profile": profile, "frame_count": len(frames),
                            "keyframe_seconds": keyframes,
                            "start_seconds": 3.5 if nonzero_start else None,
                            "expected_landing_seconds": 3.0 if nonzero_start else None,
                            "mp4_sha256": hashlib.sha256(mp4.read_bytes()).hexdigest()}
        print(json.dumps({"fixture_index": fixture_identity}), flush=True)
        run([args.ffmpeg, "-v", "error", "-i", str(mp4), "-c", "copy", str(root / "media.mkv")])
        run([args.ffmpeg, "-v", "error", "-i", str(mp4), "-c", "copy", "-f", "mpegts", str(root / "segment.ts")])
        run([args.ffmpeg, "-v", "error", "-i", str(mp4), "-c", "copy", "-f", "dash", str(root / "media.mpd")])
        servers = []
        threads = []
        try:
            for transport in (context, context, None):
                server = Server(("127.0.0.1", 0), Handler)
                server.context = transport
                server.authenticated = len(servers) == 0
                server.requests = []
                server.range_requests = 0
                server.partial_responses = 0
                server.files = {"/" + f.name: (f.read_bytes(), "application/octet-stream")
                                for f in root.iterdir() if f.suffix in (".mp4", ".mkv", ".ts", ".m4s")}
                servers.append(server)
                thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True)
                thread.start()
                threads.append(thread)
            a, b, plain = servers
            origin_a = f"https://127.0.0.1:{a.server_port}"
            origin_b = f"https://127.0.0.1:{b.server_port}"
            hostname_b = f"https://localhost:{b.server_port}"

            def hls(url):
                return (f"#EXTM3U\n#EXT-X-TARGETDURATION:{duration}\n#EXTINF:{duration},\n" + url + "\n#EXT-X-ENDLIST\n").encode()

            dash = (root / "media.mpd").read_text(encoding="utf-8")
            dash = dash.replace('initialization="', 'initialization="' + origin_b + "/")
            dash = dash.replace('media="', 'media="' + origin_b + "/")
            cases = [
                ("mp4", "/media.mp4", None, True),
                ("mkv", "/media.mkv", None, True),
                ("hls-hostname", "/hostname.m3u8", hls(hostname_b + "/segment.ts"), False),
                ("hls-port", "/port.m3u8", hls(origin_b + "/segment.ts"), False),
                ("hls-same-origin", "/same.m3u8", hls(origin_a + "/segment.ts"), False),
                ("hls-master", "/master.m3u8", ("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100000\n" + origin_b + "/child.m3u8\n").encode(), False),
                ("hls-key", "/key.m3u8", ("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"" + origin_b + "/key.bin\"\n" + hls(origin_b + "/segment.ts").decode().split("\n", 1)[1]).encode(), False),
                ("dash", "/media.mpd", dash.encode(), False),
                ("playlist", "/playlist.m3u", ("#EXTM3U\n" + origin_b + "/media.mp4\n").encode(), False),
                ("edl", "/media.edl", ("# mpv EDL v0\n" + origin_b + "/media.mp4\n").encode(), False),
                ("cue", "/media.cue", ('FILE "' + origin_b + '/media.mp4" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n').encode(), False),
                ("mov-reference", "/reference.mov", atom("moov", atom("rmra", atom("rmda", atom("rdrf", b"\0\0\0\0url " + struct.pack(">I", len(origin_b + "/media.mp4") + 1) + (origin_b + "/media.mp4\0").encode())))), False),
                ("concat", "/media.ffconcat", ("ffconcat version 1.0\nfile '" + origin_b + "/media.mp4'\n").encode(), False),
                ("concat-relative", "/relative.ffconcat", b"ffconcat version 1.0\nfile 'media.mp4'\n", False),
                ("imf", "/cpl.xml", b"<CompositionPlaylist><Id>urn:uuid:00000000-0000-0000-0000-000000000001</Id><ContentTitle>synthetic</ContentTitle><EditRate>10 1</EditRate><SegmentList/></CompositionPlaylist>", False),
                ("sdp", "/media.sdp", ("v=0\no=- 0 0 IN IP4 127.0.0.1\ns=synthetic\nc=IN IP4 127.0.0.1\nt=0 0\nm=video 0 RTP/AVP 96\na=rtpmap:96 H264/90000\na=control:" + origin_b + "/media.mp4\n").encode(), None),
                ("vobsub", "/sidecar.idx", b"# VobSub index file, v7 (do not modify this line!)\nsize: 64x64\nid: en, index: 0\ntimestamp: 00:00:00:000, filepos: 000000000\n", False),
                ("redirect-https", "/redirect-https", None, False),
                ("redirect-http", "/redirect-http", None, False),
            ]
            b.files["/child.m3u8"] = (hls(origin_b + "/segment.ts"), "application/vnd.apple.mpegurl")
            b.files["/key.bin"] = (bytes(16), "application/octet-stream")
            a.files["/sidecar.sub"] = (b"invalid synthetic subtitle", "application/octet-stream")
            def audit(path):
                with a.lock, b.lock, plain.lock:
                    secondary = b.requests + plain.requests
                    return {"A_requests": len(a.requests), "B_requests": len(secondary),
                            "B_https_requests": len(b.requests), "B_http_requests": len(plain.requests),
                            "B_http_token": any(token for _, token, _ in plain.requests),
                            "A_range_requests": a.range_requests, "A_partial_responses": a.partial_responses,
                            "A_token": any(token for request, token, _ in a.requests if request == path),
                            "B_token": any(token for _, token, _ in secondary),
                            "secondary_A_token": any(token for request, token, _ in a.requests if request != path),
                            "token_in_url": any(url for server in servers for _, _, url in server.requests),
                            "server_error": any(server.failed for server in servers),
                            "server_diagnostics": {name: [dict(entry) for entry in server.errors]
                                                   for name, server in zip(("A", "B", "plain"), servers)},
                            "server_diagnostics_omitted": sum(server.errors_omitted for server in servers)}

            def invoke(name, path, ca="ca.pem", mode=None):
                for server in servers:
                    with server.lock:
                        server.requests.clear()
                        server.range_requests = 0
                        server.partial_responses = 0
                command = [str(args.harness), str(root / ca), origin_a + path]
                if mode:
                    command.append(mode)
                if nonzero_start:
                    command.append("--nonzero-start")
                result = subprocess.run(command, capture_output=True, timeout=remaining(22))
                return result, read_outcomes(result, nonzero_start), audit(path)

            for name, path, body, positive in cases:
                if body:
                    a.files[path] = (body, "application/dash+xml" if name == "dash" else "application/octet-stream")
                a.redirect = (f"http://127.0.0.1:{plain.server_port}/media.mp4" if name == "redirect-http"
                              else origin_b + "/media.mp4")
                result, fields, observed = invoke(name, path, mode="observe" if positive is None else None)
                if name in ("redirect-https", "redirect-http"):
                    passed = redirect_pass(result, fields, observed)
                else:
                    passed = media_pass(result, fields, observed, positive)
                record({"case": name, "pass": passed, **observed, **fields})
                if name == "redirect-http":
                    # A real plaintext listener must see the deliberate leak.
                    # Preserve the actual rejected/no-progress media result.
                    connection = http.client.HTTPConnection("127.0.0.1", plain.server_port, timeout=3)
                    try:
                        connection.request("GET", "/media.mp4", headers={"X-Plex-Token": TOKEN})
                        response = connection.getresponse()
                        status = response.status
                        response.read()
                    finally:
                        connection.close()
                    observed = audit(path)
                    passed = (result.returncode == 0 and fields["progressed"] == "0" and
                              fields["rejected"] == "1" and status == 200 and
                              observed["B_http_requests"] == 1 and observed["B_http_token"] and
                              observed["B_token"] and not media_pass(result, fields, observed, False))
                    record({"case": "control-http-token", "pass": passed, **observed, **fields})

            for option in ("access-references", "autoload-files"):
                result, fields, observed = invoke("reject-option-" + option, "/media.mp4", mode=option)
                passed = (result.returncode == 0 and fields["initialized"] == "0" and
                          fields["progressed"] == "0" and fields["rejected"] == "1" and
                          fields["timed_out"] == "0" and observed["A_requests"] == 0 and
                          observed["B_requests"] == 0 and not observed["server_error"])
                record({"case": "reject-option-" + option, "pass": passed, **observed, **fields})

            run([args.openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                 "-subj", "/CN=Lineup untrusted test CA", "-keyout", str(root / "wrong.key"),
                 "-out", str(root / "wrong.pem")])
            result, fields, observed = invoke("untrusted-ca", "/media.mp4", ca="wrong.pem")
            passed = (result.returncode == 0 and fields["initialized"] == "1" and
                      fields["progressed"] == "0" and fields["rejected"] == "1" and
                      fields["timed_out"] == "0" and observed["A_requests"] == 0 and
                      observed["B_requests"] == 0 and not observed["server_error"])
            record({"case": "untrusted-ca", "pass": passed, **observed, **fields})

            if nonzero_start:
                result, fields, observed = invoke("control-delayed-start", "/media.mp4", mode="control-delayed-start")
                passed = (media_pass(result, fields, observed, True) and fields["delay_exercised"] == "1" and
                          observed["A_partial_responses"] > 0)
                record({"case": "control-delayed-start", "pass": passed, **observed, **fields})
                result, fields, observed = invoke("control-ignore-start-delayed", "/media.mp4", mode="control-ignore-start-delayed")
                passed = (media_pass(result, fields, observed, None) and fields["delay_exercised"] == "1" and
                          fields["ignored_start"] == "1" and fields["initial_paused"] == "1" and
                          fields["play_released"] == "1" and fields["landing_confirmed"] == "0" and
                          fields["progressed"] == "0" and fields["rejected"] == "0" and
                          not media_pass(result, fields, observed, True))
                record({"case": "control-ignore-start-delayed", "pass": passed, **observed, **fields})
        finally:
            failed_stage = STAGE
            STAGE = "direct_cleanup"
            finish_servers(servers, threads)
            STAGE = failed_stage
    expected = {name for name, *_ in cases} | {
        "reject-option-access-references", "reject-option-autoload-files", "untrusted-ca", "control-http-token"}
    if nonzero_start:
        expected |= {"control-delayed-start", "control-ignore-start-delayed"}
    if len(records) != (25 if nonzero_start else 23) or {row["case"] for row in records} != expected:
        raise RuntimeError("incomplete_profile_matrix")
    return records


def session_playlists(playlist, other_origin):
    """Complete inputs for the native validator; no host-side filtering of bad references."""
    off_origin = playlist.replace(b'URI="session-init.mp4"',
                                  ('URI="' + other_origin + SESSION_PREFIX + '/session-init.mp4"').encode())
    off_origin = re.sub(rb"(?m)^(session-[0-9]+\.m4s)$",
                        lambda match: (other_origin + SESSION_PREFIX + "/").encode() + match[1],
                        off_origin)
    redirect = playlist.replace(b'URI="session-init.mp4"', b'URI="session-redirect-init.mp4"')
    return off_origin, redirect


def nested_hls_input(other_origin):
    # Concatenation matches the first complete HLS probe: MAP is the eight-byte
    # header; the allowed media child supplies the rest, containing a B canary.
    initialization = b"#EXTM3U\n"
    media = ("#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:1,\n" +
             other_origin + "/nested-sentinel.m4s\n#EXT-X-ENDLIST\n").encode()
    playlist = (b"#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-PLAYLIST-TYPE:VOD\n"
                b"#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:0\n"
                b'#EXT-X-MAP:URI="nested-init.mp4"\n#EXTINF:1,\nattack.m3u8\n#EXT-X-ENDLIST\n')
    return playlist, initialization, media


def session_pass(result, fields, audit, positive, restoration, mode):
    passed = (result.returncode == 0 and fields["initialized"] == "1" and
              fields["timed_out"] == "0" and fields["session_options_captured"] == "1" and
              not audit["root_requested"] and
              not audit["session_token"] and not audit["token_in_url"] and
              not audit["server_error"] and audit["off_origin_requests"] == 0 and
              audit["unexpected_requests"] == 0 and audit["off_origin_connections"] == 0 and
              fields["session_progressed"] == str(int(positive)) and
              fields["session_rejected"] == str(int(not positive)) and
              fields["session_override_removed"] == str(int(mode == "session-control-no-references")) and
              fields["restoration_attempted"] == str(int(restoration)) and
              fields["stop_confirmed"] == str(int(mode == "session-stop")))
    restored = ("references", "redirects", "demuxer", "lavf_options", "session_options")
    passed = passed and all(fields[name + "_restored_after"] == "1" for name in restored)
    if positive:
        passed = passed and audit["init_requested"] and audit["media_requests"] > 0
    elif mode == "session-nested-hls":
        passed = (passed and audit["nested_init_complete"] and audit["nested_media_complete"] and
                  audit["child_requests"] >= 2 and audit["nested_unexpected_children"] == 0 and
                  int(fields["nested_forbidden_count"]) >= 1 and
                  fields["internal_redirect_count"] == "0" and
                  int(fields["end_file_error_count"]) >= 1 and
                  fields["session_load_started"] == "1" and fields["session_structural_failure"] == "0")
    elif mode == "session-redirect":
        passed = (passed and audit["redirect_child_requests"] > 0 and
                  audit["child_requests"] == audit["redirect_child_requests"] and
                  audit["media_requests"] == 0)
    else:
        # Off-origin validation must fail before any I/O. The no-references
        # sensitivity control must reach the node filter but fetch no children.
        passed = passed and audit["child_requests"] == 0
    if restoration:
        passed = (passed and audit["restore_requested"] and audit["restore_child_requests"] == 0 and
                  fields["restoration_rejected"] == "1" and fields["restoration_progressed"] == "0" and
                  fields["references_restored_after"] == "1" and
                  (mode == "session-replace" or
                   all(fields[name + "_restored_before"] == "1" for name in restored)))
    return bool(passed)


def session_matrix(args):
    global STAGE
    STAGE = "session_fixture"
    records = []
    with tempfile.TemporaryDirectory(prefix="lineup-session-reference-") as temporary:
        root = pathlib.Path(temporary)
        context = certificate(root, args.openssl)
        run([args.ffmpeg, "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x64:r=10",
             "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-g", "10",
             "-keyint_min", "10", "-sc_threshold", "0", "-bf", "0", "-f", "hls",
             "-hls_segment_type", "fmp4", "-hls_time", "1", "-hls_list_size", "0",
             "-hls_fmp4_init_filename", "session-init.mp4", "-hls_segment_filename",
             # FFmpeg's HLS muxer locates the init output directory using '/'
             # even on Windows. Backslashes leave the init file in the CWD.
             (root / "session-%d.m4s").as_posix(), (root / "session-source.m3u8").as_posix()])
        playlist = (root / "session-source.m3u8").read_bytes()
        if b'#EXT-X-MAP:URI="session-init.mp4"' not in playlist or b"#EXT-X-ENDLIST" not in playlist:
            raise RuntimeError("invalid_session_fixture")
        servers, threads = [], []
        try:
            STAGE = "session_listener"
            for _ in range(2):
                server = Server(("127.0.0.1", 0), Handler)
                server.context = context
                server.authenticated = not servers
                server.requests = []
                server.track_bodies = True
                server.files = {"/" + path.name: (path.read_bytes(), "application/octet-stream")
                                for path in root.iterdir() if path.suffix in (".mp4", ".m4s")}
                servers.append(server)
                thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True)
                thread.start()
                threads.append(thread)
            a, b = servers
            origin_a = f"https://127.0.0.1:{a.server_port}"
            origin_b = f"https://127.0.0.1:{b.server_port}"
            variant = SESSION_PREFIX + "/index.m3u8"
            redirect_child = SESSION_PREFIX + "/session-redirect-init.mp4"
            off_origin, redirected_playlist = session_playlists(playlist, origin_b)
            nested_playlist, nested_init, nested_media = nested_hls_input(origin_b)
            a.files[SESSION_PREFIX + "/nested-init.mp4"] = (nested_init, "video/mp4")
            a.files[SESSION_PREFIX + "/attack.m3u8"] = (nested_media, "application/vnd.apple.mpegurl")
            a.whole_body_paths = {SESSION_PREFIX + "/nested-init.mp4", SESSION_PREFIX + "/attack.m3u8"}
            b.files["/nested-sentinel.m4s"] = (b"owned nested sentinel", "application/octet-stream")
            for path in root.iterdir():
                if path.name.startswith("session-") and path.suffix in (".mp4", ".m4s"):
                    a.files[SESSION_PREFIX + "/" + path.name] = (path.read_bytes(), "application/octet-stream")
            a.redirect = origin_b + SESSION_PREFIX + "/session-init.mp4"
            b.files[SESSION_PREFIX + "/session-init.mp4"] = a.files[SESSION_PREFIX + "/session-init.mp4"]
            # Direct restoration still loads an authenticated root, whose
            # off-origin references must be disabled after each session exit.
            restore = off_origin.replace(b"/session-init.mp4", b"/restore-init.mp4")
            restore = re.sub(rb"/session-([0-9]+)\.m4s", rb"/restore-\1.m4s", restore)
            a.files["/restore.m3u8"] = (restore, "application/vnd.apple.mpegurl")
            b.files[SESSION_PREFIX + "/restore-init.mp4"] = a.files[SESSION_PREFIX + "/session-init.mp4"]
            for path in root.glob("session-*.m4s"):
                b.files[SESSION_PREFIX + "/restore-" + path.name.removeprefix("session-")] = a.files[SESSION_PREFIX + "/" + path.name]

            cases = [
                ("session-complete", playlist, "session-complete", True, True),
                ("session-stop", playlist, "session-stop", True, True),
                ("session-replace", playlist, "session-replace", True, True),
                ("session-off-origin", off_origin, "session-off-origin", False, False),
                ("session-redirect", redirected_playlist, "session-redirect", False, False),
                ("session-control-no-references", playlist, "session-control-no-references", False, False),
                ("session-restored-override", playlist, "session-complete", True, True),
                ("session-nested-hls", nested_playlist, "session-nested-hls", False, False),
            ]
            for name, payload, mode, positive, restoration in cases:
                STAGE = "session_child"
                path = variant
                payload_path = root / "session-input.m3u8"
                payload_path.write_bytes(payload)
                # Serve the original only as an accidental-fallback detector.
                a.files[path] = (payload, "application/vnd.apple.mpegurl")
                a.redirect_paths = {redirect_child} if mode == "session-redirect" else set()
                for server in servers:
                    with server.lock:
                        server.requests.clear()
                        server.response_records.clear()
                        server.accepted_connections = 0
                result = subprocess.run([str(args.harness), str(root / "ca.pem"), origin_a + path, mode,
                                         "--session-playlist=" + str(payload_path)],
                                        capture_output=True, timeout=remaining(30))
                STAGE = "session_outcomes"
                fields = read_outcomes(result, False)
                required = {"session_progressed", "session_rejected", "session_override_removed",
                            "restoration_attempted", "restoration_progressed", "restoration_rejected",
                            "stop_confirmed",
                            "session_options_captured", "nested_forbidden_count", "internal_redirect_count",
                            "end_file_error_count", "session_load_started", "session_structural_failure"}
                required.update(name + "_restored_" + phase
                                for name in ("references", "redirects", "demuxer", "lavf_options", "session_options")
                                for phase in ("before", "after"))
                if required - fields.keys():
                    raise RuntimeError("missing_session_outcomes")
                responses = a.wait_for_responses(a.whole_body_paths, timeout=remaining(3))
                with a.lock, b.lock:
                    root_requested = any(request == path for request, _, _ in a.requests)
                    root_token = any(token for request, token, _ in a.requests if request == path)
                    child_requests = [(request, token) for server in servers
                                      for request, token, _ in server.requests
                                      if request.startswith(SESSION_PREFIX + "/") and request != path]
                    restore_requested = any(request == "/restore.m3u8" and token
                                            for request, token, _ in a.requests)
                    restore_child_requests = sum("/restore-" in request for request, _, _ in b.requests)
                    audit = {
                        "root_requested": root_requested,
                        "session_token": root_token or any(token for _, token in child_requests),
                        "child_requests": len(child_requests),
                        "init_requested": any(request == SESSION_PREFIX + "/session-init.mp4"
                                              for request, _ in child_requests),
                        "media_requests": sum(request.endswith(".m4s") for request, _ in child_requests),
                        "redirect_child_requests": sum(request == redirect_child for request, _ in child_requests),
                        "off_origin_requests": len(b.requests),
                        "off_origin_connections": b.accepted_connections,
                        "nested_unexpected_children": sum(request not in a.whole_body_paths
                                                          for request, _ in child_requests),
                        "nested_init_complete": any(row["path"] == SESSION_PREFIX + "/nested-init.mp4" and
                                                    row["method"] == "GET" and row["status"] == 200 and
                                                    row["bytes"] == len(nested_init) and row["complete"]
                                                    for row in responses),
                        "nested_media_complete": any(row["path"] == SESSION_PREFIX + "/attack.m3u8" and
                                                     row["method"] == "GET" and row["status"] == 200 and
                                                     row["bytes"] == len(nested_media) and row["complete"]
                                                     for row in responses),
                        "unexpected_requests": sum(not request.startswith(SESSION_PREFIX + "/") and
                                                   request != "/restore.m3u8" for server in servers
                                                   for request, _, _ in server.requests),
                        "restore_requested": restore_requested,
                        "restore_child_requests": restore_child_requests,
                        "token_in_url": any(url for server in servers for _, _, url in server.requests),
                        "server_error": any(server.failed for server in servers),
                    }
                passed = session_pass(result, fields, audit, positive, restoration, mode)
                row = {"case": name, "pass": bool(passed), **audit, **fields}
                records.append(row)
                print(json.dumps(row), flush=True)
        finally:
            failed_stage = STAGE
            STAGE = "session_cleanup"
            finish_servers(servers, threads)
            STAGE = failed_stage
    # Count TCP accepts before TLS and inspect again after listener shutdown so
    # a late sentinel contact cannot escape the last per-case snapshot.
    if len(servers) == 2 and servers[1].total_accepted_connections:
        raise RuntimeError("session_sentinel_contacted")
    if len(records) != 8 or len({row["case"] for row in records}) != 8:
        raise RuntimeError("incomplete_session_matrix")
    return records


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(failure_message(error), flush=True)
        raise SystemExit(2)
