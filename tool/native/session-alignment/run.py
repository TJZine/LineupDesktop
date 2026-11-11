#!/usr/bin/env python3
"""Offline, pinned-runtime session alignment through the desktop adapters."""

import argparse
from fractions import Fraction
import hashlib
import importlib.util
import json
import os
import platform
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time

REPO = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "reference_fixture", REPO / "tool/windows/authenticated-reference-test.py"
)
REFERENCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REFERENCE)
PREFIX = REFERENCE.SESSION_PREFIX
CASES = [
    ("copy-10", "copy", 10, True),
    ("copy-21", "copy", 21, True),
    ("copy-605", "copy", 605, True),
    ("encode-10", "encode", 10, True),
    ("encode-605", "encode", 605, True),
    ("encode-10.5", "encode", 10.5, True),
    ("copy-0", "copy", 0, True),
    ("alternate-gop", "alternate", 21, True),
    ("running", "copy", 21, False),
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def tool_output(command, *, data=None):
    result = subprocess.run(command, input=data, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError("Fixture tool failed")
    return result.stdout


def boxes(data, start=0, end=None):
    end = len(data) if end is None else end
    while start < end:
        length, kind = struct.unpack_from(">I4s", data, start)
        if length < 8 or start + length > end:
            raise ValueError("Invalid synthetic MP4 box")
        yield kind, start + 8, start + length
        start += length


def shift_fragment(fragment, shift, video_scale):
    result = bytearray(fragment)
    for kind, start, end in boxes(fragment):
        if kind != b"moof":
            continue
        for kind, start, end in boxes(fragment, start, end):
            if kind != b"traf":
                continue
            children = {key: begin for key, begin, _ in boxes(fragment, start, end)}
            track = struct.unpack_from(">I", fragment, children[b"tfhd"] + 4)[0]
            position = children[b"tfdt"]
            version = fragment[position]
            scale = {1: video_scale, 2: 48000}[track]
            ticks = shift * scale
            if version not in (0, 1) or ticks.denominator != 1:
                raise ValueError("Invalid synthetic fragment shift")
            field = ">Q" if version else ">I"
            timestamp = struct.unpack_from(field, fragment, position + 4)[0]
            struct.pack_into(field, result, position + 4, timestamp + int(ticks))
    return bytes(result)


class Corpus:
    def __init__(self, mode, ffmpeg, ffprobe, frozen):
        self.duration = 10 if mode == "copy" else 5
        self.fps = Fraction(24000, 1001) if mode == "copy" else Fraction(24)
        self.video_scale = 24000 if mode == "copy" else 12288
        self.first = 48 / self.fps if mode == "copy" else Fraction(self.duration)
        self.gop = 239 / self.fps if mode == "copy" else Fraction(self.duration)
        if mode == "alternate":
            self.gop = Fraction(2)
            self.duration = 2
            self.first = self.gop
        keys = {
            "copy": "2.002,11.970291667,21.938583333",
            "encode": "5,10,15",
            "alternate": "2,4,6",
        }[mode]
        seconds = {"copy": "24", "encode": "16", "alternate": "8"}[mode]
        self.command = [
            "-v", "error", "-f", "lavfi", "-i", f"testsrc2=size=96x54:rate={self.fps}",
            "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
            "-t", seconds, "-c:v", "libx264", "-preset", "ultrafast",
            "-pix_fmt", "yuv420p", "-g", "1000", "-keyint_min", "1",
            "-sc_threshold", "0", "-bf", "2", "-force_key_frames", keys,
            "-c:a", "aac", "-b:a", "32k", "-video_track_timescale", str(self.video_scale),
            "-movflags", "frag_keyframe+empty_moov+default_base_moof", "-f", "mp4", "pipe:1",
        ]
        if frozen and mode != "alternate":
            self.init = (frozen / f"{mode}-init.mp4").read_bytes()
            self.template = (frozen / f"{mode}-template.m4s").read_bytes()
            self.intro = (frozen / "copy-intro.m4s").read_bytes() if mode == "copy" else None
        else:
            data = tool_output([ffmpeg, *self.command])
            fragments = []
            self.init = b""
            for kind, start, end in boxes(data):
                if kind in (b"ftyp", b"moov"):
                    self.init += data[start - 8:end]
                elif kind == b"moof":
                    fragment_start = start - 8
                elif kind == b"mdat":
                    fragments.append(data[fragment_start:end])
            self.intro = fragments[0] if mode == "copy" else None
            self.template = fragments[1]
        self.probe = ffprobe

    def keyframe(self, index):
        nominal = index * self.duration
        if self.intro is not None and index == 0:
            return Fraction(0)
        return self.first + ((nominal - self.first) // self.gop) * self.gop

    def fragment(self, index):
        if self.intro is not None and index == 0:
            return shift_fragment(self.intro, Fraction(10), self.video_scale)
        source = self.keyframe(index)
        count = int((self.keyframe(index + 1) - source) / self.gop)
        if count not in (1, 2):
            raise ValueError("Unexpected synthetic GOP grid")
        return b"".join(shift_fragment(
            self.template, source + self.gop * step + 10 - self.first, self.video_scale
        ) for step in range(count))

    def manifest(self, offset):
        tags = [
            "#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-PLAYLIST-TYPE:VOD",
            f"#EXT-X-TARGETDURATION:{self.duration}", "#EXT-X-MEDIA-SEQUENCE:0",
            f"#EXT-X-START:TIME-OFFSET={offset}", '#EXT-X-MAP:URI="init.mp4"',
        ]
        for index in range(1300 // self.duration):
            tags.extend([f"#EXTINF:{self.duration},synthetic", f"{index}.m4s"])
        return ("\n".join([*tags, "#EXT-X-ENDLIST"]) + "\n").encode()

    def packet_proof(self, fragment):
        data = tool_output([
            self.probe, "-v", "error", "-protocol_whitelist", "pipe",
            "-select_streams", "v:0", "-show_packets",
            "-show_entries", "packet=pts_time,dts_time,flags", "-of", "json", "pipe:0",
        ], data=self.init + fragment)
        packets = json.loads(data)["packets"]
        if not packets or "K" not in packets[0]["flags"]:
            raise ValueError("Synthetic fragment did not start at a keyframe")
        return {"first": packets[0], "frames": len(packets)}


class BoundedHandler(REFERENCE.Handler):
    def serve_resource(self, send_body):
        with self.server.lock:
            if len(self.server.requests) >= 64:
                self.server.failed = True
                self.send_error(429)
                return
        super().serve_resource(send_body)


def run_case(args, root, context, name, corpus, offset, paused, isolation=False):
    containing = int(offset // corpus.duration)
    retained = max(0, containing - 1)
    payload = corpus.manifest(offset)
    manifest = root / "variant.m3u8"
    manifest.write_bytes(payload)
    # Provide the complete source if the demuxer reads ahead. Keep the omitted
    # prefix available too so accidental reads are observable and fail.
    fragments = {index: corpus.fragment(index) for index in range(1300 // corpus.duration)}
    server = REFERENCE.Server(("127.0.0.1", 0), BoundedHandler)
    server.context = context
    server.authenticated = False
    server.requests = []
    server.track_bodies = True
    server.files = {
        f"{PREFIX}/{index}.m4s": (data, "video/iso.segment")
        for index, data in fragments.items()
    }
    server.files[f"{PREFIX}/init.mp4"] = (corpus.init, "video/mp4")
    if isolation:
        server.files["/direct.mp4"] = (corpus.init + fragments[0], "video/mp4")
    origin = f"https://127.0.0.1:{server.server_port}"
    thread = threading.Thread(target=server.serve_forever,
                              kwargs={"poll_interval": 0.05}, daemon=True)
    thread.start()
    try:
        command = [
            str(args.harness), "--alignment", str(root / "ca.pem"),
            f"{origin}{PREFIX}/index.m3u8", str(manifest), str(round(offset * 1000000)),
            str(corpus.duration), "paused" if paused else "running",
        ]
        if isolation:
            command.append(origin + "/direct.mp4")
        result = subprocess.run(command, capture_output=True, timeout=40,
                                env=fixture_environment())
        if len(result.stdout) > 8192 or len(result.stderr) > 65536:
            raise RuntimeError("Fixture output exceeded its bound")
        # The adapter driver prints only closed numeric records and enums.
        # Discard runtime stderr, which is outside the fixture record schema.
        native = [json.loads(line) for line in result.stdout.splitlines() if line.startswith(b"{")]
        responses = server.wait_for_responses(server.files, timeout=3)
        with server.lock:
            requests = list(server.requests)
            connection_count = server.accepted_connections
            server_failed = server.failed
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=4)
    requested_indices = [
        int(path.removeprefix(PREFIX + "/").removesuffix(".m4s"))
        for path, _, _ in requests
        if path in server.files and path.endswith(".m4s")
    ]
    bytes_written = sum(row["bytes"] for row in responses)
    counts = [row for row in native if "outcome" in row]
    passed = (
        result.returncode == 0 and len(counts) == (2 if isolation else 1)
        and all(row["pass"] for row in counts)
        and native[0].get("mpvVersion") and native[0].get("ffmpegVersion")
        and native[-1].get("restored") is True
        and (not isolation or any(row.get("directRestored") is True for row in native))
        and not thread.is_alive() and not server_failed and not server.failed
        and requested_indices and requested_indices[0] == retained
        and min(requested_indices) == retained
        and all(path in server.files and not header and not query for path, header, query in requests)
        and 0 < bytes_written <= 32 * 1024 * 1024
    )
    return {
        "case": name, "containing": containing, "retained": retained, "offset": offset,
        "mode": "paused" if paused else "running", "pass": bool(passed),
        "harnessExit": result.returncode, "native": native,
        "fixtureRequests": len(requests), "fixtureBytes": bytes_written,
        "acceptedConnections": connection_count, "requests": responses,
        "serverErrors": server.errors, "serverFailed": server_failed or server.failed,
        "manifestSha256": sha(payload), "initSha256": sha(corpus.init),
        "fragmentSha256": {str(index): sha(fragments[index]) for index in set(requested_indices)},
        "containingPackets": corpus.packet_proof(fragments[containing]),
        "retainedPackets": corpus.packet_proof(fragments[retained]),
        "predecessorRequests": requested_indices.count(retained) if retained < containing else 0,
        "predecessorBytes": sum(row["bytes"] for row in responses
                                if retained < containing and row["path"] == f"{PREFIX}/{retained}.m4s"),
    }


def fixture_environment():
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("DYLD_")
           and key.lower() not in {"http_proxy", "https_proxy", "all_proxy", "no_proxy",
                                   "ssl_cert_file", "ssl_cert_dir", "curl_ca_bundle"}}
    env["NO_PROXY"] = "127.0.0.1,localhost"
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--harness", type=Path, required=True)
    parser.add_argument("--dll", type=Path)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--flutter-root", type=Path)
    parser.add_argument("--frozen-media", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe"))
    parser.add_argument("--openssl", default=shutil.which("openssl"))
    args = parser.parse_args()
    args.harness = args.harness.resolve(strict=True)
    if not args.openssl and args.dll:
        args.openssl = r"C:\Program Files\Git\usr\bin\openssl.exe"
    if args.dll:
        digest = sha(args.dll.read_bytes())
        if digest != REFERENCE.DLL_SHA256 or digest != sha(
            args.harness.with_name("libmpv-2.dll").read_bytes()
        ):
            raise RuntimeError("Pinned Windows DLL hash mismatch")
        runtime = {"libmpvSha256": digest}
    elif args.runtime and args.flutter_root:
        spec = importlib.util.spec_from_file_location(
            "mac_reference", REPO / "tool/macos/authenticated-reference/run.py"
        )
        mac = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mac)
        mac.DEADLINE = time.monotonic() + 120
        mac.OUTPUT = args.output.parent
        runtime = mac.validate_runtime(args.runtime.resolve(), args.flutter_root.resolve())
    else:
        parser.error("Specify a pinned Windows DLL or the macOS runtime and Flutter root")
    results = {
        "runtime": runtime, "platform": platform.system(), "architecture": platform.machine(),
        "harnessSha256": sha(args.harness.read_bytes()),
        "sourceHead": tool_output(["git", "-C", str(REPO), "rev-parse", "HEAD"]).decode().strip(),
        "sourceTree": tool_output(["git", "-C", str(REPO), "rev-parse", "HEAD^{tree}"]).decode().strip(),
        "ffmpeg": tool_output([args.ffmpeg, "-version"]).decode().splitlines()[0],
        "ffprobe": tool_output([args.ffprobe, "-version"]).decode().splitlines()[0],
        "ffmpegSha256": sha(Path(args.ffmpeg).read_bytes()),
        "ffprobeSha256": sha(Path(args.ffprobe).read_bytes()),
        "frozenOriginalMedia": args.frozen_media is not None, "plexRequests": 0, "cells": [],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    REFERENCE.DEADLINE = time.monotonic() + 160
    with tempfile.TemporaryDirectory(prefix="lineup-alignment-") as directory:
        root = Path(directory)
        context = REFERENCE.certificate(root, args.openssl)
        corpora = {mode: Corpus(mode, args.ffmpeg, args.ffprobe, args.frozen_media)
                   for mode in ("copy", "encode", "alternate")}
        results["corpus"] = {
            mode: {"initSha256": sha(corpus.init), "templateSha256": sha(corpus.template),
                   "introSha256": sha(corpus.intro) if corpus.intro else None,
                   "generatorArgs": corpus.command}
            for mode, corpus in corpora.items()
        }
        try:
            for name, mode, offset, paused in CASES:
                row = run_case(args, root, context, name, corpora[mode], offset, paused)
                results["cells"].append(row)
                print(json.dumps(row), flush=True)
                if not row["pass"]:
                    return 1
            row = run_case(args, root, context, "isolation", corpora["copy"], 21, True,
                           isolation=True)
            results["cells"].append(row)
            print(json.dumps(row), flush=True)
            return 0 if row["pass"] else 1
        finally:
            args.output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as error:
        print(f"Desktop session alignment fixture failed ({type(error).__name__}).", file=sys.stderr)
        sys.exit(2)
