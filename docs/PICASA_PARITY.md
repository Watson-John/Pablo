# Picasa → Pablo parity checklist

A detailed, hierarchical map of **Picasa 3** features and where **Pablo** stands against each one.
It doubles as a sequencing roadmap. Source material: the reverse-engineering corpus of
`Picasa3.exe` (`/Users/johnwatson/picasa_app_re/` — `raw/meta_*.json`, `recovered/*.cpp`,
`raw/briefing.md`) cross-referenced against a survey of this repo (`pablo/lib/features/*`,
`native/core/src/*`, `native/core/tests/*`, `docs/DECISIONS.md`).

**Scope:** "Core modern DAM" — local photo management, organization, editing, faces, search, and
viewing. Picasa's dead Google-cloud, optical-media, screensaver, and scanner features are recorded
in the *Out of scope / obsolete* appendix, not treated as parity targets.

_Last verified against the tree: 2026-07-03 (`CC/jovial-solomon-487861` worktree; SQLite catalog
at schema v10)._ Treat this as a living document.

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

- [x] **Recursive folder/file scan** — ✅ P0 — native import walk + serialized rescan jobs
  (Picasa: `CIndexer_DirEnumerateOnce 0x004e62d0`, `CIndexer_ScanTree 0x004e7d10`;
  Pablo: `photo_import_path` / `photo_rescan`, `native/core/src/runtime/engine.cpp`)
- [ ] **Watched folders / auto-import (hot folders)** — ❌ P1 — monitor folders for new/changed
  files (Picasa: `FolderMgr_*Watched* 0x004f5a30 / 0x004f5960 / 0x004efde0`, `watchedfolders.txt`,
  `FindFirstChangeNotificationW`)
- [ ] **Broader format support** — ◐ P1 — the codec layer is unified on libvips and is
  decode-capable for TIFF/HEIC/AVIF/RAW/JXL (`native/core/src/codec/codec.h`), but the import walk
  still only admits .jpg/.jpeg/.png/.webp/.gif/.bmp (`image_exts()` in `runtime/engine.cpp`) —
  TIFF, PSD, HEIF/HEIC, JXL and RAW are not yet importable (Picasa:
  `CAcquire_BuildSupportedExtensionFilter 0x00520220`)
- [ ] **Camera / SD-card / device ingest** — ❌ P1 — copy-from-device flow with dedup-on-copy;
  File → Import From… is still a menu stub (Picasa: AutoRun / `IQueryCancelAutoPlay`,
  `CImportFromGPDialog`)
- [ ] **Import-time duplicate detection** — ◐ P1 — post-import Find Duplicates shipped: exact
  (content hash) + real visually-similar (pairwise semantic cosine, `photo_dedup_similar`)
  (Pablo: `pablo/lib/features/find_duplicates/`, Tools → Find Duplicates…); no flag/skip during
  the import walk itself
- [ ] **Import from other libraries (iPhoto / Apple Photos)** — ❌ P2
  (Picasa: `CImportIPhoto`, `iPhotoXML`)
- [ ] **`.picasaoriginals` / sidecar-aware import** — ◐ P2 — the import walk now recognizes and
  skips dot-directories (`.picasaoriginals` / `.pablo-originals` are never imported as assets —
  `runtime/engine.cpp`); migration/restore from their contents still missing
  (Picasa: `.picasaoriginals 0x00c818f0`)

## 2. Library & catalog

