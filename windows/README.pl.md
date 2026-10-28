# ClipRecorder na Windowsa

> **Status: w przygotowaniu.** Ten folder jest zarezerwowany na aplikację na Windowsa. Kodu jeszcze nie ma.
> Działająca wersja na macOS jest w [`../macos`](../macos).

## Cel

Ta sama aplikacja co na macOS, w wersji natywnej dla Windowsa:

- ikona w zasobniku obok zegara;
- bufor ostatnich 30 s – 10 min ekranu, dźwięku komputera i mikrofonu;
- globalne skróty: zapisz, nagrywaj dalej, znacznik;
- karta podglądu po zapisie, przycinanie;
- osobne ścieżki dźwięku i miks;
- udostępnianie linkiem przez [clip.secc.me](https://clip.secc.me) na tym samym koncie co na Macu;
- pauza na czas, na baterii i przy zablokowanym ekranie;
- adresy `cliprecorder://` do automatyzacji.

Pełny opis zachowania (to jest specyfikacja dla wersji na Windowsa) jest w
[dokumentacji wersji na macOS](../docs/macos/README.md).

## Planowany stos

Do potwierdzenia przed rozpoczęciem prac. Propozycja: **C# / .NET** z interfejsem w **WinUI 3** albo **WPF**.

| Część | macOS (obecnie) | Windows (plan) |
|---|---|---|
| Przechwytywanie ekranu | ScreenCaptureKit | Windows.Graphics.Capture |
| Sprzętowe kodowanie wideo | VideoToolbox (HEVC) | Media Foundation (H.264/HEVC przez NVENC, AMF, Quick Sync) |
| Dźwięk komputera / mikrofon | ScreenCaptureKit / AVFoundation | WASAPI (loopback + capture) |
| Zapis i obróbka plików | AVFoundation | Media Foundation (Sink Writer) |
| Ikona w pasku | NSStatusItem | ikona w zasobniku (Shell_NotifyIcon) |
| Globalne skróty | Carbon `RegisterEventHotKey` | `RegisterHotKey` |
| Przechowywanie tokenu | pęk kluczy | Menedżer poświadczeń Windows |
| Zasilanie / blokada ekranu | IOKit, powiadomienia NSWorkspace | `RegisterPowerSettingNotification`, `WTSRegisterSessionNotification` |
| Adresy `cliprecorder://` | `CFBundleURLTypes` | protokół zarejestrowany w rejestrze |
| Uruchamianie przy logowaniu | `SMAppService` | klucz `Run` w rejestrze albo zadanie startowe |

## Konwencje repozytorium

| Co | Gdzie / jak |
|---|---|
| Kod aplikacji | `windows/` (np. `windows/src/…`, rozwiązanie `.sln` w `windows/`) |
| Dokumentacja | [`docs/windows/`](../docs/windows/README.md) |
| CI | `.github/workflows/windows-*.yml` z filtrem `paths: ["windows/**"]` |
| Tagi wydań | `windows-v0.1.0`, `windows-v0.2.0`, …  (macOS używa `v1.0.0`) |
| Wydania na GitHubie | tytuł „ClipRecorder X (Windows)”, publikowane z **`--latest=false`** |

**Dlaczego `--latest=false`:** aplikacja na Maca sprawdza aktualizacje przez `/releases/latest`.
Gdyby wydanie na Windowsa zostało oznaczone jako „najnowsze”, Maci pokazałyby baner o złej wersji.
Wersja na Windowsa powinna szukać aktualizacji na liście wydań, wśród tagów `windows-v*`.

## Wspólne elementy

- **Serwer clip.secc.me:** to samo API co na macOS:
  - logowanie kodem urządzenia (`/api/device/start`, `/api/device/poll`);
  - konto i limity (`/api/me`);
  - wysyłanie w częściach (`/api/clips`, `/parts/N`, `/thumbnail`).

  Implementacją wzorcową jest [`macos/Sources/ClipRecorder/CloudService.swift`](../macos/Sources/ClipRecorder/CloudService.swift).
- **Ikona:** [`macos/Resources/AppIcon-1024.png`](../macos/Resources/AppIcon-1024.png)
  (generator: [`macos/Tools/make-icon.swift`](../macos/Tools/make-icon.swift)).
- **Teksty interfejsu:** po polsku, jak na macOS.
- **Licencja:** ta sama, [PolyForm Noncommercial 1.0.0](../LICENSE).

## Testowanie

Przechwytywania ekranu i kodowania wideo nie da się sprawdzić w CI. Potrzebny jest prawdziwy komputer
z Windowsem 10 (2004+) albo 11, najlepiej przetestowany na kartach graficznych NVIDIA, AMD i Intel.
