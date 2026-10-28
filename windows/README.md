# ClipRecorder for Windows

[🇵🇱 Polski](README.pl.md)

> **Status: in progress.** This folder is reserved for the Windows app. There's no code yet.
> The working macOS version lives in [`../macos`](../macos).

## Goal

The same app as on macOS, built natively for Windows:

- an icon in the notification area next to the clock;
- a rolling buffer of the last 30 s – 10 min of screen, system audio and microphone;
- global shortcuts: save, keep recording, marker;
- a preview card after saving, trimming;
- separate audio tracks plus a mix;
- sharing by link via [clip.secc.me](https://clip.secc.me), with the same account as on the Mac;
- timed pause, pause on battery and while the screen is locked;
- `cliprecorder://` URLs for automation.

The full description of the behavior (this is the spec for the Windows version) is in the
[macOS documentation](../docs/en/macos/README.md).

## Planned stack

To be confirmed before work starts. Proposal: **C# / .NET** with a **WinUI 3** or **WPF** interface.

| Part | macOS (today) | Windows (plan) |
|---|---|---|
| Screen capture | ScreenCaptureKit | Windows.Graphics.Capture |
| Hardware video encoding | VideoToolbox (HEVC) | Media Foundation (H.264/HEVC via NVENC, AMF, Quick Sync) |
| System audio / microphone | ScreenCaptureKit / AVFoundation | WASAPI (loopback + capture) |
| Writing and processing files | AVFoundation | Media Foundation (Sink Writer) |
| Menu bar / tray icon | NSStatusItem | notification area icon (Shell_NotifyIcon) |
| Global shortcuts | Carbon `RegisterEventHotKey` | `RegisterHotKey` |
| Token storage | Keychain | Windows Credential Manager |
| Power / screen lock | IOKit, NSWorkspace notifications | `RegisterPowerSettingNotification`, `WTSRegisterSessionNotification` |
| `cliprecorder://` URLs | `CFBundleURLTypes` | protocol registered in the registry |
| Launch at login | `SMAppService` | `Run` registry key or a startup task |

## Repository conventions

| What | Where / how |
|---|---|
| App code | `windows/` (e.g. `windows/src/…`, the `.sln` solution in `windows/`) |
| Documentation | [`docs/en/windows/`](../docs/en/windows/README.md), [`docs/pl/windows/`](../docs/pl/windows/README.md) |
| CI | `.github/workflows/windows-*.yml` with `paths: ["windows/**"]` |
| Release tags | `windows-v0.1.0`, `windows-v0.2.0`, …  (macOS uses `v1.0.0`) |
| GitHub releases | titled "ClipRecorder X (Windows)", published with **`--latest=false`** |

**Why `--latest=false`:** the macOS app checks for updates via `/releases/latest`. If a Windows release were marked
as the latest one, Macs would show an update banner for the wrong version. The Windows app should look for updates
in the release list, among `windows-v*` tags.

## Shared pieces

- **clip.secc.me server:** the same API as on macOS:
  - device-code sign-in (`/api/device/start`, `/api/device/poll`);
  - account and limits (`/api/me`);
  - chunked upload (`/api/clips`, `/parts/N`, `/thumbnail`).

  The reference implementation is [`macos/Sources/ClipRecorder/CloudService.swift`](../macos/Sources/ClipRecorder/CloudService.swift).
- **Icon:** [`macos/Resources/AppIcon-1024.png`](../macos/Resources/AppIcon-1024.png)
  (generator: [`macos/Tools/make-icon.swift`](../macos/Tools/make-icon.swift)).
- **UI text:** English and Polish, following the system language, like on macOS.
- **License:** the same, [PolyForm Noncommercial 1.0.0](../LICENSE).

## Testing

Screen capture and video encoding can't be tested in CI. You need a real Windows 10 (2004+) or 11 machine, ideally
tested on NVIDIA, AMD and Intel graphics.
