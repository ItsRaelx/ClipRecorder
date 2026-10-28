# Troubleshooting

[← Contents](README.md) · [🇵🇱 Polski](../../pl/macos/problemy.md)

## Permissions

### The app shows “Permission needed” even though the permission is on

macOS applies the screen recording permission only after the app is relaunched. Click
**Relaunch** on the card in the popover.

If that doesn't help (usually after rebuilding the app with a different signature), reset the old entries and grant
the permissions again:

```sh
tccutil reset ScreenCapture io.github.itsraelx.ClipRecorder
tccutil reset Microphone io.github.itsraelx.ClipRecorder
```

### I have to grant permissions again after every update

That's how ad-hoc signed test releases work: macOS treats every version as a new app. When building from
source, `build.sh` uses a stable, local certificate, so this doesn't happen ([Installation](installation.md#build-signing)).

### macOS asks every now and then whether the app can keep recording the screen

That's a system reminder (since macOS 15) for every app that records the screen. Choose **Continue to Allow**.

## ClipRecorder wants to use your confidential information

After you sign in to clip.secc.me, the token is in the keychain. An app built from source with a local certificate
gets a new “fingerprint” with every build, so macOS asks for permission again. Choose **Always Allow**.
Releases signed with a Developer ID certificate don't do this.

If the prompt appears while your Mac is locked and you don't answer in time, the app **won't sign you out**.
It will simply try again later.

## Shortcuts

### A shortcut does nothing

- In *Settings → Shortcuts*, check whether the shortcut shows **Used by another app**. If it does,
  set a different one.
- When background recording is paused or the app is still starting, the save shortcuts have nothing to save.
  The menu bar icon shows the state.
- **Marker** only works while recording a clip.

### I can't set a shortcut without ⌃ / ⌘

That's on purpose: shortcuts with just <kbd>⌥</kbd> or <kbd>⇧</kbd> would steal special characters (like Polish
letters) and capital letters in every app. Use <kbd>⌃</kbd>, <kbd>⌘</kbd>, the <kbd>⌥</kbd><kbd>⇧</kbd> combination
or a function key on its own (<kbd>F13</kbd>–<kbd>F20</kbd> are usually free).

## Audio

### The clip has no system audio or microphone

- Check the **On/Off** switches in the popover. The level meters next to them should be moving.
- The microphone needs the *Microphone* permission in *System Settings → Privacy & Security*.
- A regular player plays the *Mix* track. If one of the sources is too quiet, change the balance in
  [Settings → Audio](settings.md#audio).

### Music in my AirPods sounds worse while ClipRecorder is running

Recording from a Bluetooth headset's microphone switches it to call mode. Set **Which microphone → Automatic**:
the app then picks the built-in or a wired microphone. The popover warns you when the selected microphone is Bluetooth.

### Headset microphone (8/16 kHz) and the clip doesn't save

Fixed in the current version: audio is always saved at 48 kHz, regardless of the microphone.
Update the app.

## Saving and disk

### “Not enough disk space to save the clip”

The app won't save a clip when less than 300 MB is left on the disk with the clips folder, and it warns you below 3 GB.
Free up some space or turn on automatic cleanup in [Settings → General](settings.md#general).

### 5 / 10 minute buffer and the SSD

A long buffer means continuous writing to disk, around 100–300 MB per minute, overwritten in a loop. Modern SSDs
handle that easily, but if you want minimal wear, choose a buffer of up to 2 minutes (kept in memory).

### The app crashed while recording

A clip is written in 5-second fragments, so the file in the clips folder can be played back up to the last saved
fragment. When quitting normally, the app finishes and saves the clip first.

### The clip has a gap or a “frozen” picture

When nothing changes on screen, macOS doesn't send new frames, so the clip shows the same picture during that time.
That's normal and saves space. When the screen is locked, recording is paused
([more](pausing.md#screen-lock-and-sleep)).

## Sharing

### “The clip is too big for your plan”

Your plan limits the size of a single clip. Trim the clip with ✂︎ and share it again, or change your plan
(*Settings → Account → Plans…*).

### Uploading keeps failing or takes very long

The error message tells you what happened: no internet connection, a timeout or a certificate problem. You can
cancel the upload (✕ next to the progress bar) and try again. Unfinished uploads are cleaned up on the server automatically.

### The link shows an older version of the clip

After you trim a clip, the link points to the version from before the trim. The app then “forgets” it, so click
**Share link** again.

## Other

### Where are the logs?

The app writes to the system log:

```sh
log stream --predicate 'process == "ClipRecorder"' --level info
```

### How do I report a bug?

Open an [issue on GitHub](https://github.com/ItsRaelx/ClipRecorder/issues). Include your macOS version, the app
version (*Settings*, bottom-left corner) and a snippet of the log.
