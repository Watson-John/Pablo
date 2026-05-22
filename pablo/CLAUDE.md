# Pablo — Implementation Reference

This file is the working reference for implementing the Pablo v3 desktop application in Flutter. It mirrors the approved plan at `/Users/johnwatson/.claude/plans/you-are-implementing-a-fuzzy-robin.md`.

> **For coding agents working in this repo:** read this top-to-bottom before editing anything. Then check the chunk status table at the bottom to see what's been completed and where to pick up.

## What we're building

Pablo is a Picasa-successor photo management desktop app. The source-of-truth design lives in `/tmp/pablo_design/pablo-warm/project/` (8 React/JSX modules + `Pablo v3.html`). We are recreating the visual output faithfully in Flutter, using a strict centralized theme system.

## Strict rules

1. **Theme tokens are mandatory.** No raw `Color(0xFF…)`, no raw `EdgeInsets.all(7)`, no `BorderRadius.circular(8)` outside `lib/theme/` and `lib/data/`. All colors / spacing / radii / shadows / typography go through `PabloColors`, `PabloSpacing`, `PabloRadius`, `PabloShadows`, `PabloTypography`.
2. **Modular.** Each feature lives in its own folder under `lib/features/`. Shared primitives live in `lib/components/`. No monolithic files (target ≤ 250 lines).
3. **Two distinct accents.** Copper `#C17A3A` is the *action* accent (Import button, sliders). Blue `#2563EB` is the *selection* accent (sidebar selected, photo selection ring). They are not interchangeable.
4. **Verbatim data port.** People/Folders/Albums/Timeline/Map data + the `_h()` hash + EXIF/tag generators are ported byte-for-byte from `pablo3-foundation.jsx` / `pablo3-map.jsx`.
5. **No new pub deps** beyond what's already in `pubspec.yaml`, except `google_fonts: ^6.2.1` (loads DM Sans / Lora / JetBrains Mono at runtime).

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
├── data/                         # models.dart, mock_data.dart, photo_factory.dart
├── components/                   # design-system primitives
├── layouts/                      # title_bar, menu_bar, search_header, status_bar, shell
├── features/
│   ├── sidebar/
│   ├── gallery/
│   ├── editor/
│   ├── info_panel/
│   ├── controls_bar/
│   ├── photo_tray/
│   ├── search/
│   ├── menu/
│   └── map/
└── utils/                        # hash.dart, window_setup.dart
```

## Source files for parity

When implementing a feature, open the matching JSX file and treat it as ground truth for layout, spacing, and behavior:

| Feature                                | JSX file (`/tmp/pablo_design/pablo-warm/project/`)  |
| -------------------------------------- | --------------------------------------------------- |
| Tokens, base components, icons, mock data | `pablo3-foundation.jsx`                          |
| Title/menu/search/status, app state    | `pablo3-app.jsx`                                    |
| Sidebar (all sections)                 | `pablo3-sidebar.jsx`                                |
| Gallery, lightbox, tray, controls bar  | `pablo3-gallery.jsx`                                |
| Unnamed faces, advanced search, info panel | `pablo3-panels.jsx`                             |
| Photo edit panel                       | `pablo3-editor.jsx`                                 |
| Map page                               | `pablo3-map.jsx`                                    |

## Verification gates

After each chunk:

1. `cd pablo && flutter analyze` — must be clean.
2. Theme-gate grep — `grep -rnE 'Color\(0x|EdgeInsets\.(?:all|symmetric|fromLTRB)\([0-9]' lib/features lib/layouts lib/components` returns no matches.
3. Run the app — `flutter run -d windows` (or `-d macos` for cross-platform smoke). Exercise the chunk's acceptance criteria.

## Assumptions

1. The macOS-style traffic lights in the title bar are decorative (matching the mockup). Windows chrome is provided by the OS.
2. Photos are gradient placeholders, not real images.
3. Map is the simplified USA outline; no real geo.
4. Slideshow/Print/Share/Export are visual-only (no-op handlers).
5. State is in-memory only.
6. Modifier keys: Ctrl on Windows / Linux, Cmd on macOS.

## Chunk status

| #   | Chunk                                          | Status   | Notes                              |
| --- | ---------------------------------------------- | -------- | ---------------------------------- |
| 0   | Reference doc (this file)                      | ✅ done  | -                                  |
| 1   | Theme + base components                        | ✅ done  | tokens, icons, button, slider, etc |
| 2   | Data layer                                     | ✅ done  | models + mock_data + photo_factory |
| 3   | App shell + layout                             | ✅ done  | title/menu/search/status bars      |
| 4   | Sidebar                                        | ✅ done  | nav + sections + folders/timeline  |
| 5   | Gallery + photo thumb + tray                   | ✅ done  | section_scroll_view + tray         |
| 6   | People scroll view + Unnamed Faces page        | ✅ done  | suggestions accept/reject + 3 tabs |
| 7   | Controls bar + Photo Info Panel                | ✅ done  | thumb slider + 3 info tabs         |
| 8   | Lightbox + Photo Edit Panel                    | ✅ done  | filters + tools + sliders          |
| 9   | Advanced Search + Activity + Context Menu      | ✅ done  | 2-col criteria modal + right-click |
| 10  | Map page                                       | ✅ done  | USA heat map + per-location grid   |
| 11  | Polish + final QA                              | ✅ done  | flutter analyze + theme-gate clean |
