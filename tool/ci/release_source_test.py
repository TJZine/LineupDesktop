import os
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name('release-source.py')
REPOSITORY = 'owner/lineup'
RELEASE_EVENT = {
    'GITHUB_EVENT_NAME': 'pull_request_target',
    'GITHUB_REPOSITORY': REPOSITORY,
    'PR_BASE_REF': 'main',
    'PR_HEAD_REF': 'pre-release',
    'PR_HEAD_REPOSITORY': REPOSITORY,
}


class ReleaseSourceTest(unittest.TestCase):
    def check(self, **overrides):
        env = {**os.environ, **RELEASE_EVENT, **overrides}
        return subprocess.run(
            [sys.executable, '-I', str(SCRIPT)],
            env={key: value for key, value in env.items() if value is not None},
            capture_output=True,
            text=True,
        )

    def assert_rejected(self, **overrides):
        result = self.check(**overrides)
        self.assertEqual(1, result.returncode)
        self.assertIn('Expected a pull_request_target event', result.stderr)

    def test_unexpected_events_are_rejected(self):
        for event in ('pull_request', 'push', 'workflow_dispatch'):
            with self.subTest(event=event):
                self.assert_rejected(GITHUB_EVENT_NAME=event)

    def test_same_repository_release_pull_request_succeeds(self):
        self.assertEqual(0, self.check().returncode)

    def test_other_branches_and_repositories_are_rejected(self):
        for key, value in (
            ('PR_BASE_REF', 'pre-release'),
            ('PR_HEAD_REF', 'feature/guide'),
            ('PR_HEAD_REPOSITORY', 'fork/lineup'),
        ):
            with self.subTest(key=key, value=value):
                self.assert_rejected(**{key: value})

    def test_missing_or_empty_metadata_is_rejected(self):
        for key in RELEASE_EVENT:
            for value in (None, ''):
                with self.subTest(key=key, value=value):
                    self.assert_rejected(**{key: value})
        self.assert_rejected(GITHUB_REPOSITORY='', PR_HEAD_REPOSITORY='')


if __name__ == '__main__':
    unittest.main()
