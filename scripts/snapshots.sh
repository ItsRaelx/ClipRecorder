#!/bin/zsh
# Renderuje zrzuty interfejsu (dokumentacja, README). Użycie: scripts/snapshots.sh [folder]
# Domyślnie zapisuje do docs/screenshots.
#
# Generator działa w tymczasowej paczce .app z osobnym identyfikatorem: elementy systemowe
# (np. pasek przycinania) są po polsku, a ustawienia zainstalowanej aplikacji zostają nietknięte.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-docs/screenshots}

swift build -c release
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/ClipRecorder Snapshots.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClipRecorder "$APP/Contents/MacOS/ClipRecorder"
plutil -convert xml1 -o "$APP/Contents/Info.plist" Resources/Info.plist
plutil -replace CFBundleIdentifier -string io.github.itsraelx.ClipRecorder.snapshots "$APP/Contents/Info.plist"

mkdir -p "$OUT"
"$APP/Contents/MacOS/ClipRecorder" --snapshot "$OUT"
# Zrzuty „hero” mają 2560 px szerokości – do README wystarczy 1600.
for f in "$OUT"/hero-*.png; do sips -Z 1600 "$f" >/dev/null; done
echo "✓ Zrzuty w $OUT"
