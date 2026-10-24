#!/usr/bin/env python3
"""Enforce the Android 33–35 Back callback opt-in on source or APK XML."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def check(xml: str) -> None:
    app = ET.fromstring(xml).find('application')
    attribute = '{http://schemas.android.com/apk/res/android}enableOnBackInvokedCallback'
    if app is None or app.get(attribute) != 'true':
        raise ValueError('application must enable OnBackInvokedCallback for API 33–35 Back')


if __name__ == '__main__':
    try:
        check(sys.stdin.read() if sys.argv[1] == '-' else Path(sys.argv[1]).read_text())
    except (ValueError, ET.ParseError, OSError) as error:
        sys.exit(f'Android manifest check failed: {error}')
