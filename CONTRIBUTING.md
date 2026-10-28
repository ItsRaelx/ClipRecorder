# Contributing

[🇵🇱 Polski](CONTRIBUTING.pl.md)

Thanks for wanting to help with ClipRecorder! Every contribution counts: a bug report, an idea, a docs fix or code.
You can write in English or Polish.

## Issues and ideas

- **Bug:** [new issue → Report a bug](https://github.com/ItsRaelx/ClipRecorder/issues/new/choose).
  The form asks for the app version, your system and steps to reproduce.
- **Idea:** [new issue → Feature idea](https://github.com/ItsRaelx/ClipRecorder/issues/new/choose).
- **Question:** [Discussions → Q&A](https://github.com/ItsRaelx/ClipRecorder/discussions/categories/q-a).
- **Security issue:** privately only, see [SECURITY.md](SECURITY.md).

## Repository layout

| Folder | Contents |
|---|---|
| `macos/` | the macOS app (Swift package) |
| `windows/` | the Windows app (in progress, see [windows/README.md](windows/README.md)) |
| `docs/` | user documentation with screenshots, in English (`docs/en`) and Polish (`docs/pl`) |

Architecture of the macOS app: [docs/en/macos/developers.md](docs/en/macos/developers.md).

## Building (macOS)

Requirements: macOS 15+, Xcode or the Command Line Tools.

```sh
cd macos
./build.sh            # build/ClipRecorder.app
./build.sh --install  # and copy it to /Applications
```

`build.sh` signs the app with a local certificate so the screen recording permission survives rebuilds
([details](docs/en/macos/installation.md#build-signing)).

## Pull requests

1. For bigger changes, open an issue or a discussion first. It's easier to agree on the direction before the code
   exists.
2. Fork the repo and branch off `main`.
3. Follow the style of the surrounding code:
   - UI strings are written in **English** in code. Add the Polish translation to
     `macos/Resources/pl.lproj/Localizable.strings`. Keep both short and free of jargon;
   - comments and identifiers in **English**;
   - no external dependencies unless they're really needed.
4. Make sure the project builds without warnings.
5. If you change the UI, regenerate the screenshots: `cd macos && scripts/snapshots.sh`.
6. If you change behavior, update the docs in `docs/en` and `docs/pl`.
7. Open a PR and fill in the template. CI builds the app automatically.

Commit messages are in English, in the imperative mood, e.g. "Fix marker count after trimming".

## License

The project is licensed under [PolyForm Noncommercial 1.0.0](LICENSE). By submitting changes you agree that they
will be released under the same license.

## Code of conduct

We follow a [code of conduct](.github/CODE_OF_CONDUCT.md). In short: be kind and respectful.
