import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    'collect_notices', Path(__file__).with_name('collect-notices.py'))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class CollectNoticesTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve()
        self.source = root / 'source'
        self.build = root / 'build'
        self.bin = root / 'bin'
        for directory in (self.source, self.build, self.bin):
            directory.mkdir()
        self.from_deps = self.make_source('from_deps.c')
        (self.build / 'example.d').write_text(f'example.o: {self.from_deps}\n')
        self.archive = self.build / 'example.a'
        self.archive.touch()
        env = patch.dict(os.environ, {'PATH': f'{self.bin}{os.pathsep}{os.environ["PATH"]}'})
        env.start()
        self.addCleanup(env.stop)

    def make_source(self, name):
        source = self.source / name
        source.touch()
        return source

    def fake_tool(self, name, script):
        executable = self.bin / name
        executable.write_text(f'#!/bin/sh\n{script}\n')
        executable.chmod(0o755)

    def collect(self, *, archive=False):
        archives = [str(self.archive)] if archive else []
        return collector.collect([str(self.build)], archives, str(self.source))

    def test_failed_ninja_with_readable_make_deps(self):
        (self.build / 'build.ninja').touch()
        for tool in ('deps', 'inputs'):
            with self.subTest(tool=tool):
                self.fake_tool('ninja', f'if [ "$4" = "{tool}" ]; then exit 1; fi')
                with self.assertRaises(subprocess.CalledProcessError):
                    self.collect()

    def test_unreadable_make_deps(self):
        (self.build / 'x.d').symlink_to('missing')
        with self.assertRaises(FileNotFoundError):
            self.collect()

    def test_failed_ar(self):
        self.fake_tool('lipo', 'exit 0')
        self.fake_tool('ar', 'exit 1')
        with self.assertRaises(subprocess.CalledProcessError):
            self.collect(archive=True)

    def test_thin_archive_fallback(self):
        source = self.make_source('archived.c')
        self.fake_tool('lipo', 'exit 1')
        self.fake_tool('ar', 'if [ "$2" != "$EXPECTED_ARCHIVE" ]; then exit 1; fi\necho archived.o')
        with patch.dict(os.environ, {'EXPECTED_ARCHIVE': str(self.archive)}):
            self.assertEqual({str(self.from_deps), str(source)}, self.collect(archive=True))

    def test_combines_discovery_sources(self):
        (self.build / 'build.ninja').touch()
        ninja_input = self.make_source('ninja_input.c')
        ninja_dep = self.make_source('ninja_dep.h')
        archive_source = self.make_source('archived.c')
        self.fake_tool('ninja', 'if [ "$4" = deps ]; then\n'
                       '  printf "    %s\\n" "$NINJA_DEP"\n'
                       'else\n  printf "%s\\n" "$NINJA_INPUT"\nfi')
        self.fake_tool('lipo', 'touch "$5"')
        self.fake_tool('ar', 'test -f "$2" && echo archived.o')
        with patch.dict(os.environ, {'NINJA_DEP': str(ninja_dep), 'NINJA_INPUT': str(ninja_input)}):
            self.assertEqual(
                {str(path) for path in (self.from_deps, ninja_input, ninja_dep, archive_source)},
                self.collect(archive=True))


if __name__ == '__main__':
    unittest.main()
