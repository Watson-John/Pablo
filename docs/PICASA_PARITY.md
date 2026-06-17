# Picasa → Pablo parity checklist

A detailed, hierarchical map of **Picasa 3** features and where **Pablo** stands against each one.
It doubles as a sequencing roadmap. Source material: the reverse-engineering corpus of
`Picasa3.exe` (`/Users/johnwatson/picasa_app_re/` — `raw/meta_*.json`, `recovered/*.cpp`,
`raw/briefing.md`) cross-referenced against a survey of this repo (`pablo-v4` + the
`feat/dedup-integration` worktree).

**Scope:** "Core modern DAM" — local photo management, organization, editing, faces, search, and
viewing. Picasa's dead Google-cloud, optical-media, screensaver, and scanner features are recorded
in the *Out of scope / obsolete* appendix, not treated as parity targets.

_Last verified against the tree: 2026-06-16 (`pablo-v4`)._ Treat this as a living document.

## Legend

| Status | Meaning |
|--------|---------|
| ✅ | done |
| 🔄 | in progress (on a branch) |
| ◐ | partial / UI-only / no persistence |
| ❌ | missing |

**Priority:** `P0` = required to be a credible Picasa replacement · `P1` = important parity ·
`P2` = long-tail / nice-to-have. A checkbox is ticked only when the status is ✅.
`(Picasa: …)` cites RE evidence (function `0xADDR` / string / area) for traceability.

---

## 1. Import & acquisition

- [x] **Recursive folder/file scan** — ✅ P0 — filesystem walk, recursive
  (Picasa: `CIndexer_DirEnumerateOnce 0x004e62d0`, `CIndexer_ScanTree 0x004e7d10`;
  Pablo: `pablo/lib/data/library.dart`)
- [ ] **Watched folders / auto-import (hot folders)** — ❌ P1 — monitor folders for new/changed
  files (Picasa: `FolderMgr_*Watched* 0x004f5a30 / 0x004f5960 / 0x004efde0`, `watchedfolders.txt`,
  `FindFirstChangeNotificationW`)
- [ ] **Broader format support** — ◐ P1 — Pablo decodes jpg/png/webp/gif/bmp; **add TIFF, PSD,
  HEIF/HEIC, JXL** and finish RAW (see §6) (Picasa: `CAcquire_BuildSupportedExtensionFilter
  0x00520220`; Pablo: libvips/LibRaw/libheif/libjxl already linked in `native/core/src/image/`)
- [ ] **Camera / SD-card / device ingest** — ❌ P1 — copy-from-device flow with dedup-on-copy
  (Picasa: AutoRun / `IQueryCancelAutoPlay`, `CImportFromGPDialog`)
- [ ] **Import-time duplicate detection** — 🔄 P1 — flag/skip dupes during import
  (Pablo: `feat/dedup-integration` worktree, `lib/features/find_duplicates/` + FAISS native)
- [ ] **Import from other libraries (iPhoto / Apple Photos)** — ❌ P2
  (Picasa: `CImportIPhoto`, `iPhotoXML`)
- [ ] **`.picasaoriginals` / sidecar-aware import** — ❌ P2 — recognize Picasa edit-backup folders
  for migration (Picasa: `.picasaoriginals 0x00c818f0`)

## 2. Library & catalog

