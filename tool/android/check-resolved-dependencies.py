#!/usr/bin/env python3
"""Check actual Gradle buildEnvironment and releaseRuntimeClasspath reports."""
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('notices', Path(__file__).with_name('generate-licenses.py'))
notices = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notices)


def check(report, runtime_report=None):
    if 'FAILED' in report or (runtime_report is not None and 'FAILED' in runtime_report):
        raise ValueError('Gradle dependency report contains unresolved dependencies')
    coordinates = notices.parse_report(report)
    for group, artifact, expected in (
        ('org.jetbrains.kotlin', 'kotlin-gradle-plugin', '2.4.21'),
        ('com.android.tools.build', 'gradle', '9.1.0'),
        ('com.google.guava', 'guava', '33.7.2-android'),
    ):
        selected = (notices.parse_report(runtime_report)
                    if artifact == 'guava' and runtime_report is not None else coordinates)
        versions = {version for g, a, version in selected if (g, a) == (group, artifact)}
        if versions != {expected}:
            raise ValueError(f'Expected resolved {group}:{artifact}:{expected}, got {sorted(versions)}')

if __name__ == '__main__':
    try:
        check(Path(sys.argv[1]).read_text(), Path(sys.argv[2]).read_text())
    except (ValueError, OSError, IndexError, notices.GenerationError) as error:
        sys.exit(str(error))
    print('Resolved KGP, AGP and release Guava identities verified.')
