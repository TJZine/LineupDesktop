#!/usr/bin/env python3
"""Headless macOS production-adapter authenticated-reference proof.

Fixture definitions derive from tool/windows/authenticated-reference-test.py.
No system trust, external service, Flutter app build, or real credential is used.
"""
import argparse
import hashlib
import http.client
import http.server
import json
import os
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
REPO = pathlib.Path(__file__).resolve().parents[3]
DEADLINE = 0
OUTPUT = None


def remaining(timeout):
    seconds = min(timeout, DEADLINE - time.monotonic())
    if seconds <= 0:
        raise RuntimeError("overall_deadline")
    return seconds


def clean_environment():
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("DYLD_") or key in {
            "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "CPATH", "CPLUS_INCLUDE_PATH",
            "C_INCLUDE_PATH", "LIBRARY_PATH", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET",
            "SSL_CERT_FILE", "SSL_CERT_DIR", "CURL_CA_BUNDLE", "LINEUP_PRESENTATION_LOG",
        } or key.lower() in {"http_proxy", "https_proxy", "all_proxy", "no_proxy"}:
            del env[key]
    env["NO_PROXY"] = "127.0.0.1,localhost"
    return env


def captured(command, timeout=30, label="tool"):
    result = subprocess.run(command, capture_output=True, timeout=remaining(timeout),
                            env=clean_environment())
    secret = TOKEN.encode()
    leaked = secret in result.stdout or secret in result.stderr
    if OUTPUT is not None:
        # Preserve diagnostic evidence, but never raw synthetic secrets.
        (OUTPUT / (label + ".log")).write_bytes(
            (result.stdout + b"\n" + result.stderr).replace(secret, b"[REDACTED]"))
    if leaked:
        raise RuntimeError("secret_in_child_output")
    return result


def run(command, timeout=30, label="tool"):
    result = captured(command, timeout, label)
    if result.returncode:
        raise RuntimeError(label + "_failed")
    return result.stdout


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool(value):
    found = shutil.which(value) if value else None
    if not found:
        raise RuntimeError("missing_tool")
    return str(pathlib.Path(found).resolve())


def validate_runtime(runtime, flutter):
    lock = REPO / "tool/macos/mpv-runtime.lock"
    info_path = runtime / "BUILD-INFO.txt"
    info = info_path.read_text()
    lock_sha = sha(lock)
    if f"Pin file SHA-256: {lock_sha}" not in info:
        raise RuntimeError("runtime_pin_mismatch")
    commit = re.search(r"^MPV_COMMIT=([a-f0-9]{40})$", lock.read_text(), re.M)
    if not commit or "commit:" + commit[1] not in info:
        raise RuntimeError("runtime_source_mismatch")
    patch_lines = info.split("Patches:\n", 1)[1].split("Sources:\n", 1)[0]
    patches = re.findall(r"^  ([\w./-]+\.patch) ([a-f0-9]{64})$", patch_lines, re.M)
    if not patches:
        raise RuntimeError("missing_patch_identity")
    for name, expected in patches:
        if ".." in pathlib.PurePosixPath(name).parts:
            raise RuntimeError("invalid_patch_identity")
        if sha(REPO / "tool/macos" / name) != expected or sha(runtime / "patches" / name.replace("-patches/", "/", 1)) != expected:
            raise RuntimeError("runtime_patch_mismatch")
    library_lines = info.split("Libraries:\n", 1)[1]
    identities = dict(re.findall(r"^  ([\w.+-]+\.dylib) ([a-f0-9]{64})$", library_lines, re.M))
    files = {p.name: p for p in (runtime / "lib").glob("*.dylib")}
    if not identities or set(files) != set(identities) or "libmpv.2.dylib" not in files:
        raise RuntimeError("runtime_library_set_mismatch")
    for name, path in files.items():
        if path.is_symlink() or sha(path) != identities[name]:
            raise RuntimeError("runtime_library_hash_mismatch")
        if "arm64" not in run(["/usr/bin/lipo", "-archs", str(path)], label="runtime-arch").decode().split():
            raise RuntimeError("runtime_architecture_mismatch")
        own = run(["/usr/bin/otool", "-D", str(path)], label="runtime-id").decode().splitlines()[1:]
        if own != ["@rpath/" + name]:
            raise RuntimeError("runtime_install_name_mismatch")
        dependencies = run(["/usr/bin/otool", "-L", str(path)], label="runtime-closure").decode().splitlines()[1:]
        for line in dependencies:
            dep = line.strip().split(" (", 1)[0]
            if dep.startswith("@rpath/") and dep[7:] in files:
                continue
            if dep.startswith(("/usr/lib/", "/System/Library/")):
                continue
            raise RuntimeError("runtime_foreign_dependency")
        commands = run(["/usr/bin/otool", "-l", str(path)], label="runtime-load-commands").decode()
        for rpath in re.findall(r"cmd LC_RPATH\n.*?\n\s*path (.*?) \(offset", commands):
            if rpath not in ("@loader_path", "/usr/lib/swift"):
                raise RuntimeError("runtime_foreign_rpath")
    if not (runtime / "include/mpv/client.h").is_file():
        raise RuntimeError("missing_runtime_headers")
    pin = json.loads((REPO / "tool/flutter_version.json").read_text())
    revision = run(["git", "-C", str(flutter), "rev-parse", "HEAD"], label="flutter-revision").decode().strip()
    if revision != pin["frameworkRevision"]:
        raise RuntimeError("flutter_revision_mismatch")
    return {"lock_sha256": lock_sha, "build_info_sha256": sha(info_path),
            "mpv_commit": commit[1], "libmpv_sha256": identities["libmpv.2.dylib"],
            "libraries": dict(sorted(identities.items()))}


