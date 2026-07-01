# SPEC-05 — Organize & Metadata (test plan)

Test design and as-built coverage for Pablo's **Organize & metadata** capability
group (PICASA_PARITY §5): the user-authored organize fields (star / numeric
rating / caption / keywords-tags), EXIF read, and the C ABI + Dart FFI seams
that expose them. This document is the companion to the suite added under
`native/core/tests/` and `pablo/test/ffi/`.

---

## 0. Scope, status, and as-built reality

### 0.1 Features in scope

| # | Feature | Status | Where |
|---|---------|--------|-------|
| OM-1 | Star / favorite | 📦 | `catalog.set_starred` / `starred_assets`; C ABI `photo_asset_set_starred` |
| OM-2 | Caption (surface + edit + persist) | 📦 | `catalog.set_caption`; C ABI `photo_asset_set_caption` / `photo_asset_organize` |
| OM-3 | Keywords / tags (CRUD + persist) | 📦 | `tag` / `asset_tag` tables; C ABI `photo_asset_{add,remove}_tag` / `photo_asset_tags` |
| OM-4 | Numeric rating (0..5) | 📦 | `catalog.set_rating`; C ABI `photo_asset_set_rating` |
| OM-5 | EXIF / IPTC / XMP read | 📦 | `exif/exif.cpp` (libexif) → `asset_metadata` → `photo_asset_metadata` |
| OM-6 | Metadata write-back to file / sidecar | ❌ (deferred, **D1**) | — |
| OM-7 | `.picasa.ini` interop | ❌ | — |
| OM-8 | Batch metadata edit | ❌ | — |
| OM-9 | Rename / batch rename | ❌ | — |
| OM-10 | File ops: copy / move / delete | 🟡 | engine `FileOps.applyPlan` tested (`file_ops_test.dart`); context-menu handlers still no-op |
| OM-11 | Color labels | ❌ | — |
| OM-12 | Adjust date / time | ❌ | — |

### 0.2 Status legend

- **✅ Shipped** — on `main`, tested.
- **📦 Native** — implemented in the native backend; covered by this suite.
- **🟡 Partial** — engine exists and is tested; UI wiring incomplete.
- **❌ Not started** — no implementation; **nothing to test** (see §4).

### 0.3 Read-only invariant (DECISIONS D1)

All user-authored organize state is **catalog-only** in v1. Nothing is written
back to the original files or to sidecars. EXIF is **read** only. Two tests pin
this as an enforced invariant rather than a convention:
`ExifFixture.ExtractionDoesNotModifyTheFile` (bytes + mtime unchanged after
`extract`) and the absence of any write path in the C ABI / FFI surface.

---

## 1. Test architecture

The suite is layered to match the seams a value crosses on its way from the UI
to disk and back. Each layer is tested in isolation so a failure localizes.

```
 Dart UI  ──FFI──►  C ABI (photo_*)  ──►  Engine (locked)  ──►  Catalog (SQLite)
 organize_ffi_test    c_api_organize_test         organize_state_test / tags_test
 (real dylib)         (real engine handle)        metadata_storage_test (white-box)
                                                   exif_extract_test (libexif + fixture)
```

| Layer | Harness | File(s) | Needs |
|-------|---------|---------|-------|
| Catalog (white-box) | GoogleTest | `organize_state_test.cpp`, `tags_test.cpp`, `metadata_storage_test.cpp` | SQLite |
| EXIF extractor | GoogleTest | `exif_extract_test.cpp` | libexif + committed fixture |
| C ABI | GoogleTest (+ real `photo::Engine`) | `c_api_organize_test.cpp` | SQLite |
| Dart FFI (e2e) | `flutter_test` | `pablo/test/ffi/organize_ffi_test.dart` | loadable `libphoto_core` |

Pre-existing coverage this suite builds on: `catalog_test.cpp` (upsert preserves
user fields across re-import), `organize_test.cpp` (tag happy-path),
`metadata_test.cpp` (catalog metadata round-trip + engine geotag),
`smart_test.cpp` (recent/starred sets), `catalog_ffi_test.dart` (star + tags
through the real dylib).

---

## 2. Test inventory

### 2.1 `organize_state_test.cpp` — star / rating / caption (OM-1,2,4)

