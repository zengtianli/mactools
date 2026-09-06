from datetime import date
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import client_due as c


class ClientDueTests(unittest.TestCase):
    def setUp(self):
        self.today = date(2026, 9, 6)
        self.source = Path('/work/.work.yaml')
        self.row = {'name': '交付样本', 'status': '未完成', 'deadline': '2026-09-10'}

    def evaluate(self, row, **kwargs):
        return c.evaluate(row, self.source, self.today, 14, **kwargs)

    def test_explicit_open(self):
        self.assertIsNotNone(self.evaluate(self.row)[0])

    def test_historical_unknown_is_silent(self):
        self.assertIsNone(self.evaluate(dict(self.row, status='', deadline='2026-05-31'))[0])

    def test_parent_acceptance_overrides_child_pending(self):
        self.assertIsNone(self.evaluate(self.row, parent_status='已验收 · 验收后可选深化期')[0])

    def test_completed_child_overrides_active_parent(self):
        self.assertIsNone(self.evaluate(dict(self.row, status='已交付'), parent_status='进行中')[0])

    def test_invalid_date_and_placeholder(self):
        for changes in ({'deadline': '9月底'}, {'name': ''}, {'deadline': ''}):
            self.assertIsNone(self.evaluate(dict(self.row, **changes))[0])

    def test_future_outside_window(self):
        self.assertIsNone(self.evaluate(dict(self.row, deadline='2027-01-01'))[0])

    def test_receivable_requires_all_three(self):
        with tempfile.TemporaryDirectory() as d:
            evidence = Path(d)/'合同.txt'
            evidence.write_text('fixture')
            row = {'party': '客户样本', 'kind': '应收款', 'status': '未收款', 'due_date': '2026-09-10', 'file': str(evidence)}
            self.assertIsNotNone(self.evaluate(row, kind='receivable')[0])
            for change in ({'kind': '专家费'}, {'status': '已付'}, {'file': ''}, {'file': '/missing/contract'}):
                self.assertIsNone(self.evaluate(dict(row, **change), kind='receivable')[0])

    def test_scan_missing_and_empty_fail(self):
        with tempfile.TemporaryDirectory() as d:
            for root in (Path(d), Path(d)/'missing'):
                with self.assertRaises(ValueError):
                    c.scan([root], self.today, 14)

    def test_dry_run_does_not_notify(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/'.work.yaml').write_text('deliverables: []\n')
            with patch.object(c.task_notify, 'main') as notify:
                self.assertEqual(c.main(['--root', d, '--dry-run']), 0)
                notify.assert_not_called()


if __name__ == '__main__':
    unittest.main()
