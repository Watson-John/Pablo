# Pablo backend — M0 decision records

This file records the locked architectural decisions from M0. Each entry has a date, the decision, the rationale, and what would trigger a revisit. Decisions cascade into [BUILD.md](BUILD.md), [LICENSES.md](../LICENSES.md), [CMakePresets.json](../CMakePresets.json), [native/models/MANIFEST.md](../native/models/MANIFEST.md), the SQLite schema, and the C ABI in `native/core/include/photo_core.h`.

The full architectural plan lives at [`/Users/johnwatson/.claude/plans/what-are-your-thoughts-scalable-puddle.md`](/Users/johnwatson/.claude/plans/what-are-your-thoughts-scalable-puddle.md).

---

## D1. Metadata library — libexif + read-only XMP shim

**Date:** 2026-05-22
**Status:** Locked

**Decision:** Use libexif (LGPL 2.1, dynamically linked) for EXIF read. Implement a minimal read-only XMP/IPTC parser in `native/core/src/metadata/xmp_reader.cpp` using a small XML parser (pugixml, MIT) for sidecar `.xmp` files and embedded XMP packets. No metadata write-back to originals. No sidecar write-back in v1.

**Rationale:**
- Exiv2 (the obvious full-featured choice) is GPLv2 and would force commercial licensing for a closed-source commercial app. Cost and contract negotiation are non-trivial and would block M5.
- libexif is LGPL 2.1 and covers EXIF read cleanly. The gap is XMP/IPTC, which a small custom reader can handle for v1 (read keywords, rating, caption, title; ignore everything else).
- All user-authored metadata (ratings, captions, tags, face assignments) is **catalog-only** in v1. The SQLite catalog is the source of truth. Other apps will not see these edits.

**Implications:**
- M5 will not produce Lightroom-compatible sidecars. Users who want interop are out of scope for v1.
- LICENSES.md must enforce dynamic linkage for libexif.
- BUILD.md vcpkg manifest includes `libexif` and `pugixml`.
- `asset_metadata` schema (M5) stores normalized fields; sidecars are read on import and on sidecar-mtime change only.

**Revisit trigger:** if a v1.5 needs interop, evaluate Exiv2 commercial license against accumulated user demand.

**Amendment (2026-06-30, editor §6 / Stage 7):** the catalog-only rule still holds
as the **default** for the non-destructive editor — "Save Edits" persists a
parametric edit spec in the `asset_edit` table and never touches the original.
A user-configurable opt-in (`Settings → Edit save → Layered TIFF`,
`AppConfig.editSaveMode = layeredTiff`) additionally writes a self-contained
`<name>.pablo.tif` beside the photo: page 0 = the edited render, page 1 = the
**untouched original**, and the parametric spec in the TIFF ImageDescription.
This is non-destructive at the file level (the original is embedded, not
overwritten) and portable, but it IS a real new-file write, so it is opt-in and
off by default. "Save as Copy" (`photo_asset_export`) likewise writes a separate
flattened file. No original file is ever modified or deleted by the editor.

**Amendment (2026-07-01) — opt-in XMP face-region write-back (§7 parity).** The
"no write-back" rule is relaxed for ONE explicit, user-initiated action: exporting
an asset's named face regions to an XMP **sidecar** (`<path>.xmp`) in the MWG
Regions schema (`native/core/src/xmp/face_xmp.cpp`, `photo_asset_write_face_xmp`).
This never runs on import or automatically, is a pure-text sidecar (no dependency,
no pugixml, and the **original image bytes are never touched**), and is the write
half the parity checklist §7 tracked as ❌. Catalog-only remains the DEFAULT for
all other user metadata (ratings/captions/tags/face assignments); manual geotags
also stay catalog-only (a `geo_override` table, not the file). Reading third-party
XMP regions on import is still out of scope. Does not reverse the interop stance
in the Implications — Pablo still produces no Lightroom-compatible metadata beyond
this one sidecar on request.

---

## D2. Face model source — BlazeFace + permissively-licensed embedder

**Date:** 2026-05-22
**Status:** Locked (specific embedder model TBD before M7)

