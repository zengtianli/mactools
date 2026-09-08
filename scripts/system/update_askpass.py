#!/usr/bin/env python3
"""sudo askpass for Homebrew: password goes only to sudo's private stdout pipe."""
import os
from pathlib import Path
import subprocess
import sys

SCRIPT = '''on run argv
    set itemName to item 1 of argv
    tell application "System Events"
        activate
        set answer to display dialog ("Homebrew 正在更新：" & itemName & return & return & "此步骤需要 sudo 管理员权限。密码仅交给本次 sudo，不会保存。" & return & "取消后，本轮不再请求密码。") with title "Homebrew 软件更新授权" default answer "" with hidden answer buttons {"取消本轮授权", "授权"} default button "授权" cancel button "取消本轮授权" giving up after 120
        if gave up of answer then error number -128
        return text returned of answer
    end tell
end run
'''


def main():
    raw = os.environ.get('AUTOMATION_UPDATE_CANCEL_FILE')
    if not raw:
        return 1
    cancelled = Path(raw)
    if cancelled.exists():
        return 1
    item = os.environ.get('AUTOMATION_UPDATE_ITEM', 'Homebrew 软件维护')
    try:
        result = subprocess.run(['/usr/bin/osascript', '-e', SCRIPT, item],
                                capture_output=True, text=True, timeout=130)
        # Never log stdout/stderr or attach the process result to an exception.
        if result.returncode or not result.stdout.rstrip('\n'):
            cancelled.touch(mode=0o600)
            return 1
        sys.stdout.write(result.stdout.rstrip('\n') + '\n')
        sys.stdout.flush()
        return 0
    except (OSError, subprocess.TimeoutExpired):
        cancelled.touch(mode=0o600)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
