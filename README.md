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

The scripts work from any current directory and put compiler/build caches in `.cache/` and `.build/`. The bundle and generated icons go into `build/`. The developer build uses Python 3 to vendor an installed ffmpeg-full build. The packaged app includes FFmpeg and its libraries; end users need no separate installation. See docs/FFMPEG.md for the current development-only distribution status.

Prerequisites: Apple silicon, macOS 27+, Xcode with the macOS 27 SDK and a Swift 6.2+ compiler. Validated here with Xcode 27.1, Swift 6.4, and SDK 27.0. Xcode and Apple's SDKs are system tools, not copied into this repository. Xcode may maintain its own system caches and preferences.

## Launch reminder

A standard macOS dialog reminds you to back up your local library each time the app launches. Select **Don’t show this again**, then **Got it**, to remember your preference. The sidebar keeps its Finder button clear of the bottom edge. The bottom status strip is reserved for operation messages; the backup reminder no longer appears there.

## Your first project

1. Click **New project**, enter a name and artist, then create it.
2. Click **Add files**. Audio and documents are read directly from their original paths. Keep originals in place and their drives connected.
3. Play a mix with the play button. The folder button reveals its original in Finder.
4. Add notes and click **Save notes**. Notes are not autosaved.
5. Choose a source and settings in Handoff, then click **Add version**. Repeat for each source/format combination.
6. Alternatively paste a brief or use **Import document** for TXT, Word, Pages or PDF with **one version per line**, then click **Add from brief**. Include the source filename to identify it; unmatched filenames use the selected source with a warning. Ambiguous sources must be selected manually.
7. Review the delivery list. **Edit** loads a version into the editor; **Save version** applies your changes. **Export WAV** exports just that item.
8. **Export all as WAV files** creates a new delivery folder in your chosen directory. **Export all as ZIP** saves a single archive. Existing files are never replaced; a failed batch leaves no partial delivery.

The delivery list is temporary and resets when you leave the workspace. Additions from briefs append to the list. Metadata belongs on each version's line, separated by semicolons, or can be edited using the metadata fields.

```text
master.wav; Stereo WAV, 24-bit, 48 kHz; Artist: Luna Park; Title: Night Drive
master.wav; Stereo WAV, 16-bit, 44.1 kHz; Artist: Luna Park; Title: Night Drive
instrumental.wav; Stereo WAV, 32-bit float, 192 kHz; Title: Night Drive Instrumental
```

## Document briefs

**Import document** reads text locally into the editor; review it and arrange one
version per line, then press **Add from brief**. Importing does not automatically
create delivery rows or modify the source document.

| Format | Import behavior |
| --- | --- |
| TXT | macOS encoding detection, including UTF-8 and UTF-16 |
| DOC / DOT | Legacy Word reader provided by macOS |
| DOCX / DOCM / DOTX / DOTM | macOS Office Open XML text reader; macros are not executed |
| RTF / RTFD / ODT | Native formatted-text reader |
| Pages / Pages templates | Requires installed Apple Pages and Automation permission; reads a disposable copy via PDF export. Current and Pages ’09 tested. Older versions depend on what installed Pages can open. |
| PDF | PDFKit embedded text, or offline Vision OCR on pages without text; supports unlocking with a supplied password. PDF/A and PDF/X use the same PDF reader. |

Scanned PDFs may take longer on first use. Check OCR numbers, table reading
order, filenames and line breaks. On mixed pages with embedded text and scanned
images, only the embedded text is read. PDF portfolio attachments are not
imported, and copy-restricted PDFs are rejected. Password-protected Word/Pages
files must first be exported unlocked; passwords supplied for PDFs are not saved.
Unreadable or empty imports leave the existing brief and delivery list unchanged.
PDF briefs are limited to 300 pages. Complex documents are not guaranteed to
extract with perfect layout or completeness.

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
  Files/<project UUID>/<legacy copied files>
```

Use **Show library in Finder** to find it. Back up the entire folder, not just the JSON file. Close the app before restoring a backup. Deleting `.build/`, `.cache/`, or `build/` does not delete your music library. Do not edit the library JSON while the app is open.

A developer can override the library location with the `DEADLINE_MASTER_LIBRARY` environment variable when launching the executable directly. This is useful for disposable QA data inside the project folder.

The original web prototype remains in `../sidea/`. Its IndexedDB library is separate. This native app does not automatically migrate browser data: download originals from the web prototype and import them here. Version control remains out of scope.

## Prototype limits

- Outputs WAV at 16/24-bit integer PCM or 32-bit float, 44.1/48/96/192 kHz, mono/stereo. Resampling precedes TPDF dithering and integer quantization; matching rate/channel/codec exports preserve audio samples via stream copy. Standard RIFF WAV is limited to 4 GB; oversized exports fail without replacing the destination.
- Inputs depend on AVFoundation's installed decoders. Mono and stereo only; surround input is explicitly rejected. A file extension indicates a candidate audio file, not guaranteed decoder support.
- No loudness normalization, peak limiting, mastering, noise-shaped dither, MP3/FLAC output, AI parsing, folder watching, cloud sync, or version control.
- The parser handles explicit numeric settings, not arbitrary prose. It warns on known unsupported requirements and conflicting settings; always review the original brief.
- WAV INFO metadata uses UTF-8. Metadata visibility and Unicode handling vary across other audio apps.
- Export runs in the background but currently has no percentage or cancel UI. Do not quit during conversion.
- Development builds are ad-hoc signed and are not sandboxed or notarized. Developer ID signing, hardened runtime, sandbox/file access design, and notarization are future distribution work; don't disable Gatekeeper to distribute this build.

The app requires no online service. Handoff restricts FFmpeg inputs to local files; the full bundled FFmpeg runtime retains its upstream network capabilities for potential future features.



## Current storage behavior

New projects store absolute original file paths in library.json (schema 3). No file copies or shortcuts are created. Creation scans immediately; after that, folder inventories refresh once at each app launch, with no timer or background polling. Project deletion only removes metadata. Original files remain untouched.

Handoff is the only workflow that writes audio output. Choose a new filename, including in the original project directory: existing files cannot be overwritten. Recreate older beta projects to use direct-path records. Historical shortcut/copy folders are not automatically purged.
