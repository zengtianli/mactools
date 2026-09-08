import subprocess
import unittest
from unittest.mock import patch

import automation


class DisabledStateTests(unittest.TestCase):
    def test_macos_output_formats(self):
        for yes, no in [('disabled', 'enabled'), ('true', 'false')]:
            output = f'"com.tianli.a" => {yes}\n"com.tianli.b" => {no}'
            with patch.object(automation, 'launch', return_value=subprocess.CompletedProcess([], 0, output, '')):
                self.assertEqual(automation.disabled(), {'com.tianli.a': True, 'com.tianli.b': False})

    def test_paused_job_cannot_run_or_reload(self):
        for action in ['run', 'reload']:
            with patch.object(automation, 'loaded', return_value=None), patch.object(automation, 'disabled', return_value={'com.tianli.a': True}), patch.object(automation, 'launch') as launch:
                with self.assertRaisesRegex(ValueError, '已暂停'):
                    automation.control(action, 'com.tianli.a', '/unused.plist', {})
                launch.assert_not_called()


if __name__ == '__main__':
    unittest.main()
