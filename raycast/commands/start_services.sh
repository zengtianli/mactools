#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Start Background Service
# @raycast.mode compact
# @raycast.icon ⚙️
# @raycast.packageName System
# @raycast.argument1 { "type": "dropdown", "placeholder": "service", "data": [ {"title":"Window Manager (yabai+skhd)","value":"wm"}, {"title":"yabai","value":"yabai"}, {"title":"skhd","value":"skhd"}, {"title":"ollama","value":"ollama"}, {"title":"syncthing","value":"syncthing"}, {"title":"xray","value":"xray"}, {"title":"lucarned","value":"lucarned"} ] }
# @raycast.description 按需启动登录时不再自启的后台服务(只启动,不重新注册开机自启)
#
# 配套「只留 Raycast 登录自启」方案: 这些服务的开机自启已取消(plist 备份在
# ~/Dev/_scratch/disabled-login-autostart-*/), 需要时用本命令手动拉起。
set -uo pipefail
BREW=/opt/homebrew/bin
BIN=/opt/homebrew/bin

# CLI 服务直接后台拉起(nohup 脱离,脚本退出后存活), 不安装 launchd 自启
spawn(){ nohup "$1" >/dev/null 2>&1 & disown; }

case "${1:-}" in
  wm)        spawn "$BIN/yabai"; spawn "$BIN/skhd"; echo "✅ yabai + skhd 已启动";;
  yabai)     spawn "$BIN/yabai"; echo "✅ yabai 已启动";;
  skhd)      spawn "$BIN/skhd";  echo "✅ skhd 已启动";;
  # brew services run = 运行但不注册开机自启(区别于 start)
  ollama)    "$BREW/brew" services run ollama    >/dev/null 2>&1 && echo "✅ ollama 已启动";;
  syncthing) "$BREW/brew" services run syncthing >/dev/null 2>&1 && echo "✅ syncthing 已启动";;
  xray)      "$BREW/brew" services run xray      >/dev/null 2>&1 && echo "✅ xray 已启动";;
  lucarned)  "$BREW/brew" services run lucarned  >/dev/null 2>&1 && echo "✅ lucarned 已启动";;
  *)         echo "用法: 在下拉里选服务"; exit 1;;
esac