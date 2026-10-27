#!/bin/zsh
# Buduje ClipRecorder.app. Użycie: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/ClipRecorder.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClipRecorder "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# Ikona: Resources/AppIcon-1024.png → AppIcon.icns (źródło: Tools/make-icon.swift)
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Stały podpis = macOS pamięta uprawnienia (ekran, mikrofon) po przebudowaniu.
# Bez SIGN_IDENTITY używamy lokalnego certyfikatu, tworzonego jednorazowo w pęku kluczy „login”.
LOCAL_IDENTITY="ClipRecorder Local Signing"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  if ! security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
    echo "→ Tworzę lokalny certyfikat „$LOCAL_IDENTITY” (jednorazowo)"
    TMP=$(mktemp -d)
    cat > "$TMP/cert.cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $LOCAL_IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CFG
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cfg" \
      -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
      -name "$LOCAL_IDENTITY" -out "$TMP/id.p12" -passout pass:cliprecorder
    security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db \
      -P cliprecorder -T /usr/bin/codesign >/dev/null
    rm -rf "$TMP"
  fi
  SIGN_IDENTITY="$LOCAL_IDENTITY"
fi
codesign --force --options runtime --sign "$SIGN_IDENTITY" \
  --entitlements Resources/ClipRecorder.entitlements "$APP"
echo "✓ Zbudowano $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ClipRecorder 2>/dev/null || true
  rm -rf /Applications/ClipRecorder.app
  cp -R "$APP" /Applications/
  open /Applications/ClipRecorder.app
  echo "✓ Zainstalowano w /Applications i uruchomiono"
fi
