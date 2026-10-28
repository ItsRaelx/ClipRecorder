#!/bin/zsh
# Assembles ClipRecorder.app from a built binary.
# Usage: scripts/make-app.sh <binary> <path.app> [version] [build-number]
set -euo pipefail
cd "$(dirname "$0")/.."

BIN=$1
APP=$2
VERSION=${3:-}
BUILD=${4:-}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipRecorder"
cp Resources/Info.plist "$APP/Contents/"
# Translations (en = base, pl, …)
for lproj in Resources/*.lproj; do cp -R "$lproj" "$APP/Contents/Resources/"; done
if [[ -n "$VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "$BUILD" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi

# Icon: Resources/AppIcon-1024.png → AppIcon.icns (source: Tools/make-icon.swift)
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"
