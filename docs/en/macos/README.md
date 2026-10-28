# ClipRecorder for macOS – documentation

[← Documentation](../../README.md) · [Windows](../windows/README.md) · [🇵🇱 Polski](../../pl/macos/README.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/hero-dark.png">
  <img src="screenshots/hero-light.png" alt="ClipRecorder: the menu bar popover and a saved clip preview">
</picture>

ClipRecorder is a macOS menu bar app that always remembers the last minute (or anything from 30 s to 10 min)
of what's happening on your screen, together with system audio and your microphone. When something worth keeping
happens, you press a shortcut and the clip contains what has **already happened**.

## Contents

| Page | What's inside |
|---|---|
| [Installation](installation.md) | downloading, building from source, permissions, updates, uninstalling |
| [Getting started](getting-started.md) | the menu bar icon, the popover, the quick menu, how the buffer works |
| [Clips](clips.md) | saving and recording, markers, the recording bar, preview, the clip list, trimming, files and audio tracks |
| [Sharing by link](sharing.md) | the clip.secc.me account, signing in, uploading, visibility, limits |
| [Pausing and power](pausing.md) | timed pause, battery, Low Power Mode, screen lock |
| [Settings](settings.md) | every section of the Settings window, option by option |
| [Automation](automation.md) | `cliprecorder://` URLs, the Shortcuts app, Stream Deck, Terminal, Raycast |
| [Troubleshooting](troubleshooting.md) | permissions, keychain, shortcuts, audio, disk space, FAQ |
| [For developers](developers.md) | how the app is built, data flow, screenshots, releases |

## At a glance

| Shortcut (default) | What it does |
|---|---|
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>R</kbd> | saves the last N s **and keeps recording**; press it again to finish the clip |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd> | instantly saves **only** the last N s |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>M</kbd> | adds a marker (a chapter in the file) while recording |

- Clips go to `~/Movies/Clips` as `.mov` files (HEVC video, separate audio tracks).
- Without signing in, the app never uploads anything. Once you sign in to [clip.secc.me](https://clip.secc.me),
  you get a link to a clip with a single click.
- Requirements: macOS 15 Sequoia or later.
- The app follows your system language: Polish on Polish systems, English everywhere else.

## Limitations

- One display or one window is recorded at a time.
- Changing the source, resolution, frame rate or quality clears the buffer.
- A 5 / 10 min buffer means continuous writing to disk (around 100–300 MB per minute, overwritten in a loop).
