# FFmpeg full integration — development status

The app uses Homebrew ffmpeg-full 9.0.2_1, not regular ffmpeg. The installed
configuration is preserved in build/FFmpegFull/provenance/version.txt. Native
arm64 executables, transitive libraries and frei0r plugins are copied and their
Mach-O load paths relocated. No codecs, filters or formats are stripped. There
is no runtime download or Homebrew lookup inside the packaged app.

Handoff invokes ffprobe and ffmpeg as separate subprocesses, using argument
arrays (no shell), local-file-only input protocols and no stdin. WAV export
supports 16/24-bit integer PCM and 32-bit float through 192 kHz. When needed,
libsoxr at precision 28 resamples in double precision before a separate
ordinary triangular TPDF quantization stage. Float output is not dithered.
Integer output is dithered when reducing source precision, converting float
to integer, or when source precision is unknown. Unchanged or increased
integer source depth skips dither, even after rate/channel processing.
Matching sample rates skip resampling. Matching rate, channels and codec use
stream copy, preserving PCM samples while allowing updated metadata.
Source files and existing destinations cannot be overwritten. Successful
output is committed from a temporary sibling. UI export choices remain WAV;
other compiled codecs and filters are available for future features.

This is Homebrew's full configuration, not every optional upstream integration.
The formula disables JACK. Whisper is compiled but requires separately licensed
model weights to perform transcription; no weights are bundled. Development
scripts shipped upstream may require Python/Ruby and are not app user features.
No claim is made that every optional workflow has been exercised.

## Licensing and distribution gate

**Development build only; not ready for redistribution.** The package script's
--distribution mode refuses to build a release until this work is finished.

Primary sources studied:
- https://ffmpeg.org/legal.html (retrieved from its official website source at
  https://raw.githubusercontent.com/FFmpeg/web/master/src/legal)
- The installed FFmpeg LICENSE.md and COPYING.GPLv3 (including GPL section 6).
- https://formulae.brew.sh/formula/ffmpeg-full and the installed exact formula.

The enabled GPL components plus --enable-version3 make this FFmpeg build
GPL-3.0-or-later. FFmpeg's LGPL-only linking checklist does not describe this
configuration. --enable-nonfree is rejected. Deadline Master's existing GPLv3
LICENSE was retained. Running FFmpeg as a subprocess does not waive FFmpeg's
own redistribution obligations.

The bundle includes available copyright/license notices, FFmpeg license texts,
IJG acknowledgement, exact installed formulas, receipts, SBOMs, original build
configuration, binary hashes, and capability listings. The app menu exposes
FFmpeg Licenses & Notices. No FFmpeg source changes are made; relocation and
ad-hoc signing are documented in scripts/bundle-ffmpeg.py.

scripts/collect-ffmpeg-sources.py attempts to retrieve the exact source archives
from installed SBOMs and verifies SHA-256 hashes. See build/FFmpegSources/source-status.json.
A list of upstream URLs is not a Corresponding Source distribution.

Before public distribution:
1. Obtain and review all exact corresponding sources, including formula patches,
   resources, generated-code inputs and required build dependencies. Installed
   binaries and current upstream HEAD alone do not satisfy this requirement.
2. Review each dependency's licensing/notices, including statically incorporated
   components. Resolve any missing notices in the collected license directories.
3. Package source and reproducible build/relocation instructions and provide them
   alongside the binary as required by GPLv3 section 6; archive app source too.
   For download distribution, host matching source with equivalent access and
   clear links. Do not rely on upstream URLs remaining available indefinitely.
4. Verify obligations for all third-party components; do not assert source/license
   completeness based solely on Homebrew SPDX labels. Review patent obligations
   for the actual distribution territories separately from copyright licenses.
5. Complete signing/notarization and clean-Mac verification, then remove the
   development-only notice and distribution gate as a reviewed release change.

## Development commands

    python3 scripts/bundle-ffmpeg.py
    ./scripts/dev.sh test
    ./scripts/package.sh
    python3 scripts/collect-ffmpeg-sources.py

FFMPEG_FULL_PREFIX can select an installed full build for the vendor script.
Development tests use DEADLINE_FFMPEG_ROOT=build/FFmpegFull; packaged apps always
use Contents/Resources/FFmpegFull, ignoring that override. Generated runtime
and source archives live under ignored build/. Preserve them with any binary
release rather than assuming git tracks them.
