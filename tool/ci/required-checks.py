#!/usr/bin/env python3
"""Validate CI job conclusions, including justified conditional Windows skips."""

import json
import os
import sys

UNCONDITIONAL = (
    'verify', 'android', 'build-macos', 'macos-player-core',
    'windows-release-policy', 'build-windows', 'release-inputs',
)
CONDITIONAL = ('windows-engine-tests', 'build-windows-engine')


def failures(needs):
    expected_jobs = set(UNCONDITIONAL + CONDITIONAL)
    errors = []
    if set(needs) != expected_jobs:
        errors.append('Required job inventory does not match CI dependencies.')
    for job in UNCONDITIONAL:
        if needs.get(job, {}).get('result') != 'success':
            errors.append(f'{job} must succeed.')
    outputs = needs.get('release-inputs', {}).get('outputs', {})
    engine = outputs.get('engine-required')
    package = outputs.get('package-required')
    if engine not in ('true', 'false') or package not in ('true', 'false'):
        errors.append('Windows release-input decisions must be explicit booleans.')
    else:
        requirements = {
            'windows-engine-tests': engine == 'true',
            'build-windows-engine': engine == 'true' or package == 'true',
        }
        for job, required in requirements.items():
            expected = 'success' if required else 'skipped'
            if needs.get(job, {}).get('result') != expected:
                errors.append(f'{job} must be {expected} for these release inputs.')
    return errors


def main():
    needs = json.loads(os.environ['CI_NEEDS'])
    errors = failures(needs)
    for error in errors:
        print(error, file=sys.stderr)
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
