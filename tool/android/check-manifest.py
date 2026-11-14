#!/usr/bin/env python3
"""Check the Android Back opt-in and exclude debug configuration from release APKs."""
import argparse
import sys
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


ANDROID = '{http://schemas.android.com/apk/res/android}'


def check(xml: str) -> None:
    app = ET.fromstring(xml).find('application')
    if app is None or app.get(ANDROID + 'enableOnBackInvokedCallback') != 'true':
        raise ValueError('application must enable OnBackInvokedCallback for API 33–35 Back')


def check_release(xml: str, extraction_reference='@xml/data_extraction_rules') -> None:
    check(xml)
    app = ET.fromstring(xml).find('application')
    for name, expected in {
        'allowBackup': 'false',
        'fullBackupContent': 'false',
        'dataExtractionRules': extraction_reference,
        'usesCleartextTraffic': 'false',
    }.items():
        if app.get(ANDROID + name) != expected:
            raise ValueError(f'release application must set {name}={expected}')
    if app.get(ANDROID + 'debuggable') not in (None, 'false'):
        raise ValueError('release application must not be debuggable')
    if ANDROID + 'networkSecurityConfig' in app.attrib:
        raise ValueError('release application must not declare networkSecurityConfig')


def check_extraction_rules(xml: str) -> None:
    root = ET.fromstring(xml)
    if root.tag != 'data-extraction-rules':
        raise ValueError('expected data-extraction-rules')
    domains = {'root', 'file', 'database', 'sharedpref', 'external',
               'device_root', 'device_file', 'device_database', 'device_sharedpref'}
    for mode in ('cloud-backup', 'device-transfer'):
        sections = root.findall(mode)
        if len(sections) != 1:
            raise ValueError(f'extraction rules require one {mode} section')
        section = sections[0]
        excluded = {entry.get('domain') for entry in section.findall('exclude')
                    if entry.get('path') == '.'}
        if section.findall('include') or not domains.issubset(excluded):
            raise ValueError(f'extraction rules must exclude every domain in {mode}')


def check_packaged(apk: Path, analyzer: Path, aapt2: Path) -> None:
    def run(*arguments):
        return subprocess.check_output([str(argument) for argument in arguments], text=True)

    xml = run(analyzer, 'manifest', 'print', apk)
    table = run(aapt2, 'dump', 'resources', apk)
    resources = re.findall(
        r'^[ \t]*resource (0x[0-9a-f]+) xml/data_extraction_rules[ \t]*\n'
        r'((?:[ \t]+\([^\n]*\n?)+)', table, re.MULTILINE)
    if len(resources) != 1:
        raise ValueError('APK must contain one named data_extraction_rules resource')
    identifier, configurations = resources[0]
    values = configurations.strip().splitlines()
    if len(values) != 1 or not values[0].startswith('() (file) '):
        raise ValueError('extraction rules must have one default configuration')
    check(xml)
    reference = ET.fromstring(xml).find('application').get(ANDROID + 'dataExtractionRules')
    expected = ('@xml/data_extraction_rules' if reference == '@xml/data_extraction_rules'
                else '@ref/' + identifier)
    check_release(xml, extraction_reference=expected)
    # Resource shrinking can rename the packaged XML path. Resolve the named
    # resource instead of assuming its source filename survives packaging.
    resource_path = run(analyzer, 'resources', 'value', '--type', 'xml',
                        '--name', 'data_extraction_rules', '--config', 'default', apk).strip()
    rules = run(analyzer, 'resources', 'xml', '--file', resource_path, apk)
    check_extraction_rules(rules)


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
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--apkanalyzer', type=Path)
    parser.add_argument('--aapt2', type=Path)
    parser.add_argument('--extraction-rules', type=Path)
    parser.add_argument('--reject-entry-bytes', nargs=2, type=Path, metavar=('FILE', 'APK'))
    args = parser.parse_args()
    if args.apk:
        if args.manifest or args.release or args.reject_entry_bytes or args.extraction_rules:
            parser.error('--apk cannot be combined with source checks')
        if not args.apkanalyzer or not args.aapt2:
            parser.error('--apk requires --apkanalyzer and --aapt2')
        check_packaged(args.apk, args.apkanalyzer, args.aapt2)
    elif args.reject_entry_bytes:
        if args.manifest is not None or args.release:
            parser.error('--reject-entry-bytes cannot be combined with a manifest check')
        reject_entry_bytes(*args.reject_entry_bytes)
    else:
        if args.manifest is None:
            parser.error('provide a manifest or --reject-entry-bytes FILE APK')
        xml = sys.stdin.read() if args.manifest == '-' else Path(args.manifest).read_text()
        (check_release if args.release else check)(xml)
        if args.release:
            if args.extraction_rules is None:
                parser.error('--release requires --extraction-rules')
            rules = (sys.stdin.read() if str(args.extraction_rules) == '-'
                     else args.extraction_rules.read_text())
            check_extraction_rules(rules)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, ET.ParseError, OSError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        sys.exit(f'Android release check failed: {error}')
