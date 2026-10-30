import importlib.util
import io
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('deliver_session', Path(__file__).with_name('deliver_session.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class SessionInputTest(unittest.TestCase):
    def payload(self, **extra):
        return json.dumps({'variant': 'https://synthetic.invalid/session/private-capability',
                           'offsetSeconds': 600, **extra}).encode()

    def test_input_is_bounded_and_refuses_credentials_and_start_properties(self):
        self.assertEqual(probe.validate(self.payload()), self.payload())
        values = [b'x' * (probe.MAX_BYTES + 1), b'{}', b'{',
                  self.payload(plexToken='synthetic'), self.payload(startSeconds=0),
                  self.payload(offsetSeconds=True), self.payload(observeSeconds=31)]
        values += [self.payload(variant=uri) for uri in (
            'http://synthetic.invalid/a', 'https://u:p@synthetic.invalid/a',
            'https://synthetic.invalid/a?%58-pLeX-tOkEn=synthetic',
            'https://synthetic.invalid/a?X-Plex-Token', 'https://synthetic.invalid/a?x-plex-token=',
            'https://synthetic.invalid/a#fragment')]
        for value in values:
            with self.assertRaises(probe.InputRefused):
                probe.validate(value)

    def test_requires_explicit_emulator_mapping_and_never_puts_payload_in_adb_arguments(self):
        data = self.payload()
        with patch.object(probe.subprocess, 'run') as run, patch.object(probe.socket, 'create_connection') as connect:
            run.return_value = types.SimpleNamespace(stdout=b'emulator-5554 tcp:25445 tcp:18445\n')
            peer = connect.return_value.__enter__.return_value
            peer.recv.side_effect = [b'acce', b'pted\n', b'']
            probe.deliver(data, 'emulator-5554', 25445)
            self.assertEqual(run.call_args.args[0], ['adb', '-s', 'emulator-5554', 'forward', '--list'])
            peer.sendall.assert_called_once_with(data)
            self.assertEqual(connect.call_args.args[0], ('127.0.0.1', 25445))
            for serial, port in [('physical-stick', 25445), ('emulator-5554', 0)]:
                with self.assertRaises(probe.InputRefused):
                    probe.deliver(data, serial, port)
            run.return_value.stdout = b'emulator-5556 tcp:25445 tcp:18445\n'
            with self.assertRaises(probe.InputRefused):
                probe.deliver(data, 'emulator-5554', 25445)
            self.assertEqual(connect.call_count, 1)

    def test_stdin_read_is_bounded_and_has_a_deadline(self):
        stream = types.SimpleNamespace(fileno=lambda: 123)
        with patch.object(probe.select, 'select', return_value=([stream], [], [])), \
             patch.object(probe.os, 'read', side_effect=[b'first', b'second', b'']):
            self.assertEqual(probe.read_input(stream), b'firstsecond')
        with patch.object(probe.select, 'select', return_value=([], [], [])):
            with self.assertRaises(probe.InputRefused):
                probe.read_input(stream)
        with patch.object(probe.select, 'select', return_value=([stream], [], [])), \
             patch.object(probe.os, 'read', return_value=b'x' * (probe.MAX_BYTES + 1)):
            with self.assertRaises(probe.InputRefused):
                probe.read_input(stream)

    def test_command_errors_are_fixed_and_do_not_serialize_capability(self):
        data = self.payload()
        stdin = types.SimpleNamespace(buffer=io.BytesIO(data), isatty=lambda: False)
        with patch.object(probe.sys, 'argv', ['deliver_session.py', '--serial', 'emulator-5554', '--port', '25445']), \
             patch.object(probe.sys, 'stdin', stdin), patch.object(probe, 'read_input', return_value=data), \
             patch.object(probe.sys, 'stderr', io.StringIO()) as error, \
             patch.object(probe.subprocess, 'run', side_effect=RuntimeError(data.decode())):
            self.assertEqual(probe.main(), 1)
            self.assertEqual(error.getvalue(), 'E6_INPUT_REFUSED\n')


if __name__ == '__main__':
    unittest.main()
