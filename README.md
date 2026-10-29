# Deadline Master for macOS

An offline, native SwiftUI music-project workspace for **Apple silicon and macOS 27.0+**. This is a working development prototype, not a distribution-ready release.

## Open the app

After building, double-click **build/Deadline Master.app** in Finder. There is no local web server to start or stop. Quit with **Command–Q**, or close the last window. The compiled app does not need Xcode or an internet connection to run on a compatible Mac.

## Build it yourself

Open Terminal and run these commands one at a time:

```sh
cd "/Users/jameschang/Works/Project Master/DeadlineMaster"
./scripts/dev.sh build
./scripts/dev.sh test
./scripts/package.sh
open "build/Deadline Master.app"
```

- `build` compiles a debug executable and reports compiler errors with file and line numbers.
- `test` builds and runs the automated tests with Swift Testing. Read the final Swift Testing summaries: the separate XCTest compatibility summary may say zero tests.
- `package.sh` compiles an optimized arm64 release, generates the icon, builds a real `.app` bundle, and applies a local ad-hoc signature.
- `open` launches the finished app. Quit a running copy before packaging a replacement.

The scripts work from any current directory and put compiler/build caches in `.cache/` and `.build/`. The bundle and generated icons go into `build/`. No npm, Python, third-party Swift packages, remote fonts, API keys, or package downloads are required.

Prerequisites: Apple silicon, macOS 27+, Xcode with the macOS 27 SDK and a Swift 6.2+ compiler. Validated here with Xcode 27.1, Swift 6.4, and SDK 27.0. Xcode and Apple's SDKs are system tools, not copied into this repository. Xcode may maintain its own system caches and preferences.

## Launch reminder

A standard macOS dialog reminds you to back up your local library each time the app launches. Select **Don’t show this again**, then **Got it**, to remember your preference. The sidebar keeps its Finder button clear of the bottom edge. The bottom status strip is reserved for operation messages; the backup reminder no longer appears there.

## Your first project

1. Click **New project**, enter a name and artist, then create it.
2. Click **Add files**. Audio and documents are linked without copying. Keep originals in place and their drives connected.
3. Play a mix with the play button. The folder button reveals its original in Finder.
4. Add notes and click **Save notes**. Notes are not autosaved.
5. Paste a brief, or import a UTF-8 `.txt` file. Click **Extract specs**.
6. Review every setting. Choose a source audio file and click **Convert & save WAV**.
7. Choose a destination in the standard macOS save panel. The app reveals the finished export in Finder.

Example brief (metadata labels use separate lines or semicolons):

```text
Stereo WAV, 24-bit, 48 kHz
Artist: Luna Park
Title: Night Drive
```

## Read and change the code

Start with [the developer guide](docs/DEVELOPMENT.md), then [the architecture](docs/ARCHITECTURE.md). Open `Package.swift` in Xcode to browse the complete package and use its compiler, debugger, and test navigator. Select the DeadlineMaster scheme and My Mac destination. Command–B builds; Command–R runs; Command–U tests the selected scheme. The scripts are the reproducible path for testing all modules and producing the named app bundle.

| Location | Responsibility |
| --- | --- |
| `Package.swift` | Modules, dependencies, and minimum macOS version |
| `Sources/DeadlineCore/` | Data models, brief parsing, atomic local storage |
| `Sources/DeadlineAudio/` | Streaming conversion and integer WAV/metadata writing |
| `Sources/DeadlineMaster/` | Native SwiftUI screens, app lifecycle, UI state and panels |
| `Tests/` | Isolated data and actual audio-conversion tests |
| `Resources/Info.plist` | App identity, version, icon, minimum system version |
| `scripts/` | Debug/test/release build, app packaging, icon generation |
| `docs/` | Architecture, learning guide, and manual verification checklist |

## Where your music lives

By default, the app stores its library in:

```text
~/Library/Application Support/Deadline Master/
  library.json
  References/<project UUID>/<shortcut tree>
  Files/<project UUID>/<legacy copied files>
```

Use **Show library in Finder** to find it. Back up the entire folder, not just the JSON file. Close the app before restoring a backup. Deleting `.build/`, `.cache/`, or `build/` does not delete your music library. Do not edit the library JSON while the app is open.

A developer can override the library location with the `DEADLINE_MASTER_LIBRARY` environment variable when launching the executable directly. This is useful for disposable QA data inside the project folder.

The original web prototype remains in `../sidea/`. Its IndexedDB library is separate. This native app does not automatically migrate browser data: download originals from the web prototype and import them here. Version control remains out of scope.

## Prototype limits

- Outputs integer PCM WAV at 16/24-bit, 44.1/48/96 kHz, mono/stereo. Standard RIFF WAV is limited to 4 GB; oversized exports fail without replacing the destination.
- Inputs depend on AVFoundation's installed decoders. Mono and stereo only; surround input is explicitly rejected. A file extension indicates a candidate audio file, not guaranteed decoder support.
- No loudness normalization, peak limiting, mastering, dither, batch delivery, MP3/FLAC output, PDF/Word briefs, AI parsing, folder watching, cloud sync, or version control.
- The parser handles explicit numeric settings, not arbitrary prose. It warns on known unsupported requirements and conflicting settings; always review the original brief.
- WAV INFO metadata uses UTF-8. Metadata visibility and Unicode handling vary across other audio apps.
- New imports use symbolic links, including Pages document packages. Moving or deleting originals breaks their links; restore the path or add them again. Project deletion removes only shortcuts and their containers. Older copied assets are preserved because their original locations were not recorded.
- Export runs in the background but currently has no percentage or cancel UI. Do not quit during conversion.
- Development builds are ad-hoc signed and are not sandboxed or notarized. Developer ID signing, hardened runtime, sandbox/file access design, and notarization are future distribution work; don't disable Gatekeeper to distribute this build.

This app has no networking code, web view, analytics, accounts, or online service dependency.

New folder-created projects automatically refresh their shortcuts while the app is open (roughly every three seconds, plus scan time). Added/renamed/deleted supported files are reconciled using the same Ableton exclusions. ZIPs and other unsupported additions are ignored. A missing or disconnected root preserves the library and shows a warning until it returns. Older beta projects must be recreated to record their watched source folder.
