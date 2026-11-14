#!/usr/bin/env python3
"""Live affected/fixed controls for the maintained scanner, including API errors."""

import json
from pathlib import Path
import subprocess
import sys


def main():
    scanner = sys.argv[1]
    fixtures = Path(__file__).resolve().parent / 'fixtures'
    for fixture, expected_exit in (('affected', 1), ('fixed', 0)):
        result = subprocess.run(
            [scanner, 'scan', 'source', '--format=json',
             f'--lockfile={fixtures / fixture / "pubspec.lock"}'],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode != expected_exit:
            raise RuntimeError(f'{fixture} scanner control failed: {result.stderr}')
        report = json.loads(result.stdout)
        packages = [package for source in report.get('results', [])
                    for package in source['packages']]
        vulnerabilities = {v['id'] for package in packages
                           for v in package.get('vulnerabilities', [])}
        if fixture == 'affected' and 'GHSA-9v85-q87q-g4vg' not in vulnerabilities:
            raise RuntimeError('Affected archive control did not detect its known advisory.')
        if fixture == 'fixed' and vulnerabilities:
            raise RuntimeError('Fixed archive control reports advisories; review the fixture.')
        print(f'{fixture} scanner control passed.')


if __name__ == '__main__':
    main()
