"""Receipt contract tests only: every updater/notification subprocess is mocked."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import automation_monitor as monitor

SOURCE = Path(__file__).resolve().parents[2] / 'bin' / 'always_latest.py'
spec = importlib.util.spec_from_file_location('always_latest_receipt_subject', SOURCE)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class ReceiptContractTests(unittest.TestCase):
    old_stamp = '20260914-110005'
    new_stamp = '20260915-110005'

    def folder(self, home):
        folder = home / 'Library/Application Support/AutomationUpdates'
        folder.mkdir(parents=True, exist_ok=True)
        return folder

    def receipt(self, home, *, stamp=None, status='ok', pid=111, tasks=None, failures=None):
        stamp = stamp or self.old_stamp
        folder = self.folder(home)
        path = folder / f'{stamp}.log'
        path.write_text('\n--- Homebrew 更新 ---\n\n--- npm 全局软件更新 ---\n')
        payload = {'run_key': stamp, 'pid': pid, 'started_at': 100, 'status': status,
                   'tasks': tasks if tasks is not None else {name: {'status': 'ok', 'exit_code': 0} for name in monitor.UPDATE_STAGES}}
        if status != 'running':
            payload['finished_at'] = 200
        if failures is not None:
            payload['failures'] = failures
        path.with_suffix('.json').write_text(json.dumps(payload))
        return path

    def mocked_maintain(self, home, *, brew_exit=0, npm_exit=0, root_error=None, setup_error=None):
        folder = self.folder(home)
        npm_root = home / 'mock-npm-root'
        npm_root.mkdir(exist_ok=True)
        node = home / 'mock-node-bin'
        node.mkdir(exist_ok=True)
        observed = []

        def run(command, **kwargs):
            receipt = json.loads((folder / f'{self.new_stamp}.json').read_text())
            observed.append((command, receipt, kwargs))
            if any(str(item).endswith('brew_maintain.py') for item in command):
                return subprocess.CompletedProcess(command, brew_exit)
            if command[1:] == ['root', '-g']:
                if root_error:
                    raise root_error
                return subprocess.CompletedProcess(command, 0, stdout=str(npm_root) + '\n')
            if command[1:] == ['update', '-g']:
                return subprocess.CompletedProcess(command, npm_exit)
            if any(str(item).endswith('task_notify.py') for item in command):
                return subprocess.CompletedProcess(command, 0)
            self.fail(f'unexpected mocked command: {command!r}')

        with patch.object(updater, 'STATE', folder), patch.object(updater, 'datetime') as clock, \
             patch.object(updater, 'node_bin', side_effect=setup_error, return_value=node), \
             patch.object(updater.subprocess, 'run', side_effect=run) as runner, \
             contextlib.redirect_stdout(io.StringIO()):
            clock.now.return_value.astimezone.return_value.strftime.return_value = self.new_stamp
            if setup_error:
                with self.assertRaises(type(setup_error)):
                    updater.maintain()
                self.assertEqual(runner.call_count, 0)
                code = None
            else:
                code = updater.maintain()
        final = json.loads((folder / f'{self.new_stamp}.json').read_text())
        return code, final, observed

    def test_successful_mocked_run_publishes_two_task_receipts(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            code, final, observed = self.mocked_maintain(home)
            self.assertEqual(code, 0)
            self.assertEqual(final['status'], 'ok')
            self.assertEqual(final['pid'], os.getpid())
            self.assertEqual(set(final['tasks']), set(monitor.UPDATE_STAGES))
            self.assertTrue(all(task['status'] == 'ok' and task['exit_code'] == 0 for task in final['tasks'].values()))
            self.assertEqual(observed[0][1]['tasks']['Homebrew 更新']['status'], 'running')
            self.assertEqual(observed[2][1]['tasks']['npm 全局软件更新']['status'], 'running')
            row = {'pid': None, 'status': 'waiting', 'exit_code': 0}
            monitor.updates(row, home, 300)
            self.assertEqual(row['status'], 'success')
            self.assertEqual([step['done'] for step in row['steps']], [True, True])

    def test_failed_homebrew_keeps_npm_result_separate(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            code, final, observed = self.mocked_maintain(home, brew_exit=1)
            self.assertEqual(code, 1)
            self.assertEqual(final['status'], 'failed')
            self.assertEqual(final['tasks']['Homebrew 更新']['exit_code'], 1)
            self.assertEqual(final['tasks']['npm 全局软件更新']['status'], 'ok')
            self.assertEqual(len(observed), 4)
            row = {'pid': None, 'status': 'failed', 'exit_code': 1}
            monitor.updates(row, home, 300)
            self.assertEqual(row['status'], 'failed')
            self.assertEqual([step['done'] for step in row['steps']], [False, True])

    def test_npm_root_error_has_failed_receipt_and_skips_npm_update(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, final, observed = self.mocked_maintain(Path(tmp), root_error=subprocess.TimeoutExpired(['npm', 'root', '-g'], 60))
            self.assertEqual(code, 1)
            self.assertEqual(final['tasks']['Homebrew 更新']['status'], 'ok')
            self.assertEqual(final['tasks']['npm 全局软件更新']['status'], 'failed')
            self.assertEqual(len(observed), 3)

    def test_setup_failure_creates_new_run_before_it_can_mask_old_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.receipt(home)
            _, final, _ = self.mocked_maintain(home, setup_error=RuntimeError('fixture setup failure'))
            self.assertEqual(final['status'], 'running')
            self.assertTrue((self.folder(home) / f'{self.new_stamp}.log').exists())
            row = {'pid': None, 'status': 'failed', 'exit_code': 1}
            monitor.updates(row, home, 300)
            self.assertEqual(row['run_key'], self.new_stamp)
            self.assertEqual(row['status'], 'interrupted')
            self.assertFalse(any(step['done'] for step in row['steps']))

    def test_new_pid_cannot_borrow_previous_complete_progress(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.receipt(home, pid=111)
            row = {'pid': 222, 'status': 'running', 'exit_code': 0}
            monitor.updates(row, home, 300)
            self.assertEqual(row['status'], 'running')
            self.assertFalse(any(step['done'] for step in row['steps']))

    def test_current_running_receipt_without_process_is_interrupted(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.receipt(home, stamp=self.new_stamp, status='running', tasks={'Homebrew 更新': {'status': 'ok'}})
            row = {'pid': None, 'status': 'failed', 'exit_code': 9}
            monitor.updates(row, home, 300)
            self.assertEqual(row['status'], 'interrupted')
            self.assertNotEqual(row['status'], 'success')

    def test_failed_receipt_without_failure_strings_never_reports_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.receipt(home, status='failed', tasks={'Homebrew 更新': {'status': 'failed'}, 'npm 全局软件更新': {'status': 'ok'}})
            row = {'pid': None, 'status': 'failed', 'exit_code': 1}
            monitor.updates(row, home, 300)
            self.assertNotEqual(row['status'], 'success')

    def test_success_receipt_with_missing_stage_never_claims_both_completed(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.receipt(home, status='ok', tasks={'Homebrew 更新': {'status': 'ok'}}, failures=[])
            row = {'pid': None, 'status': 'waiting', 'exit_code': 0}
            monitor.updates(row, home, 300)
            self.assertNotEqual(row['status'], 'success')


if __name__ == '__main__':
    unittest.main()
