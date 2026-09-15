import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import automation_monitor as m


class ProgressTests(unittest.TestCase):
    def update_fixture(self, home, *, npm_failure=False):
        folder = home / 'Library/Application Support/AutomationUpdates'
        folder.mkdir(parents=True)
        path = folder / '20260914-110005.log'
        text = ('\n--- Homebrew 更新 ---\n'
                'dingtalk 8.0.2,1 -> 8.5.5,2\n'
                '   dingtalk: 安装失败\n'
                '⚠️ 维护结束，存在未完成更新\n'
                '\n--- npm 全局软件更新 ---\n')
        path.write_text(text)
        os.utime(path, (100, 100))
        failure = 'Homebrew 更新未完成：钉钉；安装需要管理员密码'
        if npm_failure:
            failure += '\nnpm 全局软件更新未完成'
        (folder / 'latest-failure.txt').write_text('软件更新未全部完成\n\n' + failure + '\n\n完整日志：\n' + text)
        return path

    def test_manual_install_repairs_only_matching_failed_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            token = root / 'dingtalk'
            (token / '.metadata').mkdir(parents=True)
            (token / '8.5.5,2').mkdir()
            receipt = token / '.metadata/INSTALL_RECEIPT.json'
            text = 'dingtalk 8.0.2,1 -> 8.5.5,2\n'
            for version, timestamp, expected in [('8.0.2,1', 200, False), ('8.5.5,2', 90, False), ('8.5.5,2', 200, True)]:
                receipt.write_text(json.dumps({'time': timestamp, 'source': {'version': version}}))
                self.assertEqual(bool(m.repaired_casks(text, ['dingtalk'], 100, root)), expected)

    def test_legacy_failed_update_then_verified_manual_repair(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.update_fixture(home)
            row = {'pid': None, 'status': 'failed', 'exit_code': 1}
            with patch.object(m, 'repaired_casks', return_value={}):
                m.updates(row, home, 300)
            self.assertEqual(row['status'], 'failed')
            self.assertEqual([s['done'] for s in row['steps']], [False, True])
            self.assertIn('管理员密码', row['detail'])
            with patch.object(m, 'repaired_casks', return_value={'dingtalk': 200}):
                m.updates(row, home, 300)
            self.assertEqual(row['status'], 'success')
            self.assertEqual(row['exit_code'], 1)  # Preserve scheduler history.
            self.assertTrue(all(s['done'] for s in row['steps']))

    def test_manual_brew_repair_does_not_clear_npm_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.update_fixture(home, npm_failure=True)
            row = {'pid': None, 'status': 'failed'}
            with patch.object(m, 'repaired_casks', return_value={'dingtalk': 200}):
                m.updates(row, home, 300)
            self.assertEqual(row['status'], 'failed')

    def test_new_run_does_not_reuse_old_failure_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            old = self.update_fixture(home)
            old.with_name('20260915-110005.log').write_text('\n--- Homebrew 更新 ---\n')
            row = {'pid': None, 'status': 'failed'}
            m.updates(row, home, 300)
            self.assertEqual(row['steps'], [])
            self.assertEqual(row['status'], 'failed')

    def test_structured_receipt_reports_each_completed_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            path = self.update_fixture(home)
            path.with_suffix('.json').write_text(json.dumps({'run_key': path.stem, 'status': 'ok', 'tasks': {name: {'status': 'ok'} for name in m.UPDATE_STAGES}}))
            row = {'pid': None, 'status': 'waiting'}
            m.updates(row, home, 300)
            self.assertEqual(row['status'], 'success')
            self.assertTrue(all(s['done'] for s in row['steps']))

    def test_progress_survives_large_deployment_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'run.log'
            record = '@@STEP@@ ' + json.dumps({'steps': [{'name': '正文', 'done': True}]})
            path.write_text(record + '\n' + 'upload file\n' * 40000)
            self.assertEqual(m.file_steps(path)[0]['done'], True)
            with path.open('a') as f:
                f.write('\n执行：python review_auto.py --date 2026-09-10\n')
            self.assertEqual(m.file_steps(path), [])

    def test_last_attempt_and_partial_log(self):
        first = '@@STEP@@ ' + json.dumps({'steps': [{'name': '正文', 'done': True}]})
        text = first + '\n执行：python review_auto.py --date 2026-09-10\n'
        self.assertEqual(m.last_steps(text), [])
        text += '@@STEP@@ ' + json.dumps({'steps': [{'name': '正文', 'done': False}, {'name': '退役', 'done': False, 'skipped': 'retired'}]})
        text += '\n@@STEP@@ {incomplete'
        self.assertEqual(m.last_steps(text), [{'name': '正文', 'done': False, 'status': 'pending'}])

    def test_running_retry_ignores_previous_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            folder = home / 'Library/Application Support/InvestmentDaily'
            folder.mkdir(parents=True)
            (folder / '2026-09-10.json').write_text(json.dumps({'attempts': 1, 'stage': '生成当日复盘', 'error': 'old failure'}))
            row = {'pid': 123}
            m.investment(row, home, dt.datetime.fromisoformat('2026-09-11T08:57:00+08:00').timestamp())
            self.assertEqual(row['status'], 'running')
            self.assertIsNone(row['error'])
            row = {'pid': None}
            m.investment(row, home, dt.datetime.fromisoformat('2026-09-11T08:57:00+08:00').timestamp())
            self.assertEqual(row['status'], 'failed')

    def test_all_artifacts_do_not_mean_published(self):
        old = {'status': 'running', 'run_key': 'day:1', 'phase': '生成', 'done': 6}
        new = dict(old, done=7)
        self.assertEqual(m.transition(old, new), 'progress')
        published = dict(new, status='success', phase='已发布并核验')
        self.assertEqual(m.transition(new, published), 'success')

    def test_error_dedup_and_notification_policy(self):
        row = {'status': 'failed', 'phase': '生成', 'error': 'broken', 'run_key': 'old'}
        self.assertIsNone(m.transition(None, row))
        self.assertIsNone(m.transition(row, dict(row, run_key='new')))
        self.assertEqual(m.transition(dict(row, status='running'), row), 'failed')
        self.assertFalse(m.should_notify('errors', 'running'))
        self.assertTrue(m.should_notify('errors', 'failed'))
        self.assertFalse(m.should_notify('silent', 'failed'))
        self.assertTrue(m.should_notify('all', 'progress'))

    def test_daemons_are_not_forever_running_jobs(self):
        with patch.object(m.auto, 'tasks', return_value={'com.tianli.test': (Path('/tmp/test'), {'KeepAlive': True})}), patch.object(m.auto, 'disabled', return_value={}), patch.object(m, 'launch_snapshot', return_value={'com.tianli.test': {'pid': 123, 'exit_code': 0}}):
            row = m.collect()[0]
            self.assertEqual(row['status'], 'service')

    def test_quick_report_due_check_is_silent(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            path = home / 'Library/Application Support/AutomationGroups/reports.json'
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps({'started_at': 100, 'finished_at': 101, 'status': 'ok', 'tasks': {}}))
            row = {'id': 'com.tianli.reports', 'pid': None}
            m.grouped(row, home, 102)
            self.assertTrue(row['quiet_check'])

    def test_settings_and_events_survive_restart(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            m.save(root / 'settings.json', {'com.tianli.test': 'silent'})
            monitor = m.Monitor(root, notify=False)
            row = dict(id='com.tianli.test', name='测试', status='running', run_key='1', phase='执行', detail='', done=0, total=0, default_mode='all')
            with patch.object(m, 'collect', return_value=[row]):
                monitor.refresh()
            monitor.pool.shutdown()
            restarted = m.Monitor(root, notify=False)
            self.assertEqual(restarted.settings['com.tianli.test'], 'silent')
            self.assertEqual(len(restarted.events), 1)
            self.assertEqual(restarted.events[0]['notification'], 'silent')
            restarted.pool.shutdown()


if __name__ == '__main__':
    unittest.main()
