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
- **AudioExporter** runs on a detached task. AVAudioConverter resamples and maps mono/stereo channels into float buffers. WAVWriter quantizes each chunk to integer PCM and writes RIFF INFO tags. It stages output in a hidden sibling and commits the result only after the file is complete. Existing destination replacement is requested via NSSavePanel first.
- **WAVWriter** handles byte layout, signed PCM scaling, RIFF padding, metadata, and size limits. It is internal to the audio module.

## Local storage decisions

Copied imports avoid stale bookmarks and missing originals. This uses more disk space than a linked-file library, but is predictable for a prototype. Copies use UUID prefixes so identical filenames never overwrite each other. No source files are modified.

Metadata is in Application Support rather than inside the app bundle or source repository. Rebuilding or moving the app therefore does not remove projects. The development library override supports isolated UI testing.

The prototype is a local development app without App Sandbox entitlements. A sandboxed distribution will need a deliberate document/import/export access design. No network service or cloud account is used.

## Audio decisions

Chunked conversion bounds memory independently of song duration. Apple's native decoder and sample-rate converter handle input formats; our writer gives explicit control of output bit depth and metadata. Integer conversion clips out-of-range samples and maps nonfinite samples to silence. This is not a mastering pipeline. There is no dither or loudness adjustment, and no promise of delivery compliance beyond the selected encoding settings.

## Growth path

Extend tests and domain types before UI for new requirements. Suggested next increments: import/export progress and cancellation, per-project saved delivery presets, more robust brief ingestion, library recovery/backup UI, then signed distribution. Version control remains intentionally excluded.

References:
- [Swift Package Manager](https://docs.swift.org/main/documentation/packagemanagerdocs/)
- [Package target definitions](https://docs.swift.org/latest/documentation/packagedescription/target/)
- [Apple AVAudioConverter](https://developer.apple.com/documentation/AVFAudio/AVAudioConverter/convert(to:error:withInputFrom:))

## Window layout

`WorkspaceView` owns a native `HSplitView` and a separate status row in a vertical stack. `WorkspaceSidebar` owns the branding, navigation, scrolling project list, and fixed footer. Reserving actual layout space for the status row avoids an overlay covering sidebar controls. The footer never scrolls with the project list. `BackupReminder` presents the launch reminder separately and stores its suppression choice in UserDefaults.

## Reference storage (schema 2)

New assets have isReference=true and live under References/<project UUID> as absolute symbolic links, with ordinary container directories preserving relative paths. fileURL resolves links for playback, Finder and export. No source data is copied or deleted. Missing references produce an actionable error for playback/export. These are path-based symlinks, not Finder aliases: moved originals need their path restored or must be added again.

Version 1 libraries still load; saving writes schema 2 so older builds refuse to load the new format. Legacy assets without the flag keep resolving under Files. No automatic migration is attempted because earlier records contain no original path.

Deletion verifies that the reference tree contains only links/directories, stages that tree by renaming it, commits the library index, then removes the staged links. Index-save failure restores the tree. Cleanup failure reports the remaining path. Real files in References cause deletion to stop. Files containing older copies are always retained. A crash between staging and saving can leave a .deleting-* tree requiring manual recovery.

## Automatic folder refresh

New folder-created projects persist sourceFolderPath; scanned assets store their relative source path and filesystem identity (device/inode). StudioModel checks all linked roots at launch and every three seconds after each scan while the window is open. Refresh is serialized with other app operations. No network access or copying of source data is involved.

A complete inventory is collected using the same Ableton and extension rules as creation. Unchanged results (including ignored ZIP additions) cause no writes. IDs and import dates survive renames when filesystem identity matches; same-path replacements retain the asset ID. Manually added external links are kept. A deleted Spotlight selection clears and can fall back to the automatic master rule; deleted Handoff sources are cleared and default to Spotlight. Local notes edits remain in their existing view state.

Changed inventories are staged into a new shortcut tree. Unexpected real files in the managed tree stop refresh. The old tree is retained until the index save succeeds and restored on save failure. Unavailable roots or scan errors preserve the previous library and show a non-modal warning; polling retries automatically. As with deletion, process termination during the swap can leave a .previous-* tree requiring manual recovery.

This beta does not infer source roots for older projects. Recreate them to enable monitoring. Moving or renaming the source root itself requires restoring its path or recreating the project. Only files inside the chosen root are watched; independent Add files links are preserved but not rescanned. Large trees may take longer than the three-second polling interval.
