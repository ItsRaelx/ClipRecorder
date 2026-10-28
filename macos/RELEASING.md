# Releasing ClipRecorder for macOS

[🇵🇱 Polski](RELEASING.pl.md)

Run all commands in the `macos/` folder.

`v*` tags (e.g. `v1.1.0`) are macOS releases. The Windows app has its own `windows-v*` tags
(see [windows/README.md](../windows/README.md)), so the two never mix.

## Every release

1. Bump the version in `Resources/Info.plist` (`CFBundleShortVersionString`), e.g. `1.1.0`, and commit.
2. Tag and push:
   ```sh
   git tag v1.1.0
   git push origin main v1.1.0
   ```
3. The **Release (macOS)** workflow builds a universal DMG and publishes it in GitHub Releases.
   Users' apps will show a "Version 1.1.0 available" banner (they check once a day).

Locally, `./release.sh 1.1.0` does the same (output in `dist/`).

Without an Apple certificate you get a **test release** (ad-hoc signature): macOS shows a warning, and after every
update users have to grant the screen recording and microphone permissions again.

## Signed releases – one-time setup (Apple Developer Program, $99/year)

### 1. Account
Enroll at <https://developer.apple.com/programs/> (an individual account is enough; you need an Apple ID with
two-factor authentication).

### 2. "Developer ID Application" certificate
1. <https://developer.apple.com/account/resources/certificates> → **+** → *Developer ID Application*.
2. Create the CSR in *Keychain Access* → *Certificate Assistant* → *Request a Certificate From a Certificate
   Authority* (save it to disk).
3. Download the certificate and double-click it (it goes into your keychain).
4. Check the identity name:
   ```sh
   security find-identity -p codesigning -v
   # → "Developer ID Application: Jane Doe (TEAMID)"
   ```
5. Export it together with the private key to a `.p12` file (in Keychain Access: right-click → *Export*, set a
   password).

### 3. API key for notarization
<https://appstoreconnect.apple.com/access/integrations/api> → *Team Keys* → **+**, role *Developer*.
Note the **Key ID** and **Issuer ID** and download `AuthKey_XXXX.p8` (it can be downloaded only once).

### 4. GitHub secrets
Repo → *Settings* → *Secrets and variables* → *Actions* → *New repository secret*:

| Secret | Value |
|---|---|
| `MACOS_CERT_P12_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | the `.p12` password |
| `DEVELOPER_ID` | `Developer ID Application: Jane Doe (TEAMID)` |
| `NOTARY_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `NOTARY_KEY_ID` | Key ID |
| `NOTARY_ISSUER_ID` | Issuer ID |

From then on every `v*` tag produces a signed and notarized DMG.

### 5. (Optional) locally
```sh
xcrun notarytool store-credentials clip-notary --key AuthKey_XXXX.p8 --key-id KEYID --issuer ISSUERID
DEVELOPER_ID="Developer ID Application: Jane Doe (TEAMID)" NOTARY_PROFILE=clip-notary ./release.sh 1.1.0
```

## Good to know

- **Don't change `CFBundleIdentifier`** (`io.github.itsraelx.ClipRecorder`) – macOS ties users' permissions and
  settings to it.
- The first Developer ID–signed release changes the signature compared to test releases, so users of test releases
  will grant the permissions once more. Later updates won't touch them.
- A Developer ID certificate is valid for 5 years; apps signed before it expires keep working.
