# For developers

[← Contents](README.md) · [🇵🇱 Polski](../../pl/macos/dla-programistow.md)

The macOS app is a Swift package (no Xcode project) in the [`macos/`](../../../macos) folder, built on
ScreenCaptureKit, VideoToolbox, AVFoundation and SwiftUI. The Command Line Tools are all you need.

```sh
cd macos
swift build -c release   # binary in .build/release/ClipRecorder
./build.sh --install     # signed .app bundle, installed to /Applications
./release.sh 1.1.0       # universal DMG (optionally Developer ID signing + notarization), output in dist/
```

## Data flow

```
ScreenCaptureKit ──► video ──► VideoToolbox (HEVC, real time) ────┐
      │                                                           ├─► SampleRing (buffer: RAM or files on disk)
      ├──► system audio (PCM) ────────────────────────────────────┤        │
      └──► microphone (PCM) ──────────────────────────────────────┘        │ shortcut
                                                                           ▼
                                       ClipWriter (.mov: HEVC without re-encoding + 2× AAC, 5 s fragments)
                                                                           │
                                       ClipFinalizer (“Mix” track with a limiter, chapters, trimming)
                                                                           │
                                       ShareExporter (MP4 H.264 up to 1080p) ──► CloudService (upload in parts)
```

- Video is encoded **right away**, so the buffer already holds compressed HEVC samples. Saving a clip is a copy
  without re-encoding, which makes it instant.
- When the screen is still, ScreenCaptureKit doesn't send frames. The engine then encodes the last frame twice per second,
  so the buffer always starts with a keyframe.
- The 5 and 10 min buffers go into ~10-second files in `~/Library/Caches/ClipRecorder/Buffer/<session>`. Only the file
  currently being written is open, because GUI apps have a limit of 256 file descriptors.
- Audio is kept as PCM and encoded to 48 kHz AAC only when a clip is saved. Any microphone works,
  including 8 and 16 kHz ones.

## Source files

| File | Role |
|---|---|
| `CaptureEngine.swift` | ScreenCaptureKit stream, HEVC encoder, buffers, clips, start retries, excluded apps filter |
| `SampleRing.swift` | sample buffer for one track – in RAM or in files on disk |
| `ClipWriter.swift` | writing a clip (AVAssetWriter, video without re-encoding + AAC, 5 s fragments) |
| `ClipFinalizer.swift` | the *Mix* track, chapters, trimming – without re-encoding the video |
| `ShareExporter.swift` | MP4 H.264 (up to 1080p, mix track) before uploading |
| `CloudService.swift` | clip.secc.me account: device code sign-in, token in the keychain, upload in parts, limits |
| `AppState.swift` | app state and settings, pause, power, screen lock, sharing |
| `HotKey.swift` | global shortcuts (Carbon `RegisterEventHotKey`, no Accessibility permission) |
| `PowerMonitor.swift` | battery and Low Power Mode |
| `Microphones.swift` | microphone list and automatic selection (no Bluetooth) |
| `ClipLibrary.swift` | file names, clip list, cleanup to the Trash |
| `ClipInfo.swift` | thumbnails, length and size in the “Recent clips” list |
| `UpdateChecker.swift` | checking GitHub Releases for new versions |
| `main.swift` | `AppDelegate`: menu bar icon, popover, quick menu, recording bar, `cliprecorder://` URLs |
| `PopoverView.swift`, `RecordingHUD.swift`, `ClipPreview.swift`, `SettingsView.swift`, `Components.swift` | user interface (SwiftUI) |
| `Snapshots.swift` | screenshot generator for the documentation |

## Screenshots

All images in `docs/en/macos/screenshots` and `docs/pl/macos/screenshots` are generated from code, with no actual
recording and no network:

```sh
scripts/snapshots.sh   # → docs/en/macos/screenshots and docs/pl/macos/screenshots (run in macos/)
```

The script runs the app with `--snapshot` in a temporary `.app` bundle with a separate bundle identifier. This way it:
- renders system-provided elements in the language of each screenshot set;
- starts with default settings;
- doesn't touch the settings or keychain of the installed app.

The account, clips, thumbnails and app list are fake. Most screens are rendered in a `-light` and a `-dark` version,
and the documentation picks the right one with `<picture>` to match GitHub's theme.

After changing the UI, run the script and include the new images in your commit.

## Releases

The version is bumped in `macos/Resources/Info.plist`. A `v*` tag triggers the **Release** workflow, which builds a universal DMG
and publishes it to GitHub Releases together with a SHA-256 checksum. Details, including signing and notarization,
are in [macos/RELEASING.md](../../../macos/RELEASING.md).

The **Build** workflow builds the app on every push to `main` and every pull request.

## Conventions

- Swift 5 language mode (Swift 6 toolchain), macOS 15+.
- UI strings are written in English in the code; the Polish translations live in
  `macos/Resources/pl.lproj/Localizable.strings`. Code comments are in English.
- The engine's mutable state lives on a single serial queue (`CaptureEngine.queue`), and UI state on the `MainActor`.
- No external dependencies.