**Decision:** Use MediaPipe BlazeFace (Apache 2.0) for face detection. Use a permissively-licensed 512-d face embedder (candidate: FaceNet Inception-ResNet-v1 ONNX export from David Sandberg's facenet, Apache 2.0; final pick decided before M7). No InsightFace SCRFD / MobileFaceNet / ArcFace weights — those carry non-commercial restrictions that would block ship.

**Rationale:**
- InsightFace code is MIT but trained weights are non-commercial. Buying a commercial license is an option but adds cost and contract risk to a single-developer project.
- BlazeFace is small, fast, and shipped by Google under Apache 2.0. Detection accuracy is sufficient for personal-library face clustering.
- A permissive embedder gives lower per-pair accuracy than ArcFace/MobileFaceNet trained on WebFace, but for clustering an individual's faces within a single user's library, the ceiling is far below the model's ceiling — quality differences will rarely surface.
- Architecture (HDBSCAN bootstrap, prototype ensemble, negative constraints, approve/reject) is model-agnostic; we can swap embedders in M7 without disturbing M0–M6.

**Implications:**
- M6 model registry must reject any non-commercial-flagged model unless the user explicitly opts in.
- M7 face pipeline must validate the embedder produces L2-normalized 512-d vectors before integration; if the chosen embedder uses 128-d (FaceNet's native output) we either accept that and update `face_embedding.vec` size or pick a different one.
- The fast/deep two-pass detector design in the plan collapses to "BlazeFace only" for v1 unless quality dictates otherwise during dogfood.

**Revisit trigger:** if M7 spot-check accuracy on 100 hand-labeled images is below 85% precision, evaluate (a) a different permissive embedder, (b) fine-tuning the embedder on a commercial-clean dataset, or (c) the InsightFace commercial license as a fallback.

**Amendment (2026-06-14) — embedder resolved, detector revised.** The cluster_replay
A/B bake-off D2 deferred to M7 was built early as the standalone `eval/` harness
(branch `feat/face-ingestion`) and run on the real dogfood library (1,243
Picasa-labeled faces). Results updated [native/models/MANIFEST.md](native/models/MANIFEST.md):

- **Embedder = `auraface`** (fal/AuraFace-v1, Apache-2.0, ResNet100 ArcFace, 512-d):
  the commercial-clean ArcFace D2 wanted but believed unavailable. Ceiling-level
  (AUC 0.974, cluster F1 0.96 with a label-trained projection head); supersedes the
  FaceNet placeholder. `sface` (Apache, 128-d) is the CPU/speed fallback.
- **Detector = `scrfd_10g`** via fal's Apache-2.0 AuraFace re-release: 97.7% recall
  vs BlazeFace's untested/likely-lower (and YuNet's 70.7%) on scanned photos —
  detection was the dominant bottleneck. **Licensing basis:** InsightFace *code* is
  MIT; the SCRFD weights are redistributed by fal (a commercial vendor) under
  Apache-2.0. Owner accepts this basis (2026-06-14). Risk if fal's relicensing is
  later found invalid: swap to BlazeFace (kept as a fallback in the MANIFEST).
- **Clustering = agglomerative** (avg-linkage, cosine), grid-search winner
  (F1 0.94 ± 0.03 over 5-seed CV; beat HDBSCAN/Leiden/Infomap/DBSCAN/Chinese-Whispers
  at personal-library scale). Per-person prototype + suggest-and-confirm UX retained.

---

## D3. Windows ML provider — WinML preferred, DirectML fallback

**Date:** 2026-05-22
**Status:** Locked

**Decision:** On Windows, the ML runtime probes WinML first. DirectML is registered only as fallback when WinML is unavailable (Windows 10 pre-1903, or hardware where WinML cannot enumerate a device). CPU is the universal baseline below both.

**Rationale:** Microsoft's official guidance now recommends WinML for new Windows projects; DirectML is in sustained engineering. The provider-probe abstraction in M6 already supports per-platform branches, so picking WinML costs nothing architecturally.

**Implications:**
- M6 `provider_probe.cpp` Windows branch attempts WinML session creation first.
- DirectML session (when used) must enforce sequential execution, no memory-pattern optimization, max 1 concurrent `Run()`.

---

## D4. RAW scope — embedded preview only

**Date:** 2026-05-22
**Status:** Locked

**Decision:** v1 RAW support is read-the-embedded-preview only via LibRaw's `unpack_thumb` + `dcraw_make_mem_thumb`. No demosaic, no highlight recovery, no white-balance tools, no full-resolution RAW rendering.

**Rationale:** LibRaw's own documentation says production-quality RAW rendering is not its scope; doing it well requires a librtprocess / darktable-derived pipeline that is a multi-month epic on its own. Embedded previews from modern cameras are large (often 1600×1067+) and color-managed, so the browse experience is already strong.

**Implications:**
- `native/core/src/image/raw_codec.cpp` uses LibRaw thumb API only.
- RAW files without embedded previews surface a "RAW (no preview)" placeholder; do not attempt fallback demosaic.
- Roadmap entry: "Develop RAW" as a separate post-v1 epic.

---

## D5. LGPL link policy — dynamic linkage, relink artifact in installer

**Date:** 2026-05-22
**Status:** Locked

**Decision:** All LGPL-licensed libraries (libvips, libheif, LibRaw, libexif) are dynamically linked. The Pablo installer ships either the object files necessary to relink against an alternative version of each LGPL library, or a documented procedure for the user to do so. CMake enforces this from day one — any `add_library(... STATIC ...)` for an LGPL dep fails the build.

**Rationale:** LGPL § 6 requires that users can replace the LGPL component. Dynamic linkage + relink artifact is the standard mitigation. Static linkage is possible but adds source-or-object-disclosure obligations that complicate distribution.

**Implications:**
- [CMakePresets.json](CMakePresets.json) sets `BUILD_SHARED_LIBS=ON` and adds per-library overrides.
- CI has a grep check that fails on `add_library.*STATIC` for blacklisted libs.
- Installer build (post-M3) bundles per-platform `.dylib`/`.dll`/`.so` files separately from the main app binary.
- LICENSES.md per-library row documents the exact link mode.

---

## D6. macOS FFI loading — explicit `DynamicLibrary.open`

**Date:** 2026-05-22
**Status:** Locked

**Decision:** Per-platform `DynamicLibrary.open` in `packages/photo_native/lib/src/ffi/load_library.dart`. Revisit `@Native()` native assets after v1 ships.

**Rationale:** `DynamicLibrary.process()` is unreliable on macOS because Flutter plugins ship as embedded frameworks and symbols may not be globally visible. Native assets are still preview-state in the Dart SDK we target.

**Implications:** see plan §M2.

---

## D7. Texture cross-fade locking — double-buffered, no compositor work under lock

**Date:** 2026-05-22
**Status:** Locked

**Decision:** Slot mutex protects state transitions and back-buffer acquisition only. Alpha blending happens outside any lock. Front/back buffer swap is under a separate present mutex. The render-thread texture callback always reads a complete immutable front buffer.

**Rationale:** prevents (a) deadlock from synchronous texture callback re-entering the slot lock, and (b) torn-frame glitches when the callback reads a buffer being concurrently overwritten by the next blend tick.

**Implications:** see plan §M3 task 9 and the locked pseudocode.

---

## D8. Cache key versioning — bake every codec library version into the key

**Date:** 2026-05-22
**Status:** Locked

**Decision:** `cache_key = blake3_128(asset_id, file_size, mtime_ns, content_rev, sidecar_hash, stage, target_w, target_h, resize_mode, orientation_policy, color_policy, app_pipeline_version, libvips_version, libjpegturbo_version, libheif_version, libjxl_version, libraw_version)`.

**Rationale:** SIMD updates in libjpeg-turbo (and similar) can shift decoded LSBs between releases. A coarse `decoder_pipeline_ver` field invalidates everything on a Pablo upgrade but won't invalidate on a libjpeg-turbo upgrade — leading to silent cache poisoning that's invisible to humans but breaks any future content-hash dedup.

**Implications:** `native/core/src/cache/cache_key.cpp` queries each codec library for its `_version_string()` at init and incorporates them into the key seed.

---

## D9. Writer lane discipline — single writer, hot reads bypass

**Date:** 2026-05-22
**Status:** Locked

**Decision:** A single dedicated thread is the only writer to SQLite (catalog) and LMDB (blob writes/deletes). All reads — especially LMDB hot blob reads during scroll — bypass the writer lane entirely. Eviction batches in groups of 50–200 entries triggered by a high-water mark, not per-request.

**Rationale:** SQLite WAL serializes writers anyway; centralizing makes batch eviction trivial and removes contention. LMDB's MVCC means readers genuinely don't need to coordinate with writers. Batched eviction avoids waking the writer lane on every viewport scroll event.

**Implications:** see plan §M3 (cache subsystem).

---

## D10. Thumbnail cache eviction — rotating self-describing segments

**Date:** 2026-06-14
**Status:** Locked (current `ThumbCache` implementation)

**Decision:** The on-disk thumbnail cache (`native/core/src/thumb/thumb_cache.{h,cpp}`) is a set of rotating, self-describing segment files `seg-<id>.pak` rather than a single pack+index pair (or the LMDB store sketched in D9). Each segment is `[8-byte magic 'PABSEG02'][RecHeader][blob]...`; the per-blob `RecHeader` carries `(key,len,width,height,flags)` inline, so each segment validates standalone and the in-RAM index is rebuilt by scanning segments at open (ascending id + offset ⇒ newest live copy wins). Disk-budget eviction deletes the **oldest whole segment** when the sum of segment sizes exceeds `disk_budget_bytes`; LRU is approximated by a RAM-only CLOCK bit set on `get()` plus promote-at-evict (hot entries are re-appended into the active segment just before their segment is dropped). A single blob is bounded to 64 MiB and the per-segment cap to ≤256 MiB so all in-segment offsets stay under `LONG_MAX` (portable `std::fseek`).

**Rationale:**
- Eviction from an append-only store needs either compaction (a multi-GB rewrite under the lock) or whole-file rotation. Rotation gives O(1) reclaim, a whole-file atomic crash unit, and no compaction pass — the simplest design that never serves wrong bytes after a crash.
- Dropping the separate index file removes the half-renamed-pair / dangling-pointer hazard a pack+idx pair would have under eviction; the index is always rebuilt from the same self-describing bytes.

**Implications:**
- The new magic `PABSEG02` is foreign to the prior `PABPACK1`/`PABIDX01` single-pack format, so an existing cache is **reset once** on upgrade (cold start; the cache is regenerable). Not a bug.
- Crash-**consistent**, not power-loss-**durable**: writes use `fflush` (libc), not `fsync`. A power cut may lose recently-written thumbnails; this is within tolerance (they re-decode).
- Cache key remains the existing FNV-1a of `(asset_id, stage, path + size + mtime)` — it does **not** yet incorporate codec-library versions as D8 specifies; revisit when D8's keying is adopted.
- Blobs are stored **JPEG-encoded** (Q85, alpha dropped — thumbnails are opaque) when libvips is available, ~10x smaller than raw BGRA so far more thumbnails fit the disk budget; the RecHeader `flags` bit1 marks JPEG and `get()` decodes on read. Without libvips the blob is raw premultiplied BGRA. Records self-describe their format, so raw and JPEG records coexist in one cache (no magic bump). A torn/garbage JPEG fails to decode → clean cache miss, never wrong bytes.
- Differs from D9's LMDB + batched-eviction model: that store is not yet implemented; this file-based cache is what ships in M3.

**Revisit trigger:** if per-drop index-erase latency at the 16 GiB default proves too high (benchmark before shipping a huge default), lower the segment cap or move `remove()`+erase to a brief-lock background reclaimer. If D8/D9's LMDB store is adopted, supersede this.

---

## D11. Editor retouch (heal + red-eye) — classical CPU passes, ONNX inpaint deferred

**Date:** 2026-06-30
**Status:** Locked for §6 / Stage D (ships classical; model hook structured for later)

**Decision:** Both retouch tools run as **pure-C++ passes over the BGRA
`FrameBuffer`** (`native/core/src/edit/render.cpp`), so they build and are unit-
tested on every desktop target with **no new dependency**:
- **Red-eye** (`apply_redeye`): a **seed-connected red-blob segmentation** per
  brush dab (not a per-pixel threshold). It measures redness with a
  luminance-normalized rg-chromaticity metric `p` (skin of every tone pools near
  ~0.1; a flash pupil sits near ~0.65 — so a single cutoff works where the old
  brightness-sensitive `R/((G+B)/2)>1.35` ratio put warm skin at 1.37 and dark
  skin at 1.82 on both sides of its constant), derives an **adaptive threshold**
  from the surrounding skin ring, seeds at the reddest central pixel, and grows
  **only the connected pupil blob** — so the skin background (large, low-redness,
  disconnected) is structurally excluded. Shape-validated (area/fill/circularity),
  with a per-pixel adaptive-threshold fallback. Recolor is luminance-preserving
  (0.7·luma), **keeps the specular catch-light**, and feathers the edge. Pure
  C++/CPU, no model. (The original v1 was a fixed `R/((G+B)/2)>1.35` ratio that
  greyed warm/dark skin inside the brush; replaced 2026-07-01 after a GUI smoke +
  a 5-way algorithm study — see the redeye-algorithm-research workflow.)
- **Heal** (`apply_heal`): classical spot-heal — clone a donor patch offset from
  the blemish (~2.4× radius, first axis offset that fits the frame), mean-match
  its boundary ring to the target's (a cheap seamless-clone approximation), and
  feather it in with a smoothstep alpha. Overlapping dabs clone from a pre-pass
  snapshot so they don't smear each other.

The parametric spec carries `redeye=x,y,r|…` and `heal=x,y,r|…` (normalized
centre; radius as a fraction of the short edge, post-geometry coords). These are
retouch-domain ops, **not** part of `apply_pixels` — `has_pixel_ops()` now =
`has_tone_ops() || !redeye.empty() || !heal.empty() || !texts.empty()`, and the
three render sites gate each pass on its own non-empty list.

**Rationale:**
- The plan named **MI-GAN** (Picsart, ICCV 2023; MIT-licensed, CPU-efficient
  ONNX) for content-aware heal — chosen over `big-lama` because big-lama's
  Places-Challenge weights ship **without an explicit weights license**
  (commercial-use ambiguity). MI-GAN remains the intended upgrade.
- But onnxruntime is only linked into the **macOS + standalone** builds today
  (like OpenCV), not the Linux/Windows plugins; and integrating a model blind
  (WebFetch for the checkpoint was unavailable at implementation time) is high-
  risk. Shipping a working, tested, dependency-free heal now — and structuring
  the swap point — delivers the P1 feature without blocking on model diligence.

**Implications:**
- Heal quality is "spot-clone", not full inpainting: great for small blemishes on
  a fairly uniform surround, weaker across strong edges. Documented in the tool.
- `render.cpp` marks the extension point (`heal_region_onnx` hook in the file-
  level note): a bundled MI-GAN ONNX session would replace `heal_region_classical`
  on targets that link onnxruntime, degrading to the classical path elsewhere.
- No ABI or dependency change: the C ABI is unchanged (retouch rides the existing
  `photo_asset_set_edits`/`preview_edits` spec string).

**Revisit trigger:** when the MI-GAN checkpoint is vetted + bundled, wire it behind
the `heal_region_onnx` hook (macOS/standalone first) and keep the classical path as
the cross-platform fallback.

**SOTA verification (2026-07-01):** a multi-agent literature + commercial-practice
review confirmed the red-eye pipeline is best-practice for this context: academic
work on photographic red-eye ended ~2012 at exactly this architecture (redness
channel → morphology → geometric validation → feathered luminance-preserving
recolor with catch-light preservation); no learned corrector exists in the
literature; the face-detector-first Auto mode mirrors the strongest known lineage
(Gaubatz-Ulichney/HP) with SCRFD landmarks at zero added model weight. Two
externally suggested references were **evaluated and rejected as design drivers**:
ACM DOI 10.1145/3718491.3718554 is a *medical* conjunctival-hyperemia grading
paper (YOLOv8+ConvNeXt, corrects nothing); the Kaggle `brianlangay/red-eye-removal`
dataset is a 2.9 MB OpenCV tutorial dump (the LearnOpenCV baseline + 3 unlabeled
images, no ground truth) — strictly weaker than this pipeline on every axis and
unusable as an eval corpus. Shipped from the review's do-now list: auto-detect
regions mapped through the geometry chain (`map_region_through_geometry`, pinned
against `apply_geometry`), per-dab tap-to-remove veto (Picasa's signature
interaction), honest platform messaging (`photo_redeye_auto_supported`).
**Backlog (do-later, ranked):** golden/amber-eye channel; "no red found under this
dab" feedback; auto-run on tool open; synthetic-pupil eval harness sweep; darken
strength (4th spec field); pet-eye mode; drag-to-size; landmark-free Auto for
Linux/Windows. Skipped: per-dab confidence scores, Auto-origin fallback flags
(validation already guards these).

---

## D12. Export options — dedicated ABI POD, watermark stays out of the edit spec

**Status:** Locked (2026-07-02, Stage V1).

Export resize + quality + text watermark ship as a new append-only C-ABI call
`photo_asset_export2(engine, src, dst, spec, const photo_export_options_t*)`
(ABI version unchanged; `opts == NULL` reproduces `photo_asset_export` at
quality 92). The watermark is a RENDER-TIME option (`photo_export_options_t`),
deliberately NOT an `EditSpec` `text=` entry: that grammar is positional with
the free text LAST, so it cannot grow an opacity field backward-compatibly, and
its (x,y) is a box centre while a watermark needs corner anchoring against the
rasterized text metrics. The watermark is drawn on the POST-resize frame so
`wm_size`/`wm_margin` (fractions of the output short edge) are exact on disk.
Batch export is Dart-side (one idle-lane request per file, tracked against the
shared `PHOTO_EVT_EXPORT_COMPLETE` stream) — no native batch job. Any future
spec-level text opacity must be a NEW key, never a positional insert into
`text=`. Amends nothing in [D1] (originals untouched; export writes new files).

---

## D13. Video (§11) — FFmpeg optional native module + video_player playback

**Status:** Locked (2026-07-02, Stage V3).

Video support is a native `video/video_io` module gated on `PHOTO_HAVE_FFMPEG`
(the same optional-dep pattern as libvips): `probe` (dims/duration/codec via
libavformat) and `poster_frame` (seek ~10% → decode → swscale→BGRA) flow through
the existing thumb slot/cache pipeline, so the grid needs no special path.
`is_video_path()` is always compiled; without FFmpeg a video still imports
(catalog **v9** `asset.kind=1`, `duration_ms=0`) — video is never dropped for
lack of a decoder. Duration reaches Dart via `photo_asset_t.flags` bit1
(`PHOTO_ASSET_FLAG_VIDEO`) + `_reserved[0]` (ms) — **no struct growth, ABI
unchanged**. Playback is Flutter `video_player` (AVFoundation on macOS); it has
no desktop Linux/Windows backend, so the lightbox player is `Platform.isMacOS`-
gated with a poster-only fallback elsewhere. Trim is non-destructive per [D1]:
catalog `video_edit(trim_start_ms, trim_end_ms)` (shipped in v9) + a
stream-copy `remux_trim` for explicit clip export (wired in Stage V4) — the
original file is never rewritten.

**Watch-out (shipping):** Homebrew's FFmpeg is a **GPL** build (bundles
x264/x265). For a shippable LGPL binary, rebuild FFmpeg `--disable-gpl`
(decode + stream-copy only need LGPL components). Recorded in LICENSES.md.

---

## Decision queue (open)

| Item | Owed by | Notes |
|------|---------|-------|
| Specific permissive embedder model (FaceNet vs. alternative) | M7 start | Pick after M6 model registry exists so we can A/B against the spot-check corpus. |
| vcpkg vs. Conan for C++ dependency management | M1 start | Defaulting to vcpkg unless explicit objection. |
| Installer/packaging tool per platform | post-M3 | Out of M0 scope; track separately. |
