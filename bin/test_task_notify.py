import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import task_notify as notify
from due_notify import stable


class Notifications(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = patch.object(notify, 'ROOT', Path(self.temp.name))
        self.root.start()
        self.args = ['--key', 'test', '--title', '测试', '--message', '失败原因']

    def tearDown(self):
        self.root.stop()
        self.temp.cleanup()

    def state(self):
        return json.loads(notify.paths('test')[0].read_text())

    def test_delivery_failure_retries_and_does_not_acknowledge(self):
        with patch.object(notify.subprocess, 'run', return_value=subprocess.CompletedProcess([], 3, '', 'denied')):
            self.assertEqual(notify.main(self.args), 3)
        self.assertNotIn('sent_at', self.state())
        with patch.object(notify.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            self.assertEqual(notify.main(self.args), 0)
            self.assertEqual(notify.main(self.args), 0)
            self.assertEqual(run.call_count, 1)

    def test_snooze_dismiss_and_new_event(self):
        with patch.object(notify.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            notify.main(self.args)
            notify.main(['--key', 'test', '--action', 'snooze'])
            notify.main(self.args)
            self.assertEqual(run.call_count, 1)
            self.assertGreater(self.state()['snoozed_until'], self.state()['sent_at'])
            notify.main(['--key', 'test', '--action', 'dismiss'])
            notify.main(self.args)
            self.assertEqual(run.call_count, 1)
            notify.main(self.args + ['--fingerprint', 'another event'])
            self.assertEqual(run.call_count, 2)
            self.assertFalse(self.state().get('dismissed'))

    def test_clear_allows_recurrence(self):
        with patch.object(notify.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            notify.main(self.args)
            notify.main(['--key', 'test', '--clear'])
            notify.main(self.args)
            self.assertEqual(run.call_count, 3)

    def test_changed_details_do_not_spam(self):
        detail = Path(self.temp.name) / 'source.txt'
        detail.write_text('check 1')
        with patch.object(notify.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            notify.main(self.args + ['--details', str(detail)])
            detail.write_text('check 2')
            notify.main(self.args + ['--details', str(detail)])
            self.assertEqual(run.call_count, 1)
            self.assertIn('check 2', notify.paths('test')[1].read_text())

    def test_deadline_countdown_is_not_a_new_event(self):
        self.assertEqual(stable('🔴 剩 3 天 · A（2026-09-09）'), stable('🔴 剩 2 天 · A（2026-09-09）'))
        self.assertNotEqual(stable('🔴 剩 3 天 · A（2026-09-09）'), stable('🔴 剩 3 天 · A（2026-10-09）'))


if __name__ == '__main__':
    unittest.main()
