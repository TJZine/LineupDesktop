"""Run against a booted disposable emulator with no installed Lineup Dev app.

Build with flutter build apk --debug --target-platform android-arm,android-arm64.
Set ANDROID_SERIAL to the emulator and run python3 tool/android/startup-e2e.py.
"""

import os
from pathlib import Path
import re
import shlex
import subprocess
import time
import unittest
import xml.etree.ElementTree as ET

PACKAGE = "com.tjzine.lineup.dev"
STORE = "files/Lineup Desktop"
STATE = f"{STORE}/state.json"
APK = Path("build/app/outputs/flutter-apk/app-debug.apk")
UPDATE = "This build is too old to open your saved data."
RECOVERED = "Saved app data was corrupt and has been reset."


class StartupTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        serial = os.environ["ANDROID_SERIAL"]
        if not re.fullmatch(r"emulator-\d+", serial):
            raise RuntimeError("Select a disposable emulator with ANDROID_SERIAL")
        adb = Path(os.environ["ANDROID_HOME"]) / "platform-tools/adb"
        devices = subprocess.check_output([adb, "devices", "-l"], text=True)
        match = re.search(rf"^{serial}\s+device\s+.*transport_id:(\d+)", devices, re.M)
        if not match:
            raise RuntimeError("The selected emulator must be online")
        cls.target = [adb, "-t", match[1]]
        if cls.shell("pm", "list", "packages", PACKAGE).strip():
            raise RuntimeError("Use an emulator without Lineup Dev installed")
        cls.adb("install", str(APK))
        cls.addClassCleanup(cls.adb, "uninstall", PACKAGE)
        cls.tree_path = (
            cls.shell("mktemp", "/data/local/tmp/lineup-ui.XXXXXX").decode().strip()
        )
        cls.addClassCleanup(cls.shell, "rm", "-f", cls.tree_path)

    @classmethod
    def adb(cls, *args, data=None):
        return subprocess.run(
            [*cls.target, *args],
            input=data,
            capture_output=True,
            check=True,
            timeout=90,
        ).stdout

    @classmethod
    def shell(cls, *args, data=None):
        return cls.adb("shell", "-T", shlex.join(args), data=data)

    def as_app(self, *args, data=None):
        return self.shell("run-as", PACKAGE, *args, data=data)

    def setUp(self):
        self.assertEqual(self.shell("pm", "clear", PACKAGE).strip(), b"Success")
        self.as_app("mkdir", "-p", STORE)

    def write(self, path, data):
        self.as_app("sh", "-c", 'cat > "$1"', "sh", path, data=data)

    def launch(self):
        self.shell("am", "start", "-n", PACKAGE + "/com.tjzine.lineup.MainActivity")

    def wait_for_label(self, label, *, absent=None):
        deadline = time.monotonic() + 90
        observed = "waiting for the app window"
        while time.monotonic() < deadline:
            self.shell("sh", "-c", ': > "$1"', "sh", self.tree_path)
            self.shell("uiautomator", "dump", self.tree_path)
            xml = self.shell("cat", self.tree_path)
            if not xml.strip():
                continue
            labels = [
                (node, node.get("content-desc", "") + " " + node.get("text", ""))
                for node in ET.fromstring(xml).iter("node")
                if node.get("package") == PACKAGE
            ]
            if labels:
                observed = "app window"
            for _, text in labels:
                for known in (UPDATE, RECOVERED, "Restart the app", "Sign in to Plex"):
                    if known in text:
                        observed = known
            if absent and any(absent in text for _, text in labels):
                continue
            for node, text in labels:
                if label in text:
                    return node
        self.fail(f"Expected {label!r} (excluded {absent!r}), observed {observed!r}")

    def test_future_format_refuses_startup_and_preserves_files(self):
        future = b'{"formatVersion":2147483647,"futureField":"preserve this"}\n'
        backup = b"existing backup\n"
        self.write(STATE, future)
        self.write(STATE + ".pre-desktop-ui", backup)
        self.launch()
        self.wait_for_label(UPDATE)
        self.assertEqual(self.as_app("cat", STATE), future)
        self.assertEqual(self.as_app("cat", STATE + ".pre-desktop-ui"), backup)
        self.assertEqual(
            self.as_app("find", STORE, "-name", "state.json.corrupt-*"), b""
        )

    def test_invalid_utf8_is_recoverable_after_relaunch(self):
        invalid = b'{"damaged":"\xff"}\n'
        self.write(STATE, invalid)
        self.launch()
        self.wait_for_label(RECOVERED)
        dismiss = self.wait_for_label("Dismiss")
        left, top, right, bottom = map(
            int, re.findall(r"\d+", dismiss.attrib["bounds"])
        )
        self.shell("input", "tap", str((left + right) // 2), str((top + bottom) // 2))
        self.wait_for_label("Sign in to Plex", absent=RECOVERED)
        copies = self.as_app("find", STORE, "-name", "state.json").decode().splitlines()
        self.assertEqual(len(copies), 1)
        self.assertNotEqual(copies[0], STATE)
        self.assertEqual(self.as_app("cat", copies[0]), invalid)
        self.shell("am", "force-stop", PACKAGE)
        self.launch()
        self.wait_for_label("Sign in to Plex", absent=RECOVERED)
        self.assertEqual(self.as_app("cat", copies[0]), invalid)


if __name__ == "__main__":
    unittest.main()
