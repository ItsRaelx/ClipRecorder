#!/bin/zsh
# Renders the UI screenshots (docs, README) in every language. Usage (inside macos/): scripts/snapshots.sh
# English goes to ../docs/en/macos/screenshots, Polish to ../docs/pl/macos/screenshots (same file names).
#
# The generator runs in a temporary .app bundle with its own identifier: it carries the app's
# translations (so system-provided parts such as the trim bar follow the language too), and the
# installed app's settings stay untouched.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/ClipRecorder Snapshots.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClipRecorder "$APP/Contents/MacOS/ClipRecorder"
for lproj in Resources/*.lproj; do cp -R "$lproj" "$APP/Contents/Resources/"; done
plutil -convert xml1 -o "$APP/Contents/Info.plist" Resources/Info.plist
plutil -replace CFBundleIdentifier -string io.github.itsraelx.ClipRecorder.snapshots "$APP/Contents/Info.plist"

# language  locale (time and number formats in the pictures)
for lang locale in en en_US pl pl_PL; do
  OUT=../docs/$lang/macos/screenshots
  mkdir -p "$OUT"
  "$APP/Contents/MacOS/ClipRecorder" --snapshot "$OUT" -AppleLanguages "($lang)" -AppleLocale "$locale"
  # The hero shots are 2560 px wide – 1600 is plenty for the README.
  for f in "$OUT"/hero-*.png; do sips -Z 1600 "$f" >/dev/null; done
  echo "✓ Screenshots ($lang) in $OUT"
done
