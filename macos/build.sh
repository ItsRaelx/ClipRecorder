#!/bin/zsh
# Development build (this Mac's architecture only). Usage: ./build.sh [--install]
# Public releases (universal + DMG + notarization): ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/ClipRecorder.app
scripts/make-app.sh .build/release/ClipRecorder "$APP"

# A stable signature lets macOS remember the permissions (screen, microphone) across rebuilds.
# Without SIGN_IDENTITY we use a local certificate, created once in the "login" keychain.
LOCAL_IDENTITY="ClipRecorder Local Signing"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  if ! security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
    echo "→ Creating the local certificate \"$LOCAL_IDENTITY\" (one time)"
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
echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ClipRecorder 2>/dev/null || true
  rm -rf /Applications/ClipRecorder.app
  cp -R "$APP" /Applications/
  open /Applications/ClipRecorder.app
  echo "✓ Installed to /Applications and launched"
fi
