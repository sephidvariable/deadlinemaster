# Learning the source and build workflow

## 1. Understand what you're opening

`Package.swift` is the build recipe, not the app's main program. Each target is a separately compiled module. The executable target combines the two reusable modules with the interface. Open this file in Xcode to load the package.

Read in this order:

1. `Sources/DeadlineCore/Models.swift`: the shape of a project, file, and export request. `struct` means a value type; `Codable` supports JSON; `Sendable` permits safe transfer between concurrency contexts.
2. `BriefParser.swift`: follow a string through extraction and ambiguity warnings. This is a good first place to make a small behavior change.
3. `ProjectRepository.swift`: follow `load`, `importFile`, and `save`. An `actor` serializes access to its state. `throws` means errors go back to the caller rather than being ignored.
4. `Sources/DeadlineMaster/DeadlineMasterApp.swift`: the native app entry point (`@main`) and window lifecycle.
5. `StudioModel.swift`: the connection between buttons and operations. `@MainActor` keeps UI state updates on the UI thread; `Task.detached` moves audio work off it.
6. `WorkspaceView.swift` and `ProjectDetailView.swift`: SwiftUI describes what the interface should look like for the current state. A binding (`$value`) lets a control edit that value.
7. `Sources/DeadlineAudio/AudioExporter.swift` and `WAVWriter.swift`: read these after understanding the settings model. They contain the streaming conversion and binary file format logic.

## 2. Make one small change

Try changing “Master the deadline.” in `WorkspaceView.swift` to your preferred tagline. Save the file. Run `./scripts/dev.sh build`. If it succeeds, quit the old app and run `./scripts/package.sh`, then open the rebuilt app. The already-running app does not update itself when you edit source.

Avoid changing a parser rule and the audio writer at the same time while learning. Small changes make failures easier to locate.

## 3. Check a change

Run `./scripts/dev.sh test`. Tests use temporary directories and synthetic audio; they do not touch your real projects. A passing run ends with Swift Testing summaries for both targets.

The tests cover project round-trip persistence, reference persistence and original-file preservation, corrupt-library refusal, exact/ambiguous/unspecified brief values, invalid settings, source overwrite refusal, failed-export preservation, and 12 actual audio conversion combinations.

To add behavior, first add an example to the relevant test file. Run tests and confirm your new expectation fails before implementing the change. Then implement it and rerun. Avoid tests that merely repeat internal implementation details; test outcomes a user relies on.

## 4. Read compiler errors

An error usually includes a filename and line, followed by a diagnostic. Fix the first meaningful error, then rebuild: later errors can be consequences of the first one. In Xcode, click the red issue marker to jump to the source. Warnings are separate from errors; the build exit status and final “Build complete!” tell you whether compilation succeeded.

If a toolchain problem appears, run:

```sh
xcodebuild -version
swift --version
xcrun --show-sdk-version
uname -m
```

Expect Xcode/SDK supporting macOS 27 and `arm64`. If Xcode is missing or first-run setup isn't complete, finish Apple's normal Xcode setup before retrying. Do not download random toolchains or disable OS security to fix a build.

## 5. Debug in Xcode

Select DeadlineMaster / My Mac, then Command–R. Click the gutter beside a source line to set a breakpoint. Trigger the corresponding action in the app; Xcode pauses and shows variable values. Resume with the play/continue control. A debug run is useful for inspecting state; `package.sh` is the path to a self-contained Finder-launchable app bundle.

For an isolated UI test library, add the environment variable `DEADLINE_MASTER_LIBRARY` in the scheme's Run > Arguments settings, pointing to a new folder inside this project. Do not point an experimental build at your only copy of important data.

## 6. Release locally

`./scripts/package.sh` builds arm64 optimized code and bundles it with Info.plist and the generated icon. `codesign --verify --strict "build/Deadline Master.app"` verifies the local signature. This is an ad-hoc development signature, not Apple's notarization or an identity-based distribution signature.

You can move the finished `.app` to Applications yourself. On this development machine, double-click it like any other app. Offline use requires no web server, subscription, or API token. Quit with Command–Q.

## 7. Review before handing a build to someone

Follow `QA.md`. Automated tests do not replace checking native file panels, layout, long filenames, keyboard navigation, or real mixes. Keep a backup before making storage/schema changes. Real distribution needs its own signing/notarization work; this prototype does not implement that.
