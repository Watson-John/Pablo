# Testing Pablo

The full local gate every stage/PR runs, exactly as CI would (CI mirrors a
subset; the local gate is authoritative while CI billing is constrained).

## The full gate

```bash
# 0. Fresh worktree only: wire the macOS plugin symlinks, then clean.
bash tools/setup-plugin-symlinks.sh
(cd pablo && flutter clean)   # + rm -rf pablo/macos/Pods if the build acts stale

# 1. Native build + unit tests (standalone, Homebrew deps — no vcpkg needed).
cmake -S . -B build/macos-dev -G Ninja \
      -DCMAKE_PREFIX_PATH=$(brew --prefix) -DPHOTO_BUILD_TESTS=ON
cmake --build build/macos-dev
ctest --test-dir build/macos-dev --output-on-failure

# 2. Flutter analyze + theme gate + unit/widget tests.
cd pablo
flutter analyze                       # must be clean
grep -rnE 'Color\(0x|EdgeInsets\.(all|symmetric|fromLTRB)\([0-9]' \
     lib/features lib/layouts lib/components   # no matches (one documented
                                               # exemption: collage_dialog's
                                               # dynamic Color(0xFF000000|rgb))
flutter test --reporter compact

# 3. FFI tests against the REAL dylib (they self-skip without it).
PHOTO_CORE_LIB=$PWD/../build/macos-dev/native/core/libphoto_core.dylib \
  flutter test test/ffi --reporter compact

# 4. photo_native package: ABI drift gate + its tests.
cd ../packages/photo_native
flutter analyze
PHOTO_CORE_LIB=$OLDPWD/../build/macos-dev/native/core/libphoto_core.dylib \
  flutter test --reporter compact

# 5. App build.
cd ../../pablo && flutter build macos --debug
```

## What lives where

| Suite | Location | Needs | Covers |
|---|---|---|---|
| Native unit/integration | `native/core/tests/*.cpp` (ctest) | SQLite; vips/ffmpeg/OpenCV+ORT optional — gated tests `GTEST_SKIP` without them | catalog + migrations, import/rescan, edit spec/render/export, in-place save, organize, faces store + model registry, semantic, video, collage, analyzers, ABI static_asserts |
| Flutter unit/widget | `pablo/test/*.dart` | nothing native | controllers, stores, pure logic, widget behavior, components |
| Cross-FFI E2E | `pablo/test/ffi/*.dart` | `PHOTO_CORE_LIB=<abs path to libphoto_core.dylib>` | import→catalog round-trips, organize, export/collage/video, edit save modes, metadata parity, similar-dedup, in-place save cycle |
| ABI drift gate | `packages/photo_native/test/abi_drift_test.dart` | regenerate first when the header changed | hand-written mirrors vs ffigen-generated layouts vs the dylib's `photo_abi_version` |
| Env-gated real-model E2E | ctest, skipped unless env set | `PABLO_MODELS_DIR` + `PABLO_REDEYE_FACE_SRC` | real SCRFD/AuraFace scan → detect → correct |
| Goldens | `pablo/test/goldens/` | `GOLDEN=true` to compare, `--update-goldens` to bless | find-duplicates review layout |

## The FFI drift procedure (after ANY photo_core.h change)

```bash
cd packages/photo_native
dart run ffigen --config ffigen.yaml      # regenerate the reference artifact
flutter test                              # abi_drift_test must pass
# commit bindings_generated.dart WITH the header change
```

The native twin is the `static_assert` block at the bottom of
`native/core/src/api/c_api.cpp` — new ABI structs get a size pin there AND an
entry in `debugNativeStructSizes()` (core_api.dart) + the generated map in
`abi_drift_test.dart`. CI runs the regenerate-and-diff in the `ffi-drift` job.

## Face-model quirks

- The models dir is probed for profiles (`faces/model_registry.h`); the
  user-level dir is `~/Library/Application Support/Pablo/models`. If model
  symlinks point into a deleted worktree, resolution silently fails — point
  them at the main checkout's `native/models/`.
- The faces-ON test build is the default here (brew OpenCV + onnxruntime
  found); CI's native job runs faces-OFF (lean).

## GUI smoke

```bash
cd pablo && flutter run -d macos --dart-define=PABLO_AUTOSCAN=false
```

`PABLO_AUTOSCAN=false` avoids the face-autoscan saturating the box while you
drive the UI. Known computer-use quirks (double-tap timing, Escape delivery)
are in the project memory, not a Pablo bug.
