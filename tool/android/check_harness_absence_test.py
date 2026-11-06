import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('check-harness-absence.py')
spec = importlib.util.spec_from_file_location('check_harness_absence', SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class CheckHarnessAbsenceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'Clean.kt').write_text('class Clean')

    def test_clean_tree(self):
        result = checker.inspect(self.root, source=True)
        self.assertEqual(1, result['membersChecked'])
        self.assertEqual([], result['findings'])

    def test_marker_in_readable_source(self):
        (self.root / 'Other.kt').write_text('class DebugSessionLogging')
        result = checker.inspect(self.root, source=True)
        self.assertEqual([{'member': 'Other.kt', 'marker': 'DebugSessionLogging'}],
                         result['findings'])

    @unittest.skipIf(os.geteuid() == 0, 'root can read chmod 000 directories')
    def test_unreadable_sibling(self):
        blocked = self.root / 'blocked'
        blocked.mkdir()
        blocked.chmod(0)
        self.addCleanup(blocked.chmod, 0o700)
        result = subprocess.run([sys.executable, str(SCRIPT), '--source', str(self.root)],
                                capture_output=True, text=True)
        self.assertEqual(1, result.returncode, result.stdout)
        self.assertFalse(json.loads(result.stdout)['harnessAbsent'])

    def test_file_symlink(self):
        (self.root / 'linked.txt').symlink_to(self.root / 'Clean.kt')
        with self.assertRaisesRegex(ValueError, 'invalid_input'):
            checker.inspect(self.root, source=True)

    def test_directory_symlink(self):
        directory = self.root / 'nested'
        directory.mkdir()
        (self.root / 'linked').symlink_to(directory, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'invalid_input'):
            checker.inspect(self.root, source=True)


if __name__ == '__main__':
    unittest.main()
