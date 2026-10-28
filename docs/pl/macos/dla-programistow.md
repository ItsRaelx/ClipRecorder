# Dla programistów

[← Spis treści](README.md) · [🇬🇧 English](../../en/macos/developers.md)

Aplikacja na macOS to pakiet Swift (bez projektu Xcode) w folderze [`macos/`](../../../macos), zbudowany na
ScreenCaptureKit, VideoToolbox, AVFoundation i SwiftUI. Wystarczą same Command Line Tools.

```sh
cd macos
swift build -c release   # binarka w .build/release/ClipRecorder
./build.sh --install     # paczka .app z podpisem, instalacja w /Applications
./release.sh 1.1.0       # universal DMG (opcjonalnie podpis Developer ID + notaryzacja), wynik w dist/
```

## Przepływ danych

```
ScreenCaptureKit ──► obraz ──► VideoToolbox (HEVC, w czasie rzeczywistym) ─┐
      │                                                                    ├─► SampleRing (bufor: RAM albo pliki na dysku)
      ├──► dźwięk systemu (PCM) ───────────────────────────────────────────┤        │
      └──► mikrofon (PCM) ─────────────────────────────────────────────────┘        │ skrót
                                                                                     ▼
                                       ClipWriter (.mov: HEVC bez rekompresji + 2× AAC, części co 5 s)
                                                                                     │
                                       ClipFinalizer (ścieżka „Miks” z ogranicznikiem, rozdziały, przycinanie)
                                                                                     │
                                       ShareExporter (MP4 H.264 do 1080p) ──► CloudService (upload w częściach)
```

- Obraz jest kodowany **od razu** i w buforze leżą już skompresowane próbki HEVC. Zapis klipu to kopiowanie bez
  ponownego kodowania, więc jest natychmiastowy.
- Gdy ekran stoi, ScreenCaptureKit nie wysyła klatek. Silnik koduje wtedy ostatnią klatkę dwa razy na sekundę,
  żeby bufor zawsze zaczynał się od klatki kluczowej.
- Bufor 5 i 10 min trafia do ~10-sekundowych plików w `~/Library/Caches/ClipRecorder/Buffer/<sesja>`. Otwarty jest
  tylko plik aktualnie zapisywany, bo aplikacje GUI mają limit 256 deskryptorów.
- Dźwięk jest trzymany jako PCM i kodowany do AAC 48 kHz dopiero przy zapisie klipu. Każdy mikrofon działa,
  także 8 i 16 kHz.

## Pliki źródłowe

| Plik | Rola |
|---|---|
| `CaptureEngine.swift` | strumień ScreenCaptureKit, enkoder HEVC, bufory, klipy, ponawianie startu, filtr wykluczonych aplikacji |
| `SampleRing.swift` | bufor próbek jednej ścieżki – w RAM albo w plikach na dysku |
| `ClipWriter.swift` | zapis klipu (AVAssetWriter, wideo bez rekompresji + AAC, fragmenty co 5 s) |
| `ClipFinalizer.swift` | ścieżka *Miks*, rozdziały, przycinanie – bez ponownego kodowania obrazu |
| `ShareExporter.swift` | MP4 H.264 (do 1080p, ścieżka miksu) przed wysłaniem |
| `CloudService.swift` | konto clip.secc.me: logowanie kodem urządzenia, token w pęku kluczy, upload w częściach, limity |
| `AppState.swift` | stan aplikacji i ustawienia, pauza, zasilanie, blokada ekranu, udostępnianie |
| `HotKey.swift` | globalne skróty (Carbon `RegisterEventHotKey`, bez uprawnień Dostępności) |
| `PowerMonitor.swift` | bateria i tryb niskiego zużycia energii |
| `Microphones.swift` | lista mikrofonów i wybór automatyczny (bez Bluetooth) |
| `ClipLibrary.swift` | nazwy plików, lista klipów, sprzątanie do Kosza |
| `ClipInfo.swift` | miniatury, długość i rozmiar na liście „Ostatnie klipy” |
| `UpdateChecker.swift` | sprawdzanie nowych wersji w GitHub Releases |
| `main.swift` | `AppDelegate`: ikona w pasku menu, popover, szybkie menu, pasek nagrywania, adresy `cliprecorder://` |
| `PopoverView.swift`, `RecordingHUD.swift`, `ClipPreview.swift`, `SettingsView.swift`, `Components.swift` | interfejs (SwiftUI) |
| `Snapshots.swift` | generator zrzutów ekranu do dokumentacji |

## Zrzuty ekranu

Wszystkie obrazki w `docs/en/macos/screenshots` i `docs/pl/macos/screenshots` są generowane z kodu, bez prawdziwego
nagrywania i bez sieci:

```sh
scripts/snapshots.sh   # → docs/en/macos/screenshots i docs/pl/macos/screenshots (uruchamiane w macos/)
```

Skrypt uruchamia aplikację z `--snapshot` w tymczasowej paczce `.app` z osobnym identyfikatorem. Dzięki temu:
- systemowe elementy są w języku danego zestawu zrzutów;
- startuje z domyślnymi ustawieniami;
- nie dotyka ustawień ani pęku kluczy zainstalowanej aplikacji.

Konto, klipy, miniatury i lista aplikacji są fikcyjne. Większość ekranów powstaje w wersji `-light` i `-dark`,
a dokumentacja wybiera właściwą przez `<picture>` zgodnie z motywem GitHuba.

Po zmianie interfejsu uruchom skrypt i dołącz nowe obrazki do commita.

## Wydania

Wersję podbija się w `macos/Resources/Info.plist`. Tag `v*` uruchamia workflow **Release**, który buduje universal DMG
i publikuje go w GitHub Releases razem z sumą SHA-256. Szczegóły, w tym podpisywanie i notaryzację,
opisuje [macos/RELEASING.md](../../../macos/RELEASING.md).

Workflow **Build** buduje aplikację przy każdym pushu do `main` i każdym pull requeście.

## Konwencje

- Swift 5 language mode (Swift 6 toolchain), macOS 15+.
- Teksty interfejsu są w kodzie po angielsku, a polskie tłumaczenia leżą w
  `macos/Resources/pl.lproj/Localizable.strings`. Komentarze w kodzie są po angielsku.
- Stan mutowalny silnika żyje na jednej szeregowej kolejce (`CaptureEngine.queue`), a stan UI na `MainActor`.
- Bez zależności zewnętrznych.
