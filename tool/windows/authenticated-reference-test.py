"""Gated pinned-libmpv containment test; only normalized outcomes leave the run."""

import argparse
import hashlib
import http.server
import json
import pathlib
import shutil
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
import time


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
        # Tool output can contain paths, URLs or headers. Never emit it.
        raise RuntimeError("fixture tool failed")
    return result.stdout


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False

    def handle_error(self, *_):
        self.failed = True

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(3)
        try:
            return self.context.wrap_socket(connection, server_side=True), address
        except BaseException:
            connection.close()
            raise


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        with self.server.lock:
            self.server.requests.append((self.path, self.headers.get("X-Plex-Token") == TOKEN))
        if self.server.authenticated and self.headers.get("X-Plex-Token") != TOKEN:
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body, content_type = self.server.files.get(self.path, (b"", "application/octet-stream"))
        if self.path.startswith("/redirect"):
            self.send_response(302)
            self.send_header("Location", self.server.redirect)
        else:
            self.send_response(200 if body else 404)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except OSError:
            pass


def certificate(root, openssl):
    # No OS trust-store writes. Both names are covered; libmpv receives CA file.
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
    args = parser.parse_args()
    if not args.openssl:
        git_openssl = pathlib.Path("C:/Program Files/Git/usr/bin/openssl.exe")
        if git_openssl.is_file():
            args.openssl = str(git_openssl)
    if not args.ffmpeg or not args.openssl:
        raise RuntimeError("ffmpeg and openssl are required")
    for dll in (args.dll, args.harness.parent / "libmpv-2.dll"):
        if hashlib.sha256(dll.read_bytes()).hexdigest() != DLL_SHA256:
            raise RuntimeError("pinned DLL hash mismatch")
    failures = 0
    with tempfile.TemporaryDirectory(prefix="lineup-reference-") as temporary:
        root = pathlib.Path(temporary)
        context = certificate(root, args.openssl)
        mp4 = root / "media.mp4"
        run([args.ffmpeg, "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x64:r=10",
             "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4)])
        run([args.ffmpeg, "-v", "error", "-i", str(mp4), "-c", "copy", str(root / "media.mkv")])
        run([args.ffmpeg, "-v", "error", "-i", str(mp4), "-c", "copy", "-f", "mpegts", str(root / "segment.ts")])
        run([args.ffmpeg, "-v", "error", "-i", str(mp4), "-c", "copy", "-f", "dash", str(root / "media.mpd")])
        servers = []
        threads = []
        try:
            for _ in range(2):
                server = Server(("127.0.0.1", 0), Handler)
                server.context = context
                server.failed = False
                server.authenticated = len(servers) == 0
                server.lock = threading.Lock()
                server.requests = []
                server.files = {"/" + f.name: (f.read_bytes(), "application/octet-stream")
                                for f in root.iterdir() if f.suffix in (".mp4", ".mkv", ".ts", ".m4s")}
                servers.append(server)
                thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True)
                thread.start()
                threads.append(thread)
            a, b = servers
            origin_a = f"https://127.0.0.1:{a.server_port}"
            origin_b = f"https://127.0.0.1:{b.server_port}"
            hostname_b = f"https://localhost:{b.server_port}"

            def hls(url):
                return ("#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\n" + url + "\n#EXT-X-ENDLIST\n").encode()

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
            for name, path, body, positive in cases:
                if body:
                    a.files[path] = (body, "application/dash+xml" if name == "dash" else "application/octet-stream")
                a.redirect = ("http" if name == "redirect-http" else "https") + f"://127.0.0.1:{b.server_port}/media.mp4"
                for server in servers:
                    with server.lock:
                        server.requests.clear()
                command = [str(args.harness), str(root / "ca.pem"), origin_a + path]
                if positive is None:
                    command.append("observe")
                result = subprocess.run(command,
                                        capture_output=True, timeout=remaining(22))
                outcomes = dict(field.split("=") for field in result.stdout.decode("ascii").strip().split())
                with a.lock, b.lock:
                    a_token = any(token for request_path, token in a.requests if request_path == path)
                    b_token = any(token for _, token in b.requests)
                    sidecar_token = any(token for request_path, token in a.requests if request_path != path)
                    counts = (len(a.requests), len(b.requests))
                passed = (result.returncode == 0 and not a.failed and not b.failed and a_token and not b_token and
                          not sidecar_token and
                          (positive is None or (outcomes.get("progressed") == "1" if positive else outcomes.get("rejected") == "1")))
                if name == "vobsub":
                    passed = passed and not sidecar_token
                if name == "hls-same-origin":
                    passed = passed and not sidecar_token
                failures += not passed
                print(json.dumps({"case": name, "pass": passed, "A_requests": counts[0],
                                  "A_token": a_token, "B_requests": counts[1], "B_token": b_token,
                                  "secondary_A_token": sidecar_token, **outcomes}), flush=True)
            for option in ("access-references", "autoload-files"):
                with a.lock, b.lock:
                    a.requests.clear()
                    b.requests.clear()
                result = subprocess.run([str(args.harness), str(root / "ca.pem"), origin_a + "/media.mp4", option],
                                        capture_output=True, timeout=remaining(22))
                with a.lock, b.lock:
                    passed = result.returncode == 0 and not a.requests and not b.requests
                failures += not passed
                print(json.dumps({"case": "reject-option-" + option, "pass": passed,
                                  "A_requests": len(a.requests), "B_requests": len(b.requests)}), flush=True)

            run([args.openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                 "-subj", "/CN=Lineup untrusted test CA", "-keyout", str(root / "wrong.key"),
                 "-out", str(root / "wrong.pem")])
            with a.lock, b.lock:
                a.requests.clear()
                b.requests.clear()
            result = subprocess.run([str(args.harness), str(root / "wrong.pem"), origin_a + "/media.mp4"],
                                    capture_output=True, timeout=remaining(22))
            outcomes = dict(field.split("=") for field in result.stdout.decode("ascii").strip().split())
            with a.lock, b.lock:
                passed = result.returncode == 0 and outcomes.get("rejected") == "1" and not a.requests and not b.requests
            failures += not passed
            print(json.dumps({"case": "untrusted-ca", "pass": passed,
                              "A_requests": len(a.requests), "B_requests": len(b.requests)}), flush=True)
        finally:
            for server in servers:
                server.shutdown()
                server.server_close()
            for thread in threads:
                thread.join(timeout=3)
                if thread.is_alive():
                    raise RuntimeError("server termination timed out")
    return int(failures != 0)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
        print("FAIL: fixture, runtime, or bounded-wait prerequisite", flush=True)
        raise SystemExit(2)
