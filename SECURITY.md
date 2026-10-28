# Security policy

[🇵🇱 Polski](SECURITY.pl.md)

## Supported versions

| Version | Security fixes |
|---|---|
| macOS – latest release (`v*`) | ✅ |
| macOS – older releases | ❌ please update |
| Windows | in progress |

## Reporting a vulnerability

**Please don't report vulnerabilities in public issues, discussions or pull requests.**

Use GitHub's private form instead:
**[Report a vulnerability](https://github.com/ItsRaelx/ClipRecorder/security/advisories/new)**
(*Security* tab → *Report a vulnerability*). Only the project maintainers can see it.

Please include:
- the app and OS version;
- a description of the issue and its possible impact;
- steps to reproduce or a proof of concept;
- whether the issue has been disclosed anywhere.

We'll confirm we received your report, agree on next steps with you, and publish an advisory once a fix is released.
If you'd like, we'll credit you as the reporter.

## Scope

In scope:
- the ClipRecorder apps (macOS, and Windows in the future);
- storage of the sign-in token (Keychain);
- handling of `cliprecorder://` URLs;
- uploading clips and communication with the server;
- the update check;
- build and release scripts in this repository.

Issues with the [clip.secc.me](https://clip.secc.me) server (accounts, shared clips, API) can be reported through the
same form. We'll pass them on.

Out of scope:
- macOS permissions the user granted to the app on purpose, e.g. screen recording;
- Gatekeeper warnings for test releases that aren't signed with an Apple certificate (a known limitation);
- attacks that require prior full access to the user's account on the computer.

## How the app protects your data

- Recordings never leave your computer until you share a clip.
- The sign-in token is stored in the macOS Keychain, never in settings files. Signing out revokes it on the server.
- The app's own windows are excluded from recordings. You can hide chosen apps (e.g. a password manager) from clips.
- Connections to clip.secc.me and GitHub use HTTPS. App Transport Security blocks unencrypted connections to servers
  on the internet.