| Test | Pins |
|------|------|
| `StarToggleAndPerAssetIsolation` | default off; set/clear; idempotent; per-asset isolation |
| `SettersOnUnknownIdAreNoOps` | star/rating/caption on a missing id create no row, never throw |
| `RatingStoredVerbatimIncludingOutOfRange` | 0/1/5 stored; **no clamp** at the catalog layer (−1, 99 persist) — contract is enforced above |
| `CaptionOverwriteClearAndUtf8` | overwrite, clear-to-empty, multibyte UTF-8 round-trip |
| `CaptionWithSqlMetacharactersIsBoundSafely` | `O'Brien "x"; DROP TABLE asset;--` stored as an inert literal (binding, not concat) |
| `FieldsAreIndependentAndPersistAcrossReopen` | star/rating/caption/hidden survive a DB reopen, independently |
| `StarredSmartSetExcludesHiddenOrdersByPathReflectsUnstar` | `starred_assets()` is path-ordered, hidden-excluded, and reflects unstar |

### 2.2 `tags_test.cpp` — keywords / tags edge cases (OM-3)

| Test | Pins |
|------|------|
| `NamesAreCaseSensitive` | `Beach` ≠ `beach`; `assets_with_tag` is exact-match |
| `AddIsIdempotentPerMembership` | re-adding a tag is a no-op (membership PK) |
| `RemoveNonMemberIsNoOp` | removing an absent membership never throws |
| `SharedAcrossManyAssets` | one tag across 4 assets; removing one membership leaves the rest |
| `OrphanTagRowSurvivesAndIsReused` | a `tag` row outlives its last membership and is reused (UNIQUE(name)) |
| `ManyTagsForOneAssetAreSorted` | `tags_for_asset` is sorted |
| `Utf8AndMetacharNamesRoundTrip` | Unicode + injection-literal tag names stored safely |
| `UnknownAssetOrTagYieldsEmpty` | empty result, not error |
| `PersistAcrossReopenWithSharing` | tags + sharing survive a reopen |

### 2.3 `metadata_storage_test.cpp` — `asset_metadata` round-trip (OM-5 storage)

| Test | Pins |
|------|------|
| `EveryFieldRoundTrips` | lens / focal / shutter / width / height (the fields `metadata_test.cpp` omits) |
| `SouthAndWestCoordinatesPersistWithSign` | signed S/W coordinates persist exactly; both appear in `geotagged()` |
| `HasGpsFalseIsExcludedFromGeotagged` | a row with coords but `has_gps=false` is **not** geotagged |
| `ReUpsertOverwritesEveryFieldNotInserts` | re-upsert replaces the row (clears unset fields), does not duplicate |
| `Utf8CameraAndLensRoundTrip` | UTF-8 camera/lens strings |
| `GetMissingIsNullopt` | absent metadata → `nullopt` |

### 2.4 `exif_extract_test.cpp` — real libexif vs exiftool (OM-5 read)

Robustness (runs in every build — `extract` never throws):

| Test | Pins |
|------|------|
| `NonExifFileReturnsEmpty` | garbage file → empty struct, orientation defaults to 1 |
| `MissingFileReturnsEmpty` | nonexistent path → empty |
| `DirectoryPathReturnsEmpty` | a directory → empty |
| `TruncatedExifHeaderDoesNotCrash` | a JPEG with a truncated APP1/Exif marker does not crash |

Ground-truth cross-check (`PHOTO_HAVE_EXIF` only, against `fixtures/exif_full.jpg`):

| Test | Pins |
|------|------|
| `AllFieldsMatchBakedGroundTruth` | camera/lens/iso/orientation/width/height match exiftool's baked values exactly; the unit-bearing aperture/shutter/focal are asserted by numeric core (`2.8`/`1/250`/`50`), robust to libexif formatting drift |
| `DateTimeOriginalParsedAsUtcSeconds` | `2021:07:15 12:30:45` → `1626352245` (parsed as UTC) |
| `GpsDecodedWithHemisphereSign` | N → +lat, W → −lon, within 1e-4° of deg/min/sec |
| `ExtractionDoesNotModifyTheFile` | **D1**: bytes + mtime unchanged after extract |

