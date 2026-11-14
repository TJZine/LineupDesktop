#!/usr/bin/env python3
"""Reject JAR signatures and APK Signing Blocks before isolated signing."""
import argparse
from pathlib import Path
import sys
import zipfile


def check(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('corrupt APK entry')
        for name in archive.namelist():
            upper = name.upper()
            if upper.startswith('META-INF/') and upper.endswith(('.SF', '.RSA', '.DSA', '.EC')):
                raise ValueError('APK contains a JAR signing entry')
        # Android v2/v3/v3.1 signatures live immediately before the ZIP central
        # directory. Read the ZIP offset independently of signature verification.
        offset = archive.start_dir
    with path.open('rb') as apk:
        if offset >= 24:
            apk.seek(offset - 16)
            if apk.read(16) == b'APK Sig Block 42':
                raise ValueError('APK contains an APK Signing Block')
    print('APK ZIP integrity checked. No JAR signature or APK Signing Block.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    try:
        check(parser.parse_args().apk)
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
