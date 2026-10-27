#!/bin/zsh
# Buduje wydanie: universal (Apple Silicon + Intel) ClipRecorder.app spakowany w DMG.
#
# Użycie: ./release.sh [wersja]          (domyślnie: ostatni tag git bez „v”)
#
# Bez zmiennych poniżej powstaje wydanie testowe podpisane ad-hoc
# (macOS pokaże ostrzeżenie „nie można zweryfikować twórcy”).
#
# Podpis Developer ID (wymaga konta Apple Developer, 99 $/rok):
#   DEVELOPER_ID="Developer ID Application: Imię Nazwisko (TEAMID)"
#
# Notaryzacja – jedno z dwóch:
#   NOTARY_PROFILE=nazwa          profil z `xcrun notarytool store-credentials`
#   NOTARY_KEY_PATH=AuthKey.p8    klucz API App Store Connect
#   NOTARY_KEY_ID=ABC123XYZ
#   NOTARY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# Szczegóły: RELEASING.md
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}
VERSION=${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
DIST=dist
APP=$DIST/ClipRecorder.app
DMG=$DIST/ClipRecorder-$VERSION.dmg

echo "→ ClipRecorder $VERSION (build $BUILD)"
rm -rf "$DIST"
mkdir -p "$DIST"

echo "→ Kompilacja (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
scripts/make-app.sh "$BIN_DIR/ClipRecorder" "$APP" "$VERSION" "$BUILD"
lipo -info "$APP/Contents/MacOS/ClipRecorder"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "→ Podpis: $DEVELOPER_ID"
  codesign --force --options runtime --timestamp \
    --entitlements Resources/ClipRecorder.entitlements --sign "$DEVELOPER_ID" "$APP"
else
  echo "⚠︎ Brak DEVELOPER_ID – podpis ad-hoc (wydanie testowe)"
  codesign --force --options runtime \
    --entitlements Resources/ClipRecorder.entitlements --sign - "$APP"
fi
codesign --verify --strict --deep "$APP"

echo "→ DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "ClipRecorder $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

  NOTARY_ARGS=()
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
  fi

  if (( ${#NOTARY_ARGS} )); then
    echo "→ Notaryzacja (może potrwać kilka minut)"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
  else
    echo "⚠︎ Brak danych do notaryzacji – DMG jest podpisany, ale nie notaryzowany"
  fi
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "✓ Gotowe: $DMG"
