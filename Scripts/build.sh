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

echo "==> 编译 Swift 组件 (Universal Binaries)..."
cd "$PROJECT_DIR"
# 显式指定构建架构为 x86_64 和 arm64
swift build -c release --product tbcontrold --arch x86_64 --arch arm64
swift build -c release --product TBControl --arch x86_64 --arch arm64

# 定义二进制文件路径 (Universal binary usually stays in .build/apple/Products/Release)
# 或者在默认路径下，取决于 Swift 版本。我们将检查常规路径。
RELEASE_DIR="$PROJECT_DIR/.build/apple/Products/Release"
if [ ! -d "$RELEASE_DIR" ]; then
    # 兼容旧版本或单架构路径
    RELEASE_DIR="$PROJECT_DIR/.build/release"
fi

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

# 注入版本号 (如果环境变量 VERSION 存在)
if [ ! -z "$VERSION" ]; then
    echo "==> 注入版本号: $VERSION"
    # 清理 v 前缀
    CLEAN_VER=$(echo $VERSION | sed 's/^v//')
    plutil -replace CFBundleShortVersionString -string "$CLEAN_VER" "$APP_BUNDLE/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$CLEAN_VER" "$APP_BUNDLE/Contents/Info.plist"
    # 同时同步到源码配置文件，确保本地构建也一致
    plutil -replace CFBundleShortVersionString -string "$CLEAN_VER" "$PROJECT_DIR/Scripts/TBControl-Info.plist"
fi

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
