# Manual verification checklist

Use a disposable library for QA. Run the unit tests first.

- Launch the packaged app from Finder. Confirm the correct name and timer/waveform icon.
- Create a project, import an audio file and a non-audio asset, and add/save notes.
- Quit and reopen. Confirm the project, files, and notes survive.
- Rename or move a linked original. Confirm playback reports it unavailable; restore the path and confirm playback works again.
- Search projects, select a project, return to All projects, and create a second one.
- Verify the layout at minimum window size and in dark mode.
- Paste an explicit brief; check the selectors and metadata fields. Import the same brief as UTF-8 `.txt`.
- Paste conflicting values (16/24-bit, mono/stereo, 44.1/96 kHz). Confirm warnings appear instead of a silent guess.
- Export and audition a WAV; inspect it in another audio app for sample rate, channels, bit depth, duration, and metadata.
- Cancel an import and save panel. Existing data should remain unchanged.
- Export over an existing disposable output, accepting the normal save-panel confirmation. Confirm replacement succeeds.
- Try a corrupt audio file. Confirm an error and no damaged destination.
- Disconnect internet yourself, then create/import/parse/play/export. These features should continue to work.
- Quit normally after operations finish; no server process should remain.

Automated checks exercise all supported WAV encoding combinations and storage behavior. App launch/UI checks performed during development are recorded in the task handoff; unchecked cases above remain manual follow-up items.

## Verified on 2026-10-28

Environment: Apple silicon, macOS 27.0.1, Xcode 27.1, Swift 6.4, SDK 27.0.

- Debug and optimized release builds passed.
- 11 Swift Testing tests passed (6 core, 5 audio); the conversion test exercises all 12 supported encoding combinations.
- Packaged binary verified as arm64, deployment minimum macOS 27.0, SDK 27.0.
- App bundle's ad-hoc signature passed `codesign --verify --strict`.
- Native UI verified: launch, project creation, save notes, file import, brief extraction, source selection, native save panel, and completed WAV export.
- Independently inspected the UI-produced WAV: 1 channel, 44,100 Hz, 16-bit, 44,100 frames, exactly 1 second.
- Quit/reopen verified project, imported file, and saved notes persisted.
- QA used `build/QA Library` and synthetic audio. The QA app instance was closed after verification; normal launch uses the real Application Support library.

Not manually verified in this session: network-disconnected operation, listening/audition quality, dark mode, package-session imports, accessibility beyond basic native control interaction, long-running exports, or distribution to another Mac. Offline operation is supported by having no networking code or runtime external dependencies.

## GUI regression repair — 2026-10-28

The final layout uses `HSplitView` with a separate, fixed-height status row. `WorkspaceSidebar` keeps its header/footer outside the scrolling project list. This replaces the root `NavigationSplitView`/bottom-inset combination that clipped content in compact windows. No geometry offsets or extra footer-clearance padding remain.

Verified in the packaged release:
- Compact and enlarged windows show the complete workspace heading, banner, sidebar footer, and Finder button.
- The Finder action opens `~/Library/Application Support/Deadline Master`.
- Sidebar hide/show works and restores the Finder control.
- New project sheet opens and cancels normally.
- Launch reminder still appears with its suppression checkbox; it no longer occupies the footer.
- Optimized build and app signature verification passed.

Data/audio code was unchanged in this repair; the earlier 11-test run remains its latest verification. This repair used native UI checks rather than additional data/audio tests.

### Window title overlap — 2026-10-28

Moved the visible title into a centered principal toolbar item and disabled the automatic leading title using the unified toolbar style. The sidebar divider no longer crosses the app name. Visually checked the packaged app at its restored window size and zoomed size; the Finder footer remains visible. Release packaging and signature verification passed.

## Shortcut storage — 2026-10-29

25 automated tests passed. Added coverage for live source edits, missing originals, deleting links without deleting original audio/document packages, preserving unexpected real files, broken-link deletion, and restoring links after index-save failure. Folder filters and automatic Spotlight remain covered. Native end-to-end playback/Finder/export UI with shortcuts has not yet been manually exercised. No old library migration or real user-file cleanup was performed.

## Folder refresh — 2026-10-29

29 automated tests passed, including nested Ableton exclusion, ignored ZIP additions, audio add/rename/delete, Spotlight identity retention and deletion fallback, disconnected-root preservation and reconnection, independent manual links, and rollback after failed index save. Release compilation and signature checked. Native UI timer interaction remains a manual check: create a disposable linked project, add/rename/delete audio outside the app, and verify its file list/Spotlight/Handoff update after a few seconds.
