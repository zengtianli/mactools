import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import grouped_tasks as g


class GroupTests(unittest.TestCase):
    def test_failure_does_not_skip_next_and_logs_stay_separate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            jobs = [('first', [sys.executable, '-c', 'print("one");raise SystemExit(7)'], 5),
                    ('second', [sys.executable, '-c', 'print("two")'], 5)]
            with patch.object(g, 'STATE', root / 'state'), patch.object(g, 'LOGS', root / 'logs'), patch.dict(g.GROUPS, test=jobs):
                self.assertEqual(g.run_group('test'), 1)
                data = json.loads((root/'state/test.json').read_text())
                self.assertEqual(data['tasks']['first']['exit_code'], 7)
                self.assertEqual(data['tasks']['second']['exit_code'], 0)
                self.assertIn('one', (root/'logs/first.log').read_text())
                self.assertNotIn('two', (root/'logs/first.log').read_text())

    def test_timeout_and_missing_executable_do_not_skip_next(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            jobs = [('timeout', [sys.executable, '-c', 'import time;time.sleep(60)'], .1),
                    ('missing', ['/does/not/exist'], 1),
                    ('last', [sys.executable, '-c', 'pass'], 5)]
            with patch.object(g, 'STATE', root/'state'), patch.object(g, 'LOGS', root/'logs'), patch.dict(g.GROUPS, test=jobs):
                self.assertEqual(g.run_group('test'), 1)
                data = json.loads((root/'state/test.json').read_text())
                self.assertEqual(data['tasks']['timeout']['exit_code'], 124)
                self.assertEqual(data['tasks']['last']['status'], 'ok')

    def test_business_arguments_preserved(self):
        self.assertEqual(g.GROUPS['reports'][1][1][-2:], ['--frequency', 'monthly'])
        self.assertEqual(g.GROUPS['reminders'][0][1][-4:], ['--source', 'acad', '--days', '30'])
        self.assertEqual(g.GROUPS['reminders'][1][1][-4:], ['--source', 'cases', '--days', '30'])


if __name__ == '__main__':
    unittest.main()
