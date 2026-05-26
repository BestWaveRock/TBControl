#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "请用 sudo 运行: sudo $0"
    exit 1
fi

echo "==> 卸载 TBControl..."

# 停止并卸载守护进程
if launchctl list | grep -q com.tbcontrol.daemon; then
    launchctl unload /Library/LaunchDaemons/com.tbcontrol.daemon.plist 2>/dev/null || true
fi

# 卸载 KEXT
kextstat -b com.tbcontrol.DisableTurboBoost | grep -q . && kextunload -b com.tbcontrol.DisableTurboBoost 2>/dev/null || true

# 删除文件
rm -rf /Applications/TBControl.app
rm -rf "/Library/Application Support/TBControl"
rm -f /Library/LaunchDaemons/com.tbcontrol.daemon.plist
rm -f /var/log/tbcontrol.log
rm -f /var/run/tbcontrol.sock

echo "✅ 卸载完成"
