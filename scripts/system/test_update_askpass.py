import contextlib
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
from unittest.mock import patch

import update_askpass as a
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'bin'))
import brew_maintain as brew


class AskpassTests(unittest.TestCase):
    def test_update_environment_is_scoped_and_cancel_marker_is_removed(self):
        original = dict(brew.BREW_ENV)
        captured = {}
        def maintain():
            captured.update(brew.BREW_ENV)
            marker = Path(captured['AUTOMATION_UPDATE_CANCEL_FILE'])
            self.assertTrue(Path(captured['SUDO_ASKPASS']).is_file())
            marker.touch()
            return 1
        with patch.object(sys, 'argv', ['brew_maintain.py', '--auto', '--gui-sudo']), patch.object(brew, 'maintain', side_effect=maintain), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(brew.main(), 1)
        self.assertEqual(brew.BREW_ENV, original)
        self.assertFalse(Path(captured['AUTOMATION_UPDATE_CANCEL_FILE']).parent.exists())

    def test_secret_only_goes_to_stdout_not_disk_or_stderr(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp)/'cancelled'
            result = subprocess.CompletedProcess([], 0, 'test-only-password\n', '')
            out, err = io.StringIO(), io.StringIO()
            with patch.dict(os.environ, AUTOMATION_UPDATE_CANCEL_FILE=str(marker)), patch.object(a.subprocess, 'run', return_value=result), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                self.assertEqual(a.main(), 0)
            self.assertEqual(out.getvalue(), 'test-only-password\n')
            self.assertEqual(err.getvalue(), '')
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_cancel_blocks_later_prompts_in_same_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.CompletedProcess([], 1, '', 'user cancelled')
            out = io.StringIO()
            with patch.dict(os.environ, AUTOMATION_UPDATE_CANCEL_FILE=str(Path(tmp)/'cancelled')), patch.object(a.subprocess, 'run', return_value=result) as run, contextlib.redirect_stdout(out):
                self.assertEqual(a.main(), 1)
                self.assertEqual(a.main(), 1)
                self.assertEqual(run.call_count, 1)
            self.assertEqual(out.getvalue(), '')

    def test_timeout_does_not_leak_captured_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err = io.StringIO(), io.StringIO()
            exception = subprocess.TimeoutExpired('osascript', 130, output='test-secret')
            with patch.dict(os.environ, AUTOMATION_UPDATE_CANCEL_FILE=str(Path(tmp)/'cancelled')), patch.object(a.subprocess, 'run', side_effect=exception), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                self.assertEqual(a.main(), 1)
            self.assertEqual(out.getvalue()+err.getvalue(), '')


if __name__ == '__main__':
    unittest.main()
