# IPTVX FFmpegBuild maintenance

## 3.14.0 integration

Merge upstream `3.14.0` (`2ff2238f6b65d7686e71c8aa9e45fa4e26f33e1d`)
into `3.13.0-iptvx`. The only fork difference in the upstream build script remains
framework metadata at iOS/tvOS 16. All nine frameworks are rebuilt, preserving
all source patches, component configuration, dSYMs, privacy and license files.
The new DTS:X alternate-presentation parser and `x_presentation` export are the
unaltered upstream patch. No LibDTSX/Rust dca code or dependency is introduced.

The parser selects alternate syncwords only when `x_heights` is enabled, checks
prefix/header/NAVI CRCs, decodes only the fixed-height set, and preserves the
coded bed/object fold. It reports presentation identity only after successful
height decoding. The default is off. A stream with no heights keeps ordinary
DTS-HD output; existing height output falls back to silence for malformed frames.
Source review is not a substitute for playback of every alternate DTS:X variant.

The official FFmpeg FATE sample `dts/master_audio_7.1_24bit.dts` is used locally
for `Scripts/validate_dts_fixture.sh` (not redistributed here). Its checksum is
recorded in the validation evidence. The script decodes the sample with heights
both off and on and compares PCM; run it through a FlowDeck aggregate target.
It also supports a second package-root argument for comparison with the previous
release. Actual DTS:X standard/alternate height content needs separate playback
acceptance; this fixture contains DTS-HD 7.1 without the height extension.

### 3.14.0 validation

FlowDeck full source rebuild passes for all ten target architectures. The complete
macOS suite passes 46 results with no failures or skips; nine packaging tests
pass. The binary audit passes all 63 slices, 90 architectures, 45 paired dSYM
architectures and 21 privacy manifests. All five input hashes and 63 packaged
binary hashes match `BUILD-INFO.txt`. The four required shaping filters remain
enabled in all ten build configurations. License files are unchanged upstream.

The new `x_presentation` regression fails against 3.13.0-iptvx and passes against
this release, proving the added export is consumed at runtime. The FATE DTS-HD
sample (SHA-256 `227f1008f9529b2bdf937ce856d2562d0128162ac930e2579ef4b8fd7474ee18`)
decodes 1,172 frames / 600,064 samples identically in both releases with
`x_heights` off and on (PCM/frame-shape MD5 `b7f5d7e52a3059c182abcd6c7dfa3fac`).
The new presentation export stays zero because the fixture has no height set.
This is host decoding evidence, not DTS:X alternate-stream or physical-device
playback acceptance; the new alternate parser is unchanged upstream source.

## 3.13.0 integration

The complete upstream 3.13.0 tag is merged into 3.12.1-iptvx. All nine dynamic
frameworks are rebuilt for every supported architecture with the retained OS16
floors. The changed DTS:X patch keeps the coded channel bed with its height folds
intact; the engine's BedRegression now separates it. The optional x_heights flag
remains off by default. This is FFmpeg's decoder, not LibDTSX or Rust dca.
No existing correction, privacy manifest, attribution or dSYM is retired.

FlowDeck rebuilt all platforms from source. The complete macOS suite passes 45
results with no failures or skips. Nine packaging tests pass; the binary audit
validates 63 platform slices, 90 architectures, 45 matching dSYM architectures and 21 privacy
manifests. All five input hashes and 63 packaged binary hashes match BUILD-INFO.
These are automated build/behavior/packaging checks, not physical playback proof.

## Release ancestry and compatibility

`3.12.1-iptvx` merges the complete upstream `3.12.1` source release
(`9c87af0231fd1403654c14a0e867fe8aa43c5bea`) into the previous IPTVX release
`3.11.0-iptvx` (`84729c8d4e9c29b72cfa770272962dc443d7a229`). The release
must retain both commits in its ancestry. Upstream prebuilt binaries are
replaced by a complete source rebuild with these deployment floors:

| Platform | Minimum version |
| --- | --- |
| iOS and iOS Simulator | 16.0 |
| tvOS and tvOS Simulator | 16.0 |
| macOS | 14.0 |
| visionOS and visionOS Simulator | 1.0 |

Preserve the nine dynamic `Aether` framework identities, install names and
SwiftPM products. Check both architectures of every universal binary, matching
device/macOS dSYMs, privacy manifests and independent license notices. The
manifest alone cannot prove compatibility. No LibDTSX library is supplied.

