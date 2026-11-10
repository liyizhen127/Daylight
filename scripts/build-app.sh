#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_ROOT="${DAYLIGHT_BUILD_ROOT:-$PWD/build}"
mkdir -p "$BUILD_ROOT/module-cache" "$BUILD_ROOT/package-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/module-cache"
swift build --disable-sandbox -c release --scratch-path "$BUILD_ROOT/swift" --cache-path "$BUILD_ROOT/package-cache"
BIN_DIR="$(swift build --disable-sandbox -c release --scratch-path "$BUILD_ROOT/swift" --cache-path "$BUILD_ROOT/package-cache" --show-bin-path)"
APP="$BUILD_ROOT/Daylight.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_ROOT/AppIcon.iconset"
cp "$BIN_DIR/DaylightGoals" "$APP/Contents/MacOS/DaylightGoals"
# Remove debug and local symbols, including compiler-recorded developer paths.
xcrun strip -S -x "$APP/Contents/MacOS/DaylightGoals"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp THIRD-PARTY-NOTICES.txt "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"
swift scripts/icon.swift "$BUILD_ROOT/AppIcon.png"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$BUILD_ROOT/AppIcon.png" --out "$BUILD_ROOT/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$BUILD_ROOT/AppIcon.png" --out "$BUILD_ROOT/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD_ROOT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
