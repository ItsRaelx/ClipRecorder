# Wydawanie ClipRecordera na macOS

[🇬🇧 English](RELEASING.md)

Wszystkie polecenia uruchamiasz w folderze `macos/`.

Tagi `v*` (np. `v1.1.0`) to wydania na macOS. Aplikacja na Windowsa ma własne tagi `windows-v*`
(zob. [windows/README.pl.md](../windows/README.pl.md)), więc oba wydania się nie mieszają.

## Wydanie (każdorazowo)

1. Podbij wersję w `Resources/Info.plist` (`CFBundleShortVersionString`), np. `1.1.0`, i zrób commit.
2. Otaguj i wypchnij:
   ```sh
   git tag v1.1.0
   git push origin main v1.1.0
   ```
3. Workflow **Release** zbuduje universal DMG i opublikuje go w GitHub Releases.
   Aplikacje użytkowników zobaczą baner „Dostępna wersja 1.1.0” (sprawdzają raz dziennie).

Lokalnie to samo robi `./release.sh 1.1.0` (wynik w `dist/`).

Bez certyfikatu Apple powstaje **wydanie testowe** (podpis ad-hoc): macOS pokaże ostrzeżenie,
a po każdej aktualizacji trzeba ponownie nadać uprawnienia do nagrywania ekranu i mikrofonu.

## Podpisane wydania – konfiguracja jednorazowa (Apple Developer Program, 99 $/rok)

### 1. Konto
Zapisz się na <https://developer.apple.com/programs/> (konto indywidualne wystarczy;
potrzebne Apple ID z weryfikacją dwuetapową).

### 2. Certyfikat „Developer ID Application”
1. <https://developer.apple.com/account/resources/certificates> → **+** → *Developer ID Application*.
2. CSR utwórz w *Dostęp do pęku kluczy* → *Asystent certyfikatów* → *Poproś o certyfikat od urzędu certyfikacji* (zapisz na dysku).
3. Pobierz certyfikat i kliknij go dwukrotnie (trafi do pęku kluczy).
4. Sprawdź nazwę tożsamości:
   ```sh
   security find-identity -p codesigning -v
   # → "Developer ID Application: Imię Nazwisko (TEAMID)"
   ```
5. Eksportuj go z kluczem prywatnym do `.p12` (w pęku kluczy: prawy klik → *Eksportuj*, ustaw hasło).

### 3. Klucz API do notaryzacji
<https://appstoreconnect.apple.com/access/integrations/api> → *Team Keys* → **+**, rola *Developer*.
Zapisz **Key ID**, **Issuer ID** i pobierz plik `AuthKey_XXXX.p8` (da się go pobrać tylko raz).

### 4. Sekrety w GitHubie
Repo → *Settings* → *Secrets and variables* → *Actions* → *New repository secret*:

| Sekret | Wartość |
|---|---|
| `MACOS_CERT_P12_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | hasło do `.p12` |
| `DEVELOPER_ID` | `Developer ID Application: Imię Nazwisko (TEAMID)` |
| `NOTARY_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `NOTARY_KEY_ID` | Key ID |
| `NOTARY_ISSUER_ID` | Issuer ID |

Od tej chwili każdy tag `v*` tworzy podpisany i notaryzowany DMG.

### 5. (Opcjonalnie) lokalnie
```sh
xcrun notarytool store-credentials clip-notary --key AuthKey_XXXX.p8 --key-id KEYID --issuer ISSUERID
DEVELOPER_ID="Developer ID Application: Imię Nazwisko (TEAMID)" NOTARY_PROFILE=clip-notary ./release.sh 1.1.0
```

## Dobrze wiedzieć

- **Nie zmieniaj `CFBundleIdentifier`** (`io.github.itsraelx.ClipRecorder`) – macOS wiąże z nim uprawnienia
  i ustawienia użytkowników.
- Pierwsze wydanie podpisane Developer ID zmienia podpis względem wydań testowych, więc użytkownicy
  wydań testowych jednorazowo nadadzą uprawnienia ponownie. Kolejne aktualizacje już ich nie ruszą.
- Certyfikat Developer ID jest ważny 5 lat; aplikacje podpisane przed jego wygaśnięciem nadal działają.
