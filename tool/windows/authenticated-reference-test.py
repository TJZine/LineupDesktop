
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
import tempfile
import threading
import time
import urllib.parse


TOKEN = "lineup-synthetic-reference-test"
DLL_SHA256 = "4ba364226fd2ea5dd2c6f2333f0118462da549feed92360fb766a3924e313a51"
DEADLINE = time.monotonic() + 150


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
    if (required - fields.keys() or any(value not in ("0", "1") for value in fields.values()) or
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


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False

    def handle_error(self, *_):
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
    passed = len(records) == 48 and all(row["pass"] for row in records)
    print(json.dumps({"pass": passed, "case_count": len(records)}), flush=True)
    return 0 if passed else 1


def matrix(args, nonzero_start):
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
                record({"case": name, "pass": media_pass(result, fields, observed, positive), **observed, **fields})
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
            for server in servers:
                server.shutdown()
                server.server_close()
            for thread in threads:
                thread.join(timeout=3)
                if thread.is_alive():
                    raise RuntimeError("server termination timed out")
    expected = {name for name, *_ in cases} | {
        "reject-option-access-references", "reject-option-autoload-files", "untrusted-ca", "control-http-token"}
    if nonzero_start:
        expected |= {"control-delayed-start", "control-ignore-start-delayed"}
    if len(records) != (25 if nonzero_start else 23) or {row["case"] for row in records} != expected:
        raise RuntimeError("incomplete_profile_matrix")
    return records


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        print("FAIL: fixture, runtime, or bounded-wait prerequisite", flush=True)
        raise SystemExit(2)
