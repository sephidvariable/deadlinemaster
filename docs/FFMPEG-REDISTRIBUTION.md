# FFmpeg redistribution handoff — 2026-11-18

**Status: app packaging and integration verified; source/license completeness remains unresolved. This is a source REVIEW kit, not distribution clearance.**

## Work completed

- 82 main source packages and 293 additional inputs collected and checksum-verified. Additional inputs include all 271 rav1e registry crates, resources, patches and header/generator sources; some are conservative development/platform extras.
- 282 bundled Mach-O binaries mapped to their installed package, original input checksum, relocated output checksum, source archive and preserved notices. All 281 pre-existing binaries remain byte-for-byte unchanged.
- Added the already-installed SDL3 library, its local loader alias, source and notices. SDL2-compat loads SDL3 dynamically, so the original Mach-O dependency scan missed it. No upstream component was compiled.
- Seven FFmpeg capability listings are identical to the previous bundle. App build, 44 application tests against the packaged runtime, six codec smoke tests, SDL3 loading, a frei0r plugin, signatures, architecture and library closure passed. See [verification record](FFMPEG-VERIFICATION.md) for exact scope and limits.
- Source notice review corrected OpenMP, SVT-AV1, PCRE2 and Graphite2 metadata interpretations. Original SBOMs were preserved as evidence. FreeType's referenced FTL text and JPEG's README.ijg were added to notices, with acknowledgements.
- Five supplementary Rust notice sets recovered from the exact commits embedded in the verified crate archives. They are stored separately with provenance and checksums, not silently inserted into upstream source archives.

## Recovered version records

| Input | Recovered record | Qualification |
| --- | --- | --- |
| xcb-proto 1.17.0 | Installed libxcb pkg-config file explicitly records xcbproto_version=1.17.0 | Source collected; historical recipe modifications not independently established |
| Vulkan-Headers 1.4.363.0 | libplacebo and Vulkan-Loader receipts/SBOMs | Matches collected version |
| Xorgproto 2026.1 | libX11 and FFmpeg dependency records | Matches collected version |
| Xorgproto 2025.1 | libXau/libXdmcp/libxcb dependency records | Newly collected; checksum matches X.Org release announcement |
| GLib patch | Immutable Homebrew patch commit predating the build | Resolved in previous pass |
| rav1e dependency lock | Historical Homebrew helper adds --locked | Exact release lockfile and 271 crates preserved |

`extra-provenance/recovery-20261118.json` records the evidence. Current recipes are not treated as proof of historical build inputs.

## Remaining gaps and current constraint

1. **fast_float:** libplacebo's installed recipe substitutes external headers. No historical version was found in installed receipts, local logs/caches or embedded binary text. Public history requests returned HTTP 403. The current 8.3.3 recipe is candidate evidence only; its version is not substituted into the historical record.
2. **Historical xcb-proto recipe changes:** the source version is now known, but a contemporaneous recipe/build record has not been recovered. Source version recovery is not evidence that no patches were used.
3. **Supplementary notices:** difflib 0.4.0, simd_helpers 0.1.0 and the two winapi Windows-target 0.4.0 crates lack recovered standalone historical license texts. Their manifests contain license declarations. Some are development/platform inputs; the inventory does not assert that they are linked into macOS. Unknown fast_float also prevents complete static attribution.
4. **Upstream source-build procedure:** preserved formulas, patches and helpers have been inspected, but no clean upstream source build has been exercised. Missing historical inputs have not been guessed.

The user explicitly prohibited rebuilding affected components when records remain incomplete. **No FFmpeg or dependency component was rebuilt.** Only Deadline Master's Swift application was compiled, and installed FFmpeg/runtime libraries were copied and packaged. Upstream rebuild verification is therefore still unperformed; app packaging tests do not substitute for it. A clean source build is our completeness safeguard, not a claim that GPL requires bit-for-bit reproducibility.

The distribution gate remains blocked. Do not mark unresolved review records resolved without supporting evidence. The precise component mappings and findings are in `ThirdParty/FFmpeg/license-reconciliation.json`, `license-findings.json`, `release-review.json` and `redistribution-audit.json`.

## Repeat the non-rebuild checks

Run from the project directory with Python 3.11+, Git and Xcode installed:

```sh
python3 scripts/collect-ffmpeg-sources.py
python3 scripts/prepare-ffmpeg-source-inputs.py
python3 scripts/collect-ffmpeg-sources.py --additional-manifest ThirdParty/FFmpeg/additional-sources-required.json
python3 scripts/audit-ffmpeg-release.py --notices
python3 scripts/recover-ffmpeg-notices.py
python3 scripts/reconcile-ffmpeg-licenses.py
./scripts/package.sh --reuse-ffmpeg
python3 scripts/verify-ffmpeg-bundle.py
DEADLINE_FFMPEG_ROOT="$PWD/build/Deadline Master.app/Contents/Resources/FFmpegFull" ./scripts/dev.sh test
python3 -m unittest discover -s Tests/ReleaseToolsTests -v
python3 scripts/audit-ffmpeg-release.py --check
```

The last command intentionally fails while gaps remain. The source collector checks cached bytes again; optional `--system-proxy` uses a configured proxy without changing network settings. No source code is executed by the notice collectors. `--reuse-ffmpeg` prevents fresh Homebrew discovery and reuses the audited runtime; it compiles the Swift app, not FFmpeg. The verifier needs the previous runtime baseline under `build/FFmpegAudit/before`; the review kit preserves a copy in `extra-provenance/verification/baseline`.

`python3 scripts/bundle-ffmpeg.py` is the separate developer vendoring step. It copies the full installed runtime and dynamic SDL3/frei0r dependencies, rewrites library load paths and ad-hoc signs them. It does not compile dependencies, but a different installed runtime would require a new source/notice review. Do not run `brew upgrade`, install replacement components or change their source versions as part of this no-rebuild procedure.

## Source preservation and later distribution

`build/FFmpegSources` and generated `build/Redistribution/*.tar.gz` are ignored by Git. Preserve the review archive and checksum separately; committing the manifests does not preserve the source files. A review kit includes the current uncommitted application source snapshot, exact upstream archives, notices, formulas, receipts, SBOMs, binary origins, capability records and verification evidence. It contains no user music/library or application repository .git directory. Pinned upstream Git sources retain Git metadata needed for version generation.

After the gaps are resolved, bind the final release to the exact binary and source checksums. Preserve source changes from Homebrew recipes, external/inline patches and inreplace operations. Do not describe those upstream builds as entirely unmodified. General-purpose tools and system libraries have licensing exceptions; their source is not automatically part of Corresponding Source, although tool/SDK versions should be documented for building.

For download distribution, offer matching Corresponding Source with equivalent access and clear directions next to the app download. **Testers do not have to download the source archive.** It can be a separate optional link; FFmpeg remains inside the ready-to-run app. Include Deadline Master's source under its existing GPLv3 license. Source URLs alone are not a substitute for providing the required source. Our tools have not published anything or performed Developer ID signing/notarization.

Primary references: [FFmpeg licensing](https://ffmpeg.org/legal.html), the exact collected FFmpeg `LICENSE.md` and `COPYING.GPLv3` (sections 1 and 6), [GPLv3](https://www.gnu.org/licenses/gpl-3.0.html), [Mozilla MPL 2.0 FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/). Original component license texts in the kit take precedence over summarized package-manager labels.
