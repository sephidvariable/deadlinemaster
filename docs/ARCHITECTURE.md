# Architecture

## Module boundaries

```text
DeadlineMaster (SwiftUI + AppKit)
    ├── DeadlineCore (Foundation)
    └── DeadlineAudio (AVFoundation)
            └── DeadlineCore
```

The UI can depend on the domain/storage and audio modules. Neither lower-level module imports SwiftUI or knows about windows. Swift Package Manager enforces the target boundaries.

- **MusicProject / ProjectAsset** are Codable, Sendable value types. A project owns a list of asset records with an optional reference-storage flag; absent flags retain legacy copied-file behavior.
- **ProjectRepository** is an actor: disk operations are serialized. Library JSON has an explicit schema version and is atomically replaced on save. Invalid or future-version libraries fail to load; UI mutations remain disabled instead of silently replacing data.
- **BriefParser** is a pure deterministic function. It takes a brief and current settings, returns settings plus detection/warning messages, and never accesses files or the network.
- **StudioModel** is an observable main-actor coordinator. It manages selection, UI errors, disk operations, playback, and export. A busy flag disables overlapping mutations. UI snapshots change only after persistence succeeds.
- **AudioExporter** runs on a detached task. Bundled FFmpeg decodes, uses SoX resampling, and writes integer PCM WAV with metadata. It stages output in a hidden sibling and commits the result only after the file is complete. Existing destinations are refused.
- **WAVWriter** handles byte layout, signed PCM scaling, RIFF padding, metadata, and size limits. It is internal to the audio module.

## Local storage decisions

Copied imports avoid stale bookmarks and missing originals. This uses more disk space than a linked-file library, but is predictable for a prototype. Copies use UUID prefixes so identical filenames never overwrite each other. No source files are modified.

Metadata is in Application Support rather than inside the app bundle or source repository. Rebuilding or moving the app therefore does not remove projects. The development library override supports isolated UI testing.

The prototype is a local development app without App Sandbox entitlements. A sandboxed distribution will need a deliberate document/import/export access design. No network service or cloud account is used.

## Audio decisions

Chunked conversion bounds memory independently of song duration. FFmpeg handles input formats and libsoxr resampling; command arguments select output bit depth and metadata. WAVWriter remains an isolated legacy utility; Handoff uses FFmpeg. This is not a mastering pipeline. Resampling and channel processing precede ordinary TPDF dither and integer quantization. Float output skips dither; matching rate/channel/codec uses stream copy. There is no loudness adjustment or promise of delivery compliance beyond the selected encoding settings.

## Growth path

Extend tests and domain types before UI for new requirements. Suggested next increments: import/export progress and cancellation, per-project saved delivery presets, more robust brief ingestion, library recovery/backup UI, then signed distribution. Version control remains intentionally excluded.

References:
- [Swift Package Manager](https://docs.swift.org/main/documentation/packagemanagerdocs/)
- [Package target definitions](https://docs.swift.org/latest/documentation/packagedescription/target/)
- [Apple AVAudioConverter](https://developer.apple.com/documentation/AVFAudio/AVAudioConverter/convert(to:error:withInputFrom:))

## Window layout

`WorkspaceView` owns a native `HSplitView` and a separate status row in a vertical stack. `WorkspaceSidebar` owns the branding, navigation, scrolling project list, and fixed footer. Reserving actual layout space for the status row avoids an overlay covering sidebar controls. The footer never scrolls with the project list. `BackupReminder` presents the launch reminder separately and stores its suppression choice in UserDefaults.

## Direct original paths (schema 3)

ProjectAsset.originalPath is the source URL path. Creation and manual import read metadata only; they create neither copies nor links. The repository writes only library.json. Project deletion removes the record, never source files or folders. Old artifacts are left alone.

The window task loads the index and calls refreshFoldersAtLaunch once per process. There is no repeating task, timer, or filesystem watcher. Source inventories apply the same Ableton and extension rules and preserve IDs where filesystem identity matches. Failed scans preserve old metadata and show a warning. Newly created projects scan immediately, then refresh on the next launch.

AudioExporter reads the source through a bundled FFmpeg subprocess. It refuses existing destinations, writes to a unique temporary sibling, and commits with a move that cannot replace an existing destination. Users may export new deliverables into the original source directory. The app is not OS-sandboxed as read-only; protection is enforced by these code paths. Finder actions reveal files but do not edit them.

## Batch Handoff

`HandoffItem` holds a source asset ID and independent encoding/metadata settings.
`HandoffBriefParser` parses one version per line, matching source filenames and
surfacing ambiguity for review. The workspace keeps an editable, temporary list.
`BatchExporter` converts sequentially into a private staging directory beside
the destination, keeping memory bounded and original files read-only. Numbered,
format-labelled filenames prevent version collisions. Folder output commits a
new directory; ZIP output uses macOS `/usr/bin/ditto` with shell-free arguments.
Only after every conversion (and ZIP creation) succeeds does a no-replace move
publish the result. Errors remove staging; existing destinations are rejected.

## Document brief import

`DeadlineDocuments` isolates AppKit attributed-text import, PDFKit extraction,
Vision OCR, and Pages Automation from audio processing and brief interpretation.
The UI runs extraction off the main actor, handles PDF passwords with a secure
field, and requires review before parsing delivery rows. Pages receives only a
temporary copy, which is exported to a temporary PDF and closed without saving;
its original file is never opened by Automation. No document macros are run.
The app declares its Apple Events purpose in Info.plist. Pages needs the user's
macOS Automation permission and an installed compatible Pages version.

References: [Apple document types](https://developer.apple.com/documentation/foundation/nsattributedstring/documenttype/opendocument),
[Pages export formats](https://support.apple.com/en-euro/guide/pages/tance1161f26/mac).