class HarnessOutcomeError(RuntimeError):
    def __init__(self, result, case, validation, **details):
        super().__init__("invalid_harness_outcome")
        # Never include child output, argument values, or exception text.
        self.summary = {"case": case, "child_returncode": result.returncode,
                        "child_signal": -result.returncode if result.returncode < 0 else None,
                        "field_validation": validation, **details}


def outcomes(result, case):
    try:
        fields = dict(field.split("=") for field in result.stdout.decode("ascii").strip().split())
    except UnicodeDecodeError:
        raise HarnessOutcomeError(result, case, "non_ascii_output") from None
    except ValueError:
        raise HarnessOutcomeError(result, case, "malformed_fields") from None
    required = {"runtime_bound", "messenger_contract", "initialized", "progressed", "rejected", "timed_out",
                "start_configured", "landing_confirmed", "initial_paused", "play_released",
                "delay_exercised", "ignored_start"}
    missing = sorted(required - fields.keys())
    invalid_values = sum(value not in ("0", "1") for value in fields.values())
    if missing or invalid_values:
        raise HarnessOutcomeError(result, case, "invalid_fields",
                                  missing_required_fields=missing,
                                  invalid_value_count=invalid_values)
    return fields


def media_pass(result, fields, audit, positive):
    return (result.returncode == 0 and fields["runtime_bound"] == "1" and
            fields["messenger_contract"] == "1" and fields["initialized"] == "1" and
            fields["timed_out"] == "0" and audit["A_token"] and not audit["B_token"] and
            not audit["secondary_A_token"] and not audit["token_in_url"] and
            not audit["server_error"] and
            (positive is None or ((fields["initial_paused"] == "1" and fields["play_released"] == "1" and
                                   fields["ignored_start"] == "0" and fields["landing_confirmed"] == "1" and
                                   fields["progressed"] == "1" and fields["rejected"] == "0")
                                  if positive else (fields["progressed"] == "0" and fields["rejected"] == "1"))))


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False

    def handle_error(self, *_):
        # A client rejecting our leaf certificate may reset the connection
        # before HTTP parsing. That is expected in the wrong-CA case, not a
        # fixture failure. Unexpected handler errors still fail the matrix.
        if isinstance(sys.exc_info()[1], (ConnectionResetError, BrokenPipeError, ssl.SSLEOFError)):
            return
        self.failed = True

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(3)
        if self.context is None:
            return connection, address
        try:
            return self.context.wrap_socket(connection, server_side=True), address
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
            self.server.requests.append((self.path, any(TOKEN in value for _, value in self.headers.items()), token_url))
            if range_header:
                self.server.range_requests = getattr(self.server, "range_requests", 0) + 1
        if self.server.authenticated and self.headers.get("X-Plex-Token") != TOKEN:
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path.startswith("/redirect"):
            self.send_response(302)
            self.send_header("Location", self.server.redirect)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body, content_type = self.server.files.get(self.path, (b"", "application/octet-stream"))
        size = len(body)
        first, last = 0, size - 1
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
        self.send_response(206 if partial else 200 if body else 404)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(last - first + 1 if size else 0))
        if partial:
            self.send_header("Content-Range", f"bytes {first}-{last}/{size}")
        self.end_headers()
        if send_body:
            try:
                self.wfile.write(body[first:last + 1])
            except OSError:
                pass

