# Pablo backend — build instructions

This is the cross-platform build setup for the Pablo native backend. See [DECISIONS.md](DECISIONS.md) for the architectural choices these instructions implement, [LICENSES.md](../LICENSES.md) for the library inventory, and the full plan at [`/Users/johnwatson/.claude/plans/what-are-your-thoughts-scalable-puddle.md`](/Users/johnwatson/.claude/plans/what-are-your-thoughts-scalable-puddle.md).

## Toolchain prerequisites

| Tool | Min version | macOS | Windows | Linux |
|------|-------------|-------|---------|-------|
| CMake | 3.27 | `brew install cmake` | Visual Studio installer or `winget install Kitware.CMake` | `apt install cmake` (or build from source if distro version < 3.27) |
| C++ compiler | C++20 | Xcode 15 Command Line Tools (Apple clang 15+) | Visual Studio 2022 with "Desktop development with C++" workload | gcc 13+ or clang 16+ |
| pkg-config | any | `brew install pkg-config` | via vcpkg | `apt install pkg-config` |
| Ninja | 1.11 | `brew install ninja` | `winget install Ninja-build.Ninja` | `apt install ninja-build` |
| Python | 3.10 | system or `brew install python@3.12` | `winget install Python.Python.3.12` | distro python |
| Flutter SDK | 3.27 | https://docs.flutter.dev/get-started/install | same | same |
| Dart SDK | 3.6 | bundled with Flutter | bundled | bundled |
| `ffigen` | 12.0 | `dart pub global activate ffigen` | same | same |
| Git LFS | 3.0 | `brew install git-lfs && git lfs install` | Git for Windows includes it | `apt install git-lfs && git lfs install` |

Model files in [native/models/](native/models/) are tracked via Git LFS.

## C++ dependency management — vcpkg

We use vcpkg in manifest mode (`vcpkg.json` in the repo root). This gives reproducible per-platform builds and works cleanly with CMake on all three OSes. See [DECISIONS.md decision queue](DECISIONS.md#decision-queue-open) for the vcpkg-vs-Conan rationale.

### One-time vcpkg setup

```bash
git clone https://github.com/microsoft/vcpkg.git "$HOME/vcpkg"
cd "$HOME/vcpkg"
./bootstrap-vcpkg.sh        # or .\bootstrap-vcpkg.bat on Windows
export VCPKG_ROOT="$HOME/vcpkg"      # add to your shell rc
```

The `CMakePresets.json` in this repo expects `$VCPKG_ROOT` to be set (or the `CMAKE_TOOLCHAIN_FILE` to point at `$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake`).

### vcpkg manifest (`vcpkg.json`, created in M1)

```jsonc
{
  "name": "photo-core",
  "version-string": "0.1.0",
  "dependencies": [
    { "name": "libvips",       "default-features": false, "features": ["jpeg", "png", "tiff", "webp"] },
    { "name": "libjpeg-turbo" },
    { "name": "libheif",       "default-features": false, "features": ["libde265"] },
    { "name": "libjxl" },
    { "name": "libraw" },
    { "name": "libexif" },
    { "name": "pugixml" },
    { "name": "lmdb" },
    { "name": "sqlite3",       "features": ["json1", "fts5"] },
    { "name": "blake3" },
    { "name": "gtest" },
    { "name": "benchmark" }
  ]
}
```

**Important:** `libheif` is requested without HEVC encoder features to avoid pulling in x265 (GPLv2; see [LICENSES.md](../LICENSES.md)). Decode-only is sufficient for our read-only thumbnail path.

ONNX Runtime and USearch are vendored separately (see [native/third_party/](native/third_party/) — created in M6/M8); they are not in the vcpkg manifest because we want exact-version control of their per-platform binaries.

## Per-platform setup

### macOS

```bash
xcode-select --install
brew install cmake ninja pkg-config git-lfs
git lfs install
# Flutter: follow https://docs.flutter.dev/get-started/install/macos
dart pub global activate ffigen
```

### Windows

1. Install **Visual Studio 2022** with the "Desktop development with C++" workload (includes MSVC, Windows SDK, CMake integration).
2. Install Flutter for Windows (https://docs.flutter.dev/get-started/install/windows).
3. From an elevated terminal:
   ```pwsh
   winget install Kitware.CMake Ninja-build.Ninja Git.Git Python.Python.3.12
   dart pub global activate ffigen
   git lfs install
   ```
4. Verify **WinML** availability: it's part of the Windows App SDK and Windows Runtime; M6 will probe at runtime.

### Linux (Ubuntu 22.04 / 24.04)

```bash
sudo apt update
sudo apt install -y build-essential cmake ninja-build pkg-config \
                    git git-lfs python3 python3-pip \
                    libgtk-3-dev clang-tidy clang-format
git lfs install
# Flutter: follow https://docs.flutter.dev/get-started/install/linux
dart pub global activate ffigen

# GCC 13+ is required for C++20 modules/concepts we use. Ubuntu 22.04 ships gcc 11;
# either install gcc-13 from PPA or use clang-16+:
sudo apt install -y gcc-13 g++-13
export CC=gcc-13 CXX=g++-13
```

## Building

```bash
# from repo root
cmake --preset=macos-debug          # configure
cmake --build --preset=macos-debug  # build
ctest --preset=macos-debug           # run unit tests
```

Available presets:

| Preset | OS | Build type | Sanitizers |
|--------|-----|------------|------------|
| `macos-debug` | macOS | Debug | ASAN, UBSAN |
| `macos-release` | macOS | RelWithDebInfo | none |
| `windows-debug` | Windows | Debug | ASAN |
| `windows-release` | Windows | RelWithDebInfo | none |
| `linux-debug` | Linux | Debug | ASAN, UBSAN, TSAN-variant |
| `linux-release` | Linux | RelWithDebInfo | none |

See [CMakePresets.json](CMakePresets.json) for the full preset definitions.

## Running the Flutter app

```bash
cd pablo
flutter pub get
flutter run -d macos     # or windows / linux
```

The Flutter app depends on the local `photo_native` plugin (added in M1) via a `path:` dependency in `pablo/pubspec.yaml`. The plugin's CMake build pulls in `native/core` as a subdirectory.

## Regenerating FFI bindings

After any change to `native/core/include/photo_core.h`:

```bash
cd packages/photo_native
dart run ffigen --config ffigen.yaml
```

CI fails if `bindings_generated.dart` is out of sync with the header.

## Running harnesses

| Harness | Path | Run command | When |
|---------|------|-------------|------|
| Corpus runner | [tools/corpus_runner/](tools/corpus_runner/) | `tools/corpus_runner/run.sh` | M3+ |
| Cluster replay | [tools/cluster_replay/](tools/cluster_replay/) | `tools/cluster_replay/replay.sh fixtures/seq1.json` | M7+ |

## CI

GitHub Actions matrix (defined post-M1):

|----|-------|-------|------------|---------------------|
| macOS 13 (x64) | ✅ | ✅ | regression | ✅ |
| macOS 14 (arm64) | ✅ | ✅ | regression | ✅ |
| Windows 11 | ✅ | ✅ | regression | ✅ |
| Ubuntu 22.04 | ✅ | ✅ | regression | ✅ |
| Ubuntu 24.04 | ✅ | ✅ | regression | ✅ |

License check (`scripts/check_licenses.sh` from [LICENSES.md](../LICENSES.md)) runs on every PR.
