#!/bin/bash
# 构建原生 macOS 应用包：
#   swift build -c release（优先 universal，失败退化为本机架构）
#   → 组装 DeepSeek Harness Shell.app → 生成 AppIcon.icns → ad-hoc 签名 → zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> 1/5 编译 release 版本"
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    echo "    已构建 universal (arm64 + x86_64)"
else
    echo "    通用构建不可用，构建本机架构"
    swift build -c release
fi

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/DeepSeekHarnessShell"
APP="$ROOT/build/DeepSeek Harness Shell.app"

echo "==> 2/5 组装应用包 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeepSeekHarnessShell"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> 3/5 生成应用图标"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET" "$ROOT/build/AppIcon.icns"
swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> 4/5 清理扩展属性并 ad-hoc 签名"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"

echo "==> 5/5 打包 zip"
rm -f "$ROOT/build/DeepSeek Harness Shell.zip"
ditto -c -k --keepParent "$APP" "$ROOT/build/DeepSeek Harness Shell.zip"

echo
echo "完成：$APP"
du -sh "$APP"
du -sh "$ROOT/build/DeepSeek Harness Shell.zip"
echo "可执行：open \"$APP\""
