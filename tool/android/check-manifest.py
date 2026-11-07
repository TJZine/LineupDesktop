#!/usr/bin/env python3
"""Check the Android Back opt-in and exclude debug configuration from release APKs."""
import argparse
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


ANDROID = '{http://schemas.android.com/apk/res/android}'


def check(xml: str) -> None:
    app = ET.fromstring(xml).find('application')
    if app is None or app.get(ANDROID + 'enableOnBackInvokedCallback') != 'true':
        raise ValueError('application must enable OnBackInvokedCallback for API 33–35 Back')


def check_release(xml: str) -> None:
    check(xml)
    app = ET.fromstring(xml).find('application')
    if app.get(ANDROID + 'debuggable') == 'true':
        raise ValueError('release application must not be debuggable')
    if ANDROID + 'networkSecurityConfig' in app.attrib:
        raise ValueError('release application must not declare networkSecurityConfig')


def reject_entry_bytes(file: Path, apk: Path) -> None:
    forbidden = file.read_bytes()
    with zipfile.ZipFile(apk) as archive:
        for entry in archive.infolist():
            if not entry.is_dir() and entry.file_size == len(forbidden):
                if archive.read(entry) == forbidden:
                    raise ValueError('APK contains the forbidden fixture bytes')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', nargs='?', help='manifest path, or - for stdin')
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--reject-entry-bytes', nargs=2, type=Path, metavar=('FILE', 'APK'))
    args = parser.parse_args()
    if args.reject_entry_bytes:
        if args.manifest is not None or args.release:
            parser.error('--reject-entry-bytes cannot be combined with a manifest check')
        reject_entry_bytes(*args.reject_entry_bytes)
    else:
        if args.manifest is None:
            parser.error('provide a manifest or --reject-entry-bytes FILE APK')
        xml = sys.stdin.read() if args.manifest == '-' else Path(args.manifest).read_text()
        (check_release if args.release else check)(xml)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, ET.ParseError, OSError, zipfile.BadZipFile) as error:
        sys.exit(f'Android release check failed: {error}')
