import os
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name('release-source.py')
REPOSITORY = 'owner/lineup'


class ReleaseSourceTest(unittest.TestCase):
    def check(self, event, base='', head='', repository=''):
        return subprocess.run(
            [sys.executable, '-I', str(SCRIPT)],
            env={
                **os.environ,
                'GITHUB_EVENT_NAME': event,
                'GITHUB_REPOSITORY': REPOSITORY,
                'PR_BASE_REF': base,
                'PR_HEAD_REF': head,
                'PR_HEAD_REPOSITORY': repository,
            },
            capture_output=True,
            text=True,
        )

    def test_non_pull_request_events_succeed(self):
        for event in ('push', 'workflow_dispatch'):
            with self.subTest(event=event):
                self.assertEqual(0, self.check(event).returncode)

    def test_pull_request_to_pre_release_succeeds(self):
        result = self.check('pull_request', 'pre-release', 'feature/guide', 'fork/lineup')
        self.assertEqual(0, result.returncode)

    def test_same_repository_release_pull_request_succeeds(self):
        result = self.check('pull_request', 'main', 'pre-release', REPOSITORY)
        self.assertEqual(0, result.returncode)

    def test_other_sources_for_main_are_rejected(self):
        for head, repository in (
            ('feature/guide', REPOSITORY),
            ('pre-release', 'fork/lineup'),
            ('pre-release', ''),
            ('', REPOSITORY),
        ):
            with self.subTest(head=head, repository=repository):
                result = self.check('pull_request', 'main', head, repository)
                self.assertEqual(1, result.returncode)
                self.assertIn('Pull requests to main must come from', result.stderr)


if __name__ == '__main__':
    unittest.main()