def certificate(root, openssl):
    config = root / "leaf.cnf"
    config.write_text("[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=localhost\n"
                      "[leaf]\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n"
                      "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\n"
                      "extendedKeyUsage=serverAuth\n", encoding="ascii")
    run([openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
         "-subj", "/CN=Lineup temporary test CA", "-addext", "basicConstraints=critical,CA:TRUE",
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


def matrix(args, harness, nonzero_start):
    records = []
    profile = "nonzero-start" if nonzero_start else "omitted-start"
    duration = 6 if nonzero_start else 1
    with tempfile.TemporaryDirectory(prefix="lineup-reference-fixtures-") as temporary:
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
        (OUTPUT / (profile + "-fixture-index.json")).write_text(
            json.dumps(fixture_identity, indent=2) + "\n")
        run([args.ffmpeg, "-v", "error", "-i", str(mp4), "-c", "copy", str(root / "media.mkv")])
        run([args.ffmpeg, "-v", "error", "-i", str(mp4), "-c", "copy", "-f", "mpegts", str(root / "segment.ts")])
        run([args.ffmpeg, "-v", "error", "-i", str(mp4), "-c", "copy", "-f", "dash", str(root / "media.mpd")])
        servers = []
        threads = []
        try:
            # Two HTTPS origins plus a real plaintext downgrade destination.
            # HTTP tokens must reach the handler/audit rather than disappear in
            # a TLS handshake failure before request parsing.
            for transport in (context, context, None):
                server = Server(("127.0.0.1", 0), Handler)
                server.context = transport
                server.failed = False
                server.authenticated = len(servers) == 0
                server.lock = threading.Lock()
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
                            "server_error": any(server.failed for server in servers)}

            def invoke(name, path, ca="ca.pem", mode=None):
                for server in servers:
                    with server.lock:
                        server.requests.clear()
                        server.range_requests = 0
                        server.partial_responses = 0
                command = [str(harness), str(root / ca), origin_a + path]
                if mode:
                    command.append(mode)
                if nonzero_start:
                    command.append("--nonzero-start")
                result = captured(command, timeout=22, label=profile + "-" + name)
                fields = outcomes(result, name)
                if fields["start_configured"] != str(int(nonzero_start)):
                    raise HarnessOutcomeError(result, name, "wrong_start_profile")
                return result, fields, audit(path)

            def record(name, passed, fields, observed, **extra):
                row = {"case": name, "start_profile": profile, "pass": bool(passed), **observed, **fields, **extra}
                records.append(row)
                print(json.dumps(row, sort_keys=True), flush=True)

            for name, path, body, positive in cases:
                if body:
                    a.files[path] = (body, "application/dash+xml" if name == "dash" else "application/octet-stream")
                a.redirect = (f"http://127.0.0.1:{plain.server_port}/media.mp4" if name == "redirect-http"
                              else origin_b + "/media.mp4")
                result, fields, observed = invoke(name, path, mode="observe" if positive is None else None)
                record(name, media_pass(result, fields, observed, positive), fields, observed,
                       scope="bounded-observation" if positive is None else
                             "ordinary-media-positive" if positive else "reference-fails-closed")

                if name == "redirect-http":
                    # Keep the real rejected/no-progress result and A audit,
                    # then deliberately send a token to the plaintext target.
                    # The same classifier must detect that secondary leak.
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
                    record("control-http-token", passed, fields, observed,
                           scope="plaintext-token-detected")

            for option in ("access-references", "autoload-files"):
                result, fields, observed = invoke("reject-option-" + option, "/media.mp4", mode=option)
                passed = (result.returncode == 0 and fields["initialized"] == "0" and
                          fields["runtime_bound"] == "1" and fields["messenger_contract"] == "1" and
                          fields["rejected"] == "1" and fields["progressed"] == "0" and
                          fields["timed_out"] == "0" and observed["A_requests"] == 0 and
                          observed["B_requests"] == 0 and not observed["server_error"])
                record("reject-option-" + option, passed, fields, observed)

            run([args.openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                 "-subj", "/CN=Lineup untrusted test CA", "-keyout", str(root / "wrong.key"),
                 "-out", str(root / "wrong.pem")], label="wrong-ca-generation")
            result, fields, observed = invoke("untrusted-ca", "/media.mp4", ca="wrong.pem")
            passed = (result.returncode == 0 and fields["initialized"] == "1" and
                      fields["runtime_bound"] == "1" and fields["messenger_contract"] == "1" and
                      fields["rejected"] == "1" and fields["progressed"] == "0" and
                      fields["timed_out"] == "0" and observed["A_requests"] == 0 and
                      observed["B_requests"] == 0 and not observed["server_error"])
            record("untrusted-ca", passed, fields, observed)

            # These deliberate violations live solely in injected test operations
            # or the event collector. A control passes only if the real checker
            # detects the weaker behavior; it cannot turn a production case green.
            result, fields, observed = invoke("control-late-error", "/media.mp4", mode="control-late-error")
            positive_rejected = not media_pass(result, fields, observed, True)
            negative_rejected = not media_pass(result, fields, observed, False)
            passed = (result.returncode == 0 and fields["progressed"] == "1" and
                      fields["rejected"] == "1" and positive_rejected and negative_rejected)
            record("control-late-error", passed, fields, observed, scope="progress-then-error-detected",
                   positive_classifier_rejected=positive_rejected,
                   negative_classifier_rejected=negative_rejected)

            result, fields, observed = invoke("control-disable-tls", "/media.mp4", ca="wrong.pem", mode="control-disable-tls")
            passed = media_pass(result, fields, observed, True) and observed["A_requests"] > 0
            record("control-disable-tls", passed, fields, observed, scope="wrong-ca-detection-sensitive")

            result, fields, observed = invoke("control-allow-references", "/port.m3u8", mode="control-allow-references")
            passed = (result.returncode == 0 and fields["initialized"] == "1" and
                      observed["B_requests"] > 0 and not media_pass(result, fields, observed, False))
            record("control-allow-references", passed, fields, observed, scope="reference-policy-detection-sensitive")
            if nonzero_start:
                result, fields, observed = invoke("control-delayed-start", "/media.mp4", mode="control-delayed-start")
                passed = (media_pass(result, fields, observed, True) and fields["delay_exercised"] == "1" and
                          observed["A_partial_responses"] > 0)
                record("control-delayed-start", passed, fields, observed, scope="stationary-landing-after-delayed-consumption")
                result, fields, observed = invoke("control-ignore-start-delayed", "/media.mp4", mode="control-ignore-start-delayed")
                passed = (media_pass(result, fields, observed, None) and fields["delay_exercised"] == "1" and
                          fields["ignored_start"] == "1" and fields["initial_paused"] == "1" and
                          fields["play_released"] == "1" and fields["landing_confirmed"] == "0" and
                          fields["progressed"] == "0" and fields["rejected"] == "0" and
                          not media_pass(result, fields, observed, True))
                record("control-ignore-start-delayed", passed, fields, observed, scope="ignored-start-detected-after-delayed-consumption")
        finally:
            for server, thread in zip(servers, threads):
                if thread.is_alive():
                    server.shutdown()
                server.server_close()
            for thread in threads:
                thread.join(timeout=3)
                if thread.is_alive():
                    raise RuntimeError("server_termination_timeout")
    expected = {name for name, *_ in cases} | {
        "control-http-token", "reject-option-access-references", "reject-option-autoload-files",
        "untrusted-ca", "control-late-error", "control-disable-tls", "control-allow-references"}
    if nonzero_start:
        expected |= {"control-delayed-start", "control-ignore-start-delayed"}
    if len(records) != (28 if nonzero_start else 26) or {row["case"] for row in records} != expected:
        raise RuntimeError("incomplete_profile_matrix")
    return records


def main():
    global DEADLINE, OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=pathlib.Path,
                        default=REPO / "build/macos-runtime/dist/arm64")
    parser.add_argument("--flutter-root", type=pathlib.Path, default=os.environ.get("FLUTTER_ROOT"))
    parser.add_argument("--output-dir", type=pathlib.Path)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--openssl", default="openssl")
    parser.add_argument("--ffprobe", default="ffprobe")
    args = parser.parse_args()
    if sys.platform != "darwin" or not args.flutter_root:
        raise RuntimeError("macos_and_prepared_flutter_required")
    DEADLINE = time.monotonic() + 600
    OUTPUT = args.output_dir or pathlib.Path(tempfile.mkdtemp(prefix="lineup-macos-reference-"))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    OUTPUT = OUTPUT.resolve()
    if any(OUTPUT.iterdir()):
        raise RuntimeError("output_directory_must_be_empty")
    args.runtime = args.runtime.resolve(strict=True)
    args.flutter_root = args.flutter_root.resolve(strict=True)
    args.ffmpeg, args.openssl = tool(args.ffmpeg), tool(args.openssl)
    args.ffprobe = tool(args.ffprobe)
    cmake = tool("cmake")
    identity = validate_runtime(args.runtime, args.flutter_root)
    source_paths = [*pathlib.Path(__file__).parent.glob("*.*"),
                    *[REPO / "macos/Runner/NativePlayer" / name for name in
                      ("LineupNativePlayer.h", "LineupNativePlayer.mm", "FoundationValueConversion.h",
                       "FoundationValueConversion.mm", "VideoGeometry.h", "VideoGeometry.mm")],
                    *(REPO / "native/player_core").glob("*.h"),
                    *[REPO / "native/player_core" / name for name in
                      ("player_core.cpp", "subtitle_cues.cpp", "libmpv_operations.cpp", "platform_arguments.cpp", "track_list_encoder.cpp")]]
    source_hashes = {str(path.relative_to(REPO)): sha(path) for path in source_paths if path.is_file()}
    metadata = {"runtime": identity, "source_files": source_hashes,
                "source_head": run(["git", "-C", str(REPO), "rev-parse", "HEAD"], label="source-head").decode().strip()}
    (OUTPUT / "identity.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"runtime_identity": identity, "source_head": metadata["source_head"]}), flush=True)
    build = OUTPUT / "build"
    run([cmake, "-S", str(pathlib.Path(__file__).parent), "-B", str(build),
         "-DCMAKE_BUILD_TYPE=Debug", "-DCMAKE_OSX_ARCHITECTURES=arm64",
         "-DCMAKE_CXX_COMPILER=/usr/bin/clang++", "-DCMAKE_OBJCXX_COMPILER=/usr/bin/clang++",
         "-DLINEUP_MPV_RUNTIME=" + str(args.runtime), "-DFLUTTER_ROOT=" + str(args.flutter_root)],
        timeout=90, label="configure")
    run([cmake, "--build", str(build), "--parallel", "2"], timeout=120, label="build")
    harness = build / "authenticated-reference"
    if not harness.is_file():
        raise RuntimeError("missing_harness")
    metadata["harness_sha256"] = sha(harness)
    (OUTPUT / "identity.json").write_text(json.dumps(metadata, indent=2) + "\n")
    records = [row for nonzero_start in (False, True)
               for row in matrix(args, harness, nonzero_start)]
    # Empty, partial, or accidentally narrowed test selections cannot pass.
    passed = len(records) == 54 and all(row["pass"] for row in records)
    report = {"pass": passed, "cases": records, "runtime": identity,
              "harness_sha256": metadata["harness_sha256"], "source_head": metadata["source_head"]}
    (OUTPUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"pass": passed, "case_count": len(records), "output_dir": str(OUTPUT)}), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        # Exception text can contain tool diagnostics, paths, headers, or URLs.
        reason = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        failure = {"pass": False, "prerequisite_error": reason}
        if isinstance(error, HarnessOutcomeError):
            failure["harness_outcome"] = error.summary
        print(json.dumps(failure), flush=True)
        raise SystemExit(2)
