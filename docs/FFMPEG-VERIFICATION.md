# FFmpeg and app verification — 2026-11-18

## Scope and environment

No FFmpeg/dependency source was compiled. Existing installed binaries were vendored, including SDL3 missing from the old dynamic dependency closure. Deadline Master alone was compiled from Swift source.

- Apple silicon, macOS 27.0.1 (26A434).
- Xcode 27.2 (27B52), SDK macOS 27.2; app deployment target macOS 27.
- Apple Swift 6.4.2, target arm64-apple-macosx27.0.0.
- Full Homebrew FFmpeg 9.0.2_1 configuration retained, including GPL/version3; nonfree is disabled.

## Procedure exercised

1. Preserved the previous runtime's binary manifest and seven capability listings.
2. Ran `python3 scripts/bundle-ffmpeg.py`. This copies, relocates and ad-hoc signs existing binaries. It performs no source compilation or dependency installation.
3. Collected and verified sources for the added SDL3 package and recovered XCB/X.Org inputs. Regenerated source notices and reconciled them against the runtime's binary-origin map.
4. Ran `./scripts/dev.sh test`: all 44 tests passed (28 core, 5 documents, 11 audio).
5. Ran `./scripts/package.sh --reuse-ffmpeg`: Swift release build and app signature verification passed. This mode reuses the existing runtime without Homebrew discovery.
6. Ran `python3 scripts/verify-ffmpeg-bundle.py` against the runtime inside `build/Deadline Master.app`.
7. Ran the 44 tests again with `DEADLINE_FFMPEG_ROOT` explicitly pointing to the packaged runtime; all passed.
8. Ran seven Python release-tool regression tests, Python compilation checks, shell syntax checks and Git whitespace checks.

Xcode required normal host access to its build services; the initial restricted attempts failed before compilation and were rerun successfully with approval. No upstream rebuild was attempted.

## Verified results

| Check | Result |
| --- | --- |
| Original runtime binaries | All 281 checksums unchanged |
| Added runtime library | Existing SDL3 3.4.18; local libSDL3.dylib alias |
| Current binary inventory | 282; all arm64, signatures valid, hashes match |
| Library references | All non-system static load references resolve within bundled runtime |
| FFmpeg configuration/capabilities | All seven listings identical to the previous runtime |
| Audio smoke tests | Encode and decode PCM float, FLAC, MP3, Vorbis, Opus and AAC |
| Runtime-loaded SDL3 | ffplay succeeds with dummy audio/video; loader trace confirms app-local SDL3 and no Homebrew path |
| Runtime-loaded frei0r | invert0r filter processes a synthetic video frame |
| Preserved notices | Source and recovered supplementary notice hashes match |
| Handoff integration | WAV rates/depths, metadata, TPDF, unchanged-depth PCM preservation, batch/ZIP and original-file protection pass |

Tests generated synthetic audio in temporary folders. User music files were not used or modified. Environment for bundled FFmpeg smoke tests contains system PATH only and the app's plugin path. No Internet access or downloaded model weights are needed by these checks.

## Limits

- This is same-Mac testing, not a test on a clean second Mac.
- The Swift integration tests call the app's actual audio export modules against its packaged runtime; this pass did not manually operate the GUI.
- Retaining the complete capability listings does not mean every codec, device, hardware path, protocol or plugin has been exercised.
- FFmpeg's Whisper integration still needs separately supplied model weights. The full Homebrew configuration is preserved; it is not a promise that every optional upstream integration is enabled.
- App compilation/package verification is complete for this pass. The upstream source-build procedure remains unexercised under the user's no-rebuild constraint.
- Ad-hoc signatures are development signatures, not Developer ID signing or notarization.
- These functional checks do not resolve missing historical source/license evidence or authorize distribution.

Machine-readable results are in `ThirdParty/FFmpeg/bundle-verification.json`; raw logs and the previous baseline are preserved in the review kit under `extra-provenance/verification`.
