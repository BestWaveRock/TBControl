#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$PROJECT_DIR/.build/release"

echo "==> 编译 KEXT..."
cd "$PROJECT_DIR/Kext"
make clean 2>/dev/null || true
make
KEXT_BUNDLE="$PROJECT_DIR/Kext/build/DisableTurboBoost.kext"

echo "==> 编译 Swift 组件..."
cd "$PROJECT_DIR"
swift build -c release --product tbcontrold
swift build -c release --product TBControl

echo "==> 创建 TBControl.app 包..."
APP_BUNDLE="$BUILD_DIR/TBControl.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$RELEASE_DIR/TBControl" "$APP_BUNDLE/Contents/MacOS/TBControl"
cp "$RELEASE_DIR/tbcontrold" "$APP_BUNDLE/Contents/Resources/tbcontrold"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp -R "$KEXT_BUNDLE" "$APP_BUNDLE/Contents/Resources/DisableTurboBoost.kext"

cp "$PROJECT_DIR/Scripts/TBControl-Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> 优化二进制文件 (Strip & Sign)..."
strip "$APP_BUNDLE/Contents/MacOS/TBControl"
strip "$APP_BUNDLE/Contents/Resources/tbcontrold"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> 创建 DMG..."
DMG_PATH="$BUILD_DIR/TBControl.dmg"
rm -f "$DMG_PATH"

hdiutil create -volname "TBControl" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

echo ""
echo "✅ 构建完成!"
echo "   App Bundle: $APP_BUNDLE"
echo "   DMG:        $DMG_PATH"
