#!/bin/bash
set -e

echo "==> TBControl 安装程序"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "请用 sudo 运行: sudo $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

# 确定安装源
if [ -d "$BUILD_DIR/TBControl.app" ]; then
    APP_SOURCE="$BUILD_DIR/TBControl.app"
elif [ -d "/Applications/TBControl.app" ]; then
    APP_SOURCE="/Applications/TBControl.app"
else
    echo "错误: 找不到 TBControl.app，请先运行 build.sh"
    exit 1
fi

echo "1/4  安装 App..."
cp -R "$APP_SOURCE" /Applications/TBControl.app

echo "2/4  安装 KEXT..."
KEXT_SRC="/Applications/TBControl.app/Contents/Resources/DisableTurboBoost.kext"
KEXT_DST="/Library/Application Support/TBControl/DisableTurboBoost.kext"
mkdir -p "/Library/Application Support/TBControl"
cp -R "$KEXT_SRC" "$KEXT_DST"
chown -R root:wheel "$KEXT_DST"

echo "3/4  安装守护进程..."
DAEMON_SRC="/Applications/TBControl.app/Contents/Resources/tbcontrold"
DAEMON_DST="/Library/Application Support/TBControl/tbcontrold"
cp "$DAEMON_SRC" "$DAEMON_DST"
chown root:wheel "$DAEMON_DST"
chmod 755 "$DAEMON_DST"

cat > /Library/LaunchDaemons/com.tbcontrol.daemon.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tbcontrol.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DAEMON_DST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>UserName</key>
    <string>root</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>/var/log/tbcontrol.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/tbcontrol.log</string>
</dict>
</plist>
PLIST

chown root:wheel /Library/LaunchDaemons/com.tbcontrol.daemon.plist
chmod 644 /Library/LaunchDaemons/com.tbcontrol.daemon.plist

echo "4/4  启动守护进程..."
launchctl load /Library/LaunchDaemons/com.tbcontrol.daemon.plist
launchctl start com.tbcontrol.daemon

echo ""
echo "✅ 安装完成!"
echo "   已安装到: /Applications/TBControl.app"
echo "   守护进程: com.tbcontrol.daemon"
echo ""
echo "打开 App 即可使用。首次禁用 Turbo Boost 需在"
echo "系统设置 > 隐私与安全性 中允许加载内核扩展。"
