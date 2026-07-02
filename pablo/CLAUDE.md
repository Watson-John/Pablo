# Pablo — Implementation Reference

This file is the working reference for the Pablo desktop application in Flutter.

> **For coding agents working in this repo:** read this top-to-bottom before editing anything. The app is REAL now — real photo library on disk, C++ native backend (`native/core`) reached over FFI (`packages/photo_native`), SQLite catalog, ONNX face + semantic-search models. Design-parity notes below still govern look and feel; the "mock data" era is over.

## What we're building

Pablo is a Picasa-successor photo management desktop app. The original visual design source (React/JSX mockups) may not exist on disk anymore; `lib/theme/tokens.dart` and the shipped widgets ARE the design source of truth now, enforced by a strict centralized theme system.

## Strict rules

1. **Theme tokens are mandatory.** No raw `Color(0xFF…)`, no raw `EdgeInsets.all(7)`, no `BorderRadius.circular(8)` outside `lib/theme/` and `lib/data/`. All colors / spacing / radii / shadows / typography go through `PabloColors`, `PabloSpacing`, `PabloRadius`, `PabloShadows`, `PabloTypography`.
2. **Modular.** Each feature lives in its own folder under `lib/features/`. Shared primitives live in `lib/components/`. No monolithic files (target ≤ 250 lines).
3. **Two distinct accents.** Copper `#C17A3A` is the *action* accent (Import button, sliders). Blue `#2563EB` is the *selection* accent (sidebar selected, photo selection ring). They are not interchangeable.
4. **Real data only.** People/Folders/Albums/Timeline/Map all derive from the imported library + native catalog (`data/library.dart`, FFI repositories). No mock/generated data paths remain.
5. **No new pub deps** beyond what's already in `pubspec.yaml`, except the approved exceptions: `google_fonts: ^6.2.1` (DM Sans / Lora / JetBrains Mono at runtime), `file_selector: ^1.0.3` (native folder picker for Relocate/Export), `crypto` (model-download SHA-256), added in §10 Stage V2 — `share_plus` (OS share sheet / NSSharingServicePicker), `printing` (native print dialog), and `pdf` (pure-Dart print-layout builder); and §11 Stage V3 — `video_player` (AVFoundation playback on macOS).

## Design tokens (see `lib/theme/tokens.dart`)

### Palette

| Token                              | Hex        | Use                                       |
| ---------------------------------- | ---------- | ----------------------------------------- |
| `backgroundShell`                  | `#F3EDE6`  | App body                                  |
| `backgroundSidebar`                | `#EAE4DB`  | Sidebar surface                           |
| `backgroundSidebarHover`           | `#E0D9CE`  | Sidebar item hover                        |
| `backgroundSurface`                | `#FDFAF6`  | Cards, popovers, search input             |
| `backgroundSurfaceAlt`             | `#F7F2EC`  | Subtle alt (status bar, controls bar)     |
| `backgroundHover`                  | `#F0EBE3`  | Generic hover                             |
| `backgroundActive`                 | `#E6DFD5`  | Generic pressed                           |
| `borderSubtle`                     | `#DDD6CA`  | Default borders                           |
| `borderStrong`                     | `#C8C0B2`  | Strong borders                            |
| `textPrimary`                      | `#2D2820`  | Body text                                 |
| `textSecondary`                    | `#5C554A`  | Labels, secondary text                    |
| `textMuted`                        | `#9A9286`  | Counts, hints                             |
| `textOnAccent`                     | `#FFFFFF`  | Text on accent / colored surfaces         |
| `accentPrimary`                    | `#C17A3A`  | Copper — actions, sliders                 |
| `accentHover` / `accentActive`     | `#A8682F` / `#8F5725` | Copper interactive states      |
| `accentBackground` / `accentSoft`  | `#FBF0E0` / `#F5E3CC` | Copper tint backgrounds        |
| `selectionPrimary`                 | `#2563EB`  | Blue — selection ring, sidebar active     |
| `selectionBackground`              | `#DBEAFE`  | Sidebar selected row bg                   |
| `success` / `successBg` / `successText` | `#5E8E52` / `#EEF5EC` / `#3D6433` | Confirmed people, save state |
| `error` / `errorBg` / `errorText`  | `#C06058` / `#FDF0EE` / `#8B3E38` | Destructive            |
| `warning` / `warningBg` / `warningText` | `#E8762A` / `#FFF3E8` / `#B05518` | Pending suggestions    |
| `amber`                            | `#D4952E`  | Star icon, folder leaf                    |
| `assignGreen` / `assignGreenHover` | `#5E9E58` / `#4E8A49` | Assign action                  |
| `ignoreRed` / `ignoreRedHover`     | `#C47068` / `#AD5E57` | Ignore / reject action         |

### Typography

- **DM Sans** (UI body, labels). Weights 400 / 450 / 500 / 600 / 700.
- **Lora** (serif headings — section titles in the main grid).
- **JetBrains Mono** (counts, EXIF values, thumb-size readout).