- [ ] **Persistent catalog DB** — ◐ P0 — SQLite + LMDB exist but library state is in-memory in v1;
  make the catalog durable + incremental (Picasa: PMP column store `CBlockFile`, `#db3\`;
  Pablo: `pablo/lib/backend/native_backend.dart`, `catalog.db`)
- [x] **Folders view (on-disk hierarchy)** — ✅ P0 (Pablo: `pablo/lib/features/sidebar/folder_group.dart`)
- [ ] **Albums (user-created virtual collections)** — ❌ P0 — **largest single org gap**; album CRUD,
  manual add/remove, cover, ordering (Picasa: `CAlbum*`, `]album*` sidecar keys;
  Pablo: placeholder "No albums yet … coming soon" in `pablo/lib/features/gallery/main_grid.dart:52`)
- [ ] **Smart / auto collections** — ◐ P1 — e.g. Recently Updated, People, Starred set
  (Picasa: seeded groups in `createMainWindowAndShow 0x00402f90`)
- [ ] **Change detection / incremental rescan** — ◐ P1 — re-index only changed folders/files
  (Picasa: `CIndexer__Load/SaveThumbIndex`, per-file mtime/size/state)
- [ ] **Hide folders / hide images** — ❌ P1 (Picasa: `]hidden`, Hidden Folders group)
- [ ] **DB maintenance (compaction)** — ❌ P2 (Picasa: `HashBlockFile_Compact 0x006b9470`)
- [ ] **Move / relocate library** — ❌ P2 (Picasa: `AppLocalDataPath` move, `settings_MaybeMoveDatabase`)

## 3. Thumbnails & rendering pipeline

- [x] **Multi-level thumbnail cache (mip pyramid)** — ✅ P0 — 32 / 256 / full stages
  (Picasa: thumbs/thumbs2/bigthumbs/previews `.db`; Pablo: `native/core/src/thumb/`)
- [x] **Disk thumbnail cache** — ✅ P0 — LMDB JPEG blobs
- [x] **Background resampling workers** — ✅ P0 (Picasa: `ResampleThread__Run 0x0045c300`,
  `BackgroundResampler`; Pablo: native job system + event ring)
- [x] **GPU texture upload / fit-render** — ✅ P0 (Pablo: `pablo/lib/gallery/native_asset_texture.dart`)
- [ ] **Speculative prefetch of nearby cells** — ◐ P1 (Picasa: `ThumbGrid__TriggerPrefetch 0x0057eff0`)
- [ ] **Caption / badge overlay on thumbnails** — ❌ P2 (Picasa: `textactive`, `ytSkiaTextRender`)

## 4. View & browse

- [x] **Grid / masonry view** — ✅ P0 (Pablo: `pablo/lib/features/gallery/section_scroll_view.dart`)
- [x] **Thumbnail-size slider** — ✅ P0 (Pablo: controls bar thumb slider)
- [x] **Lightbox / single-photo view + filmstrip** — ✅ P0 (Pablo: `pablo/lib/features/gallery/lightbox_view.dart`)
- [x] **Timeline view (group by date)** — ✅ P1 (Pablo: `pablo/lib/features/sidebar/timeline_tree_node.dart`)
- [x] **Photo tray / holding basket (cross-folder selection)** — ✅ P1 (Pablo: `pablo/lib/features/photo_tray/`)
- [ ] **Fullscreen / presentation mode** — ◐ P1 — confirm dedicated fullscreen beyond lightbox
- [ ] **Sort options (name / date / size / rating)** — ◐ P1
- [ ] **Compare / side-by-side view** — ❌ P2

## 5. Organize & metadata

- [x] **Star / favorite** — ✅ P0 (Picasa: `PWAStarred 0x00c7e194`; Pablo: star action in controls bar)
- [ ] **Captions** — ◐ P0 — surface + edit + persist (Picasa: `caption`; Pablo: info panel read,
  edit mode `info_panel/manage_details.dart` — verify write path)
- [ ] **Keywords / tags** — ◐ P0 — in-app tags exist; ensure CRUD + persistence
  (Picasa: `keywords 0x00c81848`; Pablo: `pablo/lib/features/info_panel/tags_tab.dart`)
- [ ] **Numeric rating (beyond binary star)** — ◐ P1 (Picasa: `rating 0x00c81448`)
- [ ] **Color labels** — ❌ P2 (Picasa: `color:red … gray` set)
- [x] **EXIF / IPTC / XMP read** — ✅ P0 (Picasa: `MetadataField_NameToId 0x00633210`, ~335 fields;
  Pablo: `native/core/src/metadata/`)
- [ ] **Metadata write-back to file / sidecar** — ❌ P0 — Picasa wrote `.picasa.ini` **and** XMP;
  Pablo is read-only in v1 (DECISIONS D1, post-v1). Needed for round-trip / interop.
- [ ] **`.picasa.ini` interop (read + write Picasa sidecars)** — ❌ P1 — direct migration win; the full
  schema is recovered in `picasa_app_re/recovered/picasa_ini.cpp` (per-image keys + `]`-folder sections)
- [ ] **Batch metadata edit (tag / caption / star many at once)** — ❌ P1
- [ ] **Rename / batch rename** — ❌ P1 (Picasa: `CRenameDialog`)
- [ ] **File ops: copy / move / delete (functional)** — ◐ P0 — context-menu items exist but handlers
  are stubs (Pablo: `pablo/lib/components/context_menu.dart`)
- [ ] **Adjust date / time** — ❌ P2

## 6. Editing (non-destructive)

> Pablo's editor panel (`pablo/lib/features/editor/`) ships tool buttons for Crop, Straighten,
> Rotate L/R, Flip H/V, Heal, Red Eye (`tools_grid.dart`) plus 12 filter presets and Light/Color/
> Detail sliders — but they apply as **live preview only** with no persisted edit stack or
> write-back in v1. Hence most items below are ◐ (UI present) rather than ❌.

- [ ] **Non-destructive edit stack + persistence + revert-to-original** — ❌ P0 — the core editing gap:
  no saved stack today (Picasa: `filters=` edit-stack grammar, `glimmer::EffectParser 0x00bb31f0`,
  `backuphash`, `.picasaoriginals`)
- [ ] **Crop (+ aspect presets, crop-to-fit)** — ◐ P0 — tool button present, not yet functional/persisted
  (Picasa: `crop=`, `rect64(`, `croptofit`)
- [ ] **Straighten / rotate-by-angle** — ◐ P0 — tool button present, not yet functional
- [ ] **Rotate 90° + flip (lossless, persisted)** — ◐ P0 — Rotate L/R + Flip H/V buttons present, not persisted
  (Picasa: `rotate(%d)`, `flipped(%d)`)
- [ ] **Tuning: fill light, highlights, shadows, color temp, exposure** — ◐ P0 — Pablo has Light/Color/
  Detail sliders; add Picasa's full tuning set (Picasa: `Exposure / LocalContrast / ColorMatrix` ops)
- [ ] **One-click auto-fix ("I'm Feeling Lucky" / auto color / auto contrast)** — ❌ P1
  (Picasa: `enhance`, `autocolor`, `autolight`, `icnik=1;`, `AutoFixImageOperation`)
- [ ] **Red-eye removal** — ◐ P1 — 'Red Eye' tool button present, not yet functional
  (Picasa: `RedEyeEdit 0x00d41058`, `edeye=1;`)
- [ ] **Retouch / heal** — ◐ P1 — 'Heal' tool button present, not yet functional
  (Picasa: `RetouchEdit` / `CRetouchFilter`, Poisson blend)
- [ ] **Effects / filter library** — ◐ P1 — Pablo ships 12 presets; Picasa had ~40 ops (B&W, sepia,
  sharpen, blur, radial blur, glow, tint, gradient map, local contrast, border, edge, noise, pixelate,
  resaturate, …) (Picasa: `imageOperations:*`; Pablo: `editor/filter_matrices.dart`)
- [ ] **Curves** — ❌ P2 (Picasa: `AdjustCurvesImageOperation`)
- [ ] **Text overlay on photo** — ❌ P2 (Picasa: `textactive`)
- [ ] **Regional / mask edits + blend modes** — ❌ P2 (Picasa: `MaskInstruction`, `BlendInstruction`)
- [ ] **Batch edits across selection** — ❌ P1
- [ ] **Edit-backup of originals (safety) + revert** — ❌ P1 (Picasa: `.picasaoriginals`)

## 7. Faces & people

- [x] **Face detection** — ✅ P0 (Picasa: Neven Vision; Pablo: SCRFD-10g, `native/core/src/faces/`)
- [x] **Face recognition / embeddings** — ✅ P0 (Pablo: AuraFace 512-d)
- [x] **Clustering / grouping suggestions** — ✅ P0 (Picasa: HOG clustering; Pablo: agglomerative)
- [x] **Name tagging + People albums** — ✅ P0 (Pablo: `pablo/lib/features/people/face_naming.dart`)
- [x] **Confirm / reject suggestions** — ✅ P0 (Pablo: `people/decision_buttons.dart`)
- [x] **Face data persisted (catalog)** — ✅ P0 (Pablo: `data/sources/face_repository.dart`)
- [ ] **Ignore-face / unknown-face handling** — ◐ P1 (Picasa: `]ignoreface`, `]unknownface`, `<Unknown Person>`)
- [ ] **Manual face rectangle add / adjust** — ❌ P1
- [ ] **Write face tags to file metadata (XMP regions) / `.picasa.ini` interop** — ❌ P1
  (Picasa: `ThumbDB_WriteFaceTagsToImageFile 0x004852e0`, XMP IPTC-ext Regions)

## 8. Places & geo

- [ ] **Map view of geotagged photos** — ◐ P1 — Pablo has a USA-only heat map; needs a real world map +
  clustering (Picasa: `GeoPanel`, `EarthController`; Pablo: `pablo/lib/features/map/`)
- [x] **Read GPS from EXIF** — ✅ P1
- [ ] **Manual geotag (drag onto map)** — ❌ P2 (Picasa: `CGeoLocateDialog`, `CGeoTagAdornerEnable`)
- [ ] **Reverse-geocode to place names** — ❌ P2
- [ ] **KML / KMZ export** — ❌ P2 (Picasa: `CBackgroundKmzWriter`)

## 9. Search & discovery

- [x] **Text / multi-criteria search** — ✅ P0 — date, content, people, camera/EXIF, tags
  (Pablo: `pablo/lib/features/search/advanced_search_modal.dart`)
- [x] **Filter by person** — ✅ P1
- [ ] **Saved searches / smart albums** — ❌ P1 (Picasa: `]search` virtual folders)
- [ ] **Filter by star / rating** — ◐ P1
- [ ] **Filter by place** — ◐ P2
- [ ] **Search-by-color** — ❌ P2 (Picasa shipped this; `avgcolor` per image)

## 10. Create / output (core)

- [ ] **Export (resize / quality / watermark to folder)** — ❌ P0 (Picasa: `CExportPrefsDialog`)
- [ ] **Slideshow** — ❌ P1 (Picasa: `CDXSlideshowFilter`)
- [ ] **Print (layouts / contact sheet / poster)** — ❌ P1 (Picasa: `CPrintDlg`, `Layout3x4 … Wallet`, `CPosterDlg`)
- [ ] **Share sheet (OS share / generic targets)** — ❌ P1 — modern replacement for Picasa email/upload
- [ ] **Collage / picture pile** — ❌ P2 (Picasa: `CCollageUI`)
- [ ] **Movie / video creation** — ❌ P2 (Picasa: `MakeMoviePanel`)

## 11. Video / movies

- [ ] **Video files in the library** — ❌ P1 (Picasa: AVI/MOV/MP4/MKV/WMV/… filter)
- [ ] **In-app video playback** — ❌ P1 (Picasa: `ytDSMovie` DirectShow)
- [ ] **Trim (start / end points)** — ❌ P2 (Picasa: `moviestart=` / `movieend=`)

## 12. App shell & UX

- [x] **Window chrome (title / menu / status bars)** — ✅ P0 (Pablo: `pablo/lib/layouts/`)
- [x] **Sidebar nav (folders / albums / people / places)** — ✅ P0
- [x] **Info panel** — ✅ P0 (Pablo: `pablo/lib/features/info_panel/`)
- [x] **Activity / progress indicators** — ✅ P1 (Pablo: `search/activity_indicator.dart`)
- [ ] **Context menus wired to real actions** — ◐ P0 — UI present, handlers are no-ops
- [ ] **Functional menu bar (File / Edit / View / Tools …)** — ◐ P1 — present but no-op in v1
- [ ] **Keyboard shortcuts / accelerators** — ◐ P1 (Picasa: `TranslateAccelerator` set)
- [ ] **Drag & drop (to albums / tray / out to OS)** — ❌ P1
- [ ] **Global undo / redo** — ❌ P1
- [ ] **Persistent settings / preferences UI** — ◐ P1 — Pablo config is boot-flag only
  (Picasa: `COptionsDialog`, registry `Preferences\*`)
- [ ] **Notifications / toasts** — ❌ P2 (Picasa: `CNotifierWin`)
- [ ] **Single-instance + file associations + shell/Finder integration** — ❌ P2
- [ ] **Localization / i18n** — ❌ P2 (Picasa: `i18n\stringres.xml`)
- [ ] **Color management (ICC)** — ❌ P2 (Picasa: `EnableColorManagement`)

---

## Top parity gaps (executive summary)

P0 work that most defines a "Picasa replacement," roughly in dependency order:

1. **Durable catalog** (§2.1) — make the library / state persistent & incremental.
2. **Albums** (§2.3) — the headline missing organize feature.
3. **Metadata write-back + `.picasa.ini` interop** (§5.7 / §5.8) — round-trip tags / captions / edits;
   unlocks Picasa migration (schema already recovered in `picasa_app_re/recovered/picasa_ini.cpp`).
4. **Real non-destructive editor** (§6.1–§6.5, §6.8) — wire up the existing tool buttons to a
   persisted edit stack: crop, straighten, rotate/flip, tuning, revert.
5. **Export** (§10.1) and **functional file ops / context menus** (§5.12 / §12.4).

Faces, thumbnails/rendering, browse, timeline, tray, and search are already at or near parity.

---

## Appendix — Out of scope / obsolete

Recorded for completeness; **not** parity targets (they target discontinued services or legacy
desktop paradigms). Revisit only if Pablo grows its own cloud/account system.

- **PicasaWeb / Google Photos sync** ("Lighthouse", GData/Atom) — service discontinued.
- **Google+ / Buzz posting, YouTube upload, collaborative web albums** — dead.
- **Google OAuth2 identity / Gaia** — only relevant if Pablo adds its own accounts.
- **Omaha auto-update, usage-stats telemetry, crash reporting** — replace with Pablo's own infra.
- **Gift CD / DVD authoring & burning** (`CBurnPanel`, `CDVDHtmlAlbum`).
- **Windows screensaver** (`Google Photos Screensaver`).
- **Hello** (legacy peer-to-peer photo sharing).
- **TWAIN / WIA scanner acquisition.**
- **Scrapture screen capture; FTP sync; LAN share; embedded IE/ActiveX web UI.**

---

## Sources

- **RE corpus:** `/Users/johnwatson/picasa_app_re/raw/meta_*.json`, `recovered/*.cpp`,
  `raw/briefing.md` (incl. the recovered `recovered/picasa_ini.cpp` / `raw/meta_picasa_ini.json`).
- **Pablo survey:** `pablo-v4` (`pablo/lib/features/*`, `native/core/src/*`, `docs/DECISIONS.md`,
  `pablo/CLAUDE.md`) and the `feat/dedup-integration` worktree.
