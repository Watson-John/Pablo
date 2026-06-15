# Pablo

A Picasa-successor photo-management desktop app: a **Flutter** frontend over a **C++** image/ML core, bridged by an FFI + texture plugin.

## Repository map

| Path | What it is |
| --- | --- |
| `pablo/` | The Flutter desktop app (UI, state). `pablo/lib/` is the source; see its own layout below. |
| `native/core/` | The C++ core (`photo_core`): image decode, thumbnail cache, and the face pipeline (`src/faces/`). Exposes a C ABI in `include/photo_core.h`. |
| `native/models/` | ONNX models for the face pipeline (Git LFS): `scrfd_10g` (detect), `auraface` (512-d embed), `sface` (128-d fallback). See `native/models/MANIFEST.md`. |
| `packages/photo_native/` | The in-repo Flutter plugin: Dart FFI bindings (`lib/src/ffi/`) + the native texture registrar (per-platform). `pablo/` depends on it via a path dependency. |
| `tools/` | Dev scripts. `setup-plugin-symlinks.sh` wires the plugin's source symlinks; `faces_standalone/` is an end-to-end face-pipeline harness. |
| `docs/` | `BUILD.md` (build instructions) and `DECISIONS.md` (locked architectural decisions). |
| `LICENSES.md` | Third-party library inventory + LGPL link policy. |
| `CMakeLists.txt`, `CMakePresets.json`, `vcpkg.json` | Native build entry, presets, and dependency manifest. |

### `pablo/lib/` layout

```
app/          App root, state (PabloAppState), scope.
theme/        Design tokens + ThemeData.
components/   Shared design-system primitives (buttons, slider, avatar, …).
layouts/      App-shell chrome (title bar, menu bar, search header, status bar, shell).
data/
  models.dart   Domain models (Person, Photo, …).
  mock/         Mock data + generators (default data source).
  sources/      Real data sources / repositories (e.g. FaceRepository over the native engine).
backend/      The native engine bridge (NativeBackend over packages/photo_native).
features/     One folder per feature: gallery, people, sidebar, info_panel, editor,
              map, controls_bar, photo_tray, search.
utils/        hash, image dimension parsing, window setup.
```

## Building & running

Native core (standalone, for fast iteration on C++):

```sh
cmake --preset macos-debug      # see CMakePresets.json for other presets
cmake --build build/macos-debug --target photo_core
```

The Flutter app builds the native code into the `photo_native` plugin framework automatically. First-time setup wires the plugin symlinks:

```sh
tools/setup-plugin-symlinks.sh
cd pablo && flutter run -d macos
```

The face pipeline needs OpenCV + ONNX Runtime at build time (`brew install opencv onnxruntime`); without them the app still builds and the face features report unavailable.

## Runtime configuration (dart-defines)

The app runs on mock data by default. To exercise the live native engine + face pipeline:

```sh
cd pablo && flutter run -d macos \
  --dart-define PABLO_NATIVE_THUMBS=true \
  --dart-define PABLO_MODELS_DIR=<repo>/native/models \
  --dart-define PABLO_DATASET_DIR=<path-to-a-photo-folder>
```

`PABLO_DATASET_DIR` points at any folder of images — it need not live inside the repo.
