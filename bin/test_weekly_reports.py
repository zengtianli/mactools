"""Scheduling and failure semantics; no LLM, publication or notifications."""
import datetime as dt
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import weekly_reports as w


class PeriodTests(unittest.TestCase):
    def test_before_sunday_boundary(self):
        start, end = w.period(dt.datetime.fromisoformat('2026-09-06T07:59:59-07:00'))
        self.assertEqual(end.isoformat(), '2026-08-30T08:00:00-07:00')

    def test_exact_boundary(self):
        start, end = w.period(dt.datetime.fromisoformat('2026-09-06T08:00:00-07:00'))
        self.assertEqual(end.isoformat(), '2026-09-06T08:00:00-07:00')
        self.assertEqual(start.isoformat(), '2026-08-30T08:00:00-07:00')

    def test_spring_dst_keeps_eight_and_167_hours(self):
        start, end = w.period(dt.datetime.fromisoformat('2026-03-08T08:00:00-07:00'))
        self.assertEqual((start.hour, end.hour), (8, 8))
        self.assertEqual((end.timestamp()-start.timestamp())/3600, 167)

    def test_fall_dst_keeps_eight_and_169_hours(self):
        start, end = w.period(dt.datetime.fromisoformat('2026-11-01T08:00:00-08:00'))
        self.assertEqual((start.hour, end.hour), (8, 8))
        self.assertEqual((end.timestamp()-start.timestamp())/3600, 169)

    def test_utc_input(self):
        self.assertEqual(w.period(dt.datetime.fromisoformat('2026-09-06T15:00:00+00:00')),
                         w.period(dt.datetime.fromisoformat('2026-09-06T08:00:00-07:00')))


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name)
        self.start, self.end = w.period(dt.datetime.fromisoformat('2026-09-06T08:00:00-07:00'))

    def tearDown(self):
        self.temp.cleanup()

    def run_collect(self, log):
        def git(repo, *args):
            if args[0] == 'rev-parse':
                return str(self.repo)
            if args[0] == 'log':
                if isinstance(log, Exception):
                    raise log
                return log
            return 'src/example.py\n'
        with patch.object(w, 'repositories', return_value=[self.repo]), patch.object(w, 'git', side_effect=git):
            return w.collect('development', self.start, self.end)

    def test_empty_inventory_fails(self):
        with patch.object(w, 'repositories', return_value=[]):
            with self.assertRaises(RuntimeError):
                w.collect('water', self.start, self.end)

    def test_all_git_log_failures_cannot_count_as_scanned(self):
        with self.assertRaises(RuntimeError):
            self.run_collect(subprocess.CalledProcessError(128, 'git log'))

    def test_successful_empty_repo_is_valid_silence(self):
        rows, coverage = self.run_collect('')
        self.assertEqual(rows, [])
        self.assertEqual(coverage['unavailable'], [])

    def test_exclusive_end_and_pt_calendar_date(self):
        def row(sha, stamp):
            return f'{sha}\x1f{stamp}\x1fChanged code\x1f\x1e\n'
        log = row('a'*40, '2026-09-06T01:00:00+08:00') + row('b'*40, '2026-09-06T08:00:00-07:00')
        rows, _ = self.run_collect(log)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['date'], '2026-09-05')


class ExecuteTests(unittest.TestCase):
    def test_zero_records_with_gap_is_not_complete(self):
        start, end = w.period(dt.datetime.fromisoformat('2026-09-06T08:00:00-07:00'))
        with tempfile.TemporaryDirectory() as temp, patch.object(w, 'ROOT', Path(temp)), \
                patch.object(w, 'collect', return_value=([], {'scanned': ['fixture'], 'unavailable': ['read failed'], 'truncated': []})), \
                patch.object(w, 'notice'):
            try:
                w.execute('development', start, end)
            except RuntimeError:
                pass
            state = json.loads((Path(temp)/str(end.date())/'development/state.json').read_text())
            self.assertFalse(state.get('complete', False))

    def test_completed_notification_retry_does_not_recollect(self):
        start, end = w.period(dt.datetime.fromisoformat('2026-09-06T08:00:00-07:00'))
        with tempfile.TemporaryDirectory() as temp, patch.object(w, 'ROOT', Path(temp)), \
                patch.object(w, 'collect') as collect, patch.object(w, 'notice') as notice:
            path = Path(temp)/str(end.date())/'development/state.json'
            w.save(path, {'complete': True, 'notified': False, 'url': 'https://example.test/private-view/weekly'})
            w.execute('development', start, end)
            collect.assert_not_called()
            notice.assert_called_once()
            self.assertTrue(json.loads(path.read_text())['notified'])


if __name__ == '__main__':
    unittest.main()
