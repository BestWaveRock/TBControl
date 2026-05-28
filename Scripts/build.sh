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

# 如果指定了 ARCH 环境变量，则强制使用该架构
if [ ! -z "$ARCH" ]; then
    echo "    [ARCH] 强制使用架构: $ARCH"
    swift build -c release --product tbcontrold --arch "$ARCH"
    swift build -c release --product TBControl --arch "$ARCH"
    RELEASE_DIR="$PROJECT_DIR/.build/$ARCH-apple-macosx/release"
    if [ ! -d "$RELEASE_DIR" ]; then
        # 某些 Swift 版本可能路径不同
        RELEASE_DIR="$PROJECT_DIR/.build/release"
    fi
else
    # 尝试 Universal 构建，如果失败（如仅安装了 CLT）则退回到原生架构构建
    if swift build -c release --product tbcontrold --arch x86_64 --arch arm64 2>/dev/null && \
       swift build -c release --product TBControl --arch x86_64 --arch arm64 2>/dev/null; then
        echo "    [OK] Universal Binary 构建成功"
        RELEASE_DIR="$PROJECT_DIR/.build/apple/Products/Release"
    else
        echo "    [!] Universal 构建失败 (可能缺少完整 Xcode)，尝试原生架构构建..."
        swift build -c release --product tbcontrold
        swift build -c release --product TBControl
        RELEASE_DIR="$PROJECT_DIR/.build/release"
    fi
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

echo "==> 准备 DMG 内容 (Staging)..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# 将 App 移动到暂存区
cp -R "$APP_BUNDLE" "$DMG_STAGING/TBControl.app"

# 创建 /Applications 快捷方式
ln -s /Applications "$DMG_STAGING/Applications"

echo "==> 创建 DMG..."
DMG_PATH="$BUILD_DIR/TBControl.dmg"
rm -f "$DMG_PATH"

hdiutil create -volname "TBControl" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

# 清理暂存区
rm -rf "$DMG_STAGING"

echo ""
echo "✅ 构建完成!"
echo "   App Bundle: $APP_BUNDLE"
echo "   DMG:        $DMG_PATH"
