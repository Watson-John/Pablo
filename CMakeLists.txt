# Top-level CMake entry for the Pablo native backend.
#
# This is invoked when developing the native core in isolation. The Flutter
# plugin's per-platform CMakeLists.txt files include native/core directly,
# so this file is convenience for IDE setup and standalone builds.
#
# See docs/BUILD.md for build commands and CMakePresets.json for presets.

cmake_minimum_required(VERSION 3.27)

project(pablo
    VERSION 0.1.0
    DESCRIPTION "Pablo native backend"
    LANGUAGES CXX C
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# LGPL link-mode default. Per-library overrides in native/core/CMakeLists.txt
# guarantee dynamic linkage for libvips, libheif, libraw, libexif regardless
# of this default (see LICENSES.md and docs/DECISIONS.md §D5).
if(NOT DEFINED BUILD_SHARED_LIBS)
    set(BUILD_SHARED_LIBS ON)
endif()

# Sanitizer toggles. Wired up in native/core/cmake/sanitizers.cmake.
option(PHOTO_ENABLE_ASAN  "Enable AddressSanitizer"   OFF)
option(PHOTO_ENABLE_UBSAN "Enable UndefinedBehaviorSanitizer" OFF)
option(PHOTO_ENABLE_TSAN  "Enable ThreadSanitizer"    OFF)

option(PHOTO_BUILD_TESTS      "Build native unit tests" ON)
option(PHOTO_BUILD_BENCHMARKS "Build native benchmarks" ON)

# Enable testing at the top level so the root CTestTestfile.cmake recurses into
# native/core and `ctest` from the build root discovers the gtest targets.
# (native/core/CMakeLists.txt also enables testing for when it is the root, e.g.
# the Flutter plugin build.)
if(PHOTO_BUILD_TESTS)
    enable_testing()
endif()

add_subdirectory(native/core)

# Standalone near-duplicate pipeline (native/dedup). Opt-in: it pulls heavy,
# desktop-only deps (OpenCV/FAISS/ONNX Runtime/LibRaw) via its own vcpkg manifest
# and must NEVER enter the Flutter app build (which includes native/core directly,
# not this root file). Off by default so the core dev build stays light; enable
# with -DPHOTO_BUILD_DEDUP=ON to build it alongside photo_core.
option(PHOTO_BUILD_DEDUP "Build the standalone near-duplicate pipeline (native/dedup)" OFF)
if(PHOTO_BUILD_DEDUP)
    add_subdirectory(native/dedup)
endif()