## Active source patches

`build.sh` applies and checks each patch before compilation. The existing
FFmpeg base is `n8.1.3`; dav1d, zimg and libzvbi versions remain unchanged.
No retained correction is retired in this release.

| Build function | Maintained behavior |
| --- | --- |
| `patch_ffmpeg` | Balance autoreleased Metal objects in `yadif_videotoolbox`. |
| `patch_ffmpeg_pgssub` | Clear the predecessor cue when a damaged PGS set lacks its palette. |
| `patch_ffmpeg_visionos` | Avoid unavailable OpenGL buffer keys on visionOS. |
| `patch_ffmpeg_matroska_tts` | Report non-default Matroska TrackTimestampScale handling. |
| `patch_ffmpeg_vc1_parser` | Restore VC-1 parser state from extradata after repositioning. |
| `patch_ffmpeg_dav1_tag` | Recognize the `dav1` AV1 codec tag. |
| `patch_ffmpeg_mpegts_mpeg1_probe` | Probe ambiguous MPEG-TS MPEG audio correctly. |
| `patch_ffmpeg_eac3_dec3` | Preserve dependent-substream channel and JOC metadata in `dec3`. |
| `patch_ffmpeg_movenc_fragment_end` | Reject queued timestamps preceding the fragment's written samples. |
| `patch_ffmpeg_dca_x_heights` | Keep opt-in DTS:X standard/alternate height decoding and its presentation export. |
| `patch_ffmpeg_av1_delayed_rap` | Admit hidden AV1 keyframes only when every reference slot refreshes. |
| `patch_ffmpeg_matroska_skip_attachments` | Add opt-in attachment skipping while preserving ordinary stream reads. |
| `patch_ffmpeg_matroska_byte_seek_done` | Clear terminal Matroska state when byte seeking repositions input. |
| `patch_zvbi` | Exclude GPL-only sources and provide the existing LGPL stub entry points. |

The last three FFmpeg corrections are new upstream 3.12.1 release content.
Their patches live in `patches/`; their generated-fixture regressions live in
`Tests/FFmpegBuildTests/`. Keep all earlier regressions alongside them.
The required audio-shaping filters and AV1 film-grain attribution remain part
of the distribution even when a client does not expose those features.

## Upgrade checks

1. Start from the previous published IPTVX tag and merge the entire requested
   upstream tag. Resolve version documentation and generated artifact conflicts
   while preserving the compatibility settings and active patch inventory.
2. Rebuild changed source for every platform and architecture. The release
   build must not import upstream binaries with higher deployment floors.
   Use FlowDeck for Apple builds and tests; `build.sh` can run in an isolated
   aggregate Xcode target generated from a local XcodeGen manifest.
3. Run the new behavioral regressions against the previous binaries when
   applicable, then run the complete `FFmpegBuildTests` suite against the
   rebuilt artifacts. Distinguish automated macOS evidence from OS 16 and
   physical-device playback evidence.
4. Run `python3 -m unittest discover -s Tests/Packaging -v` and
   `python3 Scripts/verify_deployment_targets.py`. Require nine frameworks,
   63 platform slices, 90 architectures and 45 matching shipped dSYM
   architectures. Verify all 21 existing privacy manifests and license tests.
5. Review `BUILD-INFO.txt`: source revisions and patch hashes must match the
   actual build inputs; configure flags must retain the deployment floors and
   required filters; output hashes must match the packaged files.
6. Publish only after source ancestry, regression tests and packaging checks
   pass. The checked-in XCFrameworks are the SwiftPM artifacts; a GitHub
   release does not require duplicate binary assets.

Retire a patch only after equivalent upstream behavior is present and its
behavioral regressions pass without the patch. A clean merge alone is not
proof of equivalence.

## 3.12.1 validation record

The fresh all-platform FlowDeck build completed successfully. The complete
macOS suite passed 45 tests, including all five new upstream test declarations
(two attachment tests exercise both option values). Before rebuilding, four
of those declarations failed against the previous release and the AV1
partial-refresh control passed. All five pass with the rebuilt release.

The packaging verifier passed nine unit tests and validated all 63 platform
slices, 90 binary architectures, 45 matching dSYM architectures and 21 privacy
manifests. All 63 binary hashes in `BUILD-INFO.txt` matched, as did its build
script and patch hashes. The four required shaping filters remain enabled
in every architecture configuration. These results do not establish
physical-device playback or an OS 16 runtime result.
