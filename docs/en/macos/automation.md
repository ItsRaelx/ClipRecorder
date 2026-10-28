# Automation

[← Contents](README.md) · [🇵🇱 Polski](../../pl/macos/automatyzacja.md)

ClipRecorder supports `cliprecorder://` URLs. That means any program that can open a URL can control
recording: the Shortcuts app, Stream Deck, Raycast, Alfred, Keyboard Maestro, BetterTouchTool, Terminal scripts.

## Available actions

| URL | What it does |
|---|---|
| `cliprecorder://save` | saves the last N s (like <kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd>) |
| `cliprecorder://record` | starts a clip, or finishes it if one is in progress (like <kbd>⌃</kbd><kbd>⌥</kbd><kbd>R</kbd>). Alias: `toggle` |
| `cliprecorder://stop` | finishes the clip if one is in progress. Otherwise does nothing |
| `cliprecorder://marker` | adds a marker (like <kbd>⌃</kbd><kbd>⌥</kbd><kbd>M</kbd>) |
| `cliprecorder://pause` | pauses background recording, or resumes it |
| `cliprecorder://resume` | resumes if paused |
| `cliprecorder://open-last` | opens the last clip |
| `cliprecorder://settings` | opens Settings |

If the app isn't running, opening a URL launches it. The most common URLs are also listed in
*Settings → Shortcuts → Automation*, and clicking a URL copies it.

> `stop` and `resume` are handy in automations because, unlike `record` and `pause`, they don't toggle the state.
> Calling `stop` twice won't start a new clip.

## Terminal and scripts

```sh
open cliprecorder://save
open cliprecorder://record   # start…
sleep 30
open cliprecorder://stop     # …and stop after 30 s
```

## Shortcuts app

1. Create a new shortcut.
2. Add the **Open URLs** action and enter e.g. `cliprecorder://save`.
3. Optionally: in the shortcut details, **Add Keyboard Shortcut**, pin it to the menu bar or add it to an
   automation, e.g. “when I open app X → `cliprecorder://resume`”.

Example: a “Don't record presentations” shortcut that calls `cliprecorder://pause` when you connect to a projector.

## Stream Deck

Use the **System → Website** action (or **Open**) and enter a URL, e.g. `cliprecorder://save`.
Turn off *GET request in background* so the URL is opened by the system instead of being sent as an HTTP request.

A popular layout: one `save` button, one `record` button, one `marker` button.

## Raycast and Alfred

- **Raycast:** *Create Quicklink* with the URL `cliprecorder://save` and the name “Save clip”.
- **Alfred:** *Workflows → Templates → Web → Open URL* or *Web Search* with the URL `cliprecorder://save`.

## Keyboard Maestro and BetterTouchTool

The **Open URL** action with any URL from the table. It also works with gestures, mouse buttons or a remote.
