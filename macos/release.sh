#!/bin/zsh
# Builds a release: a universal (Apple Silicon + Intel) ClipRecorder.app packed in a DMG.
#
# Usage: ./release.sh [version]          (default: the latest v* git tag without the "v")
#
# Without the variables below you get an ad-hoc signed test release
# (macOS warns that the developer cannot be verified).
#
# Developer ID signature (requires an Apple Developer account, $99/year):
#   DEVELOPER_ID="Developer ID Application: Jane Doe (TEAMID)"
#
# Notarization – one of:
#   NOTARY_PROFILE=name           profile from `xcrun notarytool store-credentials`
#   NOTARY_KEY_PATH=AuthKey.p8    App Store Connect API key
#   NOTARY_KEY_ID=ABC123XYZ
#   NOTARY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# Details: RELEASING.md
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)}  # skips windows-v* tags
VERSION=${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
DIST=dist
APP=$DIST/ClipRecorder.app
DMG=$DIST/ClipRecorder-$VERSION.dmg

echo "→ ClipRecorder $VERSION (build $BUILD)"
rm -rf "$DIST"
mkdir -p "$DIST"

echo "→ Compiling (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
scripts/make-app.sh "$BIN_DIR/ClipRecorder" "$APP" "$VERSION" "$BUILD"
lipo -info "$APP/Contents/MacOS/ClipRecorder"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "→ Signing: $DEVELOPER_ID"
  codesign --force --options runtime --timestamp \
    --entitlements Resources/ClipRecorder.entitlements --sign "$DEVELOPER_ID" "$APP"
else
  echo "⚠︎ No DEVELOPER_ID – ad-hoc signature (test release)"
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
    echo "→ Notarizing (may take a few minutes)"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
  else
    echo "⚠︎ No notarization credentials – the DMG is signed but not notarized"
  fi
fi

(cd "$DIST" && shasum -a 256 "${DMG:t}" | tee "${DMG:t}.sha256")
echo "✓ Done: $DMG"