- [x] **Persistent catalog DB** — ✅ P0 — durable SQLite catalog with versioned additive
  migrations (v10: assets, EXIF, albums, tags, hidden, embeddings, saved searches, geo overrides,
  edit specs, video trim, analyzer results) + incremental rescan (Picasa: PMP column store
  `CBlockFile`, `#db3\`; Pablo: `native/core/src/catalog/catalog.cpp`; `catalog_test.cpp`)
- [x] **Folders view (on-disk hierarchy)** — ✅ P0 (Pablo: `pablo/lib/features/sidebar/folder_group.dart`)
- [x] **Albums (user-created virtual collections)** — ✅ P0 — album CRUD, manual add/remove, cover,
  member ordering (catalog v4 `album`/`album_member`, `photo_album_*` C API; sidebar Albums
  section + Add-to-Album / Set-as-Cover / Remove-from-Album context-menu items; `album_test.cpp`)
  (Picasa: `CAlbum*`, `]album*` sidecar keys)
- [x] **Smart / auto collections** — ✅ P1 — seeded All / Recently Added / Starred virtual views
  (`photo_smart_recent` / `photo_smart_starred`, sidebar `smart:*` rows; `smart_test.cpp`)
  (Picasa: seeded groups in `createMainWindowAndShow 0x00402f90`)
- [x] **Change detection / incremental rescan** — ✅ P1 — rescan diffs size+mtime and skips
  unchanged files, prunes removed ones (`photo_rescan`, `runtime/engine.cpp`; `import_test.cpp`)
  (Picasa: `CIndexer__Load/SaveThumbIndex`, per-file mtime/size/state)
- [x] **Hide folders / hide images** — ✅ P1 — `photo_asset_set_hidden` + persisted
  `hidden_folder` sweep (survives rescan); Hide/Unhide in the context menu, View → Show Hidden
  Photos (`hidden_test.cpp`) (Picasa: `]hidden`, Hidden Folders group)
- [x] **DB maintenance (compaction)** — ✅ P2 — async catalog compaction via Tools → Compact
  Database (`CatalogMaintenance.compact`, maintenance C API; `compact_test.cpp`)
  (Picasa: `HashBlockFile_Compact 0x006b9470`)
- [x] **Move / relocate library** — ✅ P2 — Tools → Relocate Library…: native path rebase that
  preserves asset ids so faces/albums/tags survive (`LibraryLocation.relocate`, relocate C API;
  `rebase_test.cpp`) (Picasa: `AppLocalDataPath` move, `settings_MaybeMoveDatabase`)

## 3. Thumbnails & rendering pipeline

- [x] **Multi-level thumbnail cache (mip pyramid)** — ✅ P0 — 32 / 256 / full stages
  (Picasa: thumbs/thumbs2/bigthumbs/previews `.db`; Pablo: `native/core/src/thumb/`)
- [x] **Disk thumbnail cache** — ✅ P0 — LMDB JPEG blobs
- [x] **Background resampling workers** — ✅ P0 (Picasa: `ResampleThread__Run 0x0045c300`,
  `BackgroundResampler`; Pablo: native job system + event ring)
- [x] **GPU texture upload / fit-render** — ✅ P0 (Pablo: `pablo/lib/gallery/native_asset_texture.dart`)
- [x] **Speculative prefetch of nearby cells** — ✅ P1 — neighbour cells warmed on scroll
  (Picasa: `ThumbGrid__TriggerPrefetch 0x0057eff0`; Pablo: `backend/prefetch_controller.dart`
  wired from `gallery/section_scroll_view.dart`)
- [x] **Caption / badge overlay on thumbnails** — ✅ P2 — star + "edited" badges, caption band,
  video duration/play badges (Picasa: `textactive`, `ytSkiaTextRender`;
  Pablo: `gallery/photo_thumb.dart`)

## 4. View & browse

- [x] **Grid / masonry view** — ✅ P0 (Pablo: `pablo/lib/features/gallery/section_scroll_view.dart`)
- [x] **Thumbnail-size slider** — ✅ P0 (Pablo: controls bar thumb slider)
- [x] **Lightbox / single-photo view + filmstrip** — ✅ P0 (Pablo: `pablo/lib/features/gallery/lightbox_view.dart`)
- [x] **Timeline view (group by date)** — ✅ P1 (Pablo: `pablo/lib/features/sidebar/timeline_tree_node.dart`)
- [x] **Photo tray / holding basket (cross-folder selection)** — ✅ P1 (Pablo: `pablo/lib/features/photo_tray/`)
- [x] **Fullscreen / presentation mode** — ✅ P1 — lightbox fullscreen toggle
  (`app_state.toggleLightboxFullscreen`) + the fullscreen slideshow (§10)
- [x] **Sort options (name / date / size / rating)** — ✅ P1 — View → Sort Photos: Name / Date /
  Size / Rating + Reverse Order; folder sort Tree / Alphabetical (`app/app_state.dart`,
  `layouts/menu_bar.dart`)
- [x] **Compare / side-by-side view** — ✅ P2 — 2-up side-by-side of the selection/tray
  (Pablo: `gallery/compare_view.dart`)

## 5. Organize & metadata

- [x] **Star / favorite** — ✅ P0 (Picasa: `PWAStarred 0x00c7e194`; Pablo: star action in controls bar)
- [x] **Captions** — ✅ P0 — lightbox caption bar edit → `CaptionStore` →
  `photo_asset_set_caption` (catalog `asset.caption`), shown as a thumb overlay (Picasa:
  `caption`; Pablo: `gallery/widgets/caption_bar.dart`, `data/caption_store.dart`)
- [x] **Keywords / tags** — ✅ P0 — full CRUD + native persistence (catalog v5 `tag`/`asset_tag`,
  `photo_asset_add/remove_tag`; `tags_test.cpp`) (Picasa: `keywords 0x00c81848`;
  Pablo: `pablo/lib/features/info_panel/tags_tab.dart`)
- [ ] **Numeric rating (beyond binary star)** — ◐ P1 — catalog `rating` column,
  `photo_asset_set_rating` C API and rating sort exist; no UI to set a rating (star only)
  (Picasa: `rating 0x00c81448`)
- [ ] **Color labels** — ❌ P2 (Picasa: `color:red … gray` set)
- [x] **EXIF / IPTC / XMP read** — ✅ P0 (Picasa: `MetadataField_NameToId 0x00633210`, ~335 fields;
  Pablo: `native/core/src/exif/`)
- [ ] **Metadata write-back to file / sidecar** — ◐ P0 — opt-in face-region XMP sidecar export
  (§7) and opt-in in-place pixel saves (§6) shipped; tags/captions/ratings/geo remain
  catalog-only per D1 — no general XMP/IPTC write yet. Needed for round-trip / interop.
- [ ] **`.picasa.ini` interop (read + write Picasa sidecars)** — ❌ P1 — direct migration win; the full
  schema is recovered in `picasa_app_re/recovered/picasa_ini.cpp` (per-image keys + `]`-folder sections)
- [ ] **Batch metadata edit (tag / caption / star many at once)** — ◐ P1 — multi-select
  Star/Unstar, Hide, Add-to-Album and batch rename work from the context menu; no multi-tag /
  multi-caption editor (Tools → Batch Edit… is a stub)
- [x] **Rename / batch rename** — ✅ P1 — single rename dialog + pattern-based batch rename modal
  (Picasa: `CRenameDialog`; Pablo: `features/organize/batch_rename.dart`,
  `batch_rename_modal.dart`, context menu)
- [x] **File ops: copy / move / delete (functional)** — ✅ P0 — Move to Folder (palette;
  cross-volume verified copy+delete), Split Folder Here, Rename, Delete, Copy Paths — all with
  file-op undo (Pablo: `data/file_ops.dart`, `data/move_service.dart`, `data/undo_stack.dart`,
  `gallery/photo_context_menu.dart`)
- [ ] **Adjust date / time** — ❌ P2

## 6. Editing (non-destructive)

> Pablo's editor (`pablo/lib/features/editor/`) is now a real non-destructive editor: every tool
> writes a parametric edit spec persisted per asset (catalog `asset_edit`, `key=value;` grammar in
> `native/core/src/edit/edit_spec.cpp`, `content_rev` folded into the thumb cache key) and
> rendered natively at full res. Three save modes per DECISIONS D1 amendments: catalog-only
> (default), layered TIFF (`.pablo.tif`), and Picasa-style overwrite-with-backup
> (`.pablo-originals`).

- [x] **Non-destructive edit stack + persistence + revert-to-original** — ✅ P0 — persisted
  parametric spec + Revert (catalog `asset_edit`, `edit_session.dart`; `edit_test.cpp` /
  `edit_integration_test.cpp`); plus opt-in save-in-place with `.pablo-originals` backup and
  byte-identical revert (Picasa: `filters=` edit-stack grammar,
  `glimmer::EffectParser 0x00bb31f0`, `backuphash`, `.picasaoriginals`)
- [x] **Crop (+ aspect presets, crop-to-fit)** — ✅ P0 — interactive crop with aspect presets,
  persisted as `crop=` (Pablo: `editor/crop_overlay.dart`) (Picasa: `crop=`, `rect64(`, `croptofit`)
- [x] **Straighten / rotate-by-angle** — ✅ P0 — persisted `straighten=` spec key
- [x] **Rotate 90° + flip (lossless, persisted)** — ✅ P0 — persisted `rot=` / `fliph=` / `flipv=`
  (Picasa: `rotate(%d)`, `flipped(%d)`)
- [x] **Tuning: fill light, highlights, shadows, color temp, exposure** — ✅ P0 — exposure,
  contrast, highlights, shadows, whites, blacks, clarity, dehaze, temperature, tint, vibrance,
  saturation, sharpness, noise, vignette (`edit_spec.cpp`; `editor/adjustment_section.dart`)
  (Picasa: `Exposure / LocalContrast / ColorMatrix` ops)
- [x] **One-click auto-fix ("I'm Feeling Lucky" / auto color / auto contrast)** — ✅ P1 —
  auto-levels `autofix=` toggle (`edit_session.toggleAutoFix`) (Picasa: `enhance`, `autocolor`,
  `autolight`, `icnik=1;`, `AutoFixImageOperation`)
- [x] **Red-eye removal** — ✅ P1 — region-based fix with auto-detect from SCRFD eye landmarks,
  persisted `redeye=` regions (D11 classical CPU pass; Pablo: `editor/retouch_overlay.dart`)
  (Picasa: `RedEyeEdit 0x00d41058`, `edeye=1;`)
- [x] **Retouch / heal** — ✅ P1 — brush regions persisted as `heal=`, classical CPU pass per D11
  (Pablo: `editor/retouch_overlay.dart`) (Picasa: `RetouchEdit` / `CRetouchFilter`, Poisson blend)
- [ ] **Effects / filter library** — ◐ P1 — 12 presets, now persisted in the spec (`filter=`);
  Picasa had ~40 ops (B&W, sepia, sharpen, blur, radial blur, glow, tint, gradient map, local
  contrast, border, edge, noise, pixelate, resaturate, …) (Picasa: `imageOperations:*`;
  Pablo: `editor/filter_matrices.dart`)
- [x] **Curves** — ✅ P2 — curve points persisted as `curves=` (Pablo: `editor/curves_editor.dart`)
  (Picasa: `AdjustCurvesImageOperation`)
- [x] **Text overlay on photo** — ✅ P2 — text items persisted as `text=` in the spec
  (Pablo: `editor/widgets/text_item_card.dart`) (Picasa: `textactive`)
- [ ] **Regional / mask edits + blend modes** — ❌ P2 — red-eye/heal are region lists, but no
  general masks or blend modes (Picasa: `MaskInstruction`, `BlendInstruction`)
- [ ] **Batch edits across selection** — ❌ P1 — Tools → Batch Edit… is a menu stub
- [x] **Edit-backup of originals (safety) + revert** — ✅ P1 — `.pablo-originals`
  first-save-wins backup, temp+atomic-rename replace, byte-identical Revert
  (`photo_asset_save_in_place` / `_revert_in_place` / `_has_inplace_backup`; D1 2026-07-03
  amendment) (Picasa: `.picasaoriginals`)

## 7. Faces & people

- [x] **Face detection** — ✅ P0 (Picasa: Neven Vision; Pablo: SCRFD-10g,
  `native/core/src/faces/`, pluggable model profiles in `faces/model_registry.h`)
- [x] **Face recognition / embeddings** — ✅ P0 (Pablo: AuraFace 512-d)
- [x] **Clustering / grouping suggestions** — ✅ P0 (Picasa: HOG clustering; Pablo: agglomerative)
- [x] **Name tagging + People albums** — ✅ P0 (Pablo: `pablo/lib/features/people/face_naming.dart`)
- [x] **Confirm / reject suggestions** — ✅ P0 (Pablo: `people/decision_buttons.dart`)
- [x] **Face data persisted (catalog)** — ✅ P0 (Pablo: `data/sources/face_repository.dart`)
- [x] **Ignore-face / unknown-face handling** — ✅ P1 — persisted `ignored` flag detaches a
  detection from its person/cluster + excludes it from people & re-clustering; restorable
  (Picasa: `]ignoreface`; Pablo: `face.ignored` column, `photo_face_set_ignored`, People-tab Ignore/Restore)
- [x] **Manual face rectangle add / adjust** — ✅ P1 — draw a box by hand (lightbox / info-panel
  dialog), name it, remove it (adjust = remove + redraw) (Pablo: `photo_face_add_manual`,
  `manual` column, `manual_face_dialog.dart`)
- [ ] **Write face tags to file metadata (XMP regions) / `.picasa.ini` interop** — ◐ P1 — MWG-rs
  XMP sidecar write DONE (opt-in, `photo_asset_write_face_xmp` → `<path>.xmp`); `.picasa.ini`
  interop still ❌, and third-party XMP regions are not read on import
  (Picasa: `ThumbDB_WriteFaceTagsToImageFile 0x004852e0`, XMP IPTC-ext Regions;
  Pablo: `native/core/src/xmp/face_xmp.cpp`)

## 8. Places & geo

- [x] **Map view of geotagged photos** — ✅ P1 — real equirectangular world map (simplified
  continent outlines + graticule), markers by true GPS, ~1° clustering, tap-to-select
  (Picasa: `GeoPanel`, `EarthController`; Pablo: `pablo/lib/features/map/world_map.dart`)
- [x] **Read GPS from EXIF** — ✅ P1
- [x] **Manual geotag (drag onto map)** — ✅ P2 — click-to-place pin or type coordinates; a
  catalog `geo_override` that beats EXIF and survives rescan (Picasa: `CGeoLocateDialog`;
  Pablo: `photo_asset_set_geo`, `set_location_dialog.dart`, Info-panel Location row)
- [x] **Reverse-geocode to place names** — ✅ P2 — offline nearest-city lookup (bundled ~250-city
  table, no network) → "City, Country" labels (Pablo: `reverse_geocode.dart`)
- [x] **KML / KMZ export** — ✅ P2 — KML export of all located photos for Google Earth/Maps (KMZ
  zipping still ❌) (Picasa: `CBackgroundKmzWriter`; Pablo: `kml_export.dart`)

## 9. Search & discovery

- [x] **Text / multi-criteria search** — ✅ P0 — date, content, people, camera/EXIF, tags, colour,
  file type — with real result counts — plus real semantic text→image ranking (SigLIP2,
  `native/core/src/semantic/onnx_embedder.cpp`)
  (Pablo: `pablo/lib/features/search/advanced_search_modal.dart`, `search_service.dart`)
- [x] **Filter by person** — ✅ P1
- [x] **Saved searches / smart albums** — ✅ P1 — catalog v7 `saved_search` + `SavedSearchStore`;
  saved-search chips in the advanced-search modal (Picasa: `]search` virtual folders;
  Pablo: `data/saved_search_store.dart`)
- [ ] **Filter by star / rating** — ◐ P1 — starred filter shipped in advanced search; a
  numeric-rating filter is blocked on §5.4 (no rating UI)
- [ ] **Filter by place** — ◐ P2 — has-location filter + map cluster browse; no place-name query
- [x] **Search-by-color** — ✅ P2 — model-free dominant-colour signature (catalog v7
  `embedding.dominant_rgb`) + colour chips with colour-distance ranking (Picasa shipped this;
  `avgcolor` per image; Pablo: `search_service.dart` `_ColorMatcher`)

## 10. Create / output (core)

- [x] **Export (resize / quality / watermark to folder)** — ✅ P0 (Stage V1) — batch export of the tray/selection through the native render pipeline: long-edge resize, JPEG quality, and a text watermark (`photo_asset_export2` + `photo_export_options_t`). File → Export to Folder…, gallery context menu, Options persisted in AppConfig.
- [x] **Slideshow** — ✅ P1 (Stage V2) — fullscreen auto-advancing show (crossfade, seeded shuffle, loop, auto-hide chrome, Space/←/→/Esc) via a pure `SlideshowController`; View → Slideshow + a lightbox launcher button.
- [x] **Print (layouts / contact sheet)** — ✅ P1 (Stage V2) — `printing`+`pdf`: full-page / 2-up / 4-up / contact-sheet layouts (pure `print_layouts` math) rendered from full-res temp exports into a PDF → the OS print dialog. File → Print…, context-menu Print…. (Poster/tiling still ❌.)
- [x] **Share sheet (OS share / generic targets)** — ✅ P1 (Stage V2) — `share_plus` (NSSharingServicePicker on macOS); unedited JPEGs share the original, edited assets share a rendered temp copy. File → Share…, context-menu Share….
- [x] **Collage / picture pile** — ✅ P2 (Stage V4) — grid / feature-column templates (pure `collage_layouts` math) composited full-res by a native libvips compositor (`photo_create_collage`, honours each source's saved edit, cover-fit cells), imported back into the library. Tools → Create Collage… from the tray.
- [ ] **Movie / video creation** — ❌ P2 (Picasa: `MakeMoviePanel`)

## 11. Video / movies

- [x] **Video files in the library** — ✅ P1 (Stage V3) — mp4/mov/m4v/avi/mkv/webm import (catalog v9 `kind`/`duration_ms`), FFmpeg-probed dims/duration, poster-frame thumbnails through the existing thumb pipeline, grid play-circle + duration badge.
- [x] **In-app video playback** — ✅ P1 (Stage V3) — the lightbox opens a `video_player` surface (AVFoundation on macOS) with play/pause/scrubber/mute; poster-only fallback off macOS.
- [x] **Trim (start / end points)** — ✅ P2 (Stage V4) — non-destructive trim (catalog `video_edit`, D1): set-start/set-end/clear on the lightbox player (clamped/looped playback via a pure `TrimController`), plus "Export clip…" via a stream-copy `remux_trim` (no re-encode; start snaps to the nearest keyframe).

## 12. App shell & UX

- [x] **Window chrome (title / menu / status bars)** — ✅ P0 (Pablo: `pablo/lib/layouts/`)
- [x] **Sidebar nav (folders / albums / people / places)** — ✅ P0
- [x] **Info panel** — ✅ P0 (Pablo: `pablo/lib/features/info_panel/`)
- [x] **Activity / progress indicators** — ✅ P1 (Pablo: `search/activity_indicator.dart`)
- [x] **Context menus wired to real actions** — ✅ P0 — photo + folder menus fully functional:
  View/Edit, Star, Move/Split, Rename, Album ops, Hide, Export/Share/Print, Delete, Copy Paths
  (Pablo: `gallery/photo_context_menu.dart`, `organize/folder_ops.dart`)
- [ ] **Functional menu bar (File / Edit / View / Tools …)** — ◐ P1 — most items are live
  (Export/Share/Print, sorts, Slideshow, Show Hidden, Scan Faces, Find Duplicates, Collage,
  Organization Scheme, Compact, Relocate, Options); stubs remain (Add Folder, Import From, Web
  Page, Redo, Select All, thumbnail sizes, New Album, Batch Edit, Help)
- [ ] **Keyboard shortcuts / accelerators** — ◐ P1 — ⌘Z file-op undo + ⌘⇧M move palette
  (`app/key_actions.dart`), lightbox/slideshow/compare key handling; no full accelerator map
  (Picasa: `TranslateAccelerator` set)
- [ ] **Drag & drop (to albums / tray / out to OS)** — ◐ P1 — thumbs drag onto sidebar folders to
  move files (`gallery/photo_thumb.dart` → `sidebar/folder_leaf.dart`); no drag to albums/tray or
  out to the OS
- [ ] **Global undo / redo** — ◐ P1 — file-op `UndoStack` (move/rename/delete/split) via ⌘Z +
  Edit menu (`data/undo_stack.dart`); no redo, metadata ops not covered (the editor has its own
  Revert)
- [ ] **Persistent settings / preferences UI** — ◐ P1 — persisted `AppConfig`
  (`data/app_config.dart` — edit-save mode, export options) + Tools → Options… dialog; no full
  preferences window (Picasa: `COptionsDialog`, registry `Preferences\*`)
- [ ] **Notifications / toasts** — ◐ P2 — ad-hoc SnackBar toasts on file ops / print / dedup /
  map; no notification center (Picasa: `CNotifierWin`)
- [ ] **Single-instance + file associations + shell/Finder integration** — ❌ P2
- [ ] **Localization / i18n** — ❌ P2 (Picasa: `i18n\stringres.xml`)
- [ ] **Color management (ICC)** — ❌ P2 (Picasa: `EnableColorManagement`)

---

## Top parity gaps (executive summary)

The former headline gaps — durable catalog, albums, the non-destructive editor, export, and
functional file ops — have all shipped. What remains, roughly in impact order:

1. **Metadata write-back + `.picasa.ini` interop** (§5.7 / §5.8) — the round-trip / migration
   gap; the opt-in face-XMP sidecar is the only metadata write today (schema already recovered in
   `picasa_app_re/recovered/picasa_ini.cpp`).
2. **Broader import formats** (§1.3) — the libvips decode layer is ready; widen the import
   extension filter (TIFF, HEIC, JXL) and finish the RAW story.
3. **Acquisition** — watched/hot folders (§1.2) and camera/device ingest (§1.4).
4. **Batch operations** — multi-tag/caption metadata edit (§5.9) and batch edits across a
   selection (§6.13).
5. **Shell polish** (§12) — remaining menu-bar stubs, drag & drop to albums/out to OS, redo,
   a real preferences window.

Catalog, albums, organize, editing, faces, places, search, export/print/share, video, and
duplicate finding are now at or near parity.

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
- **Pablo survey:** the `CC/jovial-solomon-487861` worktree — `pablo/lib/features/*`,
  `native/core/src/*` (catalog schema v10), `native/core/tests/*`, `docs/DECISIONS.md`
  (D1 + amendments, D11–D14).
