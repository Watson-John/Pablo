# SPEC-01 — Import & Acquisition

Functional requirements, non-functional requirements, and test cases for Pablo's
**Import & Acquisition** capability group: getting photos *into* the catalog and
keeping the catalog in sync with the filesystem and external sources.

---

## 0. Scope, status, and as-built reality

### 0.1 Features in scope

| # | Feature | Status | Where |
|---|---------|--------|-------|
| IA-1 | Recursive folder scan (6 formats) | ✅ | `pablo/lib/data/library.dart` |
| IA-2 | Native import / rescan + stable asset IDs | 📦 | `catalog/catalog.{h,cpp}`, `import_test.cpp` (PR #6) |
| IA-3 | Broader formats (TIFF/HEIC/RAW/JXL) | 🟡→📦 | `codec/codec.{h,cpp}` via libvips (PR #6) |
| IA-4 | Import-time dedup | 🟡 | `feat/dedup-integration` (FAISS), not integrated |
| IA-5 | Watched / hot folders | ❌ | — |
| IA-6 | Camera / SD ingest | ❌ | — |
| IA-7 | iPhoto / Photos.app import | ❌ | — |
| IA-8 | `.picasaoriginals` handling | ❌ | — |

### 0.2 Status legend

- **✅ Shipped** — on `main`, tested.
- **📦 Native (unmerged)** — implemented in the native backend on PR #6; **not on `main`** in this worktree.
- **🟡 Partial** — scaffolding or a side branch exists; not wired into the import path.
- **🟡→📦 Migrating** — partially working, moving to the native codec path.
- **❌ Not started** — no implementation, no scaffolding.

### 0.3 As-built note (read before testing)

This worktree is based on `main`, which contains the **Dart-side scan only**. The
native catalog, `photo_import_path`/`photo_rescan`, the libvips codec, and
`import_test.cpp` described under IA-2/IA-3 live on the **unmerged PR #6** branch.
Today on `main`:

- `assetIdFor(key)` returns `key.hashCode & 0x7FFF…` — a **process-scoped** id, *not*
  a durable catalog rowid. See [asset_id.dart](pablo/lib/utils/asset_id.dart).
- `photo_import_path` / `photo_rescan` are **C-ABI stubs returning 0**
  ([c_api.cpp](native/core/src/api/c_api.cpp)).
- There is no `catalog` table and no `import_test.cpp` on `main`.

Each requirement below is tagged **[on main]**, **[PR #6]**, or **[planned]** so the
spec doubles as a gap list. Acceptance criteria for 📦 items are written against the
PR #6 design so they're ready when that branch lands.

### 0.4 Terminology

- **Asset** — one catalogued source image file.
- **Asset ID** — the durable integer identity of an asset (target: catalog rowid).
- **Import** — first-time cataloguing of a path subtree.
- **Rescan** — reconciling the catalog with the current on-disk state (add/update/remove).
- **Library root** — a top-level folder the user has added to Pablo.
- **Sidecar** — adjacent metadata (`.picasa.ini`, XMP) describing an asset.
- **Content hash** — a strong hash of the file's bytes (`content_hash`); the dedup
  primitive **and** the move-detection key.

### 0.5 Resolved design decisions (this revision)

DD-IA-A/B/C resolve the previous revision's open questions; DD-IA-D settles the
move-and-edit case (revised this turn: **treat as removal + new**, no re-link, no
review UI). All belong in `docs/DECISIONS.md`.

- **DD-IA-A — Dedup primitive = full-content hash.** Every asset stores a
  `content_hash` over its file bytes (BLAKE3 recommended for speed; SHA-256
  acceptable), computed during import in the **same read pass** as decode/EXIF so it
  adds ~no extra I/O. Used for (a) exact-duplicate detection (IA-4) and (b) move/rename
  re-linking (IA-2). It is *not* the source of truth for asset existence — the catalog
  rowid is.
- **DD-IA-B — Missing files soft-delete.** A catalogued file absent on disk is marked
  `missing`/unavailable (row + asset ID retained), never hard-deleted. Re-appearance
  re-links the same ID. This is what makes move-detection and reconnecting removed
  volumes possible without orphaning faces/albums/tags.
- **DD-IA-C — Moves preserve identity; only folder view changes.**
  - *In-app move:* Pablo moves the file on disk **and** updates the asset's `path`
    in place — same asset ID. Folder view shows the new location.
  - *External move (on disk):* rescan sees one `missing` path + one `new` path with an
    identical `content_hash` → reconciles them as a **move**, re-linking the existing
    asset ID (resurrecting the soft-deleted row) rather than creating a new asset.
  - Either way a move changes **only** folder-view placement. Timeline (capture date),
    albums, tags, ratings, stars, and faces are keyed by asset ID and stay attached.
- **DD-IA-D — Move + edit is NOT re-linked; treat as removal + new.** When a file's
  bytes change, it is no longer the same file (`content_hash` differs), so Pablo makes
  **no attempt to recover identity** — no EXIF/capture-identity matching, no review UI.
  Rationale: when both path and bytes change, *everything has changed*, and a clever
  re-link risks silently attaching the wrong photo's album/tags/faces. Behavior:
  - the original asset has no matching path and no matching hash on disk → it becomes
    `missing` (DD-IA-B) and, being unavailable, **drops out of album / grid / timeline
    views**. Its membership and tag rows are retained only so that an *exact-bytes*
    reappearance can still re-link via DD-IA-C.
  - the new, edited file(s) import as **brand-new assets** with their own IDs and **no
    inherited curation** (the user can re-add them to an album manually).

  This keeps rescan simple and predictable. Accepted cost: a photo edited *and* moved
  outside Pablo in the same window loses its album/tag/face links; the new copy starts
  clean. **Editing in place (same path, changed bytes) is unaffected** — that stays
  `modified`, keeps its ID and curation, and just refreshes its thumbnail/faces
  (FR-IA2-19).

---

## 1. IA-1 — Recursive folder scan (6 formats)  ✅

### 1.1 Functional requirements

| ID | Requirement | Status |
|----|-------------|--------|
| FR-IA1-01 | The scanner SHALL recursively walk a library root and all descendant directories. | ✅ `recursive: true` ([library.dart:150](pablo/lib/data/library.dart:150), [:174](pablo/lib/data/library.dart:174)) |
| FR-IA1-02 | The scanner SHALL accept exactly these extensions, case-insensitively: `.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`, `.bmp`. | ✅ ([library.dart:39-44](pablo/lib/data/library.dart:39)) |
| FR-IA1-03 | Files whose extension is not in the accepted set SHALL be ignored (no error). | ✅ |
| FR-IA1-04 | The scanner SHALL NOT follow symbolic links (`followLinks: false`). | ✅ |
| FR-IA1-05 | The scanner SHALL expose both a synchronous (`Library.scan`) and an event-loop-yielding asynchronous (`Library.scanAsync`) entry point; app boot uses the async path. | ✅ ([library.dart:144](pablo/lib/data/library.dart:144), [:169](pablo/lib/data/library.dart:169)) |
| FR-IA1-06 | A scan of a missing/empty/unreadable root SHALL return an empty `Library` rather than throwing. | ✅ ([library.dart:146](pablo/lib/data/library.dart:146)) |
| FR-IA1-07 | A per-file `stat`/read failure SHALL be caught and the scan SHALL continue; the file's `mtime` MAY be null. | ✅ ([library.dart:157-159](pablo/lib/data/library.dart:157)) |
| FR-IA1-08 | Each discovered photo SHALL be keyed by its absolute file path and grouped into folder, folder-tree, and timeline (year/month) views derived from `mtime`. | ✅ |
| FR-IA1-09 | Photos with a null `mtime` SHALL be excluded from timeline buckets but still appear in folder/all views. | ✅ |
| FR-IA1-10 | *(gap)* The scanner SHOULD skip known cache/system dirs (`.picasaoriginals`, `.thumbnails`, `Thumbs.db`, `@eaDir`, …). | ❌ see IA-8 |

### 1.2 Acceptance criteria

- Given a tree with mixed media, **only** the six accepted extensions appear in `allPhotos`.
- Extension match is case-insensitive (`IMG.JPG` and `img.jpg` both import).
- Symlinked files/dirs are not traversed.
- No single bad file aborts a scan.

---

## 2. IA-2 — Native import / rescan + stable asset IDs  📦 (PR #6)

### 2.1 Functional requirements

| ID | Requirement | Status |
|----|-------------|--------|
| FR-IA2-01 | Each asset SHALL receive a **durable** integer asset ID equal to its SQLite catalog rowid, stable across process restarts and rescans. | 📦 (rowid = id; replaces unstable `path.hashCode`) |
| FR-IA2-02 | `photo_import_path(engine, path, flags)` SHALL catalog a path subtree, inserting one asset row per new file and returning a count/handle. | 📦 (today: stub → 0) |
| FR-IA2-03 | `photo_rescan(engine, flags)` SHALL reconcile catalog vs. disk: insert new files, update changed files, mark/remove missing files. | 📦 (today: stub → 0) |
| FR-IA2-04 | Re-importing or rescanning an already-catalogued file SHALL be idempotent — the same path keeps the same asset ID; no duplicate rows. | 📦 |
| FR-IA2-05 | Change detection for rescan SHALL key on a tuple of `(path, file_size, mtime_ns)` and SHALL NOT rely on full-content hashing in the hot path (per D8). Content hashing is reserved for the missing/new reconciliation step (FR-IA2-13) and dedup (IA-4), run only over the `missing`+`new` sets, not the per-file fast path. | 📦/planned |
| FR-IA2-06 | The catalog SHALL persist at minimum `id, path, file_size, mtime_ns, content_hash, width, height, orientation` per asset; `content_hash` SHALL be indexed; `path` storage SHALL accommodate ≥ 4096 bytes (`photo_asset_t.path[4096]`). | 📦 (+`content_hash`, DD-IA-A) |
| FR-IA2-07 | Downstream subsystems (faces, thumbnails, albums, tags) SHALL reference assets **only** by asset ID; `path_for_asset(id)` and `assetIdForPath(path)` SHALL be the sole id↔path bridges. | 📦 |
| FR-IA2-08 | Face/embedding/tag/album rows SHALL survive a restart without re-scan, because they are keyed by the durable asset ID. | 📦 (the core regression that motivated the rowid change) |
| FR-IA2-09 | All catalog mutations SHALL be serialized under the catalog mutex (`catalog_mu_`) and committed transactionally; a crash mid-import SHALL leave a consistent DB. | 📦 |
| FR-IA2-10 | The catalog schema SHALL carry a version and apply forward migrations on open (v2 import_root … v6). | 📦 |
| FR-IA2-11 | Rescan SHALL classify each asset as `unchanged / new / modified / moved / missing` and surface counts to the caller. | 📦/planned |
| FR-IA2-12 | A file present in the catalog but absent on disk SHALL be marked `missing`/unavailable (soft-delete) — row and asset ID retained, never hard-deleted — so re-appearance re-links the same ID. | ✅ decided (DD-IA-B) |
| FR-IA2-13 | During rescan, a `missing` path and a `new` path with **identical `content_hash`** SHALL be reconciled as a **move**: the existing asset ID is re-linked to the new path (the soft-deleted row is resurrected) rather than a new asset being created. | ✅ decided (DD-IA-C) |
| FR-IA2-14 | An **in-app move** SHALL move the file on disk and update the asset's `path`/folder in place, preserving the asset ID; folder view reflects the new location. | ✅ decided (DD-IA-C) |
| FR-IA2-15 | A move (in-app or external) SHALL change **only** folder-view placement. Timeline (capture date), album membership, tags, rating, star, caption, and faces SHALL be unchanged, because they are keyed by asset ID. | ✅ decided (DD-IA-C) |
| FR-IA2-16 | If a `new` path's `content_hash` matches a still-present (not missing) asset, that is a **duplicate**, not a move (handled by IA-4), and SHALL NOT re-link/relocate the existing asset. | ✅ decided (DD-IA-A) |
| FR-IA2-17 | A moved-and-edited file (no `path` match **and** no `content_hash` match) SHALL NOT be re-linked to any existing asset. The original becomes `missing`; the edited file imports as a new asset. No capture-identity heuristic and no review UI SHALL be used. | ✅ decided (DD-IA-D) |
| FR-IA2-18 | A `missing`/unavailable asset SHALL be excluded from album, grid, and timeline views (effectively "removed from the album"), while its album-membership and tag rows are retained so an exact-bytes reappearance (FR-IA2-13) can re-link and restore visibility. | ✅ decided (DD-IA-B/D) |
| FR-IA2-19 | A `modified` asset (same path, changed bytes/size/mtime) SHALL refresh its pixel-derived fields (`content_hash`, dims) and bump `content_rev` so its thumbnail and faces regenerate; its asset ID and all ID-keyed associations persist. | 📦/planned |

### 2.2 Acceptance criteria

- Import a folder → restart app → asset IDs are identical; faces/albums/tags still attached.
- Touch a file's bytes (size or mtime changes) → rescan reports it `modified`.
- Move a file within a watched root (externally) → rescan reports it `moved`; the **same asset ID** now points at the new path; the photo's timeline/album/tag/face links are untouched; only its folder-view placement changes.
- Move a photo to another folder **inside Pablo** → the file moves on disk and the asset's path updates in place (same ID); folder view shows it in the new folder.
- Import the same root twice → second import adds 0 rows.
- Add a byte-identical copy of an existing (present) file → treated as a duplicate (IA-4), not a move; the original asset is not relocated.

### 2.3 Resolved decisions (was: open questions)

- **Move/rename identity → preserved** via `content_hash` re-linking (FR-IA2-13/14/15). See DD-IA-C. The earlier "ID changes on move" limitation is **removed**.
- **`missing` → soft-delete** (FR-IA2-12). See DD-IA-B.
- **Move + edit → treat as removal + new** (DD-IA-D, FR-IA2-17/18). A simultaneous move+edit changes both path and bytes, so there is no path or hash match: the original goes `missing` and drops out of albums/grid/timeline; the edited copy imports as a brand-new asset with no inherited curation. No capture-identity heuristic, no review UI. Editing **in place** keeps the ID (`modified`, FR-IA2-19).

---

## 3. IA-3 — Broader formats: TIFF / HEIC / RAW / JXL  🟡→📦

### 3.1 Functional requirements

| ID | Requirement | Status |
|----|-------------|--------|
| FR-IA3-01 | The native codec `decode_bgr(path)` SHALL decode to a BGR `cv::Mat` via libvips, with `cv::imread` as fallback. | 📦 ([codec.cpp] PR #6) |
| FR-IA3-02 | TIFF, HEIC/HEIF, JPEG-XL, and common RAW formats SHALL be decodable wherever the linked libvips ships the corresponding loader (Homebrew vips bundles heif/raw/jxl/tiff). | 📦 |
| FR-IA3-03 | The thumbnail pipeline SHALL already be all-format via libvips; only the faces path needed `decode_bgr`. Both paths SHALL agree on pixels for a given asset. | 📦 |
| FR-IA3-04 | RAW SHALL be handled by libvips full-develop in v1 (NOT embedded-preview extraction); embedded-preview is a tracked follow-up. | 📦 (documented) |
| FR-IA3-05 | The scanner's **accepted-extension set** (FR-IA1-02) SHALL be widened to include `.tif/.tiff`, `.heic/.heif`, `.jxl`, and the RAW family (`.cr2/.nef/.arw/.dng/.raf/.orf/.rw2`, …) when IA-3 is wired to import. | 🟡 (codec ready; scan set not yet widened) |
| FR-IA3-06 | A file with an accepted extension that the linked libvips cannot decode SHALL fail gracefully: the asset is still catalogued, a decode error is logged, and a placeholder is shown — the import SHALL NOT abort. | planned |
| FR-IA3-07 | Decoded orientation SHALL be normalized (EXIF orientation applied) so thumbnails and full-res render upright. | 📦 (EXIF orientation in catalog, Stage 3a) |
| FR-IA3-08 | Decode of a corrupt/truncated file of any format SHALL return null/empty and SHALL NOT crash; libvips error state SHALL be cleared between calls. | 📦 |

### 3.2 Acceptance criteria

- A HEIC, a TIFF, a JXL, and a DNG each produce a correct upright thumbnail and full-res decode.
- The same asset decoded through the thumbnail path and the faces path yields equivalent pixels.
- A truncated HEIC yields a placeholder, a logged error, and no crash.

### 3.3 Notes / risks

- **Capability is libvips-build-dependent.** Tests MUST first probe the linked vips for loader support and **skip-with-reason** when a loader is absent (e.g. CI vips without HEIF), never silently pass.
- RAW full-develop is slow and memory-heavy vs. embedded preview — see NFR-IA-PERF and the follow-up.

---

## 4. IA-4 — Import-time dedup  🟡 (not integrated)

### 4.1 Functional requirements

| ID | Requirement | Status |
|----|-------------|--------|
| FR-IA4-01 | The system SHALL detect **exact-duplicate** files (identical bytes) at import via `content_hash` (DD-IA-A) — the same hash used for move detection (FR-IA2-13). Two present files with the same hash form a duplicate group. | 🟡 (primitive decided) |
| FR-IA4-02 | The system SHOULD detect **near-duplicate** images (re-encodes, resizes) via perceptual similarity over embeddings (512-d AuraFace vectors) indexed by FAISS/USearch. | 🟡 (`feat/dedup-integration`) |
| FR-IA4-03 | Dedup SHALL be **non-destructive**: duplicates are flagged/grouped for user review, never auto-deleted. | planned |
| FR-IA4-04 | Embedding-based dedup SHALL run **after** asset insertion (embeddings are produced by the scan pipeline), not block first-time import. | 🟡 (current architecture) |
| FR-IA4-05 | Dedup results SHALL be presented as review groups (keep/merge), with the user choosing the canonical asset. | planned |
| FR-IA4-06 | The dedup index SHALL be rebuildable from the catalog and SHALL NOT be the source of truth for asset existence. | planned |

### 4.2 Acceptance criteria

- Importing two byte-identical files surfaces them as a duplicate group; both remain on disk.
- A resized copy of an imported photo is flagged as a near-duplicate above the similarity threshold.
- Dedup never deletes a file without explicit user action.

### 4.3 Resolved / remaining

- **Exact-dup primitive → decided:** full-content `content_hash` (BLAKE3 recommended, SHA-256 acceptable), computed once at import and stored on the asset (DD-IA-A). Shared with move detection.
- **Remaining:** near-dup threshold; whether near-dup runs at import or as a background pass (current architecture: after import, FR-IA4-04); and the integration plan for `feat/dedup-integration` into the catalog import path.

---

## 5. IA-5 / IA-6 / IA-7 / IA-8 — Not-started acquisition sources  ❌

These are specified at requirement level so the work is scoped; all are **❌ (no code)**.

### 5.1 IA-5 Watched / hot folders

| ID | Requirement |
|----|-------------|
| FR-IA5-01 | A library root MAY be marked "watched"; OS filesystem events (FSEvents/inotify/ReadDirectoryChangesW) SHALL trigger an incremental rescan of the affected subtree. |
| FR-IA5-02 | Watch events SHALL be debounced/coalesced so a bulk file drop yields one rescan, not one per file. |
| FR-IA5-03 | Watching SHALL degrade to periodic polling where OS events are unavailable (network volumes). |
| FR-IA5-04 | A removed/disconnected watched root SHALL be marked offline (assets retained, marked unavailable), not purged. |

### 5.2 IA-6 Camera / SD ingest

| ID | Requirement |
|----|-------------|
| FR-IA6-01 | On insertion of a camera/SD volume, Pablo SHALL offer to ingest media into a destination folder, then catalog it. |
| FR-IA6-02 | Ingest SHALL copy (default) — never move/delete from the card unless the user opts in. |
| FR-IA6-03 | Ingest SHALL skip files already present (by dedup primitive) so re-inserting a card doesn't re-copy. |
| FR-IA6-04 | Ingest SHALL organize into a date-based folder pattern (configurable), preserving EXIF capture date. |
| FR-IA6-05 | A failed/cancelled ingest SHALL leave the card untouched and the catalog consistent. |

### 5.3 IA-7 iPhoto / Photos.app import

| ID | Requirement |
|----|-------------|
| FR-IA7-01 | Pablo SHALL import from an Apple Photos/iPhoto library: original masters, albums, keywords, favorites, and capture dates. |
| FR-IA7-02 | Import SHALL read originals (not rendered edits) and map albums→albums, keywords→tags, favorites→starred. |
| FR-IA7-03 | Import SHALL be idempotent and resumable; re-running maps to existing assets via dedup, not duplicates. |
| FR-IA7-04 | Import SHALL never modify the source Apple library (read-only). |

### 5.4 IA-8 `.picasaoriginals` handling

| ID | Requirement |
|----|-------------|
| FR-IA8-01 | The scanner SHALL **skip** `.picasaoriginals`, `.picasa.ini`-cache, and other known cache/system dirs as *scan roots for assets* (closes FR-IA1-10). |
| FR-IA8-02 | When a `.picasaoriginals/NAME` exists beside an edited `NAME`, Pablo SHALL treat the `.picasaoriginals` copy as the **original master** and the sibling as a derived edit. |
| FR-IA8-03 | Picasa `.picasa.ini` sidecars MAY be read for stars/captions/crops on import (opt-in), without writing back unless explicitly enabled (respects D1 catalog-only default). |

---

## 5b. IA-9 — Storage scheme builder (organization templates)  🟢 Phase A shipped

A DIM-inspired ("Digital Image Mover") way to describe **how photos are filed into
folders and renamed**, expressed as a **drag-and-drop** builder rather than typed
`%Y\%M\%D` format strings. A *scheme* = a folder-path pattern + a file-name pattern,
both built from one token vocabulary, plus processing options. See the approved
plan and DIM5 manual. Built in two phases (decided with the user):

- **Phase A (shipped):** the builder UI, the rendering engine, persistence, and a
  live preview — **no file writes**.
- **Phase B (later, needs PR #6 catalog + a file-ops seam):** apply a scheme during
  camera/SD ingest, bulk "reorganize into scheme", and in-app drag-drop reorganize.

Design decisions (this revision): **DD-IA-E — no location tokens in v1** (Pablo has
raw GPS but no reverse-geocoder; the whole geo group is deferred). **DD-IA-F —
folder-structure and file-name are two visually distinct stages** so users never
conflate *where a photo is filed* with *what it is named* (DIM's adjacent-fields trap).

### 5b.1 Functional requirements

| ID | Requirement | Status |
|----|-------------|--------|
| FR-IA9-01 | A scheme SHALL be a list of folder levels + a file-name lane, each lane an ordered run of token/literal segments, plus [SchemeOptions]. | 🟢 [storage_scheme.dart](pablo/lib/data/storage_scheme.dart) |
| FR-IA9-02 | The token vocabulary SHALL cover date (year/quarter/month/day/hour/min/sec), camera (make/model; owner & unique-id marked *needs-EXIF*), file (original name / parent folder), a running counter, and a run-time prompt (event/label). **No location tokens in v1** (DD-IA-E). | 🟢 |
| FR-IA9-03 | A pure engine SHALL render (scheme, photo metadata, counter, prompts) → a relative folder path + file name, with date resolution, night-owl rollback, counter sharing/advance, missing-metadata fallback, and path-component sanitization. Engine has no I/O. | 🟢 [scheme_engine.dart](pablo/lib/data/scheme_engine.dart) |
| FR-IA9-04 | The builder SHALL be **drag-and-drop**: tokens drag from a grouped palette into a folder level or the file-name lane; chips remove with ×; fixed text is typed inline; a token dropped on "add folder level" creates a new level. | 🟢 [features/organize/](pablo/lib/features/organize/) |
| FR-IA9-05 | Folder structure and file name SHALL be two visually distinct, separately-titled stages (DD-IA-F); the live preview SHALL reinforce this (folder path = muted tree, file name = highlighted azure leaf). | 🟢 [scheme_preview_tree.dart](pablo/lib/features/organize/scheme_preview_tree.dart) |
| FR-IA9-06 | A live preview SHALL render the resulting hierarchy from real sample photos (synthetic samples when the library is empty), recomputed on every edit. | 🟢 |
| FR-IA9-07 | Built-in presets (DIM recipes minus geo) SHALL be offered as one-tap starting templates. | 🟢 [scheme_presets.dart](pablo/lib/features/organize/scheme_presets.dart) |
| FR-IA9-08 | Schemes SHALL persist as JSON under the platform config dir using `dart:io` only (no new package dependency; per the no-new-deps rule). | 🟢 [scheme_store.dart](pablo/lib/data/scheme_store.dart) |
| FR-IA9-09 | Render-affecting options (date source, counter base, night-owl, filename case) SHALL be live; file-moving options (smart-copy, RAW pairing, verify, move, backup, suffix) SHALL be modeled and shown disabled until Phase B. | 🟢 |
| FR-IA9-10 | A scheme SHALL drive camera/SD ingest layout, bulk reorganize, and in-app drag-drop reorganize. | 📦 Phase B (needs file copy/move + PR #6) |

### 5b.2 Tests

- Engine golden cases (presets, night-owl, counter, sanitization, JSON round-trip): [scheme_engine_test.dart](pablo/test/scheme_engine_test.dart).
- Builder/preview widget checks (preview renders; two distinct stages present): [scheme_builder_widget_test.dart](pablo/test/scheme_builder_widget_test.dart).
- DnD drag-gesture and end-to-end filing are manual / Phase B.

---

## 6. Non-functional requirements

| ID | Category | Requirement | Target / measure |
|----|----------|-------------|------------------|
| NFR-IA-PERF-01 | Performance | Async scan SHALL keep the UI responsive (yield per directory entry); no main-isolate stall > 16 ms during scan. | Frame-time budget on dev dataset |
| NFR-IA-PERF-02 | Performance | Cold import throughput SHALL be ≥ ~1,000 files/sec for metadata cataloguing (stat + insert, no decode) on local SSD. | Bench on Flickr30k (~31k imgs) |
| NFR-IA-PERF-03 | Performance | Rescan of an unchanged root SHALL be **O(files changed)**, not O(files total) for the decode/metadata work; the disk walk itself is unavoidably O(files). | Re-run import → ~0 inserts, fast |
| NFR-IA-PERF-04 | Performance | Thumbnail decode of a typical JPEG SHALL use shrink-on-load (libvips `thumbnail`) rather than full decode. | No full-res buffer for thumbs |
| NFR-IA-PERF-05 | Performance | Per-asset face decode SHALL be pinned to a bounded worker pool and SHALL NOT starve the thumbnail workers (see commit 87cb8e8: scan pinned to one core; workers reserved for thumbnails). | Concurrency policy honored |
| NFR-IA-SCALE-01 | Scalability | The catalog SHALL handle ≥ 1,000,000 assets without schema redesign; queries by asset ID, folder, and timeline SHALL be index-backed. | Indices on `path`, `mtime`, FK cols |
| NFR-IA-SCALE-02 | Scalability | In-memory `Library` metadata footprint SHALL stay ≈ 1–2 KB/photo; for very large libraries the in-memory model is a known scaling limit to revisit (catalog-paged views). | ~31–62 MB at 31k |
| NFR-IA-REL-01 | Reliability | No single corrupt/unreadable/permission-denied file SHALL abort an import or rescan. | Negative tests below |
| NFR-IA-REL-02 | Durability | Catalog writes SHALL be transactional; a crash/kill mid-import SHALL leave a valid DB recoverable on next open (WAL or equivalent). | Kill-during-import test |
| NFR-IA-REL-03 | Reliability | Asset IDs SHALL be stable across restarts (the regression class that orphaned face data with `path.hashCode`). | Restart test |
| NFR-IA-PORT-01 | Portability | Format capability is libvips-build-dependent; the app SHALL detect available loaders at runtime and degrade gracefully where a loader is missing (Linux/Windows builds may lack HEIF/JXL). | Runtime probe + placeholder |
| NFR-IA-PORT-02 | Portability | Paths SHALL be handled as UTF-8 up to ≥ 4096 bytes; Unicode, spaces, and non-Latin scripts SHALL round-trip. | `path[4096]`, unicode tests |
| NFR-IA-SEC-01 | Security/Privacy | Import SHALL never transmit image data or metadata off-device; all processing is local. | No network in import path |
| NFR-IA-SEC-02 | Security | Decoders SHALL be treated as untrusted-input parsers; a malformed file SHALL not cause OOB/UAF (rely on libvips hardening + fuzz corpus). | Fuzz/corrupt corpus |
| NFR-IA-SEC-03 | Privacy | Apple Photos / SD ingest SHALL be read-only against the source (FR-IA6-02, FR-IA7-04). | Source-unmodified assertion |
| NFR-IA-OBS-01 | Observability | Import/rescan SHALL emit structured progress (scanned, added, updated, removed, skipped, errors) and per-file errors SHALL be logged with path + reason. | Activity task + log |
| NFR-IA-OBS-02 | Observability | Any silent skip (unsupported format, dedup drop, cache-dir skip) SHALL be counted and reportable — never silently absorbed. | Counters surfaced |
| NFR-IA-UX-01 | Usability | Import SHALL be cancellable; cancel SHALL leave a consistent catalog (assets imported so far are kept). | Cancel test |
| NFR-IA-I18N-01 | Robustness | Timeline bucketing SHALL handle missing, zero, and future `mtime`s without crashing (null → excluded from timeline). | mtime edge tests |

---

## 7. Test cases

Type key: **U** unit · **I** integration · **S** app smoke (manual/automated) · **M** manual.
Status: ✅ exists · 📦 PR #6 · ➕ to-write · 🚧 blocked on feature.

### 7.1 IA-1 Recursive folder scan

| TC | Title | Type | Pre | Steps | Expected | Traces | Status |
|----|-------|------|-----|-------|----------|--------|--------|
| TC-IA1-001 | Six formats accepted | U/I | Tree with one file of each: jpg, jpeg, png, webp, gif, bmp | `Library.scan(root)` | All 6 appear in `allPhotos`; count == 6 | FR-IA1-02 | ➕ |
| TC-IA1-002 | Non-image ignored | U/I | Tree with `.txt`, `.mp4`, `.pdf`, `.heic` (pre-IA-3) | scan | None of the non-accepted files imported; no error | FR-IA1-03 | ➕ |
| TC-IA1-003 | Case-insensitive ext | U/I | `IMG.JPG`, `pic.JpEg`, `x.PNG` | scan | All imported | FR-IA1-02 | ➕ |
| TC-IA1-004 | Recursion depth | I | Nested `a/b/c/d/photo.jpg` | scan | Deeply nested photo imported; folder tree reflects hierarchy | FR-IA1-01, FR-IA1-08 | ➕ |
| TC-IA1-005 | Symlinks not followed | I | Dir `real/` with photos; symlink `link → real/`; symlinked file | scan | Symlinked dir/file not traversed (no dupes via link) | FR-IA1-04 | ➕ |
| TC-IA1-006 | Missing root | U | Path does not exist | `Library.scan(bogus)` | Returns `Library.empty()`, no throw | FR-IA1-06 | ➕ |
| TC-IA1-007 | Empty root | U | Empty dir | scan | Empty library, no throw | FR-IA1-06 | ➕ |
| TC-IA1-008 | Permission-denied subdir | I | Subdir chmod 000 | scan | Scan completes, accessible photos imported, denied subtree skipped | FR-IA1-07, NFR-IA-REL-01 | ➕ |
| TC-IA1-009 | Unreadable file → null mtime | I | A file that stat fails on | scan | Photo present; `mtime == null`; excluded from timeline | FR-IA1-07, FR-IA1-09 | ➕ |
| TC-IA1-010 | Async yields | I | Large tree (10k synthetic) | `scanAsync` while pumping event loop | No main-isolate stall > 16 ms; all imported | FR-IA1-05, NFR-IA-PERF-01 | ➕ |
| TC-IA1-011 | File removed mid-scan | I | Delete a file during `scanAsync` | scan | Per-entry catch; scan completes without that file | FR-IA1-07, NFR-IA-REL-01 | ➕ |
| TC-IA1-012 | Unicode / spaces / long path | I | `Ô ô/写真 photo .jpg`, path near 4096 B | scan | Imported; path round-trips | NFR-IA-PORT-02 | ➕ |
| TC-IA1-013 | Future / zero mtime | U | Files with mtime=0 and mtime=year 2099 | scan | No crash; bucketed (or excluded) sanely | NFR-IA-I18N-01 | ➕ |
| TC-IA1-014 | Cache dirs skipped *(gap)* | I | Tree containing `.picasaoriginals/x.jpg`, `Thumbs.db` | scan | Cache dirs not imported as assets | FR-IA1-10 / FR-IA8-01 | 🚧 (IA-8) |

### 7.2 IA-2 Native import / rescan / stable IDs  *(run against PR #6)*

| TC | Title | Type | Pre | Steps | Expected | Traces | Status |
|----|-------|------|-----|-------|----------|--------|--------|
| TC-IA2-001 | Import inserts assets | U | Empty catalog, fixture folder | `photo_import_path` | One asset row per accepted file; returns count | FR-IA2-02 | 📦 `import_test.cpp` |
| TC-IA2-002 | Re-import idempotent | U | After TC-IA2-001 | import same root again | 0 new rows; same IDs | FR-IA2-04 | 📦 |
| TC-IA2-003 | rowid == asset id, stable | U | Imported catalog | Read IDs; close+reopen DB | IDs unchanged across reopen | FR-IA2-01, NFR-IA-REL-03 | 📦 |
| TC-IA2-004 | Faces survive restart | S | Import → face-scan → record persons | Restart app, no rescan | Faces/persons still linked to same assets | FR-IA2-08 | 📦 / smoke pending |
| TC-IA2-005 | Rescan detects new | U | Catalog, then add a file | `photo_rescan` | New file → 1 add; classified `new` | FR-IA2-03, FR-IA2-11 | 📦 |
| TC-IA2-006 | Rescan detects modified | U | Touch a file (size or mtime change) | rescan | File classified `modified` | FR-IA2-05, FR-IA2-11 | 📦 |
| TC-IA2-007 | Rescan detects missing (soft-delete) | U | Delete a catalogued file | rescan | Classified `missing`; row + asset ID retained; not hard-deleted | FR-IA2-12 (DD-IA-B) | ➕ |
| TC-IA2-008 | Unchanged rescan is cheap | I | Re-run on unchanged 31k root | rescan | ~0 inserts/updates; no decode work | FR-IA2-03, NFR-IA-PERF-03 | ➕ |
| TC-IA2-009 | path[4096] / long path | U | File with ~4090-byte path | import | Stored & retrievable intact | FR-IA2-06, NFR-IA-PORT-02 | ➕ |
| TC-IA2-010 | id↔path bridges agree | U | Imported asset | `path_for_asset(assetIdForPath(p)) == p` | Round-trip holds | FR-IA2-07 | 📦 |
| TC-IA2-011 | Crash-during-import durability | I | Kill process mid-import | Reopen catalog | DB valid; partial assets consistent; resumable | FR-IA2-09, NFR-IA-REL-02 | ➕ |
| TC-IA2-012 | Schema migration v→v+1 | U | Open an older-version DB fixture | open | Migrates forward; data intact | FR-IA2-10 | ➕ |
| TC-IA2-013 | Concurrent import serialized | I | Two import calls racing | both | No corruption; mutex-serialized; no dup rows | FR-IA2-09 | ➕ |
| TC-IA2-014 | External move re-links ID | I | Catalogued file with album+tag+face; move it to a sibling dir in Finder | rescan | Classified `moved`; **same asset ID** now at new path; album/tag/face links intact; no new row | FR-IA2-13, FR-IA2-15 (DD-IA-C) | ➕ |
| TC-IA2-015 | In-app move relocates file | S | Catalogued asset shown in folder A | Drag asset to folder B in Pablo | File physically moved A→B on disk; asset ID unchanged; folder view shows it under B | FR-IA2-14 (DD-IA-C) | ➕ |
| TC-IA2-016 | Move affects folder view only | I | Asset in an album + timeline bucket + tagged | Move it (in-app or external) | Album membership, timeline position, tags, star/rating, faces all unchanged; only folder path differs | FR-IA2-15 (DD-IA-C) | ➕ |
| TC-IA2-017 | Duplicate ≠ move | I | Present file X; add byte-identical copy Y in another dir | rescan | Y is a `new` asset flagged duplicate (IA-4); X is NOT relocated/re-linked | FR-IA2-16 | ➕ |
| TC-IA2-018 | content_hash stored & indexed | U | Import fixtures | inspect catalog | Each asset has a `content_hash`; lookup by hash is index-backed | FR-IA2-06 (DD-IA-A) | ➕ |
| TC-IA2-019 | Soft-deleted resurrection | I | Delete file (→`missing`), then restore identical bytes at a new path | rescan | Soft-deleted row resurrected with same ID at new path (move re-link), not a fresh row | FR-IA2-12, FR-IA2-13 | ➕ |
| TC-IA2-020 | Move+edit → old missing, new as New | I | Catalogued photo in an album with a face; move it AND re-compress (bytes change) in one rescan window | rescan | No re-link; original classified `missing` and no longer shows in the album; edited file imports as a new asset (new ID, no album/face) | FR-IA2-17 (DD-IA-D) | ➕ |
| TC-IA2-021 | Burst move+edit, no guessing | I | Two burst frames (same `DateTimeOriginal`) moved + re-compressed | rescan | Both originals → `missing` (drop out of albums); both edited files → new assets; no prompt; no mis-attached curation | FR-IA2-17 | ➕ |
| TC-IA2-022 | Missing asset hidden, rows retained | I | Catalogued asset in an album goes `missing` | rescan; inspect | Asset not shown in album/grid/timeline; its membership + tag rows still exist; restoring exact bytes re-links it and it reappears in the album | FR-IA2-18 | ➕ |
| TC-IA2-023 | Edit-in-place refreshes derived data | I | Overwrite a catalogued file's bytes at the **same path**; it had faces + thumbnail | rescan | Classified `modified`; ID retained; `content_rev` bumped → thumbnail + faces regenerate; album/tag links persist | FR-IA2-19 | ➕ |

### 7.3 IA-3 Broader formats

| TC | Title | Type | Pre | Steps | Expected | Traces | Status |
|----|-------|------|-----|-------|----------|--------|--------|
| TC-IA3-000 | Loader capability probe | U | Linked libvips | Query supported loaders | Test logs supported set; gates the cases below | NFR-IA-PORT-01 | ➕ |
| TC-IA3-001 | TIFF decode | U/I | Fixture `.tif` | `decode_bgr` + thumbnail | Correct dims & pixels both paths | FR-IA3-01, FR-IA3-03 | 📦 (fixture check) |
| TC-IA3-002 | HEIC decode | U/I | Fixture `.heic` | decode | Correct; **skip-with-reason** if no HEIF loader | FR-IA3-02 | 📦 |
| TC-IA3-003 | JXL decode | U/I | Fixture `.jxl` | decode | Correct; skip-with-reason if no JXL loader | FR-IA3-02 | ➕ |
| TC-IA3-004 | RAW (DNG/CR2) full-develop | U/I | Fixture `.dng` | decode | Develops to image (not embedded preview) | FR-IA3-04 | ➕ |
| TC-IA3-005 | Orientation normalized | U/I | EXIF-rotated JPEG + HEIC | decode | Output upright; matches EXIF orientation | FR-IA3-07 | ➕ |
| TC-IA3-006 | Thumb path == faces path | I | Any asset | Compare thumbnail-source vs `decode_bgr` | Equivalent pixels | FR-IA3-03 | ➕ |
| TC-IA3-007 | Corrupt/truncated of each fmt | U | Truncated jpg/heic/tiff/jxl | decode | Returns null/empty; no crash; vips error cleared; placeholder | FR-IA3-08, NFR-IA-SEC-02 | ➕ |
| TC-IA3-008 | Unsupported-by-build graceful | I | `.jxl` on a no-JXL build | import + view | Asset catalogued; decode logs error; placeholder shown; import not aborted | FR-IA3-06, NFR-IA-OBS-02 | ➕ |
| TC-IA3-009 | Scan set widened | U/I | Tree with tif/heic/jxl/dng | scan | Imported once IA-3 wired (else documented gap) | FR-IA3-05 | 🚧 |

### 7.4 IA-4 Import-time dedup

| TC | Title | Type | Pre | Steps | Expected | Traces | Status |
|----|-------|------|-----|-------|----------|--------|--------|
| TC-IA4-001 | Exact duplicate detected (content_hash) | U/I | Two byte-identical files, different paths | import | Same `content_hash` → one duplicate group; both files retained on disk | FR-IA4-01, FR-IA4-03 | 🚧 |
| TC-IA4-001b | Hash collision sanity | U | Different content | import | Distinct `content_hash`; not grouped | FR-IA4-01 | 🚧 |
| TC-IA4-002 | Near-duplicate detected | I | Original + resized re-encode | import + embed | Flagged near-dup above threshold | FR-IA4-02 | 🚧 |
| TC-IA4-003 | Non-dup not grouped | I | Two unrelated photos | import | No false-positive group | FR-IA4-02 | 🚧 |
| TC-IA4-004 | Dedup never deletes | I | Duplicate group | run dedup, no user action | No file deleted; no asset hard-removed | FR-IA4-03 | 🚧 |
| TC-IA4-005 | Dedup off the import critical path | I | Large import | measure | First-time import completes without waiting on embeddings | FR-IA4-04, NFR-IA-PERF-02 | 🚧 |
| TC-IA4-006 | Index rebuildable | U | Delete dedup index | rebuild from catalog | Index regenerates; catalog unaffected | FR-IA4-06 | 🚧 |

### 7.5 IA-5/6/7/8 Not-started (placeholder suites, 🚧 blocked on feature)

| TC | Title | Type | Expected (when built) | Traces |
|----|-------|------|------------------------|--------|
| TC-IA5-001 | Hot-folder add triggers rescan | I | Dropping a file into a watched root catalogs it without manual rescan | FR-IA5-01 |
| TC-IA5-002 | Bulk drop debounced | I | 500 files dropped → one coalesced rescan | FR-IA5-02 |
| TC-IA5-003 | Watched root offline | I | Disconnect volume → assets marked unavailable, not purged | FR-IA5-04 |
| TC-IA6-001 | SD ingest copies, card untouched | I | Ingest copies to dest; card files unchanged | FR-IA6-02, NFR-IA-SEC-03 |
| TC-IA6-002 | Re-insert card skips existing | I | Second ingest of same card copies 0 new | FR-IA6-03 |
| TC-IA7-001 | Photos import maps metadata | I | Albums→albums, keywords→tags, favorites→starred; source unmodified | FR-IA7-01..04, NFR-IA-SEC-03 |
| TC-IA7-002 | Photos import idempotent | I | Re-run → no duplicate assets | FR-IA7-03 |
| TC-IA8-001 | `.picasaoriginals` skipped as assets | I | Cache dir not imported as photos | FR-IA8-01 |
| TC-IA8-002 | Original/edit pairing | I | `.picasaoriginals/X` recognized as master of sibling `X` | FR-IA8-02 |
| TC-IA8-003 | `.picasa.ini` read (opt-in) | I | Stars/captions imported; no write-back unless enabled | FR-IA8-03 |

---

## 8. Traceability summary

- **Shipped & directly testable today:** FR-IA1-01..09 (Dart scan).
- **Ready to test on PR #6 merge:** FR-IA2-* (catalog/import/rescan/IDs), FR-IA3-01..04,07,08 (codec).
- **Needs feature work before tests run:** FR-IA1-10 / IA-8, IA-4 integration, IA-5/6/7.
- **Cross-cutting NFRs to bench once IA-2/IA-3 land:** NFR-IA-PERF-02/03, NFR-IA-SCALE-01, NFR-IA-REL-02/03.

### Priority gaps (recommended order)
1. Land PR #6 → unblocks the largest test block (IA-2, IA-3) and the stable-ID durability guarantees.
2. Add `content_hash` to the catalog schema + import read pass (DD-IA-A) — it's the shared primitive that unblocks both dedup (IA-4) and move-identity (FR-IA2-13).
3. Implement move/modify reconciliation in rescan: `missing` + `new` same hash → `moved`, re-link ID (DD-IA-C); in-app move = relocate file + update path in place; same-path changed-bytes → `modified` + `content_rev` bump (FR-IA2-19). Byte-changed + moved files are **not** re-linked (DD-IA-D) — old → `missing` (hidden from albums), new → new asset.
4. Ensure views filter `missing`/unavailable assets out of albums/grid/timeline while retaining their rows (FR-IA2-18).
5. Widen the scan extension set (FR-IA3-05) so IA-3 codec capability is actually reachable from import.
6. Cache-dir skip (FR-IA8-01) — cheap, prevents importing Picasa/Windows cache junk as photos.
7. Integrate `feat/dedup-integration` (near-dup, IA-4) on top of the now-defined exact primitive.

> Decisions DD-IA-A/B/C should be copied into `docs/DECISIONS.md` (they touch the locked catalog/identity model).
