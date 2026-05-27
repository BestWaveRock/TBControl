#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "请用 sudo 运行: sudo $0"
    exit 1
fi

echo "==> 卸载 TBControl..."

# 停止并卸载守护进程
if launchctl list | grep -q com.tbcontrol.tbcontrold; then
    echo "停止服务..."
    launchctl unload /Library/LaunchDaemons/com.tbcontrol.tbcontrold.plist 2>/dev/null || true
fi

# 卸载 KEXT
echo "卸载内核扩展..."
kextstat -b com.tbcontrol.DisableTurboBoost | grep -q . && kextunload -b com.tbcontrol.DisableTurboBoost 2>/dev/null || true

# 删除文件
echo "删除系统文件..."
rm -rf /Applications/TBControl.app
rm -f /Library/LaunchDaemons/com.tbcontrol.tbcontrold.plist
rm -f /Library/LaunchDaemons/com.tbcontrol.daemon.plist
rm -f /Library/PrivilegedHelperTools/com.tbcontrol.tbcontrold
rm -rf /Library/PrivilegedHelperTools/DisableTurboBoost.kext
rm -rf "/Library/Application Support/TBControl"
rm -f /tmp/tbcontrol.sock
rm -f /var/log/tbcontrol.log
rm -f /tmp/com.tbcontrol.tbcontrold.plist

echo "✅ 卸载完成"