### Spacing

`xs=2, sm=4, md=6, base=8, lg=10, xl=12, xxl=16, xxxl=20, xxxxl=24`.

### Radii

`sm=4, md=6, lg=8, panel=12, pill=20` (icon buttons use `999`/circular).

### Shadows

```text
sm: 0 1px 3px  rgba(60,40,20,0.06)
md: 0 2px 10px rgba(60,40,20,0.09)
lg: 0 8px 28px rgba(60,40,20,0.14)  +  0 0 1px rgba(60,40,20,0.08)
```

### Icon stroke weight

- Default: `1.5`
- Emphasized (rotate, star, plus, clock): `2.0`

## Feature inventory

1. App shell — decorative macOS-style title bar, menu bar (File/Edit/View/People/Albums/Tools/Help), search header with activity progress, status bar.
2. Sidebar (resizable 180–360 px) — Map nav, People (+ Unnamed Faces row), Albums, Folders (tree↔A–Z), Timeline.
3. Main grid — section dispatcher: Folders / Albums / Timeline → `SectionScrollView`; People → `PeopleScrollView` w/ suggestions; Unnamed → 3-tab page; Map → heat map.
4. Photo thumbnail — hover/selected/in-tray states, star, add-to-tray plus, double-click → lightbox.
5. Photo Info Panel (240 px) — People / Tags / Info tabs.
6. Controls bar — rotate/star/add/clock + thumb slider (snap 130) + segmented People/Tags/Info tabs.
7. Photo tray (resizable 52–160 px) — lock toggle, clear button.
8. Lightbox — filmstrip, prev/next arrows, ESC/arrow keys, wheel paging.
9. Photo Edit Panel — 12 filters, 8 tools, Light/Color/Detail sliders.
10. Advanced Search modal — date / content / people / camera EXIF / tags / album. Live result count.
11. Activity indicator — task list with progress.
12. Context menu — right-click photo.
13. Window — native Windows chrome, default 1280×820, min 960×600.

## Folder structure (target)

```text
pablo/lib/
├── main.dart
├── app/                          # PabloApp, AppState, AppScope
├── theme/                        # tokens.dart, theme.dart
├── data/                         # library, catalog stores, config, move/rename services
├── backend/                      # native_backend.dart (FFI engine bootstrap), prefetch
├── components/                   # design-system primitives (buttons, menus, inputs)
├── layouts/                      # title_bar, menu_bar, search_header, shell
├── features/
│   ├── sidebar/                  # nav tree, albums, folders, timeline, pins
│   ├── gallery/                  # main grid, lightbox (+video), thumbs, context menu
│   ├── editor/                   # edit panel, overlays (crop/curves/retouch), sessions
│   ├── info_panel/               # People / Tags / Info tabs
│   ├── controls_bar/  photo_tray/
│   ├── search/                   # search controller/service, advanced modal, indexing
│   ├── people/                   # faces: suggestions, naming, unnamed page
│   ├── organize/                 # storage schemes, move palette, batch rename, folder ops
│   ├── find_duplicates/          # dedup flow (exact + similar)
│   ├── export/  share/  print/  slideshow/  collage/
│   └── map/                      # world map, geotagging, KML export
└── utils/                        # asset_id, exif (fallback parser), reveal, sidecars, …
```

## Verification gates

After each stage:

1. `cd pablo && flutter analyze` — must be clean.
2. Theme-gate grep — `grep -rnE 'Color\(0x|EdgeInsets\.(?:all|symmetric|fromLTRB)\([0-9]' lib/features lib/layouts lib/components` returns no matches.
3. `flutter test` — all green (FFI tests under `test/ffi/` need `PHOTO_CORE_LIB=<abs path to libphoto_core.dylib>` from the standalone CMake build; they self-skip without it).
4. Native: `cmake -S . -B build/macos-dev -G Ninja -DCMAKE_PREFIX_PATH=$(brew --prefix) && cmake --build build/macos-dev && ctest --test-dir build/macos-dev`.
5. `flutter build macos --debug` (fresh worktree first needs `bash tools/setup-plugin-symlinks.sh` + `flutter clean`).
6. GUI smoke: `flutter run -d macos --dart-define=PABLO_AUTOSCAN=false` (autoscan off avoids the face-scan hang when driving the built app).

## Facts that replace the old assumptions

1. The macOS-style traffic lights in the title bar are decorative. Windows chrome is provided by the OS.
2. Photos and videos are REAL files imported into the native SQLite catalog; thumbnails render through the native texture seam.
3. Map is a real equirectangular world map fed by EXIF GPS + manual geotags (offline reverse geocoding, KML export).
4. Slideshow/Print/Share/Export/Collage are fully functional (§10–11).
5. State persists: catalog.db (native), config.json, folder_prefs.json, scheme/saved-search stores.
6. Modifier keys: Ctrl on Windows / Linux, Cmd on macOS.
7. Non-destructive edits live in the catalog (D1); layered-TIFF save is opt-in (`EditSaveMode`).