### 2.5 `c_api_organize_test.cpp` — the C ABI surface (OM-1..5 boundary)

Drives the `photo_*` exports against a real `photo::Engine` handle (the same
`reinterpret_cast` the c_api layer uses).

| Test | Pins |
|------|------|
| `StarRatingCaptionRoundTripViaOrganizeGetter` | set_starred/rating/caption → `photo_asset_organize` read-back |
| `OrganizeUnknownAssetIsNotFound` | `PHOTO_STATUS_NOT_FOUND` for a missing id |
| `NullArgumentsRejected` | null engine / out → `PHOTO_STATUS_INVALID_ARG` (no crash) |
| `CaptionTruncatedSafelyToBuffer` | a >512-byte caption truncates to 511 + NUL in the ABI struct |
| `AddTagRejectsEmptyAndNull` | empty / null tag → `PHOTO_STATUS_INVALID_ARG` |
| `TagsNulSeparatedTwoPassAndCapTruncation` | grow-and-recall sizing; a small cap stops on a tag boundary, never splits |
| `RemoveTagAndEmptyListReportsZero` | remove + empty list returns 0; remove-absent is OK |
| `MetadataOkNotFoundAndInvalid` | `photo_asset_metadata` OK / NOT_FOUND / INVALID_ARG |

### 2.6 `organize_ffi_test.dart` — end-to-end through the dylib

Gated on the dylib being loadable (`markTestSkipped` otherwise). Covers the
rating + caption read-back via `organize()`, `assetTags` growth past its initial
buffer, `organize()` null on unknown ids, and persistence across reopen — the
paths `catalog_ffi_test.dart` does not exercise.

---

## 3. Running

```bash
# C++ (catalog + EXIF enabled; faces off keeps the test build lean)
cmake -S . -B build-tests -G Ninja -DPHOTO_BUILD_FACES=OFF -DPHOTO_BUILD_BENCHMARKS=OFF
cmake --build build-tests --target photo_core_tests
ctest --test-dir build-tests --output-on-failure        # or run the exe directly

# Dart FFI (needs a built libphoto_core on the loader path; run from pablo/,
# whose pubspec.yaml is the package root — there is no repo-root pubspec)
cd pablo && DYLD_LIBRARY_PATH=../build-tests/native/core \
  flutter test test/ffi/organize_ffi_test.dart
```

### 3.1 Regenerating the EXIF fixture

`fixtures/exif_full.jpg` + `fixtures/exif_full.golden.json` are committed so the
test is hermetic (no exiftool/Pillow needed at test time). To change the baked
values, edit and re-run the generator — it bakes via exiftool (the reference
implementation) and rewrites the golden:

```bash
python3 native/core/tests/fixtures/make_exif_fixture.py   # needs exiftool + Pillow
```

Keep the `kExpected*` constants in `exif_extract_test.cpp` in sync with the
`TAGS` dict in the generator.

---

## 4. Deliberately untested (no implementation to test)

These §5 rows are **not started**; there is no behavior to assert. When each
lands, add its row here and a test file alongside.

| Feature | Why no test | First test to add |
|---------|-------------|-------------------|
| OM-6 Metadata write-back / sidecar | Deferred by DECISIONS D1 (read-only v1). The inverse — that we *don't* write — is pinned by `ExtractionDoesNotModifyTheFile`. | Round-trip: write XMP/`.picasa.ini`, re-read, assert equality |
| OM-7 `.picasa.ini` interop | No reader/writer yet (schema recovered in `picasa_app_re`) | Parse a real `.picasa.ini`, assert star/caption/tags mapped |
| OM-8 Batch metadata edit | No batch API | Apply tag/caption/star to a selection, assert all mutated atomically |
| OM-9 Rename / batch rename | No rename op (distinct from `FileOps` filing) | Rename with collision + token expansion |
| OM-11 Color labels | No `color` column/enum | Set/clear/filter by color label |
| OM-12 Adjust date/time | No date-edit op | Shift capture time, assert timeline re-buckets |

File ops (OM-10): the **engine** (`FileOps.applyPlan`, copy/move/collision/
NAME_MAX) is covered by `pablo/test/file_ops_test.dart`; only the context-menu
*handlers* remain no-ops, so there is no new behavior to test at the menu layer
until they are wired.
