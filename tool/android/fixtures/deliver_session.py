#!/usr/bin/env python3
"""Deliver an authorized E6 capability from stdin to an assigned emulator, in memory only."""
import argparse
import json
import os
import select
import time
import re
import socket
import subprocess
import sys
import urllib.parse

MAX_BYTES = 32768
DEVICE_PORT = 18445


class InputRefused(Exception):
    pass


class QuietParser(argparse.ArgumentParser):
    def error(self, _message):
        raise InputRefused()


def validate(data):
    try:
        if len(data) > MAX_BYTES:
            raise InputRefused()
        value = json.loads(data)
        if not isinstance(value, dict) or set(value) - {'variant', 'offsetSeconds', 'observeSeconds'}:
            raise InputRefused()
        uri = value['variant']
        offset = value['offsetSeconds']
        seconds = value.get('observeSeconds', 8)
        if not isinstance(uri, str) or type(offset) is not int or not 0 <= offset <= 86400:
            raise InputRefused()
        if type(seconds) is not int or not 1 <= seconds <= 30:
            raise InputRefused()
        parsed = urllib.parse.urlsplit(uri)
        if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None or
                parsed.password is not None or parsed.fragment or
                any(key.lower() == 'x-plex-token' for key, _ in urllib.parse.parse_qsl(parsed.query, keep_blank_values=True))):
            raise InputRefused()
        return data
    except Exception:
        # Neither parser errors nor caller-provided fields may reach stderr.
        raise InputRefused() from None


def deliver(data, serial, port):
    if not re.fullmatch(r'emulator-[0-9]+', serial) or not 1024 <= port <= 65535:
        raise InputRefused()
    data = validate(data)
    # Require an already-created mapping owned by this explicit emulator. Never
    # create/reassign forwards, launch an app, or touch a physical target here.
    result = subprocess.run(['adb', '-s', serial, 'forward', '--list'], capture_output=True, check=True, timeout=10)
    expected = [serial, f'tcp:{port}', f'tcp:{DEVICE_PORT}']
    if expected not in [line.split() for line in result.stdout.decode().splitlines()]:
        raise InputRefused()
    deadline = time.monotonic() + 10
    with socket.create_connection(('127.0.0.1', port), timeout=10) as peer:
        peer.settimeout(max(.001, deadline - time.monotonic()))
        peer.sendall(data)
        peer.shutdown(socket.SHUT_WR)
        reply = bytearray()
        while len(reply) < 32:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise InputRefused()
            peer.settimeout(remaining)
            chunk = peer.recv(32 - len(reply))
            if not chunk:
                break
            reply.extend(chunk)
        if reply != b'accepted\n':
            raise InputRefused()


def read_input(stream):
    deadline = time.monotonic() + 10
    data = bytearray()
    while len(data) <= MAX_BYTES:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([stream], [], [], remaining)[0]:
            raise InputRefused()
        chunk = os.read(stream.fileno(), min(4096, MAX_BYTES + 1 - len(data)))
        if not chunk:
            return bytes(data)
        data.extend(chunk)
    raise InputRefused()


def main():
    try:
        parser = QuietParser(description=__doc__)
        parser.add_argument('--serial', required=True, help='explicit assigned emulator-N serial')
        parser.add_argument('--port', required=True, type=int, help='explicit existing emulator forward port')
        args = parser.parse_args()
        if sys.stdin.isatty():
            raise InputRefused()
        data = read_input(sys.stdin.buffer)
        deliver(data, args.serial, args.port)
    except Exception:
        print('E6_INPUT_REFUSED', file=sys.stderr)
        return 1
    print('E6_INPUT_ACCEPTED')
    return 0


if __name__ == '__main__':
    sys.exit(main())
