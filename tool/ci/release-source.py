#!/usr/bin/env python3
"""Require the repository's pre-release branch as the source of main PRs."""

import os
import sys


def main():
    repository = os.environ.get('GITHUB_REPOSITORY')
    if (
        os.environ.get('GITHUB_EVENT_NAME') == 'pull_request_target'
        and os.environ.get('PR_BASE_REF') == 'main'
        and os.environ.get('PR_HEAD_REF') == 'pre-release'
        and repository
        and os.environ.get('PR_HEAD_REPOSITORY') == repository
    ):
        return 0
    print(
        'Expected a pull_request_target event for a PR from the pre-release branch '
        'in this repository into main.',
        file=sys.stderr,
    )
    return 1


if __name__ == '__main__':
    sys.exit(main())
