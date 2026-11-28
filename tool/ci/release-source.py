#!/usr/bin/env python3
"""Require the repository's pre-release branch as the source of main PRs."""

import os
import sys


def main():
    if os.environ['GITHUB_EVENT_NAME'] != 'pull_request':
        return 0
    if os.environ['PR_BASE_REF'] != 'main':
        return 0
    if (
        os.environ['PR_HEAD_REF'] == 'pre-release'
        and os.environ['PR_HEAD_REPOSITORY'] == os.environ['GITHUB_REPOSITORY']
    ):
        return 0
    print('Pull requests to main must come from the pre-release branch in this repository.',
          file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
